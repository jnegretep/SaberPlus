<?php
// /var/www/html/api/prepsaber/backend/cron_simulacros.php (revisado)

require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/vendor/autoload.php';

use Kreait\Firebase\Factory;

// Lockfile para evitar concurrencia
$lockFile = sys_get_temp_dir() . '/cron_simulacros.lock';
$fp = fopen($lockFile, 'c');
if (!flock($fp, LOCK_EX | LOCK_NB)) {
    error_log("[cron_simulacros] another instance is running, exiting");
    exit;
}

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

// Helper: comprobar si el usuario tiene token (evita llamadas innecesarias)
function userHasToken($pdo, $userId) {
    try {
        $s = $conexion->prepare("SELECT fcm_token FROM usuarios WHERE id_usuario = :id LIMIT 1");
        $s->execute([":id" => $userId]);
        $r = $s->fetch(PDO::FETCH_ASSOC);
        return ($r && !empty($r['fcm_token']));
    } catch (Throwable $e) {
        error_log("[cron_simulacros][ERROR] userHasToken DB error for user={$userId}: ".$e->getMessage());
        return false;
    }
}

try {
    // Seleccionar simulacros en curso con ventana de tolerancia para 5h y 12h
    $sql = "SELECT id, id_usuario, nombre_simulacro,
                   TIMESTAMPDIFF(HOUR, start_time, NOW()) AS horas,
                   notified_5h, notified_12h
            FROM simulacros
            WHERE estado='en_curso'
              AND TIMESTAMPDIFF(HOUR, start_time, NOW()) BETWEEN 4 AND 13";
    $stmt = $conexion->query($sql);
    $simulacros = $stmt->fetchAll(PDO::FETCH_ASSOC);

    foreach ($simulacros as $row) {
        try {
            $simId = (int)$row['id'];
            $userId = (int)$row['id_usuario'];
            $nombre = $row['nombre_simulacro'] ?? '';
            $horas = (int)$row['horas'];

            error_log("[cron_simulacros] candidate simulacro id={$simId} user={$userId} horas={$horas} title=".substr($nombre,0,80));

            // Saltar si no tiene token
            if (!userHasToken($conexion, $userId)) {
                error_log("[cron_simulacros] skip simulacro id={$simId} user={$userId} no fcm_token");
                continue;
            }

            // Caso 5 horas
            if ($horas >= 5 && $horas < 6 && empty($row['notified_5h'])) {
                $payload = [
                    "id_usuario" => $userId,
                    "type" => "simulacro_en_curso",
                    "extra" => ["nombre_simulacro" => $nombre]
                ];

                error_log("[cron_simulacros] sending 5h simulacro id={$simId} user={$userId}");
                $res = postJson("http://localhost/api/prepsaber/backend/send_notification.php", $payload, 6);
                error_log("[cron_simulacros] 5h send HTTP={$res['http']} err={$res['error']} body=".substr($res['body'] ?? '',0,500));

                $ok = false;
                if ($res['http'] === 200 && !empty($res['body'])) {
                    $j = json_decode($res['body'], true);
                    if (json_last_error() === JSON_ERROR_NONE && !empty($j['success'])) {
                        $ok = true;
                        error_log("[cron_simulacros] 5h send success simulacro={$simId} user={$userId} fcm=".json_encode($j['fcm_result']));
                    } else {
                        error_log("[cron_simulacros][WARN] 5h send returned success!=true simulacro={$simId} resp=".substr($res['body'],0,500));
                    }
                }

                // Reintento único en fallos transitorios
                if (!$ok && ($res['http'] >= 500 || $res['error'])) {
                    error_log("[cron_simulacros] retrying 5h once for simulacro={$simId} user={$userId}");
                    sleep(1);
                    $res2 = postJson("http://localhost/api/prepsaber/backend/send_notification.php", $payload, 6);
                    error_log("[cron_simulacros] 5h retry HTTP={$res2['http']} err={$res2['error']} body=".substr($res2['body'] ?? '',0,500));
                    if ($res2['http'] === 200 && !empty($res2['body'])) {
                        $j2 = json_decode($res2['body'], true);
                        if (json_last_error() === JSON_ERROR_NONE && !empty($j2['success'])) {
                            $ok = true;
                            error_log("[cron_simulacros] 5h retry success simulacro={$simId} user={$userId}");
                        }
                    }
                }

                if ($ok) {
                    $upd = $conexion->prepare("UPDATE simulacros SET notified_5h=1 WHERE id=?");
                    $upd->execute([$simId]);
                    error_log("[cron_simulacros] marked notified_5h=1 for simulacro={$simId} user={$userId}");
                } else {
                    error_log("[cron_simulacros] NOT marked notified_5h for simulacro={$simId} user={$userId}");
                }

                usleep(150000);
            }

            // Caso 12 horas
            if ($horas >= 12 && $horas < 13 && empty($row['notified_12h'])) {
                $payload = [
                    "id_usuario" => $userId,
                    "type" => "simulacro_en_curso",
                    "extra" => ["nombre_simulacro" => $nombre]
                ];

                error_log("[cron_simulacros] sending 12h simulacro id={$simId} user={$userId}");
                $res = postJson("http://localhost/api/prepsaber/backend/send_notification.php", $payload, 6);
                error_log("[cron_simulacros] 12h send HTTP={$res['http']} err={$res['error']} body=".substr($res['body'] ?? '',0,500));

                $ok = false;
                if ($res['http'] === 200 && !empty($res['body'])) {
                    $j = json_decode($res['body'], true);
                    if (json_last_error() === JSON_ERROR_NONE && !empty($j['success'])) {
                        $ok = true;
                        error_log("[cron_simulacros] 12h send success simulacro={$simId} user={$userId} fcm=".json_encode($j['fcm_result']));
                    } else {
                        error_log("[cron_simulacros][WARN] 12h send returned success!=true simulacro={$simId} resp=".substr($res['body'],0,500));
                    }
                }

                if (!$ok && ($res['http'] >= 500 || $res['error'])) {
                    error_log("[cron_simulacros] retrying 12h once for simulacro={$simId} user={$userId}");
                    sleep(1);
                    $res2 = postJson("http://localhost/api/prepsaber/backend/send_notification.php", $payload, 6);
                    error_log("[cron_simulacros] 12h retry HTTP={$res2['http']} err={$res2['error']} body=".substr($res2['body'] ?? '',0,500));
                    if ($res2['http'] === 200 && !empty($res2['body'])) {
                        $j2 = json_decode($res2['body'], true);
                        if (json_last_error() === JSON_ERROR_NONE && !empty($j2['success'])) {
                            $ok = true;
                            error_log("[cron_simulacros] 12h retry success simulacro={$simId} user={$userId}");
                        }
                    }
                }

                if ($ok) {
                    $upd = $conexion->prepare("UPDATE simulacros SET notified_12h=1, estado='finalizado' WHERE id=?");
                    $upd->execute([$simId]);
                    error_log("[cron_simulacros] marked notified_12h=1 and finalized simulacro={$simId} user={$userId}");
                } else {
                    error_log("[cron_simulacros] NOT marked notified_12h for simulacro={$simId} user={$userId}");
                }

                usleep(150000);
            }

        } catch (Throwable $rowEx) {
            error_log("[cron_simulacros][ROW-ERROR] simulacro={$row['id']} user={$row['id_usuario']} ".$rowEx->getMessage());
        }
    }

} catch (\Throwable $e) {
    error_log("[cron_simulacros][ERROR] ".$e->getMessage()." trace=".$e->getTraceAsString());
} finally {
    flock($fp, LOCK_UN);
    fclose($fp);
}
