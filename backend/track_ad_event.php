<?php
declare(strict_types=1);

/**
 * track_ad_event.php
 * Registra métricas de anuncios
 */

error_reporting(E_ALL);
ini_set('display_errors', '0');
ini_set('log_errors', '1');

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
$configJwt = require __DIR__ . '/jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

/* =======================
   JWT (opcional)
   ======================= */
$userId = null;
$headers = function_exists('getallheaders') ? getallheaders() : [];
$auth = $headers['Authorization'] ?? '';

if (preg_match('/Bearer\s+(\S+)/', $auth, $m)) {
    try {
        $decoded = JWT::decode($m[1], new Key($configJwt['secret'], 'HS256'));
        $userId = (int)($decoded->data->moodle_userid ?? null);
    } catch (Exception $e) {
        $userId = null;
    }
}

/* =======================
   BODY
   ======================= */
$data = json_decode(file_get_contents('php://input'), true);

$adId   = (int)($data['ad_id'] ?? 0);
$event  = $data['event'] ?? '';
$seconds= (int)($data['watched_seconds'] ?? 0);

$allowed = ['impression','close','completed','click'];

if ($adId <= 0 || !in_array($event, $allowed, true)) {
    http_response_code(400);
    exit(json_encode(['status' => 'error']));
}

/* =======================
   INSERT MÉTRICA
   ======================= */
$stmt = $conexion->prepare("
    INSERT INTO ad_metrics (ad_id, user_id, event, watched_seconds)
    VALUES (:ad, :user, :event, :sec)
");

$stmt->execute([
    ':ad'   => $adId,
    ':user'=> $userId,
    ':event'=> $event,
    ':sec' => $seconds
]);

echo json_encode(['status' => 'ok']);
