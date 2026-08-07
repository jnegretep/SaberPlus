<?php
require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';

use Kreait\Firebase\Factory;
use Kreait\Firebase\Messaging\CloudMessage;
use Kreait\Firebase\Messaging\Notification;

mb_internal_encoding("UTF-8");
ini_set('default_charset', 'UTF-8');
header("Content-Type: application/json; charset=UTF-8");

$conexion->exec("SET time_zone = '+00:00'");
$conexion->exec("SET NAMES utf8mb4");
$conexion->exec("SET CHARACTER SET utf8mb4");
$conexion->exec("SET COLLATION_CONNECTION = utf8mb4_unicode_ci");

$factory = (new Factory)->withServiceAccount(__DIR__.'/saberplus-1ec41-firebase-adminsdk-fbsvc-23a4103b63.json');
$messaging = $factory->createMessaging();

$rawBody = file_get_contents("php://input");
$data = json_decode($rawBody, true);

$response = [
    "success" => false,
    "error" => null,
    "fcm_result" => null,
    "db_result" => null
];

if (!is_array($data)) {
    http_response_code(400);
    $response['error'] = "JSON inválido o body vacío";
    error_log("[send_notification][ERROR] JSON inválido: " . $rawBody);
    echo json_encode($response, JSON_UNESCAPED_UNICODE);
    exit;
}

$id_usuario = isset($data['id_usuario']) ? (int)$data['id_usuario'] : null;
$type       = $data['type'] ?? null;
$eventData  = $data['data'] ?? [];
$request_id = isset($data['request_id']) ? (string)$data['request_id'] : null;

if (!$id_usuario || !$type) {
    http_response_code(400);
    $response['error'] = "Faltan parámetros: id_usuario y/o type";
    error_log("[send_notification][ERROR] faltan parámetros: " . json_encode($data, JSON_UNESCAPED_UNICODE));
    echo json_encode($response, JSON_UNESCAPED_UNICODE);
    exit;
}

