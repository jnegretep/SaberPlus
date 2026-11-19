<?php
declare(strict_types=1);

/**
 * SABER+ — Cron de envío de campañas masivas
 *
 * Ejecuta cada minuto (vía crontab o systemd timer):
 *   * * * * * /usr/bin/php /var/www/html/api/prepsaber/backend/cron_send_campaigns.php >> /var/log/saberplus_campaigns.log 2>&1
 *
 * O manualmente desde CLI:
 *   php cron_send_campaigns.php
 *
 * Qué hace:
 *   1. Busca campañas pendientes:
 *        - status='sending'   (enviadas a mano desde admin)
 *        - status='draft' AND scheduled_at <= NOW()  (programadas)
 *   2. Para cada campaña:
 *        - marca started_at=NOW(), status='sending'
 *        - obtiene audiencia (SELECT usuarios WHERE audience_filter)
 *        - itera destinatarios en chunks de 100
 *          - envía CloudMessage a FCM v1 por cada uno
 *          - UPDATE contador total_sent/total_failed
 *          - INSERT en notifications (bandeja in-app)
 *          - limpia tokens muertos con saberplus_fcm_limpiar_tokens()
 *          - usleep(30000) entre envíos (30ms — no saturar FCM)
 *        - marca completed_at=NOW(), status='completed'
 *        - audita con admin_audit_log() (módulo communications)
 *   3. Loggea progreso a error_log (syslog).
 *
 * Seguridad:
 *   - CLI permitido (crontab del servidor)
 *   - HTTP solo si header X-Internal-Token == INTERNAL_TOKEN del .env
 *   - En caso contrario: 403 y exit.
 *
 * NOTA: send_bulk.php queda como fallback legacy. Este cron es la vía oficial.
 */

// ── Guard: CLI o token interno ──
if (PHP_SAPI !== 'cli') {
    // HTTP: solo con token interno
    require_once __DIR__ . '/env.php';
    $internal = env('INTERNAL_TOKEN', '');
    $header   = $_SERVER['HTTP_X_INTERNAL_TOKEN'] ?? '';
    if ($internal === '' || $internal === null || !hash_equals($internal, (string)$header)) {
        http_response_code(403);
        header('Content-Type: application/json; charset=UTF-8');
        exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
    }
}

// Sin límite de tiempo (puede procesar miles de destinatarios)
@set_time_limit(0);
@ini_set('memory_limit', '512M');
@ini_set('max_execution_time', '0');

// ── Dependencias ──
require_once __DIR__ . '/vendor/autoload.php';
require_once __DIR__ . '/includes/conexion.php';
require_once __DIR__ . '/includes/firebase_factory.php';
require_once __DIR__ . '/includes/config.php';
require_once __DIR__ . '/env.php';

// Helpers de audiencia (compartidos con el controller admin)
require_once __DIR__ . '/admin/sections/communications/audience_helpers.php';

// Helpers admin para auditoría (sin arrancar sesión — solo define funciones)
require_once __DIR__ . '/admin/includes/admin_helpers.php';
require_once __DIR__ . '/admin/includes/admin_audit.php';

use Kreait\Firebase\Messaging\CloudMessage;
use Kreait\Firebase\Messaging\Notification;
use Kreait\Firebase\Exception\MessagingException;

// ── Log helper ──
function cron_log(string $msg): void {
    $line = '[' . date('Y-m-d H:i:s') . '] ' . $msg;
    error_log('[campaigns_cron] ' . $msg);
    echo $line . "\n";
}

// ── Inicializar FCM ──
$messaging = null;
try {
    $messaging = saberplus_fcm_messaging();
    cron_log('FCM Messaging inicializado correctamente.');
} catch (Throwable $e) {
    cron_log('ERROR FATAL inicializando FCM: ' . $e->getMessage());
    // Sin FCM no tiene sentido continuar — las campañas marcarían todo como failed.
    exit(1);
}

// ── Detectar columna de bandeja (payload_json preferida) ──
$columnaPayload = 'payload_json';
try {
    $cols = $conexion->query("SHOW COLUMNS FROM notifications LIKE 'payload_json'")->fetchAll();
    if (empty($cols)) {
        $colsData = $conexion->query("SHOW COLUMNS FROM notifications LIKE 'data'")->fetchAll();
        $columnaPayload = !empty($colsData) ? 'data' : null;
    }
} catch (Throwable $t) {
    $columnaPayload = null;
    cron_log('WARN: no se pudo inspeccionar notifications — bandeja deshabilitada: ' . $t->getMessage());
}

// ── Preparar INSERT en bandeja in-app ──
$stmtInsertNotification = null;
if ($columnaPayload !== null) {
    try {
        $stmtInsertNotification = $conexion->prepare(
            "INSERT INTO notifications (user_id, type, title, body, {$columnaPayload}, created_at)
             VALUES (:user_id, :type, :title, :body, :payload, NOW())"
        );
    } catch (Throwable $e) {
        cron_log('WARN: no se pudo preparar INSERT bandeja: ' . $e->getMessage());
        $stmtInsertNotification = null;
    }
}

