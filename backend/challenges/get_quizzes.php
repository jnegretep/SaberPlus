<?php
declare(strict_types=1);

// get_quizzes.php — Lista los quizzes de un área/nivel usando JWT + moodle_token

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

// 4) Validar parámetros area + level
$area  = $_GET['area']  ?? null;
$level = $_GET['level'] ?? null;

if (!$area || !$level) {
    http_response_code(400);
    exit(json_encode(['status'=>'error','msg'=>'Parámetros area y level requeridos']));
}

// Mapeo de cursos por área y nivel (nivel1..nivel4)
$courseMap = [
    'lectura' => [
        'nivel1' => [32, 33],
        'nivel2' => [34],
        'nivel3' => [35],
        'nivel4' => [36],
    ],
    'naturales' => [
        'nivel1' => [37, 38],
        'nivel2' => [39],
        'nivel3' => [40],
        'nivel4' => [41],
    ],
    'sociales' => [
        'nivel1' => [42, 43],
        'nivel2' => [44],
        'nivel3' => [45],
        'nivel4' => [46],
    ],
    'ingles' => [
        'nivel1' => [47, 48],
        'nivel2' => [49],
        'nivel3' => [50],
        'nivel4' => [51],
    ],
    'matematicas' => [
        'nivel1' => [19, 20],
        'nivel2' => [21],
        'nivel3' => [22],
        'nivel4' => [23],
    ],
];

// Validar directamente nivel1..nivel4
if (!isset($courseMap[$area]) || !isset($courseMap[$area][$level])) {
    http_response_code(400);
    exit(json_encode(['status'=>'error','msg'=>'Área o nivel inválido']));
}

$courses = $courseMap[$area][$level] ?? [];

if (empty($courses)) {
    echo json_encode(['status'=>'ok','quizzes'=>[]]);
    exit;
}

// 5) Recuperar moodle_token del usuario
$stmt = $conexion->prepare("
    SELECT moodle_token
      FROM usuarios
     WHERE moodle_id = :mid
     LIMIT 1
");
$stmt->execute([':mid' => $moodleUserId]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$row) {
    http_response_code(404);
    exit(json_encode(['status'=>'error','msg'=>'Usuario no encontrado']));
}
$moodleToken = $row['moodle_token'];

// 6) Llamar a Moodle WS para cada curso
try {
    $client = getMoodleClient();
    $quizzes = [];

    foreach ($courses as $courseId) {
        $result = $client->request(
            $moodleToken,
            'mod_quiz_get_quizzes_by_courses',
            ['courseids[0]' => $courseId]
        );

        $rawQuizzes = $result['quizzes'] ?? [];
        foreach ($rawQuizzes as $q) {
            $quizzes[] = [
                'quizid'    => $q['id'] ?? null,
                'courseid'  => $q['course'] ?? null,
                'title'     => $q['name'] ?? 'Sin título', // ?? ahora devolvemos siempre "title"
                'timelimit' => $q['timelimit'] ?? 0,
                'questions' => isset($q['questions']) ? (int)$q['questions'] : 0,
                'area'      => $area,
                'level'     => $level
            ];
        }
    }

    echo json_encode(['status'=>'ok','quizzes'=>$quizzes]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'status'=>'error',
        'msg'=>'Error Moodle WS',
        'debug'=>$e->getMessage()
    ]);
}
