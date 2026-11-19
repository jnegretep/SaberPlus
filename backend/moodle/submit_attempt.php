<?php
declare(strict_types=1);

error_log('[SUBMIT_ATTEMPT] Script iniciado');

// CORS + JSON
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
    error_log('[SUBMIT_ATTEMPT] Método no permitido: ' . $_SERVER['REQUEST_METHOD']);
    exit(json_encode(['status'=>'error','msg'=>'Método no permitido'], JSON_UNESCAPED_UNICODE));
}

// Includes y configuración
require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle.php'; // usa getMoodleClient()
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

// Leer y validar JWT
$hdrs        = function_exists('getallheaders') ? getallheaders() : [];
$ah          = $hdrs['Authorization'] 
             ?? $hdrs['authorization'] 
             ?? $_SERVER['HTTP_AUTHORIZATION'] 
             ?? '';
error_log('[SUBMIT_ATTEMPT] Authorization header: ' . var_export($ah, true));

if (! preg_match('/Bearer\s+(\S+)/', $ah, $m)) {
    http_response_code(401);
    error_log('[SUBMIT_ATTEMPT] No se encontró Bearer en header');
    exit(json_encode(['status'=>'error','msg'=>'No autorizado'], JSON_UNESCAPED_UNICODE));
}

$appToken = $m[1];
error_log('[SUBMIT_ATTEMPT] Token extraído: ' . substr($appToken, 0, 8) . '...');

try {
    $decoded      = JWT::decode($appToken, new Key($configJwt['secret'], 'HS256'));
    $moodleUserId = (int)($decoded->data->moodle_userid ?? 0);
    error_log('[SUBMIT_ATTEMPT] JWT decodificado, moodleUserId=' . $moodleUserId);
    if ($moodleUserId <= 0) {
        throw new \UnexpectedValueException('moodle_userid inválido');
    }
} catch (\Exception $e) {
    http_response_code(401);
    error_log('[SUBMIT_ATTEMPT] Error decodificando JWT: ' . $e->getMessage());
    exit(json_encode([
        'status'=>'error',
        'msg'=>'Token inválido',
        'debug'=>$e->getMessage()
    ], JSON_UNESCAPED_UNICODE));
}

// Leer input JSON
$rawInput = file_get_contents('php://input');
error_log('[SUBMIT_ATTEMPT] Raw input JSON: ' . $rawInput);
$input     = json_decode($rawInput, true) ?? [];
$attemptId = isset($input['attemptid']) ? (int)$input['attemptid'] : 0;
$answers   = $input['answers'] ?? [];

if ($attemptId <= 0 || ! is_array($answers)) {
    http_response_code(400);
    error_log('[SUBMIT_ATTEMPT] Parámetros inválidos');
    exit(json_encode(['status'=>'error','msg'=>'Faltan datos'], JSON_UNESCAPED_UNICODE));
}

// Recuperar moodle_token
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
    error_log('[SUBMIT_ATTEMPT] Error BD al buscar moodle_token: ' . $e->getMessage());
    exit(json_encode(['status'=>'error','msg'=>'Error de base de datos'], JSON_UNESCAPED_UNICODE));
}

if (empty($row['moodle_token'])) {
    http_response_code(404);
    error_log('[SUBMIT_ATTEMPT] No se encontró moodle_token para usuario ' . $moodleUserId);
    exit(json_encode(['status'=>'error','msg'=>'Usuario no encontrado'], JSON_UNESCAPED_UNICODE));
}

$moodleToken = $row['moodle_token'];
error_log('[SUBMIT_ATTEMPT] moodle_token recuperado: ' . substr($moodleToken, 0, 8) . '...');

// Obtener qubaid dinámicamente
try {
    $client = getMoodleClient();
    $review = $client->request(
        $moodleToken,
        'mod_quiz_get_attempt_data',
        ['attemptid' => $attemptId, 'page' => 0]
    );
    $qubaid = 0;
    if (!empty($review['questions'][0]['html'])) {
        if (preg_match('/name="q(\d+):\d+_answer"/', $review['questions'][0]['html'], $m)) {
            $qubaid = (int)$m[1];
        }
    }
    if ($qubaid <= 0) {
        throw new \RuntimeException('No se pudo extraer qubaid');
    }
    error_log('[SUBMIT_ATTEMPT] qubaid extraído: ' . $qubaid);
} catch (\Exception $e) {
    http_response_code(500);
    error_log('[SUBMIT_ATTEMPT] Error extrayendo qubaid: ' . $e->getMessage());
    exit(json_encode([
        'status'=>'error',
        'msg'=>'No se pudo obtener qubaid',
        'debug'=>$e->getMessage()
    ], JSON_UNESCAPED_UNICODE));
}

// Construir array data[] para mod_quiz_save_attempt
$data = [];
foreach ($answers as $slot => $value) {
    $slot = (int)$slot;
    $values = is_array($value) ? $value : [(string)$value];

    foreach ($values as $v) {
        $data[] = [
            'name'  => "q{$qubaid}:{$slot}_answer",
            'value' => (string)$v
        ];
    }

    $data[] = [
        'name'  => "q{$qubaid}:{$slot}_:sequencecheck",
        'value' => "1"
    ];
    $data[] = [
        'name'  => "q{$qubaid}:{$slot}_:flagged",
        'value' => "0"
    ];
}

error_log('[SUBMIT_ATTEMPT] Estructura data[]: ' . print_r($data, true));

// Invocar WS mod_quiz_save_attempt
try {
    $response = $client->request(
        $moodleToken,
        'mod_quiz_save_attempt',
        [
            'attemptid' => $attemptId,
            'data'      => $data
        ]
    );
    error_log('[SUBMIT_ATTEMPT] Respuesta WS: ' . print_r($response, true));

    echo json_encode([
        'status'   => 'ok',
        'response' => $response
    ], JSON_UNESCAPED_UNICODE);

} catch (\Exception $e) {
    http_response_code(500);
    error_log('[SUBMIT_ATTEMPT] Exception WS: ' . $e->getMessage());
    exit(json_encode([
        'status'=>'error',
        'msg'=>'Error al guardar respuestas',
        'debug'=>$e->getMessage()
    ], JSON_UNESCAPED_UNICODE));
}