// ── Buscar campañas pendientes ──
$pendientes = [];
try {
    $stmt = $conexion->query(
        "SELECT id, title, body, type, channel, audience_filter, total_targeted
         FROM notification_campaigns
         WHERE status = 'sending'
            OR (status = 'draft' AND scheduled_at IS NOT NULL AND scheduled_at <= NOW())
         ORDER BY
           FIELD(status, 'sending', 'draft'),
           scheduled_at ASC
         LIMIT 10"
    );
    $pendientes = $stmt->fetchAll(PDO::FETCH_ASSOC);
} catch (Throwable $e) {
    cron_log('ERROR consultando campañas pendientes: ' . $e->getMessage());
    exit(1);
}

if (empty($pendientes)) {
    cron_log('Sin campañas pendientes.');
    exit(0);
}

cron_log('Procesando ' . count($pendientes) . ' campaña(s).');

$procesadas = 0;
$fallos     = 0;

foreach ($pendientes as $camp) {
    $cid = (int)$camp['id'];
    cron_log("--> Campaña #{$cid}: {$camp['title']}");

    // ── Marcar started_at + status='sending' (si era draft) ──
    try {
        $upd = $conexion->prepare(
            "UPDATE notification_campaigns
             SET status = 'sending', started_at = NOW()
             WHERE id = ? AND status IN ('draft','sending')"
        );
        $upd->execute([$cid]);
    } catch (Throwable $e) {
        cron_log("ERROR marcando started_at #{$cid}: " . $e->getMessage());
        $fallos++;
        continue;
    }

    // ── Parsear filtro de audiencia ──
    $filter = json_decode((string)$camp['audience_filter'], true);
    if (!is_array($filter)) {
        cron_log("ERROR filtro inválido #{$cid}. Marcando como failed.");
        marcar_como($cid, 'failed');
        $fallos++;
        continue;
    }

    // ── Contar audiencia total (si no estaba ya calculada) ──
    $totalTargeted = (int)$camp['total_targeted'];
    if ($totalTargeted === 0) {
        $totalTargeted = admin_campaign_count_audience($conexion, $filter);
        try {
            $upd = $conexion->prepare("UPDATE notification_campaigns SET total_targeted = ? WHERE id = ?");
            $upd->execute([$totalTargeted, $cid]);
        } catch (Throwable $e) {
            cron_log("WARN actualizando total_targeted #{$cid}: " . $e->getMessage());
        }
    }
    cron_log("    Audiencia: {$totalTargeted} destinatarios.");

    if ($totalTargeted === 0) {
        cron_log("    Audiencia vacía. Marcando como completed sin envíos.");
        marcar_como($cid, 'completed');
        auditoria_cron($conexion, $cid, 'campaign.completed.empty', 'Campaña completada sin audiencia (0 destinatarios)', false);
        $procesadas++;
        continue;
    }

    // ── Iterar destinatarios en chunks de 100 ──
    $totalSent = 0;
    $totalFailed = 0;
    $tokensMuertos = [];
    $offset = 0;
    $batch = 100;
    $channel = (string)$camp['channel'];

    try {
        $updSent = $conexion->prepare("UPDATE notification_campaigns SET total_sent = total_sent + ? WHERE id = ?");
        $updFailed = $conexion->prepare("UPDATE notification_campaigns SET total_failed = total_failed + ? WHERE id = ?");
    } catch (Throwable $e) {
        cron_log("ERROR preparando UPDATEs #{$cid}: " . $e->getMessage());
        $fallos++;
        continue;
    }

    $payloadJson = json_encode([
        'action' => 'go_dashboard',
        'campaign_id' => $cid,
        'campaign_type' => $camp['type'],
    ], JSON_UNESCAPED_UNICODE);

    while (true) {
        $recipients = admin_campaign_fetch_audience($conexion, $filter, $offset, $batch);
        if (empty($recipients)) break;

        $sentEnChunk = 0;
        $failedEnChunk = 0;

        foreach ($recipients as $u) {
            $token = trim((string)($u['fcm_token'] ?? ''));
            $uid = (int)$u['id_usuario'];

            if ($token === '') {
                $failedEnChunk++;
                continue;
            }

            // ── ¿Enviar FCM? Solo si canal es push o in_app ──
            $fcmOk = false;
            $fcmError = '';
            if ($channel === 'push' || $channel === 'in_app') {
                try {
                    $message = CloudMessage::withTarget('token', $token)
                        ->withNotification(Notification::create($camp['title'], $camp['body']))
                        ->withData([
                            'type'         => $camp['type'],
                            'title'        => $camp['title'],
                            'body'         => $camp['body'],
                            'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                            'action'       => 'go_dashboard',
                            'campaign_id'  => (string)$cid,
                        ])
                        ->withAndroidConfig([
                            'priority' => 'high',
                            'notification' => [
                                'channel_id' => 'saberplus_notificaciones',
                                'sound' => 'default',
                            ],
                        ]);
                    $messaging->send($message);
                    $fcmOk = true;
                    $sentEnChunk++;
                } catch (MessagingException $e) {
                    $err = $e->getMessage();
                    $fcmError = $err;
                    $failedEnChunk++;
                    error_log('[campaigns_cron] FCM user=' . $uid . ' camp=' . $cid . ' error: ' . $err);
                    if (saberplus_fcm_token_muerto($err)) {
                        $tokensMuertos[] = $token;
                    }
                } catch (Throwable $e) {
                    $err = $e->getMessage();
                    $fcmError = $err;
                    $failedEnChunk++;
                    error_log('[campaigns_cron] user=' . $uid . ' camp=' . $cid . ' error genérico: ' . $err);
                }
            } else {
                // Canal email_future: placeholder, no se envía FCM (solo bandeja)
                $fcmOk = true;
                $sentEnChunk++;
            }

            // ── Bandeja in-app (independiente del resultado FCM) ──
            if ($stmtInsertNotification !== null) {
                try {
                    $stmtInsertNotification->execute([
                        ':user_id' => $uid,
                        ':type'    => $camp['type'],
                        ':title'   => $camp['title'],
                        ':body'    => $camp['body'],
                        ':payload' => $payloadJson,
                    ]);
                } catch (Throwable $t) {
                    error_log('[campaigns_cron] bandeja insert user=' . $uid . ': ' . $t->getMessage());
                }
            }

            usleep(30000); // 30ms para no saturar FCM
        }

        // ── Flush contadores de este chunk ──
        try {
            if ($sentEnChunk > 0) {
                $updSent->execute([$sentEnChunk, $cid]);
            }
            if ($failedEnChunk > 0) {
                $updFailed->execute([$failedEnChunk, $cid]);
            }
        } catch (Throwable $e) {
            cron_log("WARN actualizando contadores chunk #{$cid}: " . $e->getMessage());
        }

        $totalSent   += $sentEnChunk;
        $totalFailed += $failedEnChunk;
        cron_log("    chunk offset={$offset}: +{$sentEnChunk} sent, +{$failedEnChunk} failed (acum: sent={$totalSent}, failed={$totalFailed})");

        $offset += $batch;

        // Pequeña pausa entre chunks para dar oxígeno a la BD
        usleep(100000); // 100ms
    }

    // ── Limpiar tokens muertos ──
    if (!empty($tokensMuertos)) {
        $limpiados = saberplus_fcm_limpiar_tokens(array_values(array_unique($tokensMuertos)), $conexion);
        cron_log("    Tokens muertos limpiados: {$limpiados}");
    }

    // ── Marcar como completed (o failed si todo falló) ──
    $finalStatus = ($totalSent === 0 && $totalFailed > 0) ? 'failed' : 'completed';
    marcar_como($cid, $finalStatus);

    cron_log("    Campaña #{$cid} finalizada: status={$finalStatus}, sent={$totalSent}, failed={$totalFailed}");

    // ── Auditar ──
    auditoria_cron($conexion, $cid, 'campaign.' . $finalStatus,
        "Campaña {$finalStatus} por cron. sent={$totalSent}, failed={$totalFailed}, targeted={$totalTargeted}",
        $finalStatus === 'completed');

    $procesadas++;
}

