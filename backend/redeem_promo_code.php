<?php
declare(strict_types=1);
// redeem_promo_code.php
// ═══════════════════════════════════════════════════════════════════
// Canje de códigos Premium desde la app (Perfil → Planes).
//
//   POST JSON { "codigo": "..." } + JWT Bearer (patrón save_fcm_token.php)
//   → registra el canje en codigos_premium_usos (migración 008) y activa
//     access_level='premium' + unlocked_at=NOW() — la misma activación que
//     un pago Wompi aprobado (wompi_webhook.php), pero por id_usuario.
//
// Reglas de negocio:
//   - Rate limit: 8 intentos / 10 min por IP+usuario (patrón flock register.php).
//   - Código inexistente / deshabilitado / vencido → 404 genérico (no se
//     revela cuál fue la causa).
//   - Cupo agotado (usos >= max_usos) → 409 codigo_agotado.
//   - El mismo usuario no puede canjear el mismo código dos veces → 409.
//   - Usuario ya premium/early_bird: el canje se registra igual, pero NUNCA
//     se degrada su plan (respuesta incluye ya_era_premium: true).
// ═══════════════════════════════════════════════════════════════════

// Sin salida de errores al cliente (solo error_log con contexto)
ini_set('display_errors', 0);
ini_set('display_startup_errors', 0);
error_reporting(E_ALL);

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/includes/config.php';
$configJwt = require __DIR__ . '/jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit(json_encode(['status' => 'error', 'code' => 'metodo_no_permitido', 'msg' => 'Método no permitido'], JSON_UNESCAPED_UNICODE));
}

/**
 * Respuesta de error uniforme. Termina el request.
 * Nunca expone trazas ni detalles internos: eso va al error_log.
 */
function redeem_error(int $http, string $code, string $msg): void
{
    http_response_code($http);
    exit(json_encode(['status' => 'error', 'code' => $code, 'msg' => $msg], JSON_UNESCAPED_UNICODE));
}

// ── Auth JWT (patrón de save_fcm_token.php) ──
$hdrs = function_exists('getallheaders') ? getallheaders() : [];
$authHeader = $hdrs['Authorization'] ?? $hdrs['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';

if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
    redeem_error(401, 'no_autorizado', 'No autorizado');
}

try {
    $decoded = JWT::decode($m[1], new Key($configJwt['secret'], 'HS256'));
    $userId = (int)($decoded->data->id_usuario ?? 0);
    if ($userId <= 0) {
        redeem_error(401, 'usuario_no_valido', 'Usuario no válido');
    }
} catch (Exception $e) {
    redeem_error(401, 'token_invalido', 'Token inválido');
}

// ── Rate limit: 8 intentos / 10 min por IP+usuario (patrón flock de register.php) ──
function redeem_rate_limit_excedido(int $userId): bool
{
    $clave = ($_SERVER['REMOTE_ADDR'] ?? 'desconocida') . '|' . $userId;
    $archivo = sys_get_temp_dir() . '/saberplus_rl_redeem_' . md5($clave) . '.json';
    $fp = @fopen($archivo, 'c+');
    if ($fp === false) {
        return false; // si /tmp falla, no bloquear el canje
    }
    $ahora = time();
    $ventana = 600;  // 10 minutos
    $maximos = 8;    // 8 intentos por ventana
    $timestamps = [];
    $permitido = true;
    try {
        if (flock($fp, LOCK_EX)) {
            $raw = stream_get_contents($fp);
            if (is_string($raw) && $raw !== '') {
                $dec = json_decode($raw, true);
                if (is_array($dec)) {
                    foreach ($dec as $t) {
                        if (is_numeric($t) && ($ahora - (int)$t) < $ventana) {
                            $timestamps[] = (int)$t;
                        }
                    }
                }
            }
            $permitido = count($timestamps) < $maximos;
            if ($permitido) {
                $timestamps[] = $ahora;
            }
            ftruncate($fp, 0);
            rewind($fp);
            fwrite($fp, json_encode($timestamps));
            fflush($fp);
            flock($fp, LOCK_UN);
        }
    } finally {
        fclose($fp);
    }
    return !$permitido;
}

