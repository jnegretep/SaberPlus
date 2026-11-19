<?php
// api_saber_plus_ia.php  Tutor IA de Saber+ (vía Cloudflare Proxy)
// v8 (2026-11):
//   ? Fix: json_encode fallaba con caracteres acentuados (Latin-1 vs UTF-8)
//   ? Fix: curl_error se capturaba después de curl_close (mensaje perdido)
//   ? Añadido: medición de tokens (usage)
//   ? Añadido: logging del body enviado y de la respuesta del Worker
//   ? Reducido: max_tokens de 500 ? 300 y system prompt acortado (menos consumo)

header('Content-Type: application/json; charset=UTF-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require_once __DIR__ . '/vendor/autoload.php';
require_once __DIR__ . '/includes/conexion.php';
require_once __DIR__ . '/env.php';

function ia_error(string $codigo, string $error): void {
    http_response_code(200);
    echo json_encode(['exito' => false, 'codigo' => $codigo, 'error' => $error], JSON_UNESCAPED_UNICODE);
    exit;
}

// Rate limit: 6 peticiones por minuto por usuario
function ia_rate_limit_excedido(int $moodle_id): bool {
    $archivo = sys_get_temp_dir() . '/saberplus_ia_rl_' . $moodle_id . '.json';
    $fp = @fopen($archivo, 'c+');
    if ($fp === false) return false;
    $ahora = time();
    $timestamps = [];
    $permitido = true;
    if (flock($fp, LOCK_EX)) {
        $raw = stream_get_contents($fp);
        if ($raw) {
            $dec = json_decode($raw, true);
            if (is_array($dec)) {
                foreach ($dec as $t) {
                    if (($ahora - (int)$t) < 60) $timestamps[] = (int)$t;
                }
            }
        }
        $permitido = count($timestamps) < 6;
        if ($permitido) $timestamps[] = $ahora;
        ftruncate($fp, 0); rewind($fp);
        fwrite($fp, json_encode($timestamps)); fflush($fp);
        flock($fp, LOCK_UN);
    }
    fclose($fp);
    return !$permitido;
}

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200); exit;
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    ia_error('METODO', 'Método no permitido.');
}

// -- Autenticación JWT --
$allHeaders = function_exists('getallheaders') ? getallheaders() : [];
$authHeader = $allHeaders['Authorization'] ?? $allHeaders['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';
if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
    http_response_code(401);
    echo json_encode(["exito" => false, "error" => "No autorizado"]);
    exit;
}

$configJwt = require __DIR__ . '/jwt_config.php';
try {
    $decoded = \Firebase\JWT\JWT::decode($m[1], new \Firebase\JWT\Key($configJwt['secret'], 'HS256'));
    $moodle_id = (int)($decoded->data->moodle_userid ?? 0);
} catch (Exception $e) {
    http_response_code(401);
    echo json_encode(["exito" => false, "error" => "Token inválido"]);
    exit;
}
if ($moodle_id <= 0) {
    http_response_code(401);
    echo json_encode(["exito" => false, "error" => "Token sin ID"]);
    exit;
}

$data = json_decode(file_get_contents('php://input'), true);
$mensaje_estudiante = trim((string)($data['mensaje'] ?? ''));
if ($mensaje_estudiante === '') {
    ia_error('MENSAJE_VACIO', 'Escribe un mensaje.');
}

if (ia_rate_limit_excedido($moodle_id)) {
    ia_error('RATE_LIMIT', 'Vas muy rápido, espera unos segundos.');
}

// ── Persistencia en tablas IA (migración 010) ──
// DeepSeek pricing oficial: input $0.27 / 1M tokens, output $1.10 / 1M tokens.
function ia_calcular_costo(int $promptTokens, int $completionTokens): float {
    return round(
        ($promptTokens / 1_000_000) * 0.27 + ($completionTokens / 1_000_000) * 1.10,
        6
    );
}

