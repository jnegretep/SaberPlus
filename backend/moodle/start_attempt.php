<?php
declare(strict_types=1);

// start_attempt.php — Inicia o reanuda intento de quiz en Moodle
//
// FIX (Fase 2):
//  1. Eliminado el require duplicado de includes/moodle.php (se ejecutaba 2 veces).
//  2. Añadido require de includes/moodle_db.php.
//  3. Acepta "courseid" opcional en el body ? acelera timelimit.
//  4. resolve_timelimit: primero DB (mdl_quiz.timelimit), luego WS con
//     el courseid dado. Eliminado el bucle de 46 cursos (era el 38s).
//  5. Errores de negocio (attemptalreadyclosed) devuelven HTTP 409 en
//     lugar de 500.

error_log('[START_ATTEMPT] Script iniciado');

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

require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle_db.php';   // NUEVO
$mcfg      = require __DIR__ . '/../includes/moodle.php';  // único require
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

// JWT
$hdrs = function_exists('getallheaders') ? getallheaders() : [];
$ah   = $hdrs['Authorization'] ?? $hdrs['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';

if (!preg_match('/Bearer\s+(\S+)/', $ah, $m)) {
    http_response_code(401);
    error_log('[START_ATTEMPT] Bearer token no encontrado');
    exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
}

try {
    $decoded      = JWT::decode($m[1], new Key($configJwt['secret'], 'HS256'));
    $moodleUserId = (int)$decoded->data->moodle_userid;
} catch (Exception $e) {
    http_response_code(401);
    error_log('[START_ATTEMPT] Error JWT: ' . $e->getMessage());
    exit(json_encode(['status' => 'error', 'msg' => 'Token inválido']));
}

// Input
$input   = json_decode(file_get_contents('php://input'), true) ?: [];
$quizId  = (int)($input['quizid'] ?? 0);
$courseIdHint = (int)($input['courseid'] ?? 0);   // NUEVO: opcional

if ($quizId <= 0) {
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'Falta quizid']));
}

// Token Moodle del usuario
$stmt = $conexion->prepare("SELECT moodle_token FROM usuarios WHERE moodle_id = :mid LIMIT 1");
$stmt->execute([':mid' => $moodleUserId]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);
if (empty($row['moodle_token'])) {
    http_response_code(404);
    exit(json_encode(['status' => 'error', 'msg' => 'Usuario no encontrado']));
}
$moodleToken = $row['moodle_token'];

/**
 * FIX Fase 2: timelimit desde BD. Esta es la fuente de verdad rápida.
 * Solo si la BD falla caemos al WS (que puede tardar 1-2s más).
 */
function resolve_timelimit_fast(int $quizId, int $courseIdHint, $client, string $token): int {
    // 1) DB (rapidísimo, ~1 ms)
    $db = getMoodleDBConnection();
    if ($db !== null) {
        try {
            $stmt = $db->prepare("SELECT timelimit FROM mdl_quiz WHERE id = ?");
            $stmt->execute([$quizId]);
            $tl = $stmt->fetchColumn();
            if ($tl !== false) {
                error_log("[START_ATTEMPT] timelimit via DB: " . (int)$tl);
                return (int)$tl;
            }
        } catch (\Throwable $e) {
            error_log("[START_ATTEMPT] DB timelimit error: " . $e->getMessage());
        }
    }

    // 2) WS con courseid dado (1 sola llamada)
    if ($courseIdHint > 0) {
        try {
            $ql = $client->request($token, 'mod_quiz_get_quizzes_by_courses', ['courseids' => [$courseIdHint]]);
            foreach ($ql['quizzes'] ?? [] as $q) {
                if ((int)$q['id'] === $quizId) {
                    $tl = (int)($q['timelimit'] ?? 0);
                    error_log("[START_ATTEMPT] timelimit via WS courseid=$courseIdHint: $tl");
                    return $tl;
                }
            }
        } catch (Exception $e) {
            error_log('[START_ATTEMPT] WS timelimit error: ' . $e->getMessage());
        }
    }

    // 3) Último recurso: access_information (lento pero mejor que 0)
    try {
        $qa = $client->request($token, 'mod_quiz_get_quiz_access_information', ['quizid' => $quizId]);
        $cid = (int)($qa['quiz']['course'] ?? 0);
        if ($cid > 0) {
            $ql = $client->request($token, 'mod_quiz_get_quizzes_by_courses', ['courseids' => [$cid]]);
            foreach ($ql['quizzes'] ?? [] as $q) {
                if ((int)$q['id'] === $quizId) {
                    return (int)($q['timelimit'] ?? 0);
                }
            }
        }
    } catch (Exception $e) {
        error_log('[START_ATTEMPT] access_info fallback error: ' . $e->getMessage());
    }

    return 0;
}

