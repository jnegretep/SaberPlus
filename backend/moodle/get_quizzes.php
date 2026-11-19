<?php
declare(strict_types=1);

// get_quizzes.php — Lista los quizzes de un curso usando JWT + moodle_token
//
// FIX (Fase 2):
//  1. Formato de parámetro de WS: 'courseids' => [$courseId] (antes era
//     'courseids[0]' => $courseId, que Moodle ignoraba).
//  2. Enriquecimiento con DB: timelimit y questions reales desde
//     mdl_quiz y mdl_quiz_slots. Antes llegaban siempre 0 porque
//     mod_quiz_get_quizzes_by_courses NO devuelve 'questions'.

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: GET, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
}

require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle.php';
require __DIR__ . '/../includes/moodle_db.php';   // NUEVO
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

$hdrs = function_exists('getallheaders') ? getallheaders() : [];
$authHeader = $hdrs['Authorization'] ?? $hdrs['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';

if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
}

try {
    $decoded = JWT::decode($m[1], new Key($configJwt['secret'], 'HS256'));
    $moodleUserId = (int)$decoded->data->moodle_userid;
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Token inválido']));
}

$courseId = filter_input(INPUT_GET, 'courseid', FILTER_VALIDATE_INT);
if (!$courseId) {
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'Parámetro courseid faltante o inválido']));
}

$stmt = $conexion->prepare("SELECT moodle_token FROM usuarios WHERE moodle_id = :mid LIMIT 1");
$stmt->execute([':mid' => $moodleUserId]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$row) {
    http_response_code(404);
    exit(json_encode(['status' => 'error', 'msg' => 'Usuario no encontrado']));
}
$moodleToken = $row['moodle_token'];

try {
    $client = getMoodleClient();

    // FIX: 'courseids' => [int] (no 'courseids[0]')
    $result = $client->request(
        $moodleToken,
        'mod_quiz_get_quizzes_by_courses',
        ['courseids' => [$courseId]]
    );

    $rawQuizzes = $result['quizzes'] ?? [];
    $warnings   = $result['warnings'] ?? [];

    // FIX: enriquecer con DB (timelimit + questions reales)
    $db = getMoodleDBConnection();
    $metaMap = [];   // quizid => ['timelimit' => N, 'questions' => N]
    if ($db !== null && !empty($rawQuizzes)) {
        try {
            $ids = array_map(fn($q) => (int)$q['id'], $rawQuizzes);
            $ph = implode(',', array_fill(0, count($ids), '?'));
            $stmtMeta = $db->prepare("
                SELECT q.id AS quizid,
                       q.timelimit,
                       (SELECT COUNT(*) FROM mdl_quiz_slots qs WHERE qs.quizid = q.id) AS questions
                  FROM mdl_quiz q
                 WHERE q.id IN ($ph)
            ");
            $stmtMeta->execute($ids);
            foreach ($stmtMeta->fetchAll(PDO::FETCH_ASSOC) as $r) {
                $metaMap[(int)$r['quizid']] = [
                    'timelimit' => (int)$r['timelimit'],
                    'questions' => (int)$r['questions'],
                ];
            }
        } catch (\Throwable $e) {
            error_log('[GET_QUIZZES] DB enrich error: ' . $e->getMessage());
        }
    }

    $out = array_map(function (array $q) use ($metaMap) {
        $qid = (int)($q['id'] ?? 0);
        $meta = $metaMap[$qid] ?? null;
        return [
            'quizid'    => $qid,
            'courseid'  => $q['course'] ?? null,
            'name'      => $q['name'] ?? null,
            'timelimit' => $meta['timelimit'] ?? (int)($q['timelimit'] ?? 0),
            'questions' => $meta['questions'] ?? (int)($q['questions'] ?? 0),
        ];
    }, $rawQuizzes);

    echo json_encode([
        'status'   => 'ok',
        'quizzes'  => $out,
        'warnings' => $warnings,
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'msg'    => 'Error Moodle WS',
        'debug'  => $e->getMessage(),
    ]);
}