<?php
declare(strict_types=1);

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
}

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php'; // PDO $conexion
$configJwt = require __DIR__ . '/jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

// 1?? Extraer JWT
$allHeaders = function_exists('getallheaders') ? getallheaders() : [];
$authHeader = $allHeaders['Authorization'] ?? $allHeaders['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';

if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
}

$appToken = $m[1];

// 2?? Decodificar JWT
try {
    $decoded = JWT::decode($appToken, new Key($configJwt['secret'], 'HS256'));
    $moodleUserId = (int)$decoded->data->moodle_userid;
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Token inválido']));
}

// 3?? Actualizar usuario a PREMIUM
$stmt = $conexion->prepare("
    UPDATE usuarios
    SET access_level = 'premium',
        unlocked_at = NOW()
    WHERE moodle_id = :mid
");

$stmt->execute([':mid' => $moodleUserId]);

if ($stmt->rowCount() === 0) {
    http_response_code(404);
    exit(json_encode(['status' => 'error', 'msg' => 'Usuario no encontrado']));
}

// 4?? Respuesta OK
echo json_encode([
    'status' => 'ok',
    'access_level' => 'premium',
    'msg' => 'Usuario actualizado a PREMIUM'
]);
