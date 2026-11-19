<?php
declare(strict_types=1);

/**
 * start_quiz_fast.php - Saber+ Endpoint Consolidado de Inicio de Quiz
 *
 * Request: POST { quizid: 123, courseid: 26 (opcional, acelera timelimit) }
 * Response: { status: ok, attemptid, timelimit, timestart, questions: [...], savedResponses: {...} }
 *
 * HISTORIAL DE FIXES:
 *  Fase 2.1: rutas de require corregidas (faltaba "../"), timelimit vía DB.
 *  Fase 2.2: (a) NO borrar <input> del HTML — el parser los usa para
 *            identificar las opciones de respuesta dentro de <div rN>.
 *            (b) query de tags migrada de mdl_question_tags (Moodle 2.x,
 *            ya no existe) a mdl_tag_instance (schema moderno 3.x+).
 */

require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/config.php';
require __DIR__ . '/../includes/moodle.php';
require __DIR__ . '/../includes/moodle_db.php';
$__jwtCfg = require __DIR__ . '/../jwt_config.php';
if (is_array($__jwtCfg) && isset($__jwtCfg['secret'])) {
    $configJwt = $__jwtCfg;
}
if (!isset($configJwt) || !is_array($configJwt) || !isset($configJwt['secret'])) {
    error_log('[START_FAST] jwt_config.php no expone $configJwt[secret]');
    http_response_code(500);
    exit(json_encode(['status' => 'error', 'msg' => 'Configuración JWT inválida']));
}
unset($__jwtCfg);

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

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
    exit(json_encode(['status' => 'error', 'msg' => 'Metodo no permitido']));
}

// Autenticacion JWT
$hdrs = function_exists('getallheaders') ? getallheaders() : [];
$authHeader = $hdrs['Authorization'] ?? $hdrs['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';

if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
}

try {
    $decoded = JWT::decode($m[1], new Key($configJwt['secret'], 'HS256'));
    $userId = (int)($decoded->data->id_usuario ?? 0);
    if ($userId <= 0) {
        $userId = (int)($decoded->data->moodle_userid ?? 0);
    }
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Token invalido']));
}

// Leer input
$input = json_decode(file_get_contents('php://input'), true) ?: [];
$quizId = (int)($input['quizid'] ?? 0);
$courseIdHint = (int)($input['courseid'] ?? 0);

if ($quizId <= 0) {
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'quizid requerido']));
}

