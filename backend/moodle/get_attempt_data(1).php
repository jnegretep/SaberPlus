<?php
declare(strict_types=1);

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
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
}

require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle.php';
require __DIR__ . '/../includes/moodle_db.php'; // ?? proporciona getMoodleDBConnection() y MOODLE_DB_PREFIX
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

function extractJWTToken(): string {
    $allHeaders = function_exists('getallheaders') ? getallheaders() : [];
    $authHeader = $allHeaders['Authorization'] ?? $allHeaders['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $matches)) {
        http_response_code(401);
        exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
    }
    return $matches[1];
}

function clean_question_html(string $html): string {
    $html = preg_replace('#<script[^>]*>.*?</script>#is', '', $html);
    $html = preg_replace('#<noscript[^>]*>.*?</noscript>#is', '', $html);
    $html = preg_replace('/\son\w+="[^"]*"/i', '', $html);
    $html = preg_replace('/\sdata-[\w-]+="[^"]*"/i', '', $html);
    $html = preg_replace('/\sid="question-\d+-\d+"/i', '', $html);
    $html = preg_replace('#<span[^>]*class="answernumber"[^>]*>.*?</span>#i', '', $html);
    $html = preg_replace('/^\s*[a-z]\.\s*/i', '', trim($html));
    return $html;
}

function clean_questions(array &$questions): void {
    foreach ($questions as &$q) {
        $fields = ['questiontext', 'generalfeedback', 'rightanswer'];
        foreach ($fields as $field) {
            if (!empty($q[$field]['text'])) {
                $q[$field]['text'] = clean_question_html($q[$field]['text']);
            }
        }
        if (!empty($q['html'])) {
            $q['html'] = clean_question_html($q['html']);
        }
    }
}

function proxy_replace_urls(array &$questions, string $proxyBase): void {
    foreach ($questions as &$q) {
        $fields = ['questiontext', 'generalfeedback', 'rightanswer'];
        foreach ($fields as $field) {
            if (!empty($q[$field]['text'])) {
                $q[$field]['text'] = preg_replace_callback(
                    '#(https?://[^\s"\']*pluginfile\.php[^\s"\']*)#',
                    fn($match) => $proxyBase . '?url=' . urlencode($match[1]),
                    $q[$field]['text']
                );
            }
        }
    }
}

function fetch_attempt_data_page($client, string $token, int $attemptId, int $page): array {
    return $client->request($token, 'mod_quiz_get_attempt_data', [
        'attemptid' => $attemptId,
        'page'      => $page
    ]);
}

function fetch_attempt_review($client, string $token, int $attemptId): array {
    return $client->request($token, 'mod_quiz_get_attempt_review', [
        'attemptid' => $attemptId
    ]);
}

function process_saved_responses(array $questions): array {
    $savedResponses = [];
    foreach ($questions as $q) {
        if (empty($q['slot'])) continue;
        $slot = (string)$q['slot'];
        $resp = $q['responses'] ?? [];
        $answerVal = null;
        if (is_array($resp) && !empty($resp)) {
            if (isset($resp['answer']) && $resp['answer'] !== '') {
                $answerVal = $resp['answer'];
            } else {
                foreach ($resp as $val) {
                    if ($val !== '') {
                        $answerVal = $val;
                        break;
                    }
                }
            }
        }
        if ($answerVal === null && !empty($q['html'])) {
            if (preg_match('/<input[^>]+type="radio"[^>]+value="([^"]+)"[^>]+checked="checked"/i', $q['html'], $matches)) {
                $answerVal = $matches[1];
            }
        }
        if ($answerVal !== null) $savedResponses[$slot] = (string)$answerVal;
    }
    return $savedResponses;
}

// ================== ?? NUEVA FUNCIÓN: OBTENER QUESTIONID REAL DESDE question_attempts ==================
function resolveRealQuestionIds(int $uniqueId): array {
    $moodleDB = getMoodleDBConnection();
    if (!$moodleDB) {
        error_log("[RESOLVE] No se pudo conectar a la BD de Moodle");
        return [];
    }
    $prefix = MOODLE_DB_PREFIX;
    $sql = "SELECT slot, questionid 
            FROM {$prefix}question_attempts
            WHERE questionusageid = ?";
    $stmt = $moodleDB->prepare($sql);
    $stmt->execute([$uniqueId]);
    $map = [];
    while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $slot = (int)$row['slot'];
        $map[$slot] = (int)$row['questionid'];
    }
    return $map;
}
// =====================================================================================

