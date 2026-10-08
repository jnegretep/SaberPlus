
<?php
// /var/www/html/api/prepsaber/backend/cron_retos.php (con logs detallados)
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/vendor/autoload.php';

use Kreait\Firebase\Factory;

// Forzar sesión MySQL en UTC y utf8mb4
try {
    $conexion->exec("SET time_zone = '+00:00'");
    $conexion->exec("SET NAMES utf8mb4");
    $conexion->exec("SET CHARACTER SET utf8mb4");
    $conexion->exec("SET COLLATION_CONNECTION = utf8mb4_unicode_ci");
} catch (Throwable $e) {
    error_log("[cron_retos][WARN] no se pudo forzar charset/timezone: " . $e->getMessage());
}

// Lockfile para evitar concurrencia (con limpieza de obsoletos >5min)
$lockFile = sys_get_temp_dir() . '/cron_retos.lock';
if (file_exists($lockFile)) {
    $age = time() - filemtime($lockFile);
    if ($age > 300) { // 5 minutos
        @unlink($lockFile);
        error_log("[cron_retos][LOCK] lock obsoleto eliminado (age={$age}s)");
    }
}
$fp = fopen($lockFile, 'c');
if (!flock($fp, LOCK_EX | LOCK_NB)) {
    error_log("[cron_retos][LOCK] otra instancia en ejecución, saliendo");
    exit;
}
error_log("[cron_retos] start pid=" . getmypid());

// Helper: POST JSON con curl y timeouts
function postJson($url, $payload, $timeout = 6) {
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
    curl_setopt($ch, CURLOPT_TIMEOUT, $timeout);
    curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 3);
    $resp = curl_exec($ch);
    $http = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);
    return ['http' => $http, 'body' => $resp, 'error' => $err];
}

// Helper: comprobar token en BD (evita llamadas si no hay token)
function userHasToken($pdo, $userId) {
    try {
        $s = $pdo->prepare("SELECT fcm_token FROM usuarios WHERE id_usuario = :id LIMIT 1");
        $s->execute([":id" => $userId]);
        $r = $s->fetch(PDO::FETCH_ASSOC);
        $has = ($r && !empty($r['fcm_token'])) ? 1 : 0;
        error_log("[cron_retos] userHasToken user={$userId} token_present={$has}");
        return ($r && !empty($r['fcm_token']));
    } catch (Throwable $e) {
        error_log("[cron_retos][ERROR] userHasToken DB error for user={$userId}: ".$e->getMessage());
        return false;
    }
}

