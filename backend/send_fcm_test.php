<?php
// /var/www/html/api/prepsaber/backend/send_fcm_test.php

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';

use Kreait\Firebase\Factory;
use Kreait\Firebase\Messaging\CloudMessage;
use Kreait\Firebase\Messaging\Notification;

mb_internal_encoding("UTF-8");

$factory = (new Factory)->withServiceAccount(__DIR__.'/saberplus-1ec41-firebase-adminsdk-fbsvc-23a4103b63.json');
$messaging = $factory->createMessaging();

try {
    $id_usuario = 33;

    $stmt = $conexion->prepare("SELECT fcm_token FROM usuarios WHERE id_usuario = ?");
    $stmt->execute([$id_usuario]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row || empty($row['fcm_token'])) {
        die("?? No se encontró token FCM para el usuario $id_usuario\n");
    }

    $fcmToken = $row['fcm_token'];

    // ? Forzar UTF-8 limpio
    $title = "Prueba Saber+";
    $body  = "Hola Carolina, esta es una notificacion de prueba"; // sin acentos ni emojis para probar

    $notification = Notification::create($title, $body);

    $data = [
        "tipo" => "test",
        "id_usuario" => (string)$id_usuario
    ];

    $message = CloudMessage::withTarget('token', $fcmToken)
        ->withNotification($notification)
        ->withData($data);

    $result = $messaging->send($message);

    echo "? Notificación enviada a user_id=$id_usuario\n";
    var_dump($result);

} catch (\Throwable $e) {
    echo "? Error enviando notificación: ".$e->getMessage()."\n";
}
