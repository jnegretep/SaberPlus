<?php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['status' => 'error', 'msg' => 'Método no permitido']);
    exit;
}

require __DIR__ . '/includes/conexion.php';

$data = json_decode(file_get_contents('php://input'), true);

if (empty($data['user_id']) || empty($data['password']) || empty($data['token'])) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'msg' => 'Datos incompletos']);
    exit;
}

$user_id = intval($data['user_id']);
$password = trim($data['password']);
$token = trim($data['token']);

if (strlen($password) < 8) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'msg' => 'La contraseña debe tener al menos 8 caracteres']);
    exit;
}

try {
    // Verificar token válido
    $stmt = $conexion->prepare("SELECT token, expires_at FROM password_resets WHERE user_id = ? AND token = ?");
    $stmt->execute([$user_id, $token]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'msg' => 'Token inválido o no coincide']);
        exit;
    }

    if (strtotime($row['expires_at']) < time()) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'msg' => 'El token ha expirado']);
        exit;
    }

    // Actualizar contraseña
    $hash = password_hash($password, PASSWORD_DEFAULT);

    $stmt = $conexion->prepare("UPDATE usuarios SET contrasena_hash = ? WHERE id_usuario = ?");
    $stmt->execute([$hash, $user_id]);

    // Eliminar token usado
    $stmt = $conexion->prepare("DELETE FROM password_resets WHERE user_id = ?");
    $stmt->execute([$user_id]);

    echo json_encode(['status' => 'ok', 'msg' => 'Contraseña actualizada correctamente']);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'msg' => 'Error en el servidor', 'error' => $e->getMessage()]);
}
