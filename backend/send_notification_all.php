<?php
declare(strict_types=1);

/**
 * send_notification_all.php — Notificación masiva a todos los usuarios con FCM.
 *
 * v2.1 (2026-11-07) — FIX CRÍTICO:
 *   - ? Antes usaba `sendMulticast()` ? `/batch` legacy ? HTTP 404.
 *   - ? Ahora itera con `send()` individual (FCM v1).
 *   - Se mantiene: guard admin, limpieza de tokens, bandeja interna, canal Android.
 */

require_once __DIR__ . '/vendor/autoload.php';
require_once __DIR__ . '/includes/conexion.php';
require_once __DIR__ . '/includes/firebase_factory.php';

use Kreait\Firebase\Messaging\CloudMessage;
use Kreait\Firebase\Messaging\Notification;

header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: Content-Type, Authorization, X-Internal-Token");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit(json_encode(['success' => false, 'error' => 'Método no permitido']));
}

// ? Ampliar timeout
@set_time_limit(600);
@ini_set('max_execution_time', '600');

// ?? Guard: admin o token interno
saberplus_guard_admin_fcm();

mb_internal_encoding("UTF-8");
$conexion->exec("SET NAMES utf8mb4");

// -- Body --
$rawBody = file_get_contents("php://input");
$data = json_decode($rawBody, true) ?? [];

array_walk_recursive($data, function (&$item) {
    if (is_string($item) && !mb_check_encoding($item, 'UTF-8')) {
        $item = mb_convert_encoding($item, 'UTF-8', 'Windows-1252, ISO-8859-1');
    }
});

$title  = trim((string)($data['title'] ?? ''));
$body   = trim((string)($data['body'] ?? ''));
$type   = trim((string)($data['type'] ?? 'info'));
$action = trim((string)($data['action'] ?? 'go_dashboard'));

if ($title === '' || $body === '') {
    http_response_code(400);
    exit(json_encode(['success' => false, 'error' => 'Faltan título y cuerpo'], JSON_UNESCAPED_UNICODE));
}

try {
    $messaging = saberplus_fcm_messaging();
} catch (Throwable $e) {
    error_log('[SEND_ALL] Firebase init: ' . $e->getMessage());
    http_response_code(500);
    exit(json_encode(['success' => false, 'error' => 'Configuración Firebase: ' . $e->getMessage()], JSON_UNESCAPED_UNICODE));
}

// -- Consultar tokens válidos --
$stmt = $conexion->query(
    "SELECT id_usuario, fcm_token FROM usuarios
     WHERE fcm_token IS NOT NULL AND fcm_token != '' AND email_verificado = 1"
);
$usuarios = $stmt->fetchAll(PDO::FETCH_ASSOC);

if (!$usuarios) {
    echo json_encode(['success' => false, 'error' => 'No hay dispositivos registrados todavía. Instala la app actualizada, inicia sesión y vuelve a probar.'], JSON_UNESCAPED_UNICODE);
    exit;
}

$tokensMuertos = [];
$enviadas = 0;
$fallidas = 0;

// ? Envío individual (uno por uno) — evita `/batch` legacy roto
foreach ($usuarios as $u) {
    $token = trim((string)$u['fcm_token']);
    if ($token === '') continue;

    try {
        $message = CloudMessage::withTarget('token', $token)
            ->withNotification(Notification::create($title, $body))
            ->withData([
                'type' => $type,
                'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                'action' => $action,
            ])
            ->withAndroidConfig([
                'priority' => 'high',
                'notification' => [
                    'channel_id' => 'saberplus_notificaciones',
                    'sound' => 'default',
                ],
            ]);

        $messaging->send($message);
        $enviadas++;
        usleep(30000); // 30 ms entre envíos
    } catch (Throwable $t) {
        $fallidas++;
        $err = $t->getMessage();
        error_log('[SEND_ALL] user=' . $u['id_usuario'] . ' error: ' . $err);
        if (saberplus_fcm_token_muerto($err)) {
            $tokensMuertos[] = $token;
        }
    }
}

// ?? Limpiar tokens muertos reportados
$limpiados = !empty($tokensMuertos)
    ? saberplus_fcm_limpiar_tokens(array_values(array_unique($tokensMuertos)), $conexion)
    : 0;

// -- Guardar en bandeja interna --
$stmtInsert = $conexion->prepare("
    INSERT INTO notifications (user_id, type, title, body, payload_json)
    VALUES (:user_id, :type, :title, :body, :payload_json)
");
$payload = json_encode(['action' => $action], JSON_UNESCAPED_UNICODE);
foreach ($usuarios as $u) {
    try {
        $stmtInsert->execute([
            ':user_id' => $u['id_usuario'],
            ':type' => $type,
            ':title' => $title,
            ':body' => $body,
            ':payload_json' => $payload,
        ]);
    } catch (Throwable $t) {
        error_log('[SEND_ALL] Insert notificación user ' . $u['id_usuario'] . ': ' . $t->getMessage());
    }
}

echo json_encode([
    'success'  => true,
    'total'    => count($usuarios),
    'enviadas' => $enviadas,
    'fallidas' => $fallidas,
    'tokens_limpiados' => $limpiados,
], JSON_UNESCAPED_UNICODE);