/**
 * Persiste un intercambio IA completo (prompt del user + respuesta del assistant)
 * en ia_mensajes y actualiza la conversación activa en ia_conversaciones.
 *
 * Reglas:
 *   - Si las tablas IA no existen (migración 010 pendiente): NO rompe el flujo
 *     principal del endpoint; solo lo loguea una vez por request.
 *   - Reutiliza la última conversación del usuario con started_at < 30 min.
 *   - Si no hay conversación reciente, crea una nueva.
 *   - Toda la operación va dentro de una transacción (rollback ante error).
 *   - Cualquier Throwable se captura y se loguea; NUNCA se propaga al caller.
 */
function ia_persistir(
    PDO $conexion,
    int $userId,
    string $prompt,
    string $respuesta,
    int $promptTokens,
    int $completionTokens,
    int $latencyMs,
    float $costUsd,
    ?string $errorCode = null,
    ?string $errorMessage = null
): void {
    static $tablaExiste = null;
    static $yaLogeado = false;

    try {
        if ($tablaExiste === null) {
            $stmt = $conexion->query("SHOW TABLES LIKE 'ia_mensajes'");
            $tablaExiste = ($stmt && $stmt->fetchColumn() !== false);
        }
        if (!$tablaExiste) {
            if (!$yaLogeado) {
                error_log('[IA][persist] Tabla ia_mensajes no existe — migración 010 pendiente. No-op silencioso.');
                $yaLogeado = true;
            }
            return;
        }

        // 1. Buscar conversación activa del usuario (última con started_at > NOW() - 30 min)
        $stmtFind = $conexion->prepare(
            "SELECT id FROM ia_conversaciones
             WHERE user_id = :uid
               AND started_at > (NOW() - INTERVAL 30 MINUTE)
             ORDER BY id DESC LIMIT 1"
        );
        $stmtFind->execute([':uid' => $userId]);
        $convId = $stmtFind->fetchColumn();
        $convId = $convId ? (int)$convId : null;

        $conexion->beginTransaction();
        try {
            if ($convId === null) {
                // Crear nueva conversación
                $insConv = $conexion->prepare(
                    "INSERT INTO ia_conversaciones
                     (user_id, started_at, last_activity_at, message_count, total_tokens, estimated_cost_usd)
                     VALUES (:uid, NOW(), NOW(), 0, 0, 0)"
                );
                $insConv->execute([':uid' => $userId]);
                $convId = (int)$conexion->lastInsertId();
            }

            // 2a. INSERT mensaje user (prompt enviado)
            $insMsgUser = $conexion->prepare(
                "INSERT INTO ia_mensajes
                 (conversation_id, user_id, role, content, prompt_tokens, completion_tokens,
                  latency_ms, cost_usd, model, provider, error_code, error_message, created_at)
                 VALUES
                 (:cid, :uid, 'user', :content, 0, 0, 0, 0, :model, :provider, NULL, NULL, NOW())"
            );
            $insMsgUser->execute([
                ':cid'      => $convId,
                ':uid'      => $userId,
                ':content'  => mb_substr($prompt, 0, 16000),
                ':model'    => 'deepseek-chat',
                ':provider' => 'deepseek',
            ]);

            // 2b. INSERT mensaje assistant (respuesta recibida — exitosa o con error)
            $insMsgAs = $conexion->prepare(
                "INSERT INTO ia_mensajes
                 (conversation_id, user_id, role, content, prompt_tokens, completion_tokens,
                  latency_ms, cost_usd, model, provider, error_code, error_message, created_at)
                 VALUES
                 (:cid, :uid, 'assistant', :content, :pt, :ct, :lat, :cost,
                  :model, :provider, :ec, :em, NOW())"
            );
            $insMsgAs->execute([
                ':cid'      => $convId,
                ':uid'      => $userId,
                ':content'  => mb_substr($respuesta, 0, 16000),
                ':pt'       => $promptTokens,
                ':ct'       => $completionTokens,
                ':lat'      => $latencyMs,
                ':cost'     => $costUsd,
                ':model'    => 'deepseek-chat',
                ':provider' => 'deepseek',
                ':ec'       => $errorCode ? mb_substr($errorCode, 0, 50) : null,
                ':em'       => $errorMessage ? mb_substr($errorMessage, 0, 4000) : null,
            ]);

            // 3. UPDATE conversación: message_count +2, total_tokens += N, costo += N, last_activity_at
            $updConv = $conexion->prepare(
                "UPDATE ia_conversaciones
                 SET message_count = message_count + 2,
                     total_tokens = total_tokens + :tokens,
                     estimated_cost_usd = estimated_cost_usd + :cost,
                     last_activity_at = NOW()
                 WHERE id = :cid"
            );
            $updConv->execute([
                ':tokens' => $promptTokens + $completionTokens,
                ':cost'   => $costUsd,
                ':cid'    => $convId,
            ]);

            $conexion->commit();
        } catch (Throwable $inner) {
            if ($conexion->inTransaction()) {
                $conexion->rollBack();
            }
            throw $inner;
        }
    } catch (Throwable $e) {
        // NO romper el flujo del endpoint IA — solo loggea.
        error_log('[IA][persist] fallo al persistir intercambio: ' . $e->getMessage());
    }
}

