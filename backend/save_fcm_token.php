<?php
declare(strict_types=1);

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/includes/config.php';
$configJwt = require __DIR__ . '/jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit(json_encode(['status' => 'error', 'msg' => 'Metodo no permitido']));
}

// -- Auth JWT --
$hdrs = function_exists('getallheaders') ? getallheaders() : [];
$authHeader = $hdrs['Authorization'] ?? $hdrs['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';

if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
}

try {
    $decoded = JWT::decode($m[1], new Key($configJwt['secret'], 'HS256'));
    $userId = (int)($decoded->data->id_usuario ?? 0);
    if ($userId <= 0) {
        http_response_code(401);
        exit(json_encode(['status' => 'error', 'msg' => 'Usuario no valido']));
    }
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Token invalido']));
}

// -- Leer body --
$body = json_decode(file_get_contents('php://input'), true) ?? [];
$token = trim((string)($body['fcm_token'] ?? ''));

if ($token === '' || strlen($token) < 20) {
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'Token FCM invalido']));
}

// -- Guardar --
try {
    $stmt = $conexion->prepare("UPDATE usuarios SET fcm_token = ? WHERE id_usuario = ?");
    $stmt->execute([$token, $userId]);

    echo json_encode([
        'status' => 'ok',
        'msg' => 'Token FCM actualizado',
        'user_id' => $userId,
        'rows_affected' => $stmt->rowCount(),
    ], JSON_UNESCAPED_UNICODE);
} catch (Throwable $e) {
    error_log("[SAVE_FCM] Error: " . $e->getMessage());
    http_response_code(500);
    exit(json_encode(['status' => 'error', 'msg' => 'Error guardando token']));
}