if (redeem_rate_limit_excedido($userId)) {
    error_log('[REDEEM] Rate limit excedido: user=' . $userId . ' ip=' . ($_SERVER['REMOTE_ADDR'] ?? '?'));
    redeem_error(429, 'rate_limit', 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.');
}

// ── Body JSON {codigo} (normaliza: trim + MAYÚSCULAS) ──
$body = json_decode((string)file_get_contents('php://input'), true);
if (!is_array($body)) {
    redeem_error(400, 'json_invalido', 'JSON inválido');
}
$codigo = strtoupper(trim((string)($body['codigo'] ?? '')));

$codigoId = 0;

try {
    // ── Validación del código (mensaje genérico: no revelar la causa) ──
    // vence_en se compara en SQL contra NOW() para mantener una sola zona
    // horaria (la sesión MySQL de conexion.php es UTC).
    $stmt = $conexion->prepare("
        SELECT id, max_usos
        FROM codigos_premium
        WHERE codigo = :c
          AND estado = 'activo'
          AND (vence_en IS NULL OR vence_en >= NOW())
        LIMIT 1
    ");
    $stmt->execute([':c' => $codigo]);
    $filaCodigo = $stmt->fetch(PDO::FETCH_ASSOC);

    if ($filaCodigo === false) {
        redeem_error(404, 'codigo_invalido', 'Código inválido o expirado');
    }

    $codigoId = (int)$filaCodigo['id'];
    $maxUsos  = (int)$filaCodigo['max_usos'];

    // ── Cupo total del código ──
    $stmt = $conexion->prepare("SELECT COUNT(*) FROM codigos_premium_usos WHERE codigo_id = :cid");
    $stmt->execute([':cid' => $codigoId]);
    if ((int)$stmt->fetchColumn() >= $maxUsos) {
        redeem_error(409, 'codigo_agotado', 'Este código ya alcanzó su número máximo de usos');
    }

    // ── ¿Ya lo usó este usuario? (mensaje claro, sí se puede revelar) ──
    $stmt = $conexion->prepare("SELECT COUNT(*) FROM codigos_premium_usos WHERE codigo_id = :cid AND id_usuario = :u");
    $stmt->execute([':cid' => $codigoId, ':u' => $userId]);
    if ((int)$stmt->fetchColumn() > 0) {
        redeem_error(409, 'ya_utilizado', 'Ya utilizaste este código anteriormente');
    }

    // ── TRANSACCIÓN: registrar el canje + activar Premium ──
    $conexion->beginTransaction();
    try {
        // Lock pesimista del código: serializa canjes concurrentes del último cupo
        $stmtLock = $conexion->prepare("SELECT id, max_usos FROM codigos_premium WHERE id = :id FOR UPDATE");
        $stmtLock->execute([':id' => $codigoId]);
        $filaLock = $stmtLock->fetch(PDO::FETCH_ASSOC);
        if ($filaLock === false) {
            $conexion->rollBack();
            redeem_error(404, 'codigo_invalido', 'Código inválido o expirado');
        }

        // Re-verificar el cupo dentro del lock (evita la carrera por el último cupo)
        $stmt = $conexion->prepare("SELECT COUNT(*) FROM codigos_premium_usos WHERE codigo_id = :cid");
        $stmt->execute([':cid' => $codigoId]);
        if ((int)$stmt->fetchColumn() >= (int)$filaLock['max_usos']) {
            $conexion->rollBack();
            redeem_error(409, 'codigo_agotado', 'Este código ya alcanzó su número máximo de usos');
        }

        // Registrar el canje. Si hay carrera de doble canje del mismo usuario,
        // la UNIQUE KEY uq_codigo_usuario lanza 23000 → 409 ya_utilizado.
        $stmt = $conexion->prepare("INSERT INTO codigos_premium_usos (codigo_id, id_usuario) VALUES (:cid, :u)");
        $stmt->execute([':cid' => $codigoId, ':u' => $userId]);

        // Nivel actual: premium/early_bird NO se degrada ni se re-escribe
        $stmt = $conexion->prepare("SELECT access_level FROM usuarios WHERE id_usuario = :u LIMIT 1");
        $stmt->execute([':u' => $userId]);
        $nivelActual = $stmt->fetchColumn();
        if ($nivelActual === false) {
            // JWT apunta a un usuario inexistente — no dejar el canje huérfano
            $conexion->rollBack();
            error_log('[REDEEM] Usuario inexistente pese a JWT válido: user=' . $userId);
            redeem_error(401, 'usuario_no_valido', 'Usuario no válido');
        }
        $yaEraPremium = in_array($nivelActual, ['premium', 'early_bird'], true);

        if (!$yaEraPremium) {
            // Misma activación que wompi_webhook.php (APPROVED), pero por id_usuario
            $stmt = $conexion->prepare("
                UPDATE usuarios
                SET access_level = 'premium',
                    unlocked_at = NOW()
                WHERE id_usuario = :u AND access_level IN ('free', 'trial')
            ");
            $stmt->execute([':u' => $userId]);
        }

        $conexion->commit();
    } catch (PDOException $exTx) {
        if ($conexion->inTransaction()) {
            $conexion->rollBack();
        }
        // Carrera: el mismo usuario canjeó en paralelo → UNIQUE (codigo_id, id_usuario)
        if ($exTx->getCode() === '23000') {
            redeem_error(409, 'ya_utilizado', 'Ya utilizaste este código anteriormente');
        }
        throw $exTx; // re-lanzar al handler exterior (log + 500/503)
    }

    // ── Éxito ──
    error_log('[REDEEM] Canje OK: user=' . $userId . ' codigo_id=' . $codigoId . ($yaEraPremium ? ' (ya era premium)' : ' (premium activado)'));
    $respuesta = [
        'status'  => 'ok',
        'message' => '¡Código canjeado! Ahora tienes acceso Premium',
        'plan'    => 'premium',
    ];
    if ($yaEraPremium) {
        $respuesta['ya_era_premium'] = true;
    }
    http_response_code(200);
    exit(json_encode($respuesta, JSON_UNESCAPED_UNICODE));

} catch (PDOException $ex) {
    // Migración 008 sin ejecutar (tabla inexistente) → 503; el detalle va al log
    if ($ex->getCode() === '42S02') {
        error_log('[REDEEM] Tabla codigos_premium/codigos_premium_usos inexistente — ejecuta backend/migrations/008_codigos_premium.sql. Detalle: ' . $ex->getMessage());
        redeem_error(503, 'sistema_no_disponible', 'El canje de códigos no está disponible temporalmente. Por favor inténtalo más tarde.');
    }
    error_log('[REDEEM] Error BD: user=' . $userId . ' codigo_id=' . $codigoId . ' — ' . $ex->getMessage());
    redeem_error(500, 'error_interno', 'Error interno. Por favor inténtalo más tarde.');
} catch (Throwable $ex) {
    error_log('[REDEEM] Error inesperado: user=' . $userId . ' — ' . $ex->getMessage());
    redeem_error(500, 'error_interno', 'Error interno. Por favor inténtalo más tarde.');
}
