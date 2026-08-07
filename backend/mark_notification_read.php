<?php
// /var/www/html/api/prepsaber/backend/mark_notification_read.php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require __DIR__ . '/includes/conexion.php'; // ? conexión correcta

// ? Capturar body crudo una sola vez
$rawBody = file_get_contents("php://input");
$data = json_decode($rawBody, true);

$id      = $data['id'] ?? null;
$user_id = $data['user_id'] ?? null;

if (empty($id) || empty($user_id)) {
    http_response_code(400);
    echo json_encode(["success" => false, "message" => "Faltan parámetros"]);
    exit;
}

try {
    // ?? Marcar como leída
    $stmt = $conexion->prepare("
        UPDATE notifications
        SET read_at = NOW()
        WHERE id = :id AND user_id = :user_id
    ");
    $stmt->execute([":id" => $id, ":user_id" => $user_id]);

    if ($stmt->rowCount() > 0) {
        // ?? Obtener lista actualizada de notificaciones
        $stmt2 = $conexion->prepare("
            SELECT 
                id, 
                type, 
                title, 
                body, 
                payload_json, 
                CONVERT_TZ(created_at, '+00:00', '-05:00') AS created_at_local,
                CONVERT_TZ(read_at, '+00:00', '-05:00') AS read_at_local
            FROM notifications
            WHERE user_id = :user_id
            ORDER BY created_at DESC
        ");
        $stmt2->execute([":user_id" => $user_id]);
        $rows = $stmt2->fetchAll(PDO::FETCH_ASSOC);

        echo json_encode([
            "success" => true,
            "message" => "Notificación marcada como leída",
            "id"      => $id,
            "user_id" => $user_id,
            "notifications" => $rows
        ]);
    } else {
        echo json_encode([
            "success" => false,
            "message" => "No se encontró la notificación",
            "id"      => $id,
            "user_id" => $user_id
        ]);
    }
} catch (\Throwable $e) {
    error_log("[mark_notification_read][ERROR] ".$e->getMessage());
    http_response_code(500);
    echo json_encode([
        "success" => false,
        "message" => "Error interno",
        "detail"  => $e->getMessage()
    ]);
}
