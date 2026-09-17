<?php
session_start();
require_once __DIR__ . '/../vendor/autoload.php';
require_once __DIR__ . '/../includes/conexion.php';
require_once __DIR__ . '/../includes/config.php';

use Kreait\Firebase\Factory;
use Kreait\Firebase\Messaging\CloudMessage;
use Kreait\Firebase\Messaging\Notification;

if (!isset($_SESSION['admin_logged_in']) || $_SESSION['admin_logged_in'] !== true) {
    header('Location: index.php');
    exit;
}

 $title = trim($_POST['title'] ?? '');
 $body = trim($_POST['body'] ?? '');
 $type = trim($_POST['type'] ?? 'info');

if (empty($title) || empty($body)) {
    header('Location: index.php?section=notifications&error=empty');
    exit;
}

try {
    $factory = (new Factory)->withServiceAccount(__DIR__ . '/../config/firebase-service-account.json');
    $messaging = $factory->createMessaging();
} catch (Exception $e) {
    die("Error Firebase: " . $e->getMessage());
}

 $stmt = $conexion->query("SELECT id_usuario, fcm_token FROM usuarios WHERE fcm_token IS NOT NULL AND fcm_token != '' AND email_verificado = 1");
 $users = $stmt->fetchAll(PDO::FETCH_ASSOC);

 $sent = 0;
 $failed = 0;

foreach ($users as $user) {
    $userId = (int)$user['id_usuario'];
    $fcmToken = $user['fcm_token'];
    try {
        $message = CloudMessage::withTarget('token', $fcmToken)
            ->withNotification(Notification::create($title, $body))
            ->withData(['type' => $type, 'title' => $title, 'body' => $body, 'click_action' => 'FLUTTER_NOTIFICATION_CLICK', 'action' => 'go_dashboard']);
        $messaging->send($message);
        $stmt = $conexion->prepare("INSERT INTO notifications (user_id, type, title, body, data, created_at) VALUES (?, ?, ?, ?, ?, NOW())");
        $stmt->execute([$userId, $type, $title, $body, json_encode(['action' => 'go_dashboard'])]);
        $sent++;
    } catch (Exception $e) {
        $failed++;
    }
    usleep(50000);
}
header("Location: index.php?section=notifications&sent={$sent}&failed={$failed}");
exit;