<?php
/**
 * admin/send_bulk.php — Envío masivo de notificaciones FCM desde el panel.
 *
 * v2.1 (2026-11-07) — FIX CRÍTICO:
 *   - ? Antes usaba `sendMulticast()` ? internamente llama a `/batch`
 *     (endpoint legacy apagado por Google en junio 2024) ? HTTP 404.
 *   - ? Ahora itera con `send()` individual (que ya usa FCM v1 correctamente).
 *     Más lento pero 100% funcional con kreait/firebase-php v6/v7.
 *   - Se mantiene: limpieza de tokens muertos, bandeja interna, canal Android.
 */
session_start();
require_once __DIR__ . '/../vendor/autoload.php';
require_once __DIR__ . '/../includes/conexion.php';
require_once __DIR__ . '/../includes/config.php';

use Kreait\Firebase\Messaging\CloudMessage;
use Kreait\Firebase\Messaging\Notification;

if (!isset($_SESSION['admin_logged_in']) || $_SESSION['admin_logged_in'] !== true) {
    header('Location: index.php');
    exit;
}

// ? Ampliar timeout: para 500 usuarios × ~200ms = ~100s
@set_time_limit(600);
@ini_set('max_execution_time', '600');

$title = trim($_POST['title'] ?? '');
$body  = trim($_POST['body'] ?? '');
$type  = trim($_POST['type'] ?? 'info');

if (empty($title) || empty($body)) {
    header('Location: index.php?section=notifications&error=empty');
    exit;
}

require_once __DIR__ . '/../includes/firebase_factory.php';
try {
    $messaging = saberplus_fcm_messaging();
} catch (Exception $e) {
    die("Error Firebase: " . $e->getMessage());
}

// -- Detectar columna de bandeja disponible (payload_json preferida) --
$columnaPayload = 'payload_json';
try {
    $cols = $conexion->query("SHOW COLUMNS FROM notifications LIKE 'payload_json'")->fetchAll();
    if (empty($cols)) {
        $colsData = $conexion->query("SHOW COLUMNS FROM notifications LIKE 'data'")->fetchAll();
        $columnaPayload = !empty($colsData) ? 'data' : null;
    }
} catch (Throwable $t) {
    $columnaPayload = null;
    error_log('[SEND_BULK] SHOW COLUMNS notifications: ' . $t->getMessage());
}

$stmt = $conexion->query(
    "SELECT id_usuario, fcm_token FROM usuarios
     WHERE fcm_token IS NOT NULL AND fcm_token != '' AND email_verificado = 1"
);
$users = $stmt->fetchAll(PDO::FETCH_ASSOC);

$total   = count($users);
$success = 0;
$failed  = 0;
$tokensMuertos = [];

// ? Envío individual (uno por uno) — evita `/batch` legacy roto
foreach ($users as $u) {
    $token = trim((string)$u['fcm_token']);
    if ($token === '') continue;

    try {
        $message = CloudMessage::withTarget('token', $token)
            ->withNotification(Notification::create($title, $body))
            ->withData([
                'type' => $type,
                'title' => $title,
                'body' => $body,
                'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                'action' => 'go_dashboard',
            ])
            ->withAndroidConfig([
                'priority' => 'high',
                'notification' => [
                    'channel_id' => 'saberplus_notificaciones',
                    'sound' => 'default',
                ],
            ]);

        $messaging->send($message);
        $success++;

        // Pequeña pausa para no saturar FCM
        usleep(30000); // 30 ms
    } catch (Throwable $t) {
        $failed++;
        $err = $t->getMessage();
        error_log('[SEND_BULK] user=' . $u['id_usuario'] . ' error: ' . $err);
        if (saberplus_fcm_token_muerto($err)) {
            $tokensMuertos[] = $token;
        }
    }
}

// -- Bandeja interna (independiente del resultado del envío push) --
if ($columnaPayload !== null) {
    $stmtInsert = $conexion->prepare(
        "INSERT INTO notifications (user_id, type, title, body, {$columnaPayload}, created_at)
         VALUES (:user_id, :type, :title, :body, :payload, NOW())"
    );
    $payloadJson = json_encode(['action' => 'go_dashboard'], JSON_UNESCAPED_UNICODE);
    foreach ($users as $u) {
        try {
            $stmtInsert->execute([
                ':user_id' => $u['id_usuario'],
                ':type'    => $type,
                ':title'   => $title,
                ':body'    => $body,
                ':payload' => $payloadJson,
            ]);
        } catch (Throwable $t) {
            error_log('[SEND_BULK] Insert notificación user ' . $u['id_usuario'] . ': ' . $t->getMessage());
        }
    }
} else {
    error_log('[SEND_BULK] Tabla notifications sin columna payload_json/data: bandeja omitida');
}

// ?? Limpieza de tokens muertos
if (!empty($tokensMuertos)) {
    saberplus_fcm_limpiar_tokens(array_values(array_unique($tokensMuertos)), $conexion);
}

header("Location: index.php?section=notifications&sent={$success}&failed={$failed}&total={$total}");
exit;