<?php
// /var/www/html/api/prepsaber/backend/register_fcm_token.php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// Capturar el body crudo una sola vez
$rawBody = file_get_contents("php://input");
error_log("[register_fcm_token][RAW BODY] " . $rawBody);

require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/auth_middleware.php'; // valida JWT pero no debe consumir php://input

try {
    // Usar el body capturado
    $data = json_decode($rawBody, true);
    error_log("[register_fcm_token][DATA DECODED] " . json_encode($data));

    // Aceptar ambos nombres por robustez
    $id_usuario = $data['id_usuario'] ?? $data['user_id'] ?? null;
    $fcm_token = $data['fcm_token'] ?? $data['token'] ?? null;
    
    error_log("[register_fcm_token][PARSED] id_usuario=" . ($id_usuario ?? 'null') . " fcm_token=" . ($fcm_token ?? 'null'));

    if (empty($id_usuario) || empty($fcm_token)) {
        http_response_code(400);
        error_log("[register_fcm_token][ERROR] Datos incompletos recibidos");
        echo json_encode([
            "status" => "error",
            "msg" => "Datos incompletos",
            "received" => $data
        ]);
        exit;
    }

    $stmt = $conexion->prepare("
        UPDATE usuarios 
        SET fcm_token = :fcm_token 
        WHERE id_usuario = :id_usuario
    ");
    
    error_log("[register_fcm_token][UPDATE] Ejecutando para user_id=$id_usuario token=$fcm_token");
    
    $stmt->execute([
        ":fcm_token" => $fcm_token,
        ":id_usuario" => $id_usuario
    ]);

    if ($stmt->rowCount() > 0) {
        error_log("[register_fcm_token][SUCCESS] Token guardado para user_id=$id_usuario");
        echo json_encode([
            "status" => "ok",
            "msg" => "Token FCM registrado correctamente",
            "user_id" => $id_usuario
        ]);
    } else {
        error_log("[register_fcm_token][FAIL] Usuario no encontrado id_usuario=$id_usuario");
        echo json_encode([
            "status" => "error",
            "msg" => "Usuario no encontrado",
            "user_id" => $id_usuario
        ]);
    }
    exit;

} catch (\Throwable $e) {
    error_log("[register_fcm_token][EXCEPTION] " . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        "status" => "error",
        "msg" => "Error interno",
        "detail" => $e->getMessage()
    ]);
    exit;
}