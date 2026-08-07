<?php
declare(strict_types=1);

// backend/moodle/quiz_attempts_list.php
// Devuelve los intentos existentes de un usuario en un quiz + info de acceso

error_log('[QUIZ_ATTEMPTS_LIST] Script iniciado');

header('Access-Control-Allow-Origin: *');
header('Content-Type: application/json; charset=UTF-8');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['status'=>'error','msg'=>'Método no permitido']);
    exit;
}

require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle.php';
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

// === 1) Extraer token JWT ===
$hdrs = function_exists('getallheaders') ? getallheaders() : [];
$auth = $hdrs['Authorization']
      ?? $hdrs['authorization']
      ?? $_SERVER['HTTP_AUTHORIZATION']
      ?? '';

if (!preg_match('/^Bearer\s+(.+)$/i', $auth, $m)) {
    http_response_code(401);
    echo json_encode(['status'=>'error','msg'=>'No autorizado']);
    exit;
}
$rawJwt = $m[1];

try {
    $decoded = JWT::decode($rawJwt, new Key($configJwt['secret'], $configJwt['algo'] ?? 'HS256'));
} catch (Throwable $e) {
    http_response_code(401);
    echo json_encode(['status'=>'error','msg'=>'Token inválido','debug'=>$e->getMessage()]);
    exit;
}

$payloadData  = $decoded->data ?? null;
$moodleUserId = is_object($payloadData) ? (int)($payloadData->moodle_userid ?? 0) : 0;
if ($moodleUserId <= 0) {
    http_response_code(401);
    echo json_encode(['status'=>'error','msg'=>'Payload inválido']);
    exit;
}

// === 2) Leer quizid del input ===
$rawInput = file_get_contents('php://input');
$input = json_decode($rawInput, true) ?? [];
$quizId = isset($input['quizid']) ? (int)$input['quizid'] : 0;

if ($quizId <= 0) {
    http_response_code(400);
    echo json_encode(['status'=>'error','msg'=>'quizid es requerido']);
    exit;
}

// === 3) Recuperar token Moodle del usuario ===
try {
    $stmt = $conexion->prepare('SELECT moodle_token FROM usuarios WHERE moodle_id = :mid LIMIT 1');
    $stmt->execute([':mid' => $moodleUserId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['status'=>'error','msg'=>'Error BD','debug'=>$e->getMessage()]);
    exit;
}

if (empty($row['moodle_token'])) {
    http_response_code(404);
    echo json_encode(['status'=>'error','msg'=>'Usuario no encontrado']);
    exit;
}
$moodleToken = $row['moodle_token'];

// === 4) Invocar servicios Moodle ===
try {
    $client = getMoodleClient();

    // --- a) Obtener lista de intentos ---
    // ¡IMPORTANTE! Usar los mismos parámetros que start_attempt.php
    $attemptParams = [
        'quizid' => $quizId,
        'userid' => $moodleUserId,
        'status' => 'all' // ¡CRÍTICO! Incluir todos los estados
    ];
    
    error_log("[QUIZ_ATTEMPTS_LIST] Parámetros: " . print_r($attemptParams, true));
    
    $attemptsResp = $client->request($moodleToken, 'mod_quiz_get_user_attempts', $attemptParams);
    
    error_log("[QUIZ_ATTEMPTS_LIST] Respuesta intentos: " . print_r($attemptsResp, true));

    // --- b) Obtener info de acceso ---
    $accessParams = [
        'quizid' => $quizId
    ];
    $accessResp = $client->request($moodleToken, 'mod_quiz_get_quiz_access_information', $accessParams);

    $data = [
        'attempts' => $attemptsResp['attempts'] ?? [],
        'accessinfo' => $accessResp ?? []
    ];

    echo json_encode(['status' => 'ok', 'data' => $data], JSON_UNESCAPED_UNICODE);

} catch (Throwable $e) {
    http_response_code(502);
    error_log('[QUIZ_ATTEMPTS_LIST] Error Moodle: ' . $e->getMessage());
    echo json_encode(['status'=>'error','msg'=>'Error al obtener intentos','debug'=>$e->getMessage()]);
    exit;
}