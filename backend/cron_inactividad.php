
<?php
// /var/www/html/api/prepsaber/backend/cron_inactividad.php (final, listo para reemplazar)

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
    error_log("[cron_inactividad][WARN] no se pudo forzar charset/timezone: " . $e->getMessage());
}

// Lockfile para evitar concurrencia
$lockFile = sys_get_temp_dir() . '/cron_inactividad.lock';
$fp = fopen($lockFile, 'c');
if (!flock($fp, LOCK_EX | LOCK_NB)) {
    error_log("[cron_inactividad] another instance is running, exiting");
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
        $s = $pdo->prepare("SELECT fcm_token FROM usuarios WHERE id_usuario = :id LIMIT 1");
        $s->execute([":id" => $userId]);
        $r = $s->fetch(PDO::FETCH_ASSOC);
        $has = ($r && !empty($r['fcm_token'])) ? 1 : 0;
        error_log("[cron_inactividad] userHasToken user={$userId} token_present={$has}");
        return ($r && !empty($r['fcm_token']));
    } catch (Throwable $e) {
        error_log("[cron_inactividad][ERROR] userHasToken DB error for user={$userId}: ".$e->getMessage());
        return false;
    }
}

try {
    // Seleccionar usuarios con inactividad de 7, 15 o 30 días
    $sql = "SELECT id_usuario, DATEDIFF(NOW(), ultimo_login) AS dias, last_inactivity_notified
            FROM usuarios
            WHERE ultimo_login IS NOT NULL
              AND DATEDIFF(NOW(), ultimo_login) IN (7,15,30)";
    $stmt = $conexion->query($sql);
    $usuarios = $stmt->fetchAll(PDO::FETCH_ASSOC);

    foreach ($usuarios as $row) {
        try {
            $userId = (int)$row['id_usuario'];
            $dias = (int)$row['dias'];

            // Evitar duplicados: si ya se notificó ese hito, saltar
            if (!empty($row['last_inactivity_notified']) && $row['last_inactivity_notified'] >= $dias) {
                error_log("[cron_inactividad] skip user={$userId} already notified for dias={$dias}");
                continue;
            }

            error_log("[cron_inactividad] candidate user={$userId} dias={$dias}");

            // Saltar si no tiene token
            if (!userHasToken($conexion, $userId)) {
                error_log("[cron_inactividad] skip user={$userId} no fcm_token");
                continue;
            }

            // Preparar payload con request_id para trazabilidad e idempotencia
            $requestId = bin2hex(random_bytes(16));
            $payload = [
                "id_usuario" => $userId,
                "type" => "inactividad",
                "extra" => ["dias" => $dias],
                "request_id" => $requestId
            ];

            // Intento principal
            $res = postJson("http://localhost/api/prepsaber/backend/send_notification.php", $payload, 6);
            error_log("[cron_inactividad] send HTTP={$res['http']} curl_err={$res['error']} body=".substr($res['body'] ?? '',0,500));

            $ok = false;
            $j = null;
            if ($res['http'] === 200 && !empty($res['body'])) {
                $j = json_decode($res['body'], true);
                if (json_last_error() === JSON_ERROR_NONE) {
                    if (!empty($j['success'])) {
                        $ok = true;
                        error_log("[cron_inactividad] send success user={$userId} dias={$dias} fcm=" . substr(json_encode($j['fcm_result'] ?? []),0,1000));
                    } else {
                        error_log("[cron_inactividad][WARN] send returned success!=true for user={$userId} resp=".substr($res['body'],0,500));
                    }
                    if (isset($j['db_result'])) {
                        error_log("[cron_inactividad] db_result=" . substr(json_encode($j['db_result']),0,1000));
                    }
                } else {
                    error_log("[cron_inactividad][WARN] JSON decode error: " . json_last_error_msg());
                }
            } else {
                error_log("[cron_inactividad][WARN] send HTTP={$res['http']} err={$res['error']}");
            }

            // Reintento único en fallos transitorios (HTTP 5xx o curl error)
            if (!$ok && ($res['http'] >= 500 || $res['error'])) {
                error_log("[cron_inactividad] retrying once for user={$userId} dias={$dias}");
                sleep(1);
                $res2 = postJson("http://localhost/api/prepsaber/backend/send_notification.php", $payload, 6);
                error_log("[cron_inactividad] retry HTTP={$res2['http']} err={$res2['error']} body=".substr($res2['body'] ?? '',0,500));
                if ($res2['http'] === 200 && !empty($res2['body'])) {
                    $j2 = json_decode($res2['body'], true);
                    if (json_last_error() === JSON_ERROR_NONE && !empty($j2['success'])) {
                        $ok = true;
                        error_log("[cron_inactividad] retry success user={$userId} dias={$dias}");
                        if (isset($j2['db_result'])) {
                            error_log("[cron_inactividad] retry db_result=" . substr(json_encode($j2['db_result']),0,1000));
                        }
                    } else {
                        error_log("[cron_inactividad][WARN] retry returned success!=true for user={$userId} resp=".substr($res2['body'],0,500));
                    }
                } else {
                    error_log("[cron_inactividad][WARN] retry HTTP={$res2['http']} err={$res2['error']}");
                }
            }

            if ($ok) {
                // Marcar el hito como notificado solo si el envío fue exitoso
                try {
                    $upd = $conexion->prepare("UPDATE usuarios SET last_inactivity_notified=? WHERE id_usuario=?");
                    $upd->execute([$dias, $userId]);
                    error_log("[cron_inactividad] marked last_inactivity_notified={$dias} for user={$userId}");
                } catch (Throwable $uEx) {
                    error_log("[cron_inactividad][ERROR] fallo al marcar last_inactivity_notified user={$userId}: " . $uEx->getMessage());
                }
            } else {
                error_log("[cron_inactividad] NOT marked last_inactivity_notified for user={$userId} dias={$dias}");
            }

            // pequeña pausa para evitar ráfagas
            usleep(150000); // 150ms
        } catch (Throwable $rowEx) {
            error_log("[cron_inactividad][ROW-ERROR] user={$row['id_usuario']} ".$rowEx->getMessage());
        }
    }

} catch (\Throwable $e) {
    error_log("[cron_inactividad][ERROR] ".$e->getMessage()." trace=".$e->getTraceAsString());
} finally {
    // liberar lock
    flock($fp, LOCK_UN);
    fclose($fp);
}