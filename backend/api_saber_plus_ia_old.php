<?php
// api_saber_plus_ia.php — Tutor IA de Saber+ (vía Cloudflare Proxy)
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

    $response  = curl_exec($ch);
    $httpcode  = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curl_errno = curl_errno($ch);
    $curl_error = curl_error($ch); // ? IMPORTANTE: capturar antes de cerrar
    curl_close($ch);

    if ($response === false || $curl_errno !== 0) {
        error_log("[IA][worker] Error de red (errno={$curl_errno}): {$curl_error} | URL={$worker_url}");
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
        ia_error('ERROR_PROVEEDOR', 'Error al conectar con el proveedor de IA.');
    }

    // -- 5. Extraer texto de la respuesta --
    $texto_ia = $json['choices'][0]['message']['content'] ?? '';
    if (trim($texto_ia) === '') {
        error_log("[IA][worker] Respuesta vacia: " . substr($response, 0, 500));
        ia_error('RESPUESTA_VACIA', 'El tutor no pudo generar una respuesta.');
    }
    $texto_ia = preg_replace('/^\xEF\xBB\xBF/', '', $texto_ia);

    // -- 6. Medición de tokens --
    $usage = $json['usage'] ?? [];
    $prompt_tokens     = (int)($usage['prompt_tokens'] ?? 0);
    $completion_tokens = (int)($usage['completion_tokens'] ?? 0);
    $total_tokens      = (int)($usage['total_tokens'] ?? 0);
    $cache_hit         = (int)($usage['prompt_cache_hit_tokens'] ?? 0);

    error_log(sprintf(
        "[IA][TOKENS] user=%d | prompt=%d | completion=%d | total=%d | cache_hit=%d",
        $moodle_id, $prompt_tokens, $completion_tokens, $total_tokens, $cache_hit
    ));

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
    ia_error('ERROR_IA', 'Error interno del servidor.');
}