try {
    // -- 1. Contexto del estudiante --
    $stmtUser = $conexion->prepare(
        "SELECT nombre, colegio, ciudad, grado FROM usuarios WHERE moodle_id = :moodle_id LIMIT 1"
    );
    $stmtUser->execute([':moodle_id' => $moodle_id]);
    $usuario = $stmtUser->fetch(PDO::FETCH_ASSOC);

    $stmtSim = $conexion->prepare(
        "SELECT puntaje_global, fecha_realizacion FROM simulacro_resultados
         WHERE usuario_id = :moodle_id ORDER BY fecha_realizacion DESC LIMIT 1"
    );
    $stmtSim->execute([':moodle_id' => $moodle_id]);
    $simulacro = $stmtSim->fetch(PDO::FETCH_ASSOC);

    // -- 2. System prompt (SOLO ASCII, sin acentos ni caracteres especiales) --
    //    Esta es la clave del fix: elimina cualquier riesgo de encoding.
    $prompt_sistema = "Eres Saber+, tutor ICFES. Tono amigable, tuteo. Solo temas ICFES.";
    if ($usuario) {
        $nombre = explode(' ', (string)($usuario['nombre'] ?? 'Estudiante'))[0];
        $grado = (string)($usuario['grado'] ?? '11');
        $prompt_sistema .= " Alumno: {$nombre} ({$grado} grado).";
    }
    if ($simulacro) {
        $pts = (int)($simulacro['puntaje_global'] ?? 0);
        $prompt_sistema .= " Ultimo simulacro: {$pts} pts.";
    }
    $prompt_sistema .= " Max 250 tokens. Usa **negritas**.";

    // -- 3. Payload para DeepSeek --
    $worker_url = 'https://deepseek-proxy.instel91.workers.dev/';

    $payload = [
        "model" => "deepseek-chat",
        "messages" => [
            ["role" => "system", "content" => $prompt_sistema],
            ["role" => "user",   "content" => $mensaje_estudiante],
        ],
        "temperature" => 0.7,
        "max_tokens"  => 300,
    ];

    // json_encode robusto: si hay bytes invalidos, los sustituye en lugar de fallar
    $body_json = json_encode(
        $payload,
        JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE
    );
    if ($body_json === false) {
        error_log("[IA] json_encode FALLO: " . json_last_error_msg());
        ia_error('ERROR_JSON', 'Error interno al procesar el mensaje.');
    }

    // Log del body enviado (primeros 400 bytes para diagnostico)
    error_log("[IA] payload (" . strlen($body_json) . " bytes): " . substr($body_json, 0, 400));

    // -- 4. Llamada al Worker --
    $ch = curl_init($worker_url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $body_json);
    curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10);
    curl_setopt($ch, CURLOPT_TIMEOUT, 45);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);

    $t0 = microtime(true);
    $response  = curl_exec($ch);
    $latency_ms = (int)round((microtime(true) - $t0) * 1000);
    $httpcode  = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curl_errno = curl_errno($ch);
    $curl_error = curl_error($ch); // IMPORTANTE: capturar antes de cerrar
    curl_close($ch);

    if ($response === false || $curl_errno !== 0) {
        error_log("[IA][worker] Error de red (errno={$curl_errno}): {$curl_error} | URL={$worker_url}");
        ia_persistir($conexion, $moodle_id, $mensaje_estudiante, '', 0, 0, $latency_ms, 0.0,
            'SIN_CONEXION', "curl_errno={$curl_errno}: {$curl_error}");
        ia_error('SIN_CONEXION', 'No se pudo conectar con el tutor.');
    }

    $json = json_decode($response, true);

    if ($httpcode !== 200) {
        // Intentar extraer el mensaje real del Worker en varios formatos
        $err_msg = $json['error']['message']
            ?? $json['error']
            ?? $json['message']
            ?? 'Error desconocido del proxy';
        if (is_array($err_msg)) {
            $err_msg = json_encode($err_msg, JSON_UNESCAPED_UNICODE);
        }
        error_log("[IA][worker] HTTP {$httpcode} | msg={$err_msg} | body=" . substr($response, 0, 500));
        ia_persistir($conexion, $moodle_id, $mensaje_estudiante, '', 0, 0, $latency_ms, 0.0,
            'ERROR_PROVEEDOR', "HTTP {$httpcode}: {$err_msg}");
        ia_error('ERROR_PROVEEDOR', 'Error al conectar con el proveedor de IA.');
    }

    // -- 5. Extraer uso de tokens (ANTES del check de respuesta vacía para que estén disponibles) --
    $usage = $json['usage'] ?? [];
    $prompt_tokens     = (int)($usage['prompt_tokens'] ?? 0);
    $completion_tokens = (int)($usage['completion_tokens'] ?? 0);
    $total_tokens      = (int)($usage['total_tokens'] ?? 0);
    $cache_hit         = (int)($usage['prompt_cache_hit_tokens'] ?? 0);

    // -- 6. Extraer texto de la respuesta --
    $texto_ia = $json['choices'][0]['message']['content'] ?? '';
    if (trim($texto_ia) === '') {
        error_log("[IA][worker] Respuesta vacia: " . substr($response, 0, 500));
        ia_persistir(
            $conexion, $moodle_id, $mensaje_estudiante, '',
            $prompt_tokens, $completion_tokens, $latency_ms,
            ia_calcular_costo($prompt_tokens, $completion_tokens),
            'RESPUESTA_VACIA', 'Respuesta vacía del modelo'
        );
        ia_error('RESPUESTA_VACIA', 'El tutor no pudo generar una respuesta.');
    }
    $texto_ia = preg_replace('/^\xEF\xBB\xBF/', '', $texto_ia);

    error_log(sprintf(
        "[IA][TOKENS] user=%d | prompt=%d | completion=%d | total=%d | cache_hit=%d | latency=%dms",
        $moodle_id, $prompt_tokens, $completion_tokens, $total_tokens, $cache_hit, $latency_ms
    ));

    // Persistencia del intercambio completo en ia_mensajes + UPDATE conversación.
    // Si las tablas IA no existen (migración 010 pendiente), ia_persistir() hace no-op.
    $costo_usd_intercambio = ia_calcular_costo($prompt_tokens, $completion_tokens);
    ia_persistir(
        $conexion, $moodle_id, $mensaje_estudiante, $texto_ia,
        $prompt_tokens, $completion_tokens, $latency_ms, $costo_usd_intercambio
    );

    echo json_encode([
        "exito"     => true,
        "respuesta" => $texto_ia,
        "proveedor" => "deepseek_cloudflare",
        "usage"     => [
            "prompt_tokens"     => $prompt_tokens,
            "completion_tokens" => $completion_tokens,
            "total_tokens"      => $total_tokens,
            "cache_hit_tokens"  => $cache_hit,
        ],
    ], JSON_UNESCAPED_UNICODE);

} catch (Exception $e) {
    error_log("[IA][ERROR] " . $e->getMessage());
    ia_persistir($conexion, $moodle_id, $mensaje_estudiante, '', 0, 0, 0, 0.0,
        'ERROR_IA', $e->getMessage());
    ia_error('ERROR_IA', 'Error interno del servidor.');
}