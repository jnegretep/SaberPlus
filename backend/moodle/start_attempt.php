<?php
declare(strict_types=1);

// start_attempt.php — Inicia o reanuda intento de quiz en Moodle
error_log('[START_ATTEMPT] Script iniciado');

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
    error_log('[START_ATTEMPT] Método no permitido: ' . $_SERVER['REQUEST_METHOD']);
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
}

// Includes
require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle.php';
$mcfg      = require __DIR__ . '/../includes/moodle.php';
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

// Leer JWT
$hdrs = function_exists('getallheaders') ? getallheaders() : [];
$ah   = $hdrs['Authorization'] ?? $hdrs['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';
error_log('[START_ATTEMPT] Authorization header: ' . var_export($ah, true));

if (!preg_match('/Bearer\s+(\S+)/', $ah, $m)) {
    http_response_code(401);
    error_log('[START_ATTEMPT] Bearer token no encontrado');
    exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
}

$appToken = $m[1];
error_log('[START_ATTEMPT] Token extraído: ' . substr($appToken, 0, 8) . '...');

try {
    $decoded      = JWT::decode($appToken, new Key($configJwt['secret'], 'HS256'));
    $moodleUserId = (int)$decoded->data->moodle_userid;
    error_log('[START_ATTEMPT] JWT decodificado, moodleUserId=' . $moodleUserId);
} catch (Exception $e) {
    http_response_code(401);
    error_log('[START_ATTEMPT] Error JWT: ' . $e->getMessage());
    exit(json_encode(['status' => 'error', 'msg' => 'Token inválido']));
}

// Leer JSON
$rawInput = file_get_contents('php://input');
error_log('[START_ATTEMPT] Raw input: ' . $rawInput);
$input   = json_decode($rawInput, true) ?? [];
$quizId  = isset($input['quizid']) ? (int)$input['quizid'] : 0;

if ($quizId <= 0) {
    http_response_code(400);
    error_log('[START_ATTEMPT] quizid inválido');
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
    error_log('[START_ATTEMPT] Error BD: ' . $e->getMessage());
    exit(json_encode(['status' => 'error', 'msg' => 'Error de base de datos']));
}

if (empty($row['moodle_token'])) {
    http_response_code(404);
    error_log('[START_ATTEMPT] moodle_token no encontrado para usuario ' . $moodleUserId);
    exit(json_encode(['status' => 'error', 'msg' => 'Usuario no encontrado']));
}

$moodleToken = $row['moodle_token'];
error_log('[START_ATTEMPT] moodle_token: ' . substr($moodleToken, 0, 8) . '...');

$url = rtrim($mcfg['base_url'], '/') . $mcfg['ws_endpoint'];
$client = getMoodleClient();

function resolve_timelimit($client, string $token, int $quizId, int $userId): int {
    // 1) Intentar por quiz_access_information -> course -> quizzes_by_courses
    try {
        $qa = $client->request($token, 'mod_quiz_get_quiz_access_information', ['quizid' => $quizId]);
        $courseId = $qa['quiz']['course'] ?? null;
        error_log("[START_ATTEMPT] access_info courseId=" . ($courseId ?? 'null'));
        if ($courseId) {
            $ql = $client->request($token, 'mod_quiz_get_quizzes_by_courses', ['courseids' => [$courseId]]);
            if (!empty($ql['quizzes'])) {
                foreach ($ql['quizzes'] as $q) {
                    if ((int)$q['id'] === $quizId) {
                        $tl = (int)$q['timelimit'];
                        error_log("[START_ATTEMPT] timelimit via courseId=$courseId: $tl");
                        return $tl;
                    }
                }
            }
        }
    } catch (Exception $e) {
        error_log('[START_ATTEMPT] resolve_timelimit step1 error: ' . $e->getMessage());
    }

    // 2) Fallback: recorrer todos los cursos del usuario y buscar el quiz
    try {
        $courses = $client->request($token, 'core_enrol_get_users_courses', ['userid' => $userId]);
        foreach ($courses as $c) {
            $cid = (int)($c['id'] ?? 0);
            if ($cid <= 0) continue;
            $ql = $client->request($token, 'mod_quiz_get_quizzes_by_courses', ['courseids' => [$cid]]);
            if (!empty($ql['quizzes'])) {
                foreach ($ql['quizzes'] as $q) {
                    if ((int)$q['id'] === $quizId) {
                        $tl = (int)$q['timelimit'];
                        error_log("[START_ATTEMPT] timelimit via user courses cid=$cid: $tl");
                        return $tl;
                    }
                }
            }
        }
    } catch (Exception $e) {
        error_log('[START_ATTEMPT] resolve_timelimit step2 error: ' . $e->getMessage());
    }

    error_log('[START_ATTEMPT] timelimit no resuelto, devolviendo 0');
    return 0;
}

try {
    // 1. Reanudar intento en progreso si existe y no está caducado
    $checkParams = [
        'quizid' => $quizId,
        'userid' => $moodleUserId,
        'status' => 'all'
    ];
    $checkQuery = http_build_query([
        'wstoken' => $moodleToken,
        'wsfunction' => 'mod_quiz_get_user_attempts',
        'moodlewsrestformat' => 'json'
    ]);

    $ch = curl_init($url . '?' . $checkQuery);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $checkParams);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    $checkResult = curl_exec($ch);
    curl_close($ch);

    error_log('[START_ATTEMPT] get_user_attempts response: ' . $checkResult);

    $attempts = json_decode($checkResult, true)['attempts'] ?? [];
    $now = time();
    foreach ($attempts as $att) {
        if (($att['state'] ?? '') === 'inprogress') {
            $timecheck = $att['timecheckstate'] ?? null;
            if ($timecheck && $now > $timecheck) {
                error_log('[START_ATTEMPT] Intento inprogress caducado, se ignora (id=' . $att['id'] . ')');
                continue;
            }
            $timelimit = resolve_timelimit($client, $moodleToken, (int)$att['quiz'], $moodleUserId);

            echo json_encode([
                'status'    => 'ok',
                'attemptid' => (int)$att['id'],
                'uniqueid'  => (int)$att['uniqueid'],
                'timelimit' => $timelimit,
                'timestart' => $att['timestart'] ?? 0,
                'timefinish'=> $att['timefinish'] ?? 0,
                'timeleft'  => $att['timeleft'] ?? null,
                'warnings'  => []
            ]);
            exit;
        }
    }

    // 2. Iniciar intento nuevo
    $params = [
        'quizid'   => $quizId,
        'forcenew' => 0
    ];
    error_log('[START_ATTEMPT] WS params: ' . print_r($params, true));

    $query = http_build_query([
        'wstoken' => $moodleToken,
        'wsfunction' => 'mod_quiz_start_attempt',
        'moodlewsrestformat' => 'json'
    ]);

    $ch = curl_init($url . '?' . $query);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $params);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    $result = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    error_log('[START_ATTEMPT] start_attempt response: ' . $result);

    if ($httpCode !== 200 || !$result) {
        throw new Exception('Error HTTP: ' . $httpCode);
    }

    $response = json_decode($result, true);
    $attempt  = $response['attempt'] ?? [];
    $attemptId = $attempt['id'] ?? null;
    $uniqueId  = $attempt['uniqueid'] ?? null;

    if (!$attemptId) {
        throw new Exception('No se recibió attempt.id');
    }

    // timelimit robusto
    $timelimit = resolve_timelimit($client, $moodleToken, $quizId, $moodleUserId);
    error_log("[START_ATTEMPT] timelimit resuelto: $timelimit");

    echo json_encode([
        'status'    => 'ok',
        'attemptid' => (int)$attemptId,
        'uniqueid'  => (int)$uniqueId,
        'timelimit' => $timelimit,
        'timestart' => $attempt['timestart'] ?? 0,
        'timefinish'=> $attempt['timefinish'] ?? 0,
        'timeleft'  => $attempt['timeleft'] ?? null,
        'warnings'  => $response['warnings'] ?? []
    ]);
} catch (Exception $e) {
    http_response_code(500);
    error_log('[START_ATTEMPT] WS Exception: ' . $e->getMessage());
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'Error al iniciar/reanudar intento',
        'debug'  => $e->getMessage()
    ]));
}
