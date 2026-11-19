<?php
declare(strict_types=1);

// search_users.php — Buscar usuarios por nombre, email o moodle_username usando JWT

// 1) CORS + JSON
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: GET, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    exit(json_encode(['status'=>'error','msg'=>'Método no permitido']));
}

// 2) Autoload & config
require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php';      // PDO $conexion
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

// 3) Extraer y validar JWT Bearer
$hdrs       = function_exists('getallheaders') ? getallheaders() : [];
$authHeader = $hdrs['Authorization']  
            ?? $hdrs['authorization']  
            ?? $_SERVER['HTTP_AUTHORIZATION'] 
            ?? '';

if (! preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
    http_response_code(401);
    exit(json_encode(['status'=>'error','msg'=>'No autorizado']));
}
$appToken = $m[1];

try {
    $decoded      = JWT::decode($appToken, new Key($configJwt['secret'], 'HS256'));
    $currentUserId = (int)$decoded->data->id_usuario;   // ?? id del usuario autenticado
    $moodleUserId  = (int)$decoded->data->moodle_userid;
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status'=>'error','msg'=>'Token inválido']));
}

// 4) Validar parámetro query
$query = $_GET['query'] ?? '';
if (strlen($query) < 2) {
    echo json_encode(['status'=>'ok','users'=>[]]);
    exit;
}

// 5) Buscar usuarios en BD (excluyendo self y admins)
try {
    error_log("[search_users] Ejecutando búsqueda con query='$query'");

    $stmt = $conexion->prepare("
        SELECT id_usuario AS id, nombre AS name, email, moodle_username
          FROM usuarios
         WHERE (nombre LIKE :q OR email LIKE :q OR moodle_username LIKE :q)
           AND id_usuario NOT IN (:self, 2, 3)
         LIMIT 10
    ");
    $stmt->bindValue(':q', "%$query%");
    $stmt->bindValue(':self', $currentUserId, PDO::PARAM_INT);
    $stmt->execute();
    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);

    error_log("[search_users] Resultados encontrados: ".count($users));

    echo json_encode(['status'=>'ok','users'=>$users]);

} catch (Exception $e) {
    error_log("[search_users][ERROR] ".$e->getMessage());
    http_response_code(500);
    echo json_encode([
        'status'=>'error',
        'msg'=>'Error al buscar usuarios',
        'debug'=>$e->getMessage()
    ]);
}