try {
    $client = getMoodleClient();
    $url = rtrim($mcfg['base_url'], '/') . $mcfg['ws_endpoint'];

    // 1. Buscar intento en progreso
    $checkQuery = http_build_query([
        'wstoken' => $moodleToken,
        'wsfunction' => 'mod_quiz_get_user_attempts',
        'moodlewsrestformat' => 'json',
    ]);
    $ch = curl_init($url . '?' . $checkQuery);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, ['quizid' => $quizId, 'userid' => $moodleUserId, 'status' => 'all']);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    $checkResult = curl_exec($ch);
    curl_close($ch);

    $attempts = json_decode($checkResult, true)['attempts'] ?? [];
    $now = time();
    foreach ($attempts as $att) {
        if (($att['state'] ?? '') === 'inprogress') {
            $tc = $att['timecheckstate'] ?? null;
            if ($tc && $now > $tc) {
                error_log('[START_ATTEMPT] inprogress caducado, se ignora (id=' . $att['id'] . ')');
                continue;
            }
            $timelimit = resolve_timelimit_fast((int)$att['quiz'], $courseIdHint, $client, $moodleToken);
            echo json_encode([
                'status' => 'ok',
                'attemptid' => (int)$att['id'],
                'uniqueid' => (int)$att['uniqueid'],
                'timelimit' => $timelimit,
                'timestart' => $att['timestart'] ?? 0,
                'timefinish' => $att['timefinish'] ?? 0,
                'timeleft' => $att['timeleft'] ?? null,
                'warnings' => [],
            ]);
            exit;
        }
    }

    // 2. Nuevo intento
    $query = http_build_query([
        'wstoken' => $moodleToken,
        'wsfunction' => 'mod_quiz_start_attempt',
        'moodlewsrestformat' => 'json',
    ]);
    $ch = curl_init($url . '?' . $query);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, ['quizid' => $quizId, 'forcenew' => 0]);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    $result = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($httpCode !== 200 || !$result) {
        throw new Exception('Error HTTP: ' . $httpCode);
    }

    $response = json_decode($result, true);
    if (isset($response['exception'])) {
        $msg = $response['message'] ?? 'Error Moodle';
        $code = str_contains($msg, 'already closed') || str_contains($msg, 'attemptalreadyclosed') ? 409 : 500;
        http_response_code($code);
        exit(json_encode(['status' => 'error', 'msg' => $msg]));
    }

    $attempt = $response['attempt'] ?? [];
    $attemptId = $attempt['id'] ?? null;
    if (!$attemptId) {
        throw new Exception('No se recibió attempt.id');
    }

    $timelimit = resolve_timelimit_fast($quizId, $courseIdHint, $client, $moodleToken);
    error_log("[START_ATTEMPT] timelimit resuelto: $timelimit");

    echo json_encode([
        'status' => 'ok',
        'attemptid' => (int)$attemptId,
        'uniqueid' => (int)($attempt['uniqueid'] ?? 0),
        'timelimit' => $timelimit,
        'timestart' => $attempt['timestart'] ?? 0,
        'timefinish' => $attempt['timefinish'] ?? 0,
        'timeleft' => $attempt['timeleft'] ?? null,
        'warnings' => $response['warnings'] ?? [],
    ]);
} catch (Exception $e) {
    http_response_code(500);
    error_log('[START_ATTEMPT] Exception: ' . $e->getMessage());
    exit(json_encode([
        'status' => 'error',
        'msg' => 'Error al iniciar/reanudar intento',
        'debug' => $e->getMessage(),
    ]));
}