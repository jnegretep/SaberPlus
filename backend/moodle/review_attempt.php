<?php
declare(strict_types=1);

// backend/moodle/review_attempt.php
// Obtiene la revisión de un intento de quiz en Moodle y devuelve detalles con feedback.

error_log('[REVIEW_ATTEMPT] Script iniciado');

// 1) CORS + JSON headers
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
    error_log('[REVIEW_ATTEMPT] Método no permitido: ' . $_SERVER['REQUEST_METHOD']);
    echo json_encode(['status'=>'error','msg'=>'Método no permitido'], JSON_UNESCAPED_UNICODE);
    exit;
}

// 2) Requires
require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle.php'; // ? ya incluye MoodleClient
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

// 3) Extraer Bearer JWT
$hdrs = function_exists('getallheaders') ? getallheaders() : [];
$auth = $hdrs['Authorization']
      ?? $hdrs['authorization']
      ?? $_SERVER['HTTP_AUTHORIZATION']
      ?? '';
error_log('[REVIEW_ATTEMPT] Authorization header: ' . var_export($auth, true));

if (! preg_match('/^Bearer\s+(.+)$/i', $auth, $m)) {
    http_response_code(401);
    error_log('[REVIEW_ATTEMPT] Token Bearer no encontrado');
    echo json_encode(['status'=>'error','msg'=>'No autorizado'], JSON_UNESCAPED_UNICODE);
    exit;
}
$rawJwt = $m[1];

// 4) Decodificar y validar JWT
try {
    $decoded = JWT::decode(
        $rawJwt,
        new Key($configJwt['secret'], $configJwt['algo'] ?? 'HS256')
    );
    error_log('[REVIEW_ATTEMPT] JWT decodificado OK');
} catch (\Throwable $e) {
    http_response_code(401);
    error_log('[REVIEW_ATTEMPT] Error al decodificar JWT: ' . $e->getMessage());
    echo json_encode([
        'status'=>'error',
        'msg'=>'Token inválido o expirado',
        'debug'=>$e->getMessage()
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

// 5) Verificar issuer/audience si están definidos
if (
    (isset($configJwt['issuer']) && ($decoded->iss ?? '') !== $configJwt['issuer'])
    || (isset($configJwt['audience']) && ($decoded->aud ?? '') !== $configJwt['audience'])
) {
    http_response_code(401);
    error_log(
        '[REVIEW_ATTEMPT] Iss/Audience inválidos: '
        . 'iss=' . ($decoded->iss ?? '[none]')
        . ', aud=' . ($decoded->aud ?? '[none]')
    );
    echo json_encode(['status'=>'error','msg'=>'Token no autorizado'], JSON_UNESCAPED_UNICODE);
    exit;
}

// 6) Extraer moodle_userid del payload
$payloadData  = $decoded->data ?? null;
$moodleUserId = is_object($payloadData)
    ? (int)($payloadData->moodle_userid ?? 0)
    : 0;
if ($moodleUserId <= 0) {
    http_response_code(401);
    error_log('[REVIEW_ATTEMPT] moodle_userid inválido en payload');
    echo json_encode(['status'=>'error','msg'=>'Payload inválido'], JSON_UNESCAPED_UNICODE);
    exit;
}

// 7) Leer attemptid del JSON
$rawInput   = file_get_contents('php://input');
$input      = json_decode($rawInput, true) ?? [];
$attemptId  = isset($input['attemptid']) ? (int)$input['attemptid'] : 0;
error_log('[REVIEW_ATTEMPT] Raw input: ' . $rawInput);

if ($attemptId <= 0) {
    http_response_code(400);
    error_log('[REVIEW_ATTEMPT] Parámetro inválido attemptid=' . $attemptId);
    echo json_encode(['status'=>'error','msg'=>'attemptid es requerido'], JSON_UNESCAPED_UNICODE);
    exit;
}

// 8) Recuperar moodle_token de la BD
try {
    $stmt = $conexion->prepare('
        SELECT moodle_token
          FROM usuarios
         WHERE moodle_id = :mid
         LIMIT 1
    ');
    $stmt->execute([':mid' => $moodleUserId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
} catch (\Exception $e) {
    http_response_code(500);
    error_log('[REVIEW_ATTEMPT] Error BD al recuperar moodle_token: ' . $e->getMessage());
    echo json_encode(['status'=>'error','msg'=>'Error interno de BD'], JSON_UNESCAPED_UNICODE);
    exit;
}

if (empty($row['moodle_token'])) {
    http_response_code(404);
    error_log('[REVIEW_ATTEMPT] moodle_token no encontrado para moodle_id=' . $moodleUserId);
    echo json_encode(['status'=>'error','msg'=>'Usuario no encontrado'], JSON_UNESCAPED_UNICODE);
    exit;
}
$moodleToken = $row['moodle_token'];

// 9) Invocar WS mod_quiz_get_attempt_review
try {
    $client = getMoodleClient(); // ? usa instancia compartida

    $params = [
        'attemptid' => $attemptId
    ];
    error_log('[REVIEW_ATTEMPT] Llamando mod_quiz_get_attempt_review con params: ' . print_r($params, true));

    $resp = $client->request($moodleToken, 'mod_quiz_get_attempt_review', $params);
    error_log('[REVIEW_ATTEMPT] Moodle WS respuesta: ' . print_r($resp, true));

    echo json_encode(['status'=>'ok','data'=>$resp], JSON_UNESCAPED_UNICODE);

} catch (\Exception $e) {
    http_response_code(502);
    error_log('[REVIEW_ATTEMPT] Error en Moodle WS: ' . $e->getMessage());
    echo json_encode([
        'status'=>'error',
        'msg'=>'Error al obtener review',
        'debug'=>$e->getMessage()
    ], JSON_UNESCAPED_UNICODE);
    exit;
}
