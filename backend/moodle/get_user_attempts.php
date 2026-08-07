<?php
declare(strict_types=1);

// get_user_attempts.php — Consulta intentos de un quiz en Moodle
error_log('[GET_USER_ATTEMPTS] Script iniciado');

// CORS + JSON
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
    error_log('[GET_USER_ATTEMPTS] Método no permitido: ' . $_SERVER['REQUEST_METHOD']);
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
}

// Includes
require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php';
$mcfg      = require __DIR__ . '/../includes/moodle.php';
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

// Leer JWT
$hdrs = function_exists('getallheaders') ? getallheaders() : [];
$ah   = $hdrs['Authorization'] ?? $hdrs['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';
error_log('[GET_USER_ATTEMPTS] Authorization header: ' . var_export($ah, true));

if (!preg_match('/Bearer\s+(\S+)/', $ah, $m)) {
    http_response_code(401);
    error_log('[GET_USER_ATTEMPTS] Bearer token no encontrado');
    exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
}

$appToken = $m[1];
error_log('[GET_USER_ATTEMPTS] Token extraído: ' . substr($appToken, 0, 8) . '...');

try {
    $decoded      = JWT::decode($appToken, new Key($configJwt['secret'], 'HS256'));
    $moodleUserId = (int)$decoded->data->moodle_userid;
    error_log('[GET_USER_ATTEMPTS] JWT decodificado, moodleUserId=' . $moodleUserId);
} catch (Exception $e) {
    http_response_code(401);
    error_log('[GET_USER_ATTEMPTS] Error JWT: ' . $e->getMessage());
    exit(json_encode(['status' => 'error', 'msg' => 'Token inválido']));
}

// Leer JSON
$rawInput = file_get_contents('php://input');
error_log('[GET_USER_ATTEMPTS] Raw input: ' . $rawInput);
$input   = json_decode($rawInput, true) ?? [];
$quizId  = isset($input['quizid']) ? (int)$input['quizid'] : 0;

if ($quizId <= 0) {
    http_response_code(400);
    error_log('[GET_USER_ATTEMPTS] quizid inválido');
    exit(json_encode(['status' => 'error', 'msg' => 'Falta quizid']));
}

// Recuperar token Moodle
try {
    $stmt = $conexion->prepare("
        SELECT moodle_token
        FROM usuarios
        WHERE moodle_id = :mid
        LIMIT 1
    ");
    $stmt->execute([':mid' => $moodleUserId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
} catch (Exception $e) {
    http_response_code(500);
    error_log('[GET_USER_ATTEMPTS] Error BD: ' . $e->getMessage());
    exit(json_encode(['status' => 'error', 'msg' => 'Error de base de datos']));
}

if (empty($row['moodle_token'])) {
    http_response_code(404);
    error_log('[GET_USER_ATTEMPTS] moodle_token no encontrado para usuario ' . $moodleUserId);
    exit(json_encode(['status' => 'error', 'msg' => 'Usuario no encontrado']));
}

$moodleToken = $row['moodle_token'];
error_log('[GET_USER_ATTEMPTS] moodle_token: ' . substr($moodleToken, 0, 8) . '...');

// Ejecutar WS: mod_quiz_get_user_attempts
$params = [
    'quizid' => $quizId,
    'userid' => $moodleUserId,
    'status' => 'all'
];
error_log('[GET_USER_ATTEMPTS] WS params: ' . print_r($params, true));

try {
    $url = rtrim($mcfg['base_url'], '/') . $mcfg['ws_endpoint'];
    $query = http_build_query([
        'wstoken' => $moodleToken,
        'wsfunction' => 'mod_quiz_get_user_attempts',
        'moodlewsrestformat' => 'json'
    ]);

    $ch = curl_init($url . '?' . $query);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $params);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    $result = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    error_log('[GET_USER_ATTEMPTS] WS response: ' . $result);

    if ($httpCode !== 200 || !$result) {
        throw new Exception('Error HTTP: ' . $httpCode);
    }

    $response = json_decode($result, true);
    $attempts = $response['attempts'] ?? [];

    // Filtrar intento en curso
    $inProgress = null;
    foreach ($attempts as $att) {
        if (($att['state'] ?? '') === 'inprogress') {
            $inProgress = $att;
            break;
        }
    }

    echo json_encode([
        'status'     => 'ok',
        'inprogress' => $inProgress,  // null si no hay
        'attempts'   => $attempts,
        'warnings'   => $response['warnings'] ?? []
    ]);
} catch (Exception $e) {
    http_response_code(500);
    error_log('[GET_USER_ATTEMPTS] WS Exception: ' . $e->getMessage());
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'Error al consultar intentos',
        'debug'  => $e->getMessage()
    ]));
}
