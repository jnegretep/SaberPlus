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

if (!isset($_GET['token'])) {
    http_response_code(400);
    echo json_encode(['status'=>'error','msg'=>'Token no proporcionado']);
    exit;
}

$token = trim($_GET['token']);

try {
    $stmt = $conexion->prepare("
        SELECT pr.user_id, pr.expires_at, u.email, u.nombre 
        FROM password_resets pr
        INNER JOIN usuarios u ON pr.user_id = u.id_usuario
        WHERE pr.token = ?
        LIMIT 1
    ");
    $stmt->execute([$token]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        http_response_code(404);
        echo json_encode(['status'=>'error','msg'=>'Token inválido']);
        exit;
    }

    if (strtotime($row['expires_at']) < time()) {
        http_response_code(400);
        echo json_encode(['status'=>'error','msg'=>'El enlace ha expirado']);
        exit;
    }

    echo json_encode([
        'status' => 'ok',
        'msg' => 'Token válido',
        'user_id' => $row['user_id'],
        'email' => $row['email'],
        'nombre' => $row['nombre']
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['status'=>'error','msg'=>'Error en servidor','error'=>$e->getMessage()]);
}
