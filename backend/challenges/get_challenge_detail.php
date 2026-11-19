<?php
// /var/www/html/api/prepsaber/backend/challenges/get_challenge_detail.php
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
header("Access-Control-Allow-Methods: GET, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    $resp = '{"ok":true}';
    ob_end_clean();
    header("Content-Length: ".strlen($resp));
    echo $resp;
    exit;
}

error_log("========== get_challenge_detail.php ==========");

require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../auth_middleware.php';

if (ob_get_length() > 0) {
    error_log("[WARN] Includes generaron salida — limpiando buffer");
    ob_clean();
}

function respond(array $payload, int $status = 200): void {
    if (ob_get_length() > 0) ob_clean();
    http_response_code($status);

    $payload = utf8ize($payload);
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE);

    if ($json === false) {
        $fallback = '{"status":"error","msg":"Error al codificar respuesta"}';
        header("Content-Length: ".strlen($fallback));
        echo $fallback;
        exit;
    }

    header("Content-Length: ".strlen($json));
    echo $json;
    exit;
}

try {

    $authUser = $GLOBALS['authUser'] ?? null;

    if (!$authUser || !isset($authUser['id_usuario'])) {
        respond(['status'=>'error','msg'=>'Token no proporcionado'], 401);
    }

    $userId = (int)$authUser['id_usuario'];
    $challengeId = $_GET['challenge_id'] ?? null;

    error_log("[PARAM] challenge_id=$challengeId userId=$userId");

    if (!is_numeric($challengeId)) {
        respond(['status'=>'error','msg'=>'challenge_id es requerido'], 400);
    }

    $challengeId = (int)$challengeId;

    // ========= RETO (BLINDADO) =========
    $sql = "
        SELECT 
            c.id AS challenge_id,
            c.title,
            c.area,
            c.level,
            c.quiz_id,
            c.scheduled_datetime,
            c.duration_minutes,
            c.status,
            c.creator_id,
            c.started_at,
            c.ended_at,
            u.nombre AS creator_name,
            u.moodle_username AS creator_username
        FROM challenges c
        JOIN usuarios u ON u.id_usuario = c.creator_id
        WHERE c.id = :cid
          AND c.deleted_at IS NULL
        LIMIT 1
    ";

    $stmt = $conexion->prepare($sql);
    $stmt->execute([':cid' => $challengeId]);
    $challenge = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$challenge) {
        respond(['status'=>'error','msg'=>'Reto no encontrado'], 404);
    }

    error_log("[INFO] Reto válido: ID={$challengeId}, creador={$challenge['creator_id']}");

    // ========= AUTORIZACIÓN =========
    $stmt = $conexion->prepare("
        SELECT 1
        FROM challenge_participants
        WHERE challenge_id = :cid
          AND user_id = :uid
        LIMIT 1
    ");
    $stmt->execute([':cid'=>$challengeId, ':uid'=>$userId]);

    if (!$stmt->fetch()) {
        error_log("[SECURITY] Usuario $userId no autorizado para reto $challengeId");
        respond(['status'=>'error','msg'=>'No autorizado'], 403);
    }

    // ========= PARTICIPANTES =========
    $sqlP = "
        SELECT 
            cp.user_id AS id_usuario,
            u.nombre,
            u.moodle_username,
            cp.invitation_status,
            cp.ready_status,
            cp.score,
            cp.start_time,
            cp.end_time,
            cp.moodle_attempt_id,
            cp.answers_json
        FROM challenge_participants cp
        JOIN usuarios u ON u.id_usuario = cp.user_id
        WHERE cp.challenge_id = :cid
    ";

    $stmt = $conexion->prepare($sqlP);
    $stmt->execute([':cid'=>$challengeId]);
    $participants = $stmt->fetchAll(PDO::FETCH_ASSOC);

    error_log("[INFO] Participantes: ".count($participants));

    // ========= STATS =========
    $sqlStats = "
        SELECT 
            SUM(invitation_status='aceptado') AS total_aceptados,
            SUM(invitation_status='aceptado' AND ready_status='listo') AS total_listos,
            SUM(invitation_status='aceptado' AND ready_status='jugando') AS total_jugando,
            SUM(invitation_status='aceptado' AND ready_status='terminado') AS total_terminados
        FROM challenge_participants
        WHERE challenge_id = :cid
    ";

    $stmt = $conexion->prepare($sqlStats);
    $stmt->execute([':cid' => $challengeId]);
    $stats = $stmt->fetch(PDO::FETCH_ASSOC);

    // ========= TIEMPO GLOBAL =========
    $endTimeGlobal = null;
    if (!empty($challenge['started_at'])) {
        $start = new DateTime($challenge['started_at']);
        $end = clone $start;
        $end->modify("+" . (int)$challenge['duration_minutes'] . " minutes");
        $endTimeGlobal = $end
            ->setTimezone(new DateTimeZone('UTC'))
            ->format('Y-m-d\TH:i:s\Z');
    }

    respond([
        'status' => 'ok',
        'challenge' => $challenge,
        'participants' => $participants,
        'total_participants' => count($participants),
        'stats' => $stats,
        'started_at' => !empty($challenge['started_at'])
            ? (new DateTime($challenge['started_at']))
                ->setTimezone(new DateTimeZone('UTC'))
                ->format('Y-m-d\TH:i:s\Z')
            : null,
        'end_time_global' => $endTimeGlobal
    ]);

} catch (Throwable $e) {
    error_log("[ERROR] ".$e->getMessage());
    respond([
        'status'=>'error',
        'msg'=>'Error interno'
    ], 500);
}
