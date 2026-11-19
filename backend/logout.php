<?php
// logout.php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");

require 'auth_middleware.php'; // obtiene $currentJti y valida token

// Si es OPTIONS, respondemos y salimos (CORS preflight)
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

try {
    $stmt = $conexion->prepare(
        "INSERT IGNORE INTO revoked_tokens (jti, revoked_at) VALUES (?, NOW())"
    );
    $stmt->execute([$currentJti]);

    echo json_encode([
        'status' => 'ok',
        'msg' => 'Sesión cerrada correctamente'
    ], JSON_UNESCAPED_UNICODE);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'msg' => 'No se pudo cerrar la sesión',
        'error' => $e->getMessage()
    ], JSON_UNESCAPED_UNICODE);
}
