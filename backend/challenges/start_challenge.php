<?php
// /var/www/html/api/prepsaber/backend/challenges/start_challenge.php
declare(strict_types=1);
date_default_timezone_set('UTC');

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

error_log("========== start_challenge.php ==========");

require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle.php';
require __DIR__ . '/../auth_middleware.php';

if (ob_get_length() > 0) {
    error_log("[WARN] Includes generaron salida — limpiando");
    ob_clean();
}

$mc = getMoodleClient();

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

$raw = file_get_contents("php://input");
$data = json_decode($raw, true);
if (!is_array($data)) $data = $_POST;

// --------------------------------------------
// AUTENTICACIÓN
// --------------------------------------------
$authUser = $GLOBALS['authUser'] ?? null;

if (!$authUser || !isset($authUser['id_usuario'])) {
    respond(['status'=>'error','msg'=>'Token no proporcionado'], 401);
}

$userId = (int)$authUser['id_usuario'];
$challengeId = $data['challenge_id'] ?? null;
$action = strtolower(trim($data['action'] ?? 'ready')); 

if (!is_numeric($challengeId)) {
    respond(['status'=>'error','msg'=>'challenge_id es requerido'], 400);
}

$challengeId = (int)$challengeId;

try {
    // Obtener reto (blindado contra eliminados)
    $stmt = $conexion->prepare("
        SELECT 
            id,
            creator_id,
            status,
            quiz_id,
            scheduled_datetime,
            duration_minutes,
            started_at,
            ended_at
        FROM challenges
        WHERE id = ?
          AND deleted_at IS NULL
        LIMIT 1
    ");
    $stmt->execute([$challengeId]);
    $challenge = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$challenge) {
        respond(['status'=>'error','msg'=>'Reto no encontrado o eliminado'], 404);
    }

    $isCreator = ((int)$challenge['creator_id'] === $userId);

    // HORA ACTUAL UTC
    $now = new DateTime("now", new DateTimeZone('UTC'));

    // HORA PROGRAMADA ? UTC
    $scheduled = new DateTime($challenge['scheduled_datetime'], new DateTimeZone('UTC'));

    $timeOk = ($now >= $scheduled);

    // READY
    if ($action === 'ready') {
        $stmt = $conexion->prepare("
            UPDATE challenge_participants
            SET ready_status='listo'
            WHERE challenge_id=:cid AND user_id=:uid
        ");
        $stmt->execute([':cid'=>$challengeId, ':uid'=>$userId]);
    }

    // Contar
    $stmt = $conexion->prepare("
        SELECT 
            SUM(invitation_status='aceptado') AS aceptados,
            SUM(invitation_status='aceptado' AND ready_status='listo') AS listos
        FROM challenge_participants
        WHERE challenge_id=?
    ");
    $stmt->execute([$challengeId]);
    $stats = $stmt->fetch(PDO::FETCH_ASSOC);

    $todosListos = (
        $stats['aceptados'] > 0 &&
        $stats['listos'] >= $stats['aceptados']
    );

    $force = ($action === 'force_start' && $isCreator);

    // INICIO DEL RETO
    if (($todosListos && $timeOk) || $force) {

        // Si el reto no ha empezado, establecer started_at y ended_at
        if ($challenge['status'] !== 'en_curso') {
            // IMPORTANTE: Usar NOW() del servidor para consistencia
            $stmt = $conexion->prepare("
                UPDATE challenges
                SET status='en_curso', 
                    started_at=NOW(),
                    ended_at = DATE_ADD(NOW(), INTERVAL duration_minutes MINUTE)
                WHERE id=?
            ");
            $stmt->execute([$challengeId]);
            
            error_log("[CHALLENGE STARTED] Challenge {$challengeId} started at NOW()");
        }

        // Actualizar participantes - USAR EL MISMO started_at DEL RETO
        $stmt = $conexion->prepare("
            UPDATE challenge_participants cp
            JOIN challenges c ON c.id = cp.challenge_id
            SET cp.ready_status='jugando', 
                cp.start_time = c.started_at
            WHERE cp.challenge_id=:cid 
                AND cp.invitation_status='aceptado'
        ");
        $stmt->execute([':cid'=>$challengeId]);

        // Crear intentos Moodle
        $stmt = $conexion->prepare("
            SELECT cp.user_id, u.moodle_id, u.moodle_token
            FROM challenge_participants cp
            JOIN usuarios u ON u.id_usuario = cp.user_id
            WHERE cp.challenge_id=? AND cp.invitation_status='aceptado'
        ");
        $stmt->execute([$challengeId]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        foreach ($rows as $r) {
            try {
                $resp = $mc->request($r['moodle_token'], 'mod_quiz_start_attempt', [
                    'quizid' => $challenge['quiz_id']
                ]);
                $attemptId = $resp['attempt']['id'] ?? null;

                if ($attemptId) {
                    $upd = $conexion->prepare("
                        UPDATE challenge_participants
                        SET moodle_attempt_id=:aid
                        WHERE challenge_id=:cid AND user_id=:uid
                    ");
                    $upd->execute([
                        ':aid'=>$attemptId,
                        ':cid'=>$challengeId,
                        ':uid'=>$r['user_id']
                    ]);
                }
            } catch (Throwable $e) {
                error_log("[MOODLE][ERROR] ".$e->getMessage());
            }
        }

        // Obtener los tiempos actualizados del reto
        $stmt = $conexion->prepare("
            SELECT 
                started_at, 
                ended_at, 
                duration_minutes,
                TIMESTAMPDIFF(SECOND, NOW(), ended_at) as remaining_seconds
            FROM challenges 
            WHERE id=?
        ");
        $stmt->execute([$challengeId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        $startedAt = new DateTime($row['started_at'], new DateTimeZone('UTC'));
        $endedAt   = new DateTime($row['ended_at'], new DateTimeZone('UTC'));
        $remainingSeconds = max(0, (int)$row['remaining_seconds']);

        // Participantes finales
        $stmt = $conexion->prepare("
            SELECT cp.user_id, cp.invitation_status, cp.ready_status, cp.moodle_attempt_id, u.nombre
            FROM challenge_participants cp
            JOIN usuarios u ON u.id_usuario = cp.user_id
            WHERE cp.challenge_id=?
        ");
        $stmt->execute([$challengeId]);
        $participants = $stmt->fetchAll(PDO::FETCH_ASSOC);

        respond([
            'status'            => 'ok',
            'msg'               => 'Reto iniciado',
            'started'           => true,
            'force'             => $force,
            'participants'      => $participants,
            'started_at'        => $startedAt->format(DateTime::ATOM),
            'end_time_global'   => $endedAt->format(DateTime::ATOM),
            'remaining_seconds' => $remainingSeconds,
            'server_time'       => time(),
            'server_datetime'   => date('Y-m-d H:i:s')
        ]);
    }

    // Aún esperando
    $stmt = $conexion->prepare("
        SELECT u.nombre, cp.user_id
        FROM challenge_participants cp
        JOIN usuarios u ON u.id_usuario = cp.user_id
        WHERE cp.challenge_id=? AND cp.invitation_status='aceptado' AND cp.ready_status='esperando'
    ");
    $stmt->execute([$challengeId]);
    $pend = $stmt->fetchAll(PDO::FETCH_ASSOC);

    respond([
        'status'=>'ok',
        'msg'=>'Esperando participantes',
        'started'=>false,
        'pending_users'=>$pend,
        'pending_users_count'=>count($pend),
        'all_ready'=>false
    ]);

} catch (Throwable $e) {
    error_log("[ERROR] " . $e->getMessage());
    respond([
        'status'=>'error',
        'msg'=>'Error interno',
        'detail'=>$e->getMessage()
    ], 500);
}