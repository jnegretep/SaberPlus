<?php
// /var/www/html/api/prepsaber/backend/challenges/get_challenges.php

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../auth_middleware.php';

try {
    $userId = $authUser['id_usuario'] ?? null;

    if (empty($userId) || !is_numeric($userId)) {
        http_response_code(400);
        echo json_encode([
            'status' => 'error',
            'msg'    => 'user_id inválido'
        ]);
        exit;
    }

    $sql = "
        SELECT 
            c.id AS challenge_id,
            c.title,
            c.area,
            c.level,
            c.quiz_id,
            c.scheduled_datetime,
            c.duration_minutes,
            c.status AS challenge_status,
            c.creator_id,
            c.started_at,
            c.ended_at,
            u.nombre AS creator_name,
            cp.invitation_status,
            cp.ready_status,
            cp.score,
            cp.start_time,
            cp.end_time,
            (SELECT COUNT(*) 
               FROM challenge_participants 
              WHERE challenge_id = c.id
            ) AS total_participants
        FROM challenges c
        INNER JOIN challenge_participants cp 
            ON cp.challenge_id = c.id
        INNER JOIN usuarios u 
            ON u.id_usuario = c.creator_id
        WHERE cp.user_id = :uid
          AND c.deleted_at IS NULL
        ORDER BY c.scheduled_datetime DESC
    ";
    $stmt = $conexion->prepare($sql);
    $stmt->execute([':uid' => $userId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $created = [];
    $invited = [];
    $pending = [];

    foreach ($rows as $r) {
        $isCreator = ($r['creator_id'] == $userId);

        $item = [
            'challenge_id'      => (int)$r['challenge_id'],
            'title'             => $r['title'],
            'area'              => $r['area'],
            'level'             => $r['level'],
            'quiz_id'           => (int)$r['quiz_id'],
            'scheduled_datetime'=> $r['scheduled_datetime'],
            'duration_minutes'  => (int)$r['duration_minutes'],
            'status'            => $r['challenge_status'],
            'creator_id'        => (int)$r['creator_id'],
            'creator_name'      => $r['creator_name'],
            'invitation_status' => $r['invitation_status'],
            'ready_status'      => $r['ready_status'],
            'score'             => (float)$r['score'],
            'start_time'        => $r['start_time'],
            'end_time'          => $r['end_time'],
            'started_at'        => $r['started_at'],
            'ended_at'          => $r['ended_at'],
            'total_participants'=> (int)$r['total_participants']
        ];

        if ($isCreator) {
            $created[] = $item;
        } elseif ($r['invitation_status'] === 'pendiente') {
            $pending[] = $item;
        } else {
            $invited[] = $item;
        }
    }

    echo json_encode([
        'status'        => 'ok',
        'created'       => $created,
        'invited'       => $invited,
        'pending'       => $pending,
        'total'         => count($rows),
        'total_created' => count($created),
        'total_invited' => count($invited),
        'total_pending' => count($pending)
    ]);
    exit;

} catch (\Throwable $e) {
    error_log("[get_challenges][ERROR] ".$e->getMessage());
    http_response_code(500);
    echo json_encode([
        'status'=>'error',
        'msg'=>'Error interno',
        'detail'=>$e->getMessage()
    ]);
    exit;
}