try {
    $stmt = $conexion->prepare("SELECT fcm_token FROM usuarios WHERE id_usuario = :id");
    $stmt->execute([":id" => $id_usuario]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
} catch (\Throwable $e) {
    http_response_code(500);
    $response['error'] = "Error DB al buscar token";
    $response['db_result'] = ['exception' => $e->getMessage()];
    error_log("[send_notification][ERROR] DB token lookup: " . $e->getMessage());
    echo json_encode($response, JSON_UNESCAPED_UNICODE);
    exit;
}

if (!$row || empty($row['fcm_token'])) {
    http_response_code(404);
    $response['error'] = "Usuario sin token";
    error_log("[send_notification][WARN] usuario {$id_usuario} sin fcm_token");
    echo json_encode($response, JSON_UNESCAPED_UNICODE);
    exit;
}

$token = $row['fcm_token'];

/* ==========================
   NORMALIZACIÓN DE TEXTO
   ========================== */
function safeText($value) {
    if ($value === null || $value === '') return '';
    $value = trim((string)$value);
    
    // Detectar y corregir double encoding
    if (mb_check_encoding($value, 'UTF-8')) {
        // Si ya es UTF-8 válido, verificar si es double encoded
        if (preg_match('/\xC3[\x80-\xBF]/', $value)) {
            // Posible double encoding, intentar reparar
            $value = mb_convert_encoding($value, 'UTF-8', 'UTF-8');
        }
        return $value;
    }
    
    // Si no es UTF-8, convertir desde ISO-8859-1
    return mb_convert_encoding($value, 'UTF-8', 'ISO-8859-1');
}

/* ==========================
   EXTRACCIÓN DE DATOS
   ========================== */
$actorName = '';
if (isset($eventData['actor']['name'])) {
    $actorName = safeText($eventData['actor']['name']);
} elseif (isset($eventData['from_user_name'])) {
    $actorName = safeText($eventData['from_user_name']);
}

// Si no tenemos nombre, obtenerlo de la BD
if (empty($actorName) && isset($eventData['actor']['id'])) {
    try {
        $stmt = $conexion->prepare("SELECT nombre FROM usuarios WHERE id_usuario = ?");
        $stmt->execute([$eventData['actor']['id']]);
        $userRow = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($userRow && !empty($userRow['nombre'])) {
            $actorName = safeText($userRow['nombre']);
        }
    } catch (\Exception $e) {
        error_log("[send_notification] Error obteniendo nombre de BD: " . $e->getMessage());
    }
}

if (empty($actorName)) {
    switch ($type) {
        case 'challenge_created':
            $actorName = 'Un usuario';
            break;
        case 'challenge_deleted':
            $actorName = 'El creador';
            break;
        default:
            $actorName = 'Un participante';
    }
}

$challengeTitle = safeText($eventData['challenge_title'] ?? $eventData['nombre_reto'] ?? '');
if (empty($challengeTitle)) {
    $challengeTitle = "Reto #" . ($eventData['challenge_id'] ?? '?');
}

/* ==========================
   CONSTRUCCIÓN DE MENSAJES
   ========================== */
switch ($type) {
    case 'challenge_created':
    case 'reto_invitacion':
        $title = "Nuevo reto";
        $body  = "{$actorName} te invito al reto: {$challengeTitle}";
        break;
    case 'challenge_accepted':
    case 'reto_aceptado':
        $title = "Reto aceptado";
        $body  = "{$actorName} acepto el reto: {$challengeTitle}";
        break;
    case 'challenge_rejected':
    case 'reto_rechazado':
        $title = "Reto rechazado";
        $body  = "{$actorName} rechazo el reto: {$challengeTitle}";
        break;
    case 'challenge_deleted':
        $title = "Reto eliminado";
        $body  = "{$actorName} elimino el reto: {$challengeTitle}";
        break;
    default:
        $title = "Notificacion Saber+";
        $body  = "Tienes una nueva actualizacion";
}

// Eliminar cualquier carácter no UTF-8
$title = iconv('UTF-8', 'UTF-8//IGNORE', $title);
$body = iconv('UTF-8', 'UTF-8//IGNORE', $body);

error_log("[send_notification][DEBUG] to_user={$id_usuario} type={$type} title={$title} body={$body}");

/* ==========================
   PAYLOAD FCM
   ========================== */
$fcmDataPayload = [
    "click_action"   => "FLUTTER_NOTIFICATION_CLICK",
    "type"           => (string)$type,
    "request_id"     => (string)($request_id ?? ''),
    "challenge_id"   => isset($eventData['challenge_id']) ? (string)$eventData['challenge_id'] : '',
    "nombre_reto"    => (string)$challengeTitle,
    "area"           => isset($eventData['area']) ? (string)$eventData['area'] : '',
    "level"          => isset($eventData['level']) ? (string)$eventData['level'] : '',
    "from_user_id"   => isset($eventData['actor']['id']) ? (string)$eventData['actor']['id'] : '',
    "from_user_name" => (string)$actorName,
];

// Limpiar el payload para UTF-8
foreach ($fcmDataPayload as $key => $value) {
    $fcmDataPayload[$key] = iconv('UTF-8', 'UTF-8//IGNORE', $value);
}

$message = CloudMessage::withTarget('token', $token)
    ->withNotification(Notification::create($title, $body))
    ->withData($fcmDataPayload);

try {
    $fcmResponse = $messaging->send($message);
    
    $messageId = null;
    if (is_string($fcmResponse)) {
        $messageId = $fcmResponse;
    } elseif (is_array($fcmResponse)) {
        $messageId = $fcmResponse['name'] ?? json_encode($fcmResponse);
    } elseif (is_object($fcmResponse)) {
        $messageId = isset($fcmResponse->name) ? $fcmResponse->name : json_encode($fcmResponse);
    } else {
        $messageId = (string)$fcmResponse;
    }

    $response['fcm_result'] = ['message_id' => $messageId];
    error_log("[send_notification][FCM] message_id=" . substr((string)$messageId, 0, 200));
} catch (\Throwable $e) {
    http_response_code(500);
    $response['error'] = "Error enviando a FCM";
    $response['fcm_result'] = ['exception' => $e->getMessage()];
    error_log("[send_notification][FCM-ERROR] " . $e->getMessage());
    echo json_encode($response, JSON_UNESCAPED_UNICODE);
    exit;
}

try {
    $stmtInsert = $conexion->prepare("
        INSERT INTO notifications (user_id, type, title, body, payload_json)
        VALUES (:user_id, :type, :title, :body, :payload_json)
    ");

    $payload_json = json_encode($eventData, JSON_UNESCAPED_UNICODE);

    $execOk = $stmtInsert->execute([
        ":user_id" => $id_usuario,
        ":type" => $type,
        ":title" => $title,
        ":body" => $body,
        ":payload_json" => $payload_json
    ]);

    $response['db_result'] = [
        'execute_ok' => $execOk ? 1 : 0,
        'rowCount' => $stmtInsert->rowCount(),
        'lastInsertId' => $conexion->lastInsertId()
    ];
    
    error_log("[send_notification][DB] execute_ok=" . ($execOk?1:0) . " rowCount=" . $stmtInsert->rowCount());

} catch (\Throwable $e) {
    error_log("[send_notification][DB-ERROR] " . $e->getMessage());
}

$response['success'] = true;
echo json_encode($response, JSON_UNESCAPED_UNICODE);
exit;