// ================== OBTENER TAGS DIRECTAMENTE DE LA BD DE MOODLE ==================
function fetchTagsFromDB(array $questionIds): array {
    if (empty($questionIds)) return [];

    $moodleDB = getMoodleDBConnection();
    if (!$moodleDB) {
        error_log("[ETIQUETAS] No se pudo conectar a la base de datos de Moodle");
        return [];
    }

    $prefix = MOODLE_DB_PREFIX;
    $placeholders = implode(',', array_fill(0, count($questionIds), '?'));
    $sql = "SELECT ti.itemid AS questionid, t.name AS tagname
            FROM {$prefix}tag_instance ti
            JOIN {$prefix}tag t ON ti.tagid = t.id
            WHERE ti.component = 'core_question' 
              AND ti.itemtype = 'question' 
              AND ti.itemid IN ($placeholders)";
    
    $stmt = $moodleDB->prepare($sql);
    $stmt->execute($questionIds);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    $tagsMap = [];
    foreach ($rows as $row) {
        $qid = $row['questionid'];
        if (!isset($tagsMap[$qid])) $tagsMap[$qid] = [];
        $tagsMap[$qid][] = $row['tagname'];
    }
    return $tagsMap;
}
// =====================================================================

// --- INICIO ---
$appToken = extractJWTToken();
try {
    $decoded = JWT::decode($appToken, new Key($configJwt['secret'], 'HS256'));
    $moodleUserId = (int)$decoded->data->moodle_userid;
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Token inválido']));
}

$attemptId = filter_input(INPUT_GET, 'attemptid', FILTER_VALIDATE_INT);
if (!$attemptId) {
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'Falta parámetro attemptid']));
}

$stmt = $conexion->prepare("SELECT moodle_token FROM usuarios WHERE moodle_id = :mid LIMIT 1");
$stmt->execute([':mid' => $moodleUserId]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$row) {
    http_response_code(404);
    exit(json_encode(['status' => 'error', 'msg' => 'Usuario no encontrado']));
}
$moodleToken = $row['moodle_token'];

$base_url  = "http://172.93.49.94";
$proxyBase = $base_url . '/api/prepsaber/backend/get_file.php';

