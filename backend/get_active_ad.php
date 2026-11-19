<?php
declare(strict_types=1);

/**
 * get_active_ad.php
 * Devuelve un anuncio activo para mostrar en la app
 */

error_reporting(E_ALL);
ini_set('display_errors', '0');
ini_set('log_errors', '1');

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: GET, OPTIONS");
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
   JWT
   ======================= */
$headers = function_exists('getallheaders') ? getallheaders() : [];
$auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';

if (!preg_match('/Bearer\s+(\S+)/', $auth, $m)) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
}

try {
    $decoded = JWT::decode($m[1], new Key($configJwt['secret'], 'HS256'));
    $userId = (int)($decoded->data->moodle_userid ?? 0);
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Token inválido']));
}

/* =======================
   USUARIO
   ======================= */
$stmt = $conexion->prepare("
    SELECT moodle_id, access_level
    FROM usuarios
    WHERE moodle_id = :id
    LIMIT 1
");
$stmt->execute([':id' => $userId]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$user) {
    exit(json_encode(['status' => 'empty']));
}

$accessLevel = $user['access_level'] === 'premium' ? 'premium' : 'free';

/* =======================
   ANUNCIO ACTIVO
   ======================= */
$stmt = $conexion->prepare("
    SELECT
        id,
        title,
        type,
        media_url,
        target_url,
        position,
        min_view_seconds,
        show_close_immediately
    FROM ads
    WHERE is_active = 1
      AND (show_for = 'all' OR show_for = :level)
      AND (start_at IS NULL OR start_at <= NOW())
      AND (end_at IS NULL OR end_at >= NOW())
    ORDER BY created_at DESC
    LIMIT 1
");

$stmt->execute([
    ':level' => $accessLevel
]);

$ad = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$ad) {
    echo json_encode(['status' => 'empty']);
    exit;
}

/* =======================
   RESPUESTA
   ======================= */
echo json_encode([
    'status' => 'ok',
    'ad' => [
        'id'                    => (int)$ad['id'],
        'title'                 => $ad['title'],
        'type'                  => $ad['type'], // image | video
        'media_url'             => $ad['media_url'],
        'target_url'            => $ad['target_url'],
        'position'              => $ad['position'],
        'min_view_seconds'      => (int)$ad['min_view_seconds'],
        'show_close_immediately'=> (bool)$ad['show_close_immediately']
    ]
]);
