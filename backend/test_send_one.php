<?php
require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';

use Kreait\Firebase\Factory;
use Kreait\Firebase\Messaging\CloudMessage;
use Kreait\Firebase\Messaging\Notification;

// 1. Verificar que el service account existe
$saPath = __DIR__ . '/config/firebase-service-account.json';
if (!file_exists($saPath)) {
    die("? FALTA: $saPath\n");
}

// 2. Datos del usuario (cambia el email si es necesario)
$email = 'saberplus2026@gmail.com';
$stmt = $conexion->prepare("SELECT id_usuario, nombre, fcm_token FROM usuarios WHERE email = ?");
$stmt->execute([$email]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$user) {
    die("? Usuario $email no encontrado\n");
}
if (empty($user['fcm_token'])) {
    die("? Usuario {$user['id_usuario']} no tiene fcm_token. Abre la app y logueate primero.\n");
}

echo "Usuario: {$user['nombre']} (ID: {$user['id_usuario']})\n";
echo "Token: " . substr($user['fcm_token'], 0, 40) . "...\n\n";

// 3. Inicializar Firebase
try {
    $factory = (new Factory)->withServiceAccount($saPath);
    $messaging = $factory->createMessaging();

    // 4. Enviar
    $message = CloudMessage::withTarget('token', $user['fcm_token'])
        ->withNotification(Notification::create(
            'Prueba Saber+',
            "Hola {$user['nombre']}, esta es una notificación de prueba ??"
        ))
        ->withData([
            'action' => 'go_dashboard',
            'type' => 'test'
        ]);

    $messaging->send($message);
    echo "? Notificación enviada exitosamente\n";
    echo "Revisa el celular en los próximos 5 segundos.\n";

} catch (Throwable $e) {
    echo "? ERROR:\n";
    echo get_class($e) . ": " . $e->getMessage() . "\n";
}