try {
    $client = getMoodleClient();
    $firstPage = null;
    $reviewMode = false;

    try {
        $firstPage = fetch_attempt_data_page($client, $moodleToken, $attemptId, 0);
    } catch (Exception $e) {
        if (stripos($e->getMessage(), 'attemptalreadyclosed') !== false ||
            stripos($e->getMessage(), 'ya ha sido finalizado') !== false) {
            $reviewMode = true;
            $firstPage = fetch_attempt_review($client, $moodleToken, $attemptId);
        } else {
            throw $e;
        }
    }

    if (!$reviewMode && !isset($firstPage['attempt']) && isset($firstPage['questions'])) {
        $reviewMode = true;
    }

    $allQuestions = [];
    $savedResponses = [];

    if ($reviewMode) {
        // Modo revisión: 'id' es questionid
        $questions = $firstPage['questions'] ?? [];
        foreach ($questions as &$q) {
            $q['questionid'] = $q['id'] ?? 0;
        }
        proxy_replace_urls($questions, $proxyBase);
        clean_questions($questions);
        $allQuestions = $questions;
        $savedResponses = process_saved_responses($questions);
        $grade = $firstPage['grade'] ?? null;
        $feedback = $firstPage['feedback'] ?? null;

        $questionIds = array_column($allQuestions, 'questionid');
        $tagsMap = fetchTagsFromDB($questionIds);
        foreach ($allQuestions as &$q) {
            $qid = (string)$q['questionid'];
            $q['tags'] = $tagsMap[$qid] ?? [];
        }

        echo json_encode([
            'status'        => 'ok',
            'attemptid'     => $attemptId,
            'reviewMode'    => true,
            'questions'     => $allQuestions,
            'savedResponses'=> $savedResponses,
            'grade'         => $grade,
            'feedback'      => $feedback,
            'warnings'      => $firstPage['warnings'] ?? [],
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }

    // ---------- Modo intento en curso (sin review) ----------
    $attemptInfo = $firstPage['attempt'] ?? [];
    $layout = $attemptInfo['layout'] ?? '';
    if (empty($layout)) {
        throw new Exception('Layout no disponible');
    }

    // ?? CORRECCIÓN: obtener uniqueid y resolver questionid reales
    $uniqueId = (int)($attemptInfo['uniqueid'] ?? 0);
    if (!$uniqueId) {
        throw new Exception('No se pudo obtener uniqueid del intento');
    }
    $slotToQuestionId = resolveRealQuestionIds($uniqueId);
    
    // Debug: logear mapeo obtenido
    error_log("[DEBUG] SLOT MAP (primeros 5): " . json_encode(array_slice($slotToQuestionId, 0, 5)));

    // Resolver timelimit
    function resolveTimelimit($client, string $token, int $quizId): int {
        try {
            $qa = $client->request($token, 'mod_quiz_get_quiz_access_information', ['quizid' => $quizId]);
            $courseId = $qa['quiz']['course'] ?? null;
            if ($courseId) {
                $ql = $client->request($token, 'mod_quiz_get_quizzes_by_courses', ['courseids' => [$courseId]]);
                if (!empty($ql['quizzes'])) {
                    foreach ($ql['quizzes'] as $q) {
                        if ((int)$q['id'] === $quizId) return (int)$q['timelimit'];
                    }
                }
            }
        } catch (Exception $e) {}
        return 0;
    }

    $quizId = (int)($attemptInfo['quiz'] ?? 0);
    $timelimit = resolveTimelimit($client, $moodleToken, $quizId);
    $timestart  = (int)($attemptInfo['timestart'] ?? 0);
    $timefinish = (int)($attemptInfo['timefinish'] ?? 0);

    $pagesSeparatorCount = substr_count(',' . $layout . ',', ',0,');
    $totalPages = max(1, $pagesSeparatorCount);

    // Recorrer todas las páginas y recolectar preguntas
    $allQuestions = [];
    for ($page = 0; $page < $totalPages; $page++) {
        if ($page == 0) {
            $pageData = $firstPage;
        } else {
            $pageData = fetch_attempt_data_page($client, $moodleToken, $attemptId, $page);
        }
        $pageQuestions = $pageData['questions'] ?? [];
        proxy_replace_urls($pageQuestions, $proxyBase);
        clean_questions($pageQuestions);
        // Asignar questionid usando el mapeo real
        foreach ($pageQuestions as &$q) {
            $slot = (int)($q['slot'] ?? 0);
            $q['questionid'] = $slotToQuestionId[$slot] ?? 0;
        }
        $allQuestions = array_merge($allQuestions, $pageQuestions);
    }

    $savedResponses = process_saved_responses($allQuestions);
    $questionIds = array_column($allQuestions, 'questionid');
    
    // Debug: logear los questionids que se usarán para buscar etiquetas
    error_log("[DEBUG] QUESTION IDs (muestra): " . json_encode(array_slice($questionIds, 0, 5)));
    
    $tagsMap = fetchTagsFromDB($questionIds);
    foreach ($allQuestions as &$q) {
        $qid = (string)$q['questionid'];
        $q['tags'] = $tagsMap[$qid] ?? [];
    }

    // Log de cuántas preguntas tienen etiquetas
    $numWithTags = 0;
    foreach ($tagsMap as $tags) {
        if (!empty($tags)) $numWithTags++;
    }
    error_log("[ETIQUETAS] Preguntas con etiquetas encontradas: $numWithTags de " . count($questionIds));

    echo json_encode([
        'status'         => 'ok',
        'attemptid'      => $attemptId,
        'reviewMode'     => false,
        'total_pages'    => $totalPages,
        'questions'      => $allQuestions,
        'savedResponses' => $savedResponses,
        'timelimit'      => $timelimit,
        'timestart'      => $timestart,
        'timefinish'     => $timefinish,
        'warnings'       => $firstPage['warnings'] ?? [],
        'debug_info'     => [
            'layout_raw'      => $layout,
            'total_questions' => count($allQuestions),
            'tags_found'      => $numWithTags
        ]
    ], JSON_UNESCAPED_UNICODE);

} catch (Exception $e) {
    http_response_code(500);
    error_log('[GET_ATTEMPT] Error: ' . $e->getMessage());
    echo json_encode([
        'status' => 'error',
        'msg'    => 'Error Moodle WS',
        'debug'  => $e->getMessage()
    ]);
}
