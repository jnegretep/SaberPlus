<?php
// /var/www/html/api/prepsaber/backend/challenges/get_challenge_results.php

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle.php';
require __DIR__ . '/../auth_middleware.php';

try {
    $challengeId = $_GET['challenge_id'] ?? null;
    $userId      = $authUser['id_usuario'] ?? null;

    if (empty($challengeId) || !is_numeric($challengeId)) {
        http_response_code(400);
        echo json_encode(['status'=>'error','msg'=>'challenge_id es requerido']);
        exit;
    }

    // ======== Consultar reto ========
    $stmt = $conexion->prepare("
        SELECT id, title, area, level, duration_minutes, status, started_at, ended_at, quiz_id
        FROM challenges 
        WHERE id=? LIMIT 1
    ");
    $stmt->execute([$challengeId]);
    $challenge = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$challenge) {
        http_response_code(404);
        echo json_encode(['status'=>'error','msg'=>'Reto no encontrado']);
        exit;
    }
    
    error_log("[get_challenge_results] ? Reto {$challengeId} encontrado, status={$challenge['status']}");

    // ======== Ranking MEJORADO - CALCULA TIEMPO EMPLEADO CORRECTAMENTE ========
    $sqlRanking = "
        SELECT 
            cp.user_id AS user_id,
            u.nombre,
            u.avatar_path,
            COALESCE(cp.score, 0) AS score,
            cp.start_time,
            cp.end_time,
            cp.finished_at,
            cp.answers_json,
            -- Calcular tiempo empleado de forma robusta:
            CASE 
                WHEN cp.elapsed_seconds IS NOT NULL AND cp.elapsed_seconds > 0 THEN cp.elapsed_seconds
                WHEN cp.end_time IS NOT NULL AND cp.start_time IS NOT NULL THEN 
                    TIMESTAMPDIFF(SECOND, cp.start_time, cp.end_time)
                WHEN cp.finished_at IS NOT NULL AND cp.start_time IS NOT NULL THEN
                    TIMESTAMPDIFF(SECOND, cp.start_time, cp.finished_at)
                ELSE 0
            END AS elapsed
        FROM challenge_participants cp
        INNER JOIN usuarios u ON u.id_usuario = cp.user_id
        WHERE cp.challenge_id = :cid 
        AND cp.invitation_status = 'aceptado'
        ORDER BY 
            CASE WHEN COALESCE(cp.score, 0) = 0 THEN 1 ELSE 0 END, -- Poner scores 0 al final
            cp.score DESC, 
            elapsed ASC
    ";
    
    $stmt = $conexion->prepare($sqlRanking);
    $stmt->execute([':cid' => $challengeId]);
    $rankingRows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Construir URL completa del avatar
    $baseUrl = (isset($_SERVER['REQUEST_SCHEME']) ? $_SERVER['REQUEST_SCHEME'] : 'http')
             . '://' . $_SERVER['HTTP_HOST']
             . '/api/prepsaber/backend/uploads/avatars/';

    $pos = 1;
    foreach ($rankingRows as &$r) {
        $r['position'] = $pos++;
        $r['score']    = (float)$r['score'];
        $r['elapsed']  = isset($r['elapsed']) ? (int)$r['elapsed'] : 0;
        
        // Marcar si el score fue calculado (para el frontend)
        $r['score_calculated'] = false;
        if ($r['score'] == 0 && !empty($r['answers_json'])) {
            // Intentar obtener score del answers_json si existe
            $answersData = json_decode($r['answers_json'], true);
            if ($answersData && isset($answersData['grade'])) {
                $r['score'] = (float)$answersData['grade'];
                $r['score_calculated'] = true;
            }
        }

        if (!empty($r['avatar_path'])) {
            $r['avatar_url'] = $baseUrl . $r['avatar_path'];
        } else {
            $r['avatar_url'] = null;
        }

        error_log("[get_challenge_results] ?? Pos {$r['position']} user={$r['user_id']} score={$r['score']} tiempo={$r['elapsed']}s avatar={$r['avatar_url']}");
    }

    // ======== Attempt del usuario actual ========
    $stmt = $conexion->prepare("
        SELECT moodle_attempt_id
        FROM challenge_participants
        WHERE challenge_id = ? AND user_id = ?
        LIMIT 1
    ");
    $stmt->execute([$challengeId, $userId]);
    $attemptRow = $stmt->fetch(PDO::FETCH_ASSOC);
    $attemptId = $attemptRow['moodle_attempt_id'] ?? null;

    $questions = [];
    if ($attemptId) {
        $stmt = $conexion->prepare("SELECT moodle_token FROM usuarios WHERE id_usuario = ? LIMIT 1");
        $stmt->execute([$userId]);
        $u = $stmt->fetch(PDO::FETCH_ASSOC);
        $token = $u['moodle_token'] ?? null;

        if ($token) {
            $mc = getMoodleClient();
            try {
                $review = $mc->request($token, 'mod_quiz_get_attempt_review', [
                    'attemptid' => (int)$attemptId
                ]);

                if (isset($review['questions']) && is_array($review['questions'])) {
                    foreach ($review['questions'] as $q) {
                        $html = $q['html'] ?? '';
                        $slot = $q['slot'] ?? null;
                        if (!empty($html) && $slot !== null) {
                            $questions[] = [
                                'html' => $html,
                                'slot' => (int)$slot,
                            ];
                        }
                    }
                }
            } catch (Exception $e) {
                error_log("[get_challenge_results][Moodle] Error obteniendo review attempt={$attemptId}: ".$e->getMessage());
            }
        }
    }

    echo json_encode([
        'status'    => 'ok',
        'challenge' => $challenge,
        'ranking'   => $rankingRows,
        'questions' => $questions,
        'total'     => count($rankingRows),
        'current_user_id' => $userId
    ]);
    exit;

} catch (\Throwable $e) {
    error_log("[get_challenge_results][ERROR] ".$e->getMessage());
    http_response_code(500);
    echo json_encode([
        'status'=>'error',
        'msg'=>'Error interno',
        'detail'=>$e->getMessage()
    ]);
    exit;
}