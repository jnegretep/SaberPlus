<?php
declare(strict_types=1);

/**
 * registrar_evento.php — Saber+ v1.6.0
 *
 * Recibe eventos de analítica de la app y los guarda en `app_events`
 * (espejo propio de Firebase Analytics para el panel de administración).
 *
 * Seguridad:
 *  - Requiere JWT válido.
 *  - Whitelist estricta de nombres de evento (evita usar la tabla
 *    como escritura libre / spam).
 *  - Payload `params` acotado a 2 KB.
 *  - Manejado como fire-and-forget: la app nunca bloquea por esto.
 *
 * Evento especial: `app_error` → además de app_events, inserta en
 * `error_logs` (source='app') para el visor de errores del admin.
 *
 * Request:
 *   POST /registrar_evento.php
 *   Authorization: Bearer <jwt>
 *   { "event_name": "simulacro_completed", "params": {"score": 320},
 *     "app_version": "1.6.0" }
 *
 * Response:
 *   { "status": "ok" }
 */

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require __DIR__ . '/auth_middleware.php';
require __DIR__ . '/includes/analytics.php';


if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
}

$user_id = (int)($authUser['id_usuario'] ?? 0);
if ($user_id <= 0) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Usuario no válido']));
}

// ── Whitelist de eventos permitidos ──
$EVENTOS_PERMITIDOS = [
    // Sesión
    'login', 'login_failed', 'sign_up', 'logout',
    // Núcleo de estudio
    'screen_view', 'simulacro_started', 'simulacro_completed',
    'quiz_started', 'quiz_completed', 'curso_viewed', 'contenido_viewed',
    // Gamificación
    'challenge_created', 'challenge_completed', 'badge_unlocked',
    'ranking_viewed', 'daily_challenge_completed', 'level_up',
    // Monetización
    'paywall_viewed', 'purchase_started', 'purchase_completed', 'ad_shown',
    // Social / growth
    'share_clicked', 'invitation_sent',
    // IA
    'ai_chat_opened', 'ai_chat_message',
    // Soporte / errores
    'app_error', 'help_center_opened', 'rate_app_opened',
    // Cuenta
    'account_delete_started', 'account_deleted',
];

$input = json_decode(file_get_contents('php://input'), true) ?: [];
$eventName  = trim((string)($input['event_name'] ?? ''));
$params     = is_array($input['params'] ?? null) ? $input['params'] : [];
$appVersion = isset($input['app_version']) ? substr(trim((string)$input['app_version']), 0, 24) : null;
$platform   = isset($input['platform']) ? substr(trim((string)$input['platform']), 0, 16) : null;

if ($platform !== null && !in_array($platform, ['android', 'ios', 'web'], true)) {
    $platform = null;
}

if ($eventName === '' || !in_array($eventName, $EVENTOS_PERMITIDOS, true)) {
    // No revelamos la lista completa; simplemente rechazamos
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'Evento no permitido']));
}

// Acotar params a claves simples y 16 valores
$params = array_slice($params, 0, 16, true);
foreach ($params as $k => $v) {
    if (!is_scalar($v)) {
        $params[$k] = json_encode($v);
    } elseif (is_string($v)) {
        $params[$k] = mb_substr($v, 0, 256);
    }
}

try {
    // ── Evento de error → también a error_logs ──
    if ($eventName === 'app_error') {
        saberplus_log_error(
            $conexion,
            'app',
            (string)($params['message'] ?? 'Error reportado por la app'),
            $params,
            (string)($params['code'] ?? null) ?: null,
            'error',
            $user_id,
            isset($params['stack']) ? (string)$params['stack'] : null
        );
    }

    saberplus_registrar_evento($conexion, $user_id, $eventName, $params, $platform, $appVersion);

    echo json_encode(['status' => 'ok']);

} catch (Throwable $e) {
    error_log('[REGISTRAR_EVENTO] Error: ' . $e->getMessage());
    // Fire-and-forget: la app no necesita distinguir fallos aquí
    http_response_code(200);
    exit(json_encode(['status' => 'ok']));
}
