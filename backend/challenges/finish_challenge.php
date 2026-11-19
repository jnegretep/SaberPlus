<?php
// /var/www/html/api/prepsaber/backend/challenges/finish_challenge.php
declare(strict_types=1);

function utf8ize($mixed) {
    if (is_array($mixed)) {
        foreach ($mixed as $k => $v) $mixed[$k] = utf8ize($v);
        return $mixed;
    } elseif (is_string($mixed)) {
        return mb_convert_encoding($mixed, 'UTF-8', 'UTF-8');
    }
    return $mixed;
}

while (ob_get_level() > 0) ob_end_clean();
ob_start();

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Authorization, Content-Type, X-Requested-With");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    $resp = '{"ok":true}';
    ob_end_clean();
    header("Content-Length: " . strlen($resp));
    echo $resp;
    exit;
}

error_log("===== finish_challenge.php =====");

require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle.php';
require __DIR__ . '/../auth_middleware.php';

if (ob_get_length() > 0) ob_clean();

function respond(array $payload, int $status = 200): void {
    if (ob_get_length() > 0) ob_clean();
    http_response_code($status);
    $payload = utf8ize($payload);
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE);
    if ($json === false) {
        $fallback = '{"status":"error","msg":"Error al codificar respuesta"}';
        header("Content-Length: " . strlen($fallback));
        echo $fallback;
        exit;
    }
    header("Content-Length: " . strlen($json));
    echo $json;
    exit;
}

// Read body robustly
$raw = file_get_contents('php://input');
error_log("[finish_challenge] RAW: " . $raw);

$data = json_decode($raw, true);
if (json_last_error() !== JSON_ERROR_NONE) {
    error_log("[finish_challenge] JSON inválido: " . json_last_error_msg());
    $data = $_POST;
}

$challengeId = $data['challenge_id'] ?? null;
$score       = $data['score'] ?? null;
$answers     = $data['answers'] ?? null;

$authUser = $GLOBALS['authUser'] ?? null;
if (!is_array($authUser) || !isset($authUser['id_usuario'])) {
    respond(['status' => 'error', 'msg' => 'Token no proporcionado o inválido'], 401);
}
$userId = (int)$authUser['id_usuario'];

if (!is_numeric($challengeId)) {
    respond(['status' => 'error', 'msg' => 'challenge_id requerido'], 400);
}
$challengeId = (int)$challengeId;

