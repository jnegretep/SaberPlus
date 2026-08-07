
<?php
require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php'; // ? conexión correcta

use Kreait\Firebase\Factory;
use Kreait\Firebase\Messaging\CloudMessage;
use Kreait\Firebase\Messaging\Notification;

// ?? Forzar PHP a trabajar en UTF-8
mb_internal_encoding("UTF-8");
ini_set('default_charset', 'UTF-8');
header("Content-Type: application/json; charset=UTF-8");

// ?? Forzar conexión a UTF-8 en cada request
$conexion->exec("SET NAMES utf8mb4");
$conexion->exec("SET CHARACTER SET utf8mb4");
$conexion->exec("SET COLLATION_CONNECTION = utf8mb4_unicode_ci");

// ?? Inicializar Firebase
$factory = (new Factory)->withServiceAccount(__DIR__.'/saberplus-1ec41-firebase-adminsdk-fbsvc-23a4103b63.json');
$messaging = $factory->createMessaging();

// ?? Capturar body crudo
$rawBody = file_get_contents("php://input");
$data = json_decode($rawBody, true);

// ?? Convertir todos los strings del JSON a UTF-8 solo si no son válidos
if (is_array($data)) {
    array_walk_recursive($data, function (&$item) {
        if (is_string($item) && !mb_check_encoding($item, 'UTF-8')) {
            $item = mb_convert_encoding($item, 'UTF-8', 'Windows-1252, ISO-8859-1');
        }
    });
}

$title = $data['title'] ?? "Aviso general Saber+";
$body  = $data['body'] ?? "Tienes una nueva actualización";

// ?? Convertir los literales del archivo si el archivo estuviera guardado en latin1
if (!mb_check_encoding($title, 'UTF-8')) {
    $title = mb_convert_encoding($title, 'UTF-8', 'Windows-1252, ISO-8859-1');
}
if (!mb_check_encoding($body, 'UTF-8')) {
    $body = mb_convert_encoding($body, 'UTF-8', 'Windows-1252, ISO-8859-1');
}

// ?? Logs de depuración (incluye bytes hex para ver codificación)
error_log("[send_notification_all][DEBUG] title=".$title." body=".$body);
error_log("[send_notification_all][HEX] title=".bin2hex($title)." body=".bin2hex($body));

// ?? Consultar todos los tokens
$stmt = $conexion->query("SELECT id_usuario, fcm_token FROM usuarios WHERE fcm_token IS NOT NULL");
$usuarios = $stmt->fetchAll(PDO::FETCH_ASSOC);

if (!$usuarios) {
    echo json_encode(["success" => false, "message" => "No hay tokens registrados"], JSON_UNESCAPED_UNICODE);
    exit;
}

$tokens = array_column($usuarios, 'fcm_token');

// ?? Crear mensaje base
$message = CloudMessage::new()
    ->withNotification(Notification::create($title, $body))
    ->withData(["click_action" => "FLUTTER_NOTIFICATION_CLICK"]);

try {
    $report = $messaging->sendMulticast($message, $tokens);

    // ?? Guardar en tabla notifications para cada usuario
    $stmtInsert = $conexion->prepare("
        INSERT INTO notifications (user_id, type, title, body, payload_json)
        VALUES (:user_id, :type, :title, :body, :payload_json)
    ");

    foreach ($usuarios as $u) {
        // payload vacío (pero conservando codificación)
        $payload = json_encode([], JSON_UNESCAPED_UNICODE);
        error_log("[send_notification_all][PAYLOAD] user_id={$u['id_usuario']} ".$payload);

        // ?? Log de depuración antes de insertar
        error_log("[send_notification_all][DEBUG INSERT] user_id={$u['id_usuario']} title=".$title." body=".$body);

        $stmtInsert->execute([
            ":user_id" => $u['id_usuario'],
            ":type" => "masiva",
            ":title" => $title,
            ":body" => $body,
            ":payload_json" => $payload
        ]);
    }

    echo json_encode([
        "success" => true,
        "total" => count($tokens),
        "enviadas" => $report->successes()->count(),
        "fallidas" => $report->failures()->count()
    ], JSON_UNESCAPED_UNICODE);
} catch (\Throwable $e) {
    error_log("[send_notification_all][ERROR] ".$e->getMessage());
    http_response_code(500);
    echo json_encode(["success" => false, "error" => $e->getMessage()], JSON_UNESCAPED_UNICODE);
}