cron_log("Fin. Procesadas: {$procesadas}, Fallos: {$fallos}");
exit($fallos > 0 ? 2 : 0);

// ══════════════════════════════════════════════════════════════════════
//  HELPERS LOCALES
// ══════════════════════════════════════════════════════════════════════

function marcar_como(int $cid, string $status): void {
    global $conexion;
    try {
        $sql = "UPDATE notification_campaigns SET status = ?";
        $params = [$status];
        if ($status === 'completed' || $status === 'failed') {
            $sql .= ", completed_at = NOW()";
        }
        $sql .= " WHERE id = ?";
        $params[] = $cid;
        $stmt = $conexion->prepare($sql);
        $stmt->execute($params);
    } catch (Throwable $e) {
        cron_log("ERROR marcando status={$status} #{$cid}: " . $e->getMessage());
    }
}

function auditoria_cron(PDO $db, int $cid, string $action, string $details, bool $success): void {
    // admin_audit_log() lee $_SESSION['admin_email'] y $_SESSION['admin_user_id'].
    // En CLI no hay sesión activa → inicializar como array y marcar como 'cron'
    // para que el log de auditoría distinga envíos automáticos de acciones manuales.
    if (!is_array($_SESSION ?? null)) {
        $_SESSION = [];
    }
    if (empty($_SESSION['admin_email'])) {
        $_SESSION['admin_email'] = 'cron';
    }

    try {
        admin_audit_log($db, $action, 'notification_campaign', $cid, $details, 'communications', null, null, $success);
    } catch (Throwable $e) {
        cron_log("WARN auditoria #{$cid}: " . $e->getMessage());
    }
}