try {
    // Verificar el reto
    $stmtChk = $conexion->prepare("SELECT status, started_at, duration_minutes FROM challenges WHERE id = ? LIMIT 1");
    $stmtChk->execute([$challengeId]);
    $chRow = $stmtChk->fetch(PDO::FETCH_ASSOC);

    if (!$chRow) {
        respond(['status'=>'error','msg'=>'Reto no encontrado'], 404);
    }

    $statusNow = $chRow['status'] ?? null;
    $startedAtRaw = $chRow['started_at'] ?? null;
    $durationMinutes = (int)($chRow['duration_minutes'] ?? 0);

    // LÓGICA REACTIVA DE CIERRE POR TIEMPO - MEJORADA
    if (!empty($startedAtRaw) && $statusNow !== 'finalizado') {
        $startedAt = new DateTime($startedAtRaw, new DateTimeZone('UTC'));
        $endTime = (clone $startedAt)->modify("+{$durationMinutes} minutes");
        $nowUtc = new DateTime('now', new DateTimeZone('UTC'));
        $remainingSecondsCheck = max(0, $endTime->getTimestamp() - $nowUtc->getTimestamp());

        // Si el tiempo se acabó, procesar TODOS los participantes
        if ($remainingSecondsCheck <= 0) {
            $conexion->beginTransaction();
            try {
                // Obtener todos los participantes pendientes
                $stmtPend = $conexion->prepare("
                    SELECT cp.id, cp.user_id, cp.moodle_attempt_id, cp.start_time, u.moodle_token
                    FROM challenge_participants cp
                    JOIN usuarios u ON u.id_usuario = cp.user_id
                    WHERE cp.challenge_id = :cid
                    AND cp.invitation_status = 'aceptado'
                    AND cp.ready_status != 'terminado'
                ");
                $stmtPend->execute([':cid' => $challengeId]);
                $pending = $stmtPend->fetchAll(PDO::FETCH_ASSOC);
                
                // Procesar cada participante pendiente
                foreach ($pending as $participant) {
                    $participantScore = 0;
                    $participantAnswers = null;
                    
                    // Obtener puntaje real de Moodle si existe
                    if (!empty($participant['moodle_attempt_id']) && !empty($participant['moodle_token'])) {
                        try {
                            $mc = getMoodleClient();
                            $review = $mc->request($participant['moodle_token'], 'mod_quiz_get_attempt_review', [
                                'attemptid' => (int)$participant['moodle_attempt_id']
                            ]);
                            
                            if (isset($review['grade'])) {
                                $participantScore = (float)$review['grade'];
                                error_log("[finish_challenge] Puntaje real obtenido para user {$participant['user_id']}: {$participantScore}");
                            }
                        } catch (Throwable $e) {
                            error_log("[finish_challenge] Error obteniendo puntaje Moodle: " . $e->getMessage());
                        }
                    }
                    
                    // Calcular tiempo empleado
                    $elapsed = 0;
                    if (!empty($participant['start_time'])) {
                        $start = new DateTime($participant['start_time']);
                        $end = new DateTime();
                        $elapsed = max(0, $end->getTimestamp() - $start->getTimestamp());
                    }
                    
                    // Actualizar participante con datos reales
                    $updPart = $conexion->prepare("
                        UPDATE challenge_participants
                        SET ready_status = 'terminado',
                            end_time = NOW(),
                            finished_at = NOW(),
                            score = :score,
                            elapsed_seconds = :elapsed
                        WHERE id = :id
                    ");
                    $updPart->execute([
                        ':score' => $participantScore,
                        ':elapsed' => $elapsed,
                        ':id' => $participant['id']
                    ]);
                }
                
                // Marcar reto como finalizado
                $updC = $conexion->prepare("UPDATE challenges SET status='finalizado', ended_at = NOW() WHERE id = ?");
                $updC->execute([$challengeId]);
                
                $conexion->commit();
                
                // Devolver respuesta indicando que todos fueron procesados
                respond([
                    'status' => 'ok',
                    'msg' => 'Reto finalizado por tiempo. Todos los participantes han sido procesados.',
                    'finished' => true,
                    'pending_users' => [],
                    'remaining_time' => 0,
                    'time_expired' => true
                ], 200);
                
            } catch (Throwable $e) {
                if ($conexion->inTransaction()) $conexion->rollBack();
                error_log("[finish_challenge][ERROR auto-close] " . $e->getMessage());
                // Continuar con flujo normal
            }
        }
    }

    // FLUJO NORMAL (usuario finaliza manualmente)
    $conexion->beginTransaction();

    // Obtener información del participante
    $stmt = $conexion->prepare("
        SELECT id, invitation_status, ready_status, start_time, moodle_attempt_id
        FROM challenge_participants
        WHERE challenge_id = :cid AND user_id = :uid
        LIMIT 1
    ");
    $stmt->execute([':cid' => $challengeId, ':uid' => $userId]);
    $participant = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$participant) {
        $conexion->rollBack();
        respond(['status' => 'error', 'msg' => 'No estás participando en este reto'], 403);
    }
    
    if ($participant['invitation_status'] !== 'aceptado') {
        $conexion->rollBack();
        respond(['status' => 'error', 'msg' => 'Invitación no aceptada'], 403);
    }

    // Si ya está terminado, simplemente responder
    if ($participant['ready_status'] === 'terminado') {
        $conexion->rollBack();
        respond([
            'status' => 'ok',
            'msg' => 'Ya habías finalizado este reto',
            'finished' => true
        ], 200);
    }

    // Calcular tiempo empleado
    $timeUsedSeconds = 0;
    if (!empty($participant['start_time'])) {
        $start = new DateTime($participant['start_time']);
        $now = new DateTime();
        $timeUsedSeconds = max(0, $now->getTimestamp() - $start->getTimestamp());
    }

    // Preparar JSON de respuestas
    $answersJson = null;
    if (is_array($answers) || is_string($answers)) {
        $answersJson = json_encode($answers, JSON_UNESCAPED_UNICODE);
    }

    // OBTENER PUNTAJE REAL DE MOODLE SI ESTÁ DISPONIBLE
    $finalScore = is_null($score) ? 0 : (float)$score;
    if (!empty($participant['moodle_attempt_id'])) {
        try {
            // Obtener token del usuario
            $stmtToken = $conexion->prepare("SELECT moodle_token FROM usuarios WHERE id_usuario = ? LIMIT 1");
            $stmtToken->execute([$userId]);
            $userToken = $stmtToken->fetch(PDO::FETCH_ASSOC);
            
            if ($userToken && !empty($userToken['moodle_token'])) {
                $mc = getMoodleClient();
                $review = $mc->request($userToken['moodle_token'], 'mod_quiz_get_attempt_review', [
                    'attemptid' => (int)$participant['moodle_attempt_id']
                ]);
                
                if (isset($review['grade'])) {
                    $finalScore = (float)$review['grade'];
                    error_log("[finish_challenge] Puntaje Moodle obtenido: {$finalScore} para user {$userId}");
                }
            }
        } catch (Throwable $e) {
            error_log("[finish_challenge] Error obteniendo puntaje Moodle: " . $e->getMessage());
            // Usar el score enviado por el frontend
        }
    }

    // Actualizar participante
    $stmt = $conexion->prepare("
        UPDATE challenge_participants
        SET score = :score,
            answers_json = :answers_json,
            end_time = NOW(),
            finished_at = NOW(),
            ready_status = 'terminado',
            elapsed_seconds = :elapsed
        WHERE id = :pid
    ");
    $stmt->execute([
        ':score' => $finalScore,
        ':answers_json' => $answersJson,
        ':elapsed' => $timeUsedSeconds,
        ':pid' => $participant['id']
    ]);

    // Verificar si todos han terminado
    $stmt = $conexion->prepare("
        SELECT 
            SUM(CASE WHEN invitation_status='aceptado' THEN 1 ELSE 0 END) AS total_aceptados,
            SUM(CASE WHEN invitation_status='aceptado' AND ready_status='terminado' THEN 1 ELSE 0 END) AS total_terminados
        FROM challenge_participants
        WHERE challenge_id = ?
    ");
    $stmt->execute([$challengeId]);
    $stats = $stmt->fetch(PDO::FETCH_ASSOC);

    $allFinished = ($stats['total_aceptados'] > 0) && ($stats['total_terminados'] >= $stats['total_aceptados']);

    // Si todos terminaron, marcar reto como finalizado
    if ($allFinished) {
        $stmt = $conexion->prepare("UPDATE challenges SET status = 'finalizado', ended_at = NOW() WHERE id = ?");
        $stmt->execute([$challengeId]);
    }

    // Obtener participantes para respuesta
    $stmt = $conexion->prepare("
        SELECT cp.user_id, u.nombre, cp.ready_status, cp.score, cp.start_time, cp.end_time
        FROM challenge_participants cp
        JOIN usuarios u ON u.id_usuario = cp.user_id
        WHERE cp.challenge_id = ?
        ORDER BY cp.score DESC, cp.finished_at ASC
    ");
    $stmt->execute([$challengeId]);
    $participants = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Obtener usuarios pendientes
    $stmt = $conexion->prepare("
        SELECT u.nombre, cp.user_id
        FROM challenge_participants cp
        JOIN usuarios u ON u.id_usuario = cp.user_id
        WHERE cp.challenge_id = ? 
        AND cp.invitation_status = 'aceptado' 
        AND cp.ready_status != 'terminado'
    ");
    $stmt->execute([$challengeId]);
    $pendingUsers = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Calcular tiempo restante
    $remainingSeconds = 0;
    if (!empty($startedAtRaw)) {
        $startedAt = new DateTime($startedAtRaw, new DateTimeZone('UTC'));
        $endTime = (clone $startedAt)->modify("+{$durationMinutes} minutes");
        $remainingSeconds = max(0, $endTime->getTimestamp() - (new DateTime('now', new DateTimeZone('UTC')))->getTimestamp());
        
        // Si se acabó el tiempo, forzar finalización
        if ($remainingSeconds <= 0 && $statusNow !== 'finalizado') {
            // Llamar a force_finish_challenge internamente
            require_once 'force_finish_challenge.php';
            // No es la mejor forma, pero para mantener la consistencia
            $stmt = $conexion->prepare("UPDATE challenges SET status = 'finalizado', ended_at = NOW() WHERE id = ?");
            $stmt->execute([$challengeId]);
            $allFinished = true;
        }
    }

    $conexion->commit();

    respond([
        'status' => 'ok',
        'msg' => 'Intento finalizado correctamente',
        'finished' => $allFinished,
        'pending_users' => $pendingUsers,
        'remaining_time' => $remainingSeconds,
        'participants' => $participants,
        'user_score' => $finalScore,
        'user_time' => $timeUsedSeconds
    ], 200);

} catch (\Throwable $e) {
    if (isset($conexion) && $conexion->inTransaction()) {
        $conexion->rollBack();
    }
    error_log("[finish_challenge][ERROR] " . $e->getMessage());
    respond(['status'=>'error','msg'=>'Error interno','detail'=>$e->getMessage()], 500);
}