try {
    // 10 minutos
    $sql10 = "SELECT cp.user_id, cp.challenge_id, c.title AS nombre_reto, c.scheduled_datetime
              FROM challenge_participants cp
              JOIN challenges c ON cp.challenge_id = c.id
              WHERE cp.notified_10min=0
                AND c.scheduled_datetime BETWEEN DATE_ADD(NOW(), INTERVAL 9 MINUTE) AND DATE_ADD(NOW(), INTERVAL 11 MINUTE)";
    $rows10 = $conexion->query($sql10)->fetchAll(PDO::FETCH_ASSOC);
    error_log("[cron_retos][10min] candidates=" . count($rows10));

    foreach ($rows10 as $row) {
        $userId = (int)$row['user_id'];
        $challengeId = (int)$row['challenge_id'];
        $nombre = $row['nombre_reto'] ?? '';
        $sched = $row['scheduled_datetime'] ?? '';
        error_log("[cron_retos][10min] candidate user={$userId} challenge={$challengeId} sched={$sched} title=".substr($nombre,0,80));

        if (!userHasToken($conexion, $userId)) {
            error_log("[cron_retos][10min] skip user={$userId} no fcm_token");
            continue;
        }

        $payload = [
            "id_usuario" => $userId,
            "type" => "reto_10min",
            "extra" => ["nombre_reto" => $nombre],
            "request_id" => "reto10-{$challengeId}-{$userId}-" . bin2hex(random_bytes(8))
        ];

        $res = postJson("http://localhost/api/prepsaber/backend/send_notification.php", $payload, 6);
        error_log("[cron_retos][10min] send HTTP={$res['http']} err={$res['error']} body=".substr($res['body'] ?? '',0,400));

        $ok = false;
        if ($res['http'] === 200 && !empty($res['body'])) {
            $j = json_decode($res['body'], true);
            if (json_last_error() === JSON_ERROR_NONE && !empty($j['success'])) {
                $ok = true;
                error_log("[cron_retos][10min] send success user={$userId} challenge={$challengeId} fcm=" . substr(json_encode($j['fcm_result'] ?? []),0,400));
            } else {
                error_log("[cron_retos][10min][WARN] success!=true resp=".substr($res['body'],0,400));
            }
        } else {
            error_log("[cron_retos][10min][WARN] send HTTP={$res['http']} err={$res['error']}");
        }

        if ($ok) {
            try {
                $upd = $conexion->prepare("UPDATE challenge_participants SET notified_10min=1 WHERE user_id=? AND challenge_id=?");
                $upd->execute([$userId, $challengeId]);
                error_log("[cron_retos][10min] marked notified_10min=1 user={$userId} challenge={$challengeId}");
            } catch (Throwable $uEx) {
                error_log("[cron_retos][10min][ERROR] update flag user={$userId} challenge={$challengeId}: " . $uEx->getMessage());
            }
        } else {
            error_log("[cron_retos][10min] NOT marked notified_10min user={$userId} challenge={$challengeId}");
        }

        usleep(150000);
    }

    // 5 minutos
    $sql5 = "SELECT cp.user_id, cp.challenge_id, c.title AS nombre_reto, c.scheduled_datetime
             FROM challenge_participants cp
             JOIN challenges c ON cp.challenge_id = c.id
             WHERE cp.notified_5min=0
               AND c.scheduled_datetime BETWEEN DATE_ADD(NOW(), INTERVAL 4 MINUTE) AND DATE_ADD(NOW(), INTERVAL 6 MINUTE)";
    $rows5 = $conexion->query($sql5)->fetchAll(PDO::FETCH_ASSOC);
    error_log("[cron_retos][5min] candidates=" . count($rows5));

    foreach ($rows5 as $row) {
        $userId = (int)$row['user_id'];
        $challengeId = (int)$row['challenge_id'];
        $nombre = $row['nombre_reto'] ?? '';
        $sched = $row['scheduled_datetime'] ?? '';
        error_log("[cron_retos][5min] candidate user={$userId} challenge={$challengeId} sched={$sched} title=".substr($nombre,0,80));

        if (!userHasToken($conexion, $userId)) {
            error_log("[cron_retos][5min] skip user={$userId} no fcm_token");
            continue;
        }

        $payload = [
            "id_usuario" => $userId,
            "type" => "reto_5min",
            "extra" => ["nombre_reto" => $nombre],
            "request_id" => "reto5-{$challengeId}-{$userId}-" . bin2hex(random_bytes(8))
        ];

        $res = postJson("http://localhost/api/prepsaber/backend/send_notification.php", $payload, 6);
        error_log("[cron_retos][5min] send HTTP={$res['http']} err={$res['error']} body=".substr($res['body'] ?? '',0,400));

        $ok = false;
        if ($res['http'] === 200 && !empty($res['body'])) {
            $j = json_decode($res['body'], true);
            if (json_last_error() === JSON_ERROR_NONE && !empty($j['success'])) {
                $ok = true;
                error_log("[cron_retos][5min] send success user={$userId} challenge={$challengeId} fcm=" . substr(json_encode($j['fcm_result'] ?? []),0,400));
            } else {
                error_log("[cron_retos][5min][WARN] success!=true resp=".substr($res['body'],0,400));
            }
        } else {
            error_log("[cron_retos][5min][WARN] send HTTP={$res['http']} err={$res['error']}");
        }

        if ($ok) {
            try {
                $upd = $conexion->prepare("UPDATE challenge_participants SET notified_5min=1 WHERE user_id=? AND challenge_id=?");
                $upd->execute([$userId, $challengeId]);
                error_log("[cron_retos][5min] marked notified_5min=1 user={$userId} challenge={$challengeId}");
            } catch (Throwable $uEx) {
                error_log("[cron_retos][5min][ERROR] update flag user={$userId} challenge={$challengeId}: " . $uEx->getMessage());
            }
        } else {
            error_log("[cron_retos][5min] NOT marked notified_5min user={$userId} challenge={$challengeId}");
        }

        usleep(150000);
    }

    error_log("[cron_retos] end pid=" . getmypid());

} catch (Throwable $e) {
    error_log("[cron_retos][ERROR] ".$e->getMessage()." trace=".$e->getTraceAsString());
} finally {
    flock($fp, LOCK_UN);
    fclose($fp);
}