try {
    // 1. Obtener moodle_token del usuario
    $stmt = $conexion->prepare("SELECT moodle_id, moodle_token FROM usuarios WHERE id_usuario = ? LIMIT 1");
    $stmt->execute([$userId]);
    $userRow = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$userRow || empty($userRow['moodle_token'])) {
        http_response_code(404);
        exit(json_encode(['status' => 'error', 'msg' => 'Usuario no tiene Moodle asociado']));
    }

    $moodleUserId = (int)$userRow['moodle_id'];
    $moodleToken = $userRow['moodle_token'];
    $proxyBase = getBackendFileProxyUrl();

    $client = getMoodleClient();

    // 2. Iniciar el intento (Moodle WS: mod_quiz_start_attempt)
    $startResult = $client->request($moodleToken, 'mod_quiz_start_attempt', [
        'quizid' => $quizId,
    ]);

    $attemptId = (int)($startResult['attempt']['id'] ?? 0);
    if ($attemptId <= 0) {
        throw new Exception('No se pudo iniciar el intento');
    }

    $attemptInfo = $startResult['attempt'] ?? [];
    $timestart = (int)($attemptInfo['timestart'] ?? 0);
    $timefinish = (int)($attemptInfo['timefinish'] ?? 0);
    $layout = $attemptInfo['layout'] ?? '';
    $uniqueId = (int)($attemptInfo['uniqueid'] ?? 0);

    // 3. Resolver timelimit — DB primero (rápido y fiable), WS como fallback.
    $timelimit = 0;
    $moodleDb = getMoodleDBConnection();
    if ($moodleDb !== null) {
        try {
            $stmtTL = $moodleDb->prepare("SELECT timelimit FROM mdl_quiz WHERE id = ?");
            $stmtTL->execute([$quizId]);
            $tl = $stmtTL->fetchColumn();
            if ($tl !== false) {
                $timelimit = (int)$tl;
                error_log("[START_FAST] timelimit via DB: $timelimit");
            }
        } catch (\Throwable $e) {
            error_log("[START_FAST] DB timelimit error: " . $e->getMessage());
        }
    }

    // Fallback WS solo si DB no respondió
    if ($timelimit === 0 && $moodleDb === null) {
        try {
            $courseId = $courseIdHint;
            if ($courseId <= 0) {
                $qa = $client->request($moodleToken, 'mod_quiz_get_quiz_access_information', ['quizid' => $quizId]);
                $courseId = (int)($qa['quiz']['course'] ?? 0);
            }
            if ($courseId > 0) {
                $ql = $client->request($moodleToken, 'mod_quiz_get_quizzes_by_courses', ['courseids' => [$courseId]]);
                if (!empty($ql['quizzes'])) {
                    foreach ($ql['quizzes'] as $q) {
                        if ((int)$q['id'] === $quizId) {
                            $timelimit = (int)($q['timelimit'] ?? 0);
                            break;
                        }
                    }
                }
            }
        } catch (Exception $e) {
            error_log("[START_FAST] WS timelimit error: " . $e->getMessage());
        }
    }

    // 4. Resolver questionids reales (consulta directa a BD Moodle)
    $slotToQuestionId = [];
    if ($uniqueId > 0 && $moodleDb !== null) {
        try {
            $stmtQids = $moodleDb->prepare("
                SELECT slot, questionid
                FROM mdl_question_attempts
                WHERE questionusageid = ?
                ORDER BY slot ASC
            ");
            $stmtQids->execute([$uniqueId]);
            foreach ($stmtQids->fetchAll(PDO::FETCH_ASSOC) as $row) {
                $slotToQuestionId[(int)$row['slot']] = (int)$row['questionid'];
            }
        } catch (\Throwable $e) {
            error_log("[START_FAST] Error resolviendo questionids: " . $e->getMessage());
        }
    }

    // 5. Obtener TODAS las páginas de preguntas en un solo loop
    $pagesSeparatorCount = substr_count(',' . $layout . ',', ',0,');
    $totalPages = max(1, $pagesSeparatorCount);

    $allQuestions = [];

    for ($page = 0; $page < $totalPages; $page++) {
        try {
            $pageData = $client->request($moodleToken, 'mod_quiz_get_attempt_data', [
                'attemptid' => $attemptId,
                'page' => $page,
            ]);

            $pageQuestions = $pageData['questions'] ?? [];

            foreach ($pageQuestions as &$q) {
                if (!empty($q['html'])) {
                    // Proxy de URLs de pluginfile (imágenes, PDFs).
                    $q['html'] = preg_replace_callback(
                        '#(https?://[^\s"\']*pluginfile\.php[^\s"\']*)#',
                        function($m) use ($proxyBase) {
                            return $proxyBase . '?url=' . urlencode($m[1]);
                        },
                        $q['html']
                    );

                    // ? FIX (Fase 2.2): NO borrar <input> del HTML.
                    // El parser (parseQuizQuestion) usa <input type="radio">
                    // para identificar las opciones de respuesta dentro de
                    // los <div class="r0/r1">. Si se borran, las opciones
                    // desaparecen y solo queda el enunciado. El flujo
                    // tradicional (get_attempt_data.php) NO los borra,
                    // por eso "continuar intento" sí funciona.
                    // Solo limpiamos comentarios HTML (no afectan al parser).
                    $q['html'] = preg_replace('/<!--.*?-->/s', '', $q['html']);
                }

                $slot = (int)($q['slot'] ?? 0);
                $q['questionid'] = $slotToQuestionId[$slot] ?? 0;
            }
            unset($q);

            $allQuestions = array_merge($allQuestions, $pageQuestions);
        } catch (Exception $e) {
            error_log("[START_FAST] Error obteniendo pagina $page: " . $e->getMessage());
        }
    }

    // 6. Procesar respuestas guardadas
    $savedResponses = [];
    foreach ($allQuestions as $q) {
        $slot = (int)($q['slot'] ?? 0);
        if ($slot > 0 && isset($q['data']) && is_array($q['data'])) {
            foreach ($q['data'] as $data) {
                if (isset($data['name']) && $data['name'] !== 'sequencecheck' && isset($data['value']) && $data['value'] !== '') {
                    $savedResponses[(string)$slot] = $data['value'];
                    break;
                }
            }
        }
    }

    // 7. Obtener tags de las preguntas
    $questionIds = array_filter(array_column($allQuestions, 'questionid'), fn($id) => $id > 0);
    $tagsMap = [];
    if (!empty($questionIds) && $moodleDb !== null) {
        try {
            $placeholders = implode(',', array_fill(0, count($questionIds), '?'));
            // ? FIX (Fase 2.2): mdl_question_tags es schema Moodle 2.x y
            // ya NO existe en 3.x+. El schema moderno es mdl_tag_instance
            // con component='core_question', itemtype='question'.
            // Antes el catch(\Throwable) silenciaba el "table not found"
            // y devolvía tags: [] a todas las preguntas.
            $stmtTags = $moodleDb->prepare("
                SELECT ti.itemid AS questionid, t.name
                FROM mdl_tag_instance ti
                JOIN mdl_tag t ON t.id = ti.tagid
                WHERE ti.component = 'core_question'
                  AND ti.itemtype = 'question'
                  AND ti.itemid IN ($placeholders)
            ");
            $stmtTags->execute($questionIds);
            foreach ($stmtTags->fetchAll(PDO::FETCH_ASSOC) as $row) {
                $qid = (string)$row['questionid'];
                if (!isset($tagsMap[$qid])) $tagsMap[$qid] = [];
                $tagsMap[$qid][] = $row['name'];
            }
        } catch (\Throwable $e) {
            error_log("[START_FAST] Error obteniendo tags: " . $e->getMessage());
        }
    }

    foreach ($allQuestions as &$q) {
        $qid = (string)($q['questionid'] ?? '0');
        $q['tags'] = $tagsMap[$qid] ?? [];
    }
    unset($q);

    // 8. Respuesta consolidada
    $response = [
        'status'         => 'ok',
        'attemptid'      => $attemptId,
        'timelimit'      => $timelimit,
        'timestart'      => $timestart,
        'timefinish'     => $timefinish,
        'questions'      => $allQuestions,
        'savedResponses' => $savedResponses,
        'total_pages'    => $totalPages,
    ];

    error_log("[START_FAST] Quiz $quizId iniciado. Attempt: $attemptId. Preguntas: " . count($allQuestions));

    echo json_encode($response, JSON_UNESCAPED_UNICODE);

} catch (Throwable $e) {
    error_log("[START_FAST] Error: " . $e->getMessage());
    http_response_code(500);
    exit(json_encode([
        'status' => 'error',
        'msg'   => 'Error iniciando quiz',
        'debug' => $e->getMessage(),
    ]));
}