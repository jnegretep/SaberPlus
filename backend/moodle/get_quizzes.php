<?php
declare(strict_types=1);

// get_quizzes.php — Lista los quizzes de un curso usando JWT + moodle_token

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
require __DIR__ . '/../includes/moodle.php';        // Moodle config + getMoodleClient()
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
    $moodleUserId = (int)$decoded->data->moodle_userid;
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status'=>'error','msg'=>'Token inválido']));
}

// 4) Validar parámetro courseid
$courseId = filter_input(INPUT_GET, 'courseid', FILTER_VALIDATE_INT);
if (! $courseId) {
    http_response_code(400);
    exit(json_encode(['status'=>'error','msg'=>'Parámetro courseid faltante o inválido']));
}

// 5) Recuperar moodle_token
$stmt = $conexion->prepare("
    SELECT moodle_token
      FROM usuarios
     WHERE moodle_id = :mid
     LIMIT 1
");
$stmt->execute([':mid' => $moodleUserId]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);
if (! $row) {
    http_response_code(404);
    exit(json_encode(['status'=>'error','msg'=>'Usuario no encontrado']));
}
$moodleToken = $row['moodle_token'];

// 6) Llamar a Moodle WS
try {
    $client = getMoodleClient(); // ? helper centralizado
    $result = $client->request(
        $moodleToken,
        'mod_quiz_get_quizzes_by_courses',
        ['courseids[0]' => $courseId]
    );

    $rawQuizzes = $result['quizzes'] ?? [];
    $warnings   = $result['warnings'] ?? [];

    // 7) Normalizar listado de quizzes
    $out = array_map(fn(array $q) => [
        'quizid'    => $q['id'] ?? null,
        'courseid'  => $q['course'] ?? null,
        'name'      => $q['name'] ?? null,
        'timelimit' => $q['timelimit'] ?? 0,
        'questions' => isset($q['questions']) ? (int)$q['questions'] : 0,
    ], $rawQuizzes);

    echo json_encode([
        'status'   => 'ok',
        'quizzes'  => $out,
        'warnings' => $warnings
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'status'=>'error',
        'msg'=>'Error Moodle WS',
        'debug'=>$e->getMessage()
    ]);
}
