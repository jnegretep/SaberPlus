<?php
require 'vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
use Firebase\JWT\JWT;

$config = require 'jwt_config.php';
header('Content-Type: application/json');

$refresh_token = $_POST['refresh_token'] ?? '';

if (!$refresh_token || !preg_match('/^[a-f0-9]{64}$/', $refresh_token)) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'msg' => 'Refresh token inválido']);
    exit;
}

// Buscar y validar refresh token
$stmt = $conexion->prepare("SELECT id_usuario FROM refresh_tokens WHERE token = ? AND expires_at > NOW()");
$stmt->execute([$refresh_token]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$row) {
    http_response_code(401);
    echo json_encode(['status' => 'error', 'msg' => 'Refresh token inválido o expirado']);
    exit;
}

$id_usuario = $row['id_usuario'];

// Datos del usuario
$stmt = $conexion->prepare("SELECT id_usuario, email, tipo_usuario, nombre FROM usuarios WHERE id_usuario = ?");
$stmt->execute([$id_usuario]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);

// Rotar refresh token (insertar o actualizar)
$new_refresh_token = bin2hex(random_bytes(32));
$stmt = $conexion->prepare("
    INSERT INTO refresh_tokens (id_usuario, token, expires_at)
    VALUES (:uid, :token, DATE_ADD(NOW(), INTERVAL 30 DAY))
    ON DUPLICATE KEY UPDATE 
        token = VALUES(token),
        expires_at = VALUES(expires_at)
");
$stmt->execute([':uid' => $id_usuario, ':token' => $new_refresh_token]);

error_log("[refresh] Token rotado para user_id={$id_usuario}");

// Nuevo JWT
$now = time();
$exp = $now + $config['expiry_seconds'];
$jti = bin2hex(random_bytes(16));

$payload = [
    'iss' => $config['issuer'],
    'aud' => $config['audience'],
    'iat' => $now,
    'nbf' => $now,
    'exp' => $exp,
    'jti' => $jti,
    'data' => $user
];

$jwt = JWT::encode($payload, $config['secret'], 'HS256');

echo json_encode([
    'status' => 'ok',
    'token' => $jwt,
    'refresh_token' => $new_refresh_token,
    'expires_at' => date('c', $exp)
]);
