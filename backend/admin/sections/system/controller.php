<?php
declare(strict_types=1);

/**
 * SPRINT 7 — Sección System Health
 *
 * Dashboard de estado del sistema:
 *  - Tarjetas de estado por servicio (BD prepsaber, BD Moodle, Moodle WS, FCM, DeepSeek)
 *  - Logs recientes (50 últimos error_logs críticos o no resueltos)
 *  - Estado de colas (campañas pendientes, cron jobs last run)
 *  - Info del servidor (PHP, MySQL, disk /home, uptime)
 *  - Botón "Probar servicios ahora" (POST, CSRF, system.health)
 *
 * Permiso requerido: system.health
 */

require_once __DIR__ . '/../../bootstrap.php';
require_once __DIR__ . '/../../includes/layout.php';
require_once __DIR__ . '/../../../includes/system_health.php';

require_permission('system.health');

// ── Procesar POST: Probar servicios ahora ──
$onDemandResults = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['post_action'] ?? '') === 'run_health_checks') {
    // CSRF ya verificado por bootstrap

    $onDemandResults = saberplus_run_all_health_checks($conexion, true);
    $summary = saberplus_persist_health_checks($conexion, $onDemandResults);

    // Auditar
    admin_audit_log(
        $conexion,
        'system_health_check_manual',
        'system_health_checks',
        null,
        json_encode([
            'checks'    => count($onDemandResults),
            'operational' => $summary['operational'] ?? 0,
            'warning'     => $summary['warning'] ?? 0,
            'error'        => $summary['error'] ?? 0,
        ], JSON_UNESCAPED_UNICODE),
        'system'
    );

    admin_flash('success', 'Health check ejecutado: '
        . ($summary['operational'] ?? 0) . ' OK, '
        . ($summary['warning'] ?? 0) . ' warning, '
        . ($summary['error'] ?? 0) . ' error.');
}

// ── Último check por servicio (tomado de system_health_checks) ──
$latestChecks = safeRows($conexion,
    "SELECT h1.*
     FROM system_health_checks h1
     INNER JOIN (
       SELECT service, MAX(checked_at) AS max_checked
       FROM system_health_checks
       GROUP BY service
     ) h2 ON h2.service = h1.service AND h2.max_checked = h1.checked_at
     ORDER BY h1.service ASC");

// Indexar por service
$checksByService = [];
foreach ($latestChecks as $c) {
    $checksByService[$c['service']] = $c;
}

// ── Catálogo de servicios ──
$services = [
    'db_prepsaber' => ['label' => 'BD prepsaber',       'icon' => '🗄️'],
    'db_moodle'    => ['label' => 'BD Moodle',          'icon' => '📚'],
    'moodle_ws'    => ['label' => 'Moodle Web Service', 'icon' => '🌐'],
    'fcm'          => ['label' => 'Firebase FCM',       'icon' => '📨'],
    'deepseek'     => ['label' => 'DeepSeek IA (proxy)','icon' => '🤖'],
];

// ── Logs recientes (últimos 50 críticos o no resueltos) ──
$recentLogs = safeRows($conexion,
    "SELECT id, source, severity, message, created_at, resolved
     FROM error_logs
     WHERE severity = 'critical' OR resolved = 0
     ORDER BY created_at DESC
     LIMIT 50");

// ── Estado de colas: campañas pendientes ──
$pendingCampaigns = safeRows($conexion,
    "SELECT id, title, status, total_targeted, total_sent, total_failed,
            created_at, started_at
     FROM notification_campaigns
     WHERE status IN ('draft', 'sending')
     ORDER BY created_at DESC
     LIMIT 10");

// ── Cron jobs last run ──
$cronChecks = safeRows($conexion,
    "SELECT service, status, latency_ms, details, checked_at
     FROM system_health_checks
     WHERE service LIKE 'cron_%'
     ORDER BY checked_at DESC
     LIMIT 20");

// ── Info del servidor (segura) ──
$phpVersion    = PHP_VERSION;
$mysqlVersion  = '—';
try {
    $v = $conexion->query("SELECT VERSION()")->fetchColumn();
    if ($v) $mysqlVersion = $v;
} catch (Throwable $e) {}

$diskFree  = @disk_free_space('/home');
$diskTotal = @disk_total_space('/home');
$diskPct   = ($diskTotal > 0 && $diskFree !== false && $diskTotal !== false)
    ? round((1 - $diskFree / $diskTotal) * 100, 1)
    : null;

// Uptime (Linux: /proc/uptime)
$uptimeStr = '—';
if (is_file('/proc/uptime')) {
    $uptimeRaw = @file_get_contents('/proc/uptime');
    if ($uptimeRaw !== false) {
        $parts = explode(' ', $uptimeRaw);
        $secs = (float)($parts[0] ?? 0);
        if ($secs > 0) {
            $days    = (int)($secs / 86400);
            $hours   = (int)(($secs % 86400) / 3600);
            $minutes = (int)(($secs % 3600) / 60);
            $uptimeStr = "{$days}d {$hours}h {$minutes}m";
        }
    }
}

// ── Helpers de UI ──
$sevDot = function (string $status): string {
    return match ($status) {
        'operational' => '🟢',
        'warning'     => '🟡',
        'error'       => '🔴',
        default       => '⚪',
    };
};
$sevLabel = function (string $status): string {
    return match ($status) {
        'operational' => 'Operativo',
        'warning'     => 'Advertencia',
        'error'       => 'Error',
        default       => 'Desconocido',
    };
};

render_header('System Health', ['section' => 'system']);
?>

<div class="section-header">
    <div>
        <div class="section-header__title">System Health</div>
        <div class="section-header__subtitle">
            Estado de servicios y colas del sistema · última verificación cron cada 5 min
        </div>
    </div>
    <div class="quick-stats">
        <form method="post" action="index.php?section=system">
            <?= admin_csrf_field() ?>
            <input type="hidden" name="post_action" value="run_health_checks">
            <button type="submit" class="btn btn--primary btn--sm"
                    onclick="this.disabled=true; this.form.submit();">
                ⚡ Probar servicios ahora
            </button>
        </form>
    </div>
</div>

<?php if ($onDemandResults !== null): ?>
<section class="card">
    <div class="card__header">
        <div class="card__title">Resultado del check on-demand</div>
    </div>
    <table class="data-table">
        <thead>
            <tr><th>Servicio</th><th>Estado</th><th>Latencia</th><th>Detalle</th></tr>
        </thead>
        <tbody>
            <?php foreach ($onDemandResults as $r): ?>
                <tr>
                    <td><strong><?= $services[$r['service']]['icon'] ?? '⚙️' ?> <?= sp_h($services[$r['service']]['label'] ?? $r['service']) ?></strong></td>
                    <td><?= $sevDot($r['status']) ?> <?= sp_h($sevLabel($r['status'])) ?></td>
                    <td><?= isset($r['latency_ms']) ? admin_fmt_int($r['latency_ms']) . ' ms' : '—' ?></td>
                    <td style="font-size:12px;color:#475569;">
                        <?php if (!empty($r['details']['http_code'])): ?>HTTP <?= (int)$r['details']['http_code'] ?> · <?php endif; ?>
                        <?= sp_h($r['details']['message'] ?? $r['details']['error'] ?? 'OK') ?>
                    </td>
                </tr>
            <?php endforeach; ?>
        </tbody>
    </table>
</section>
<?php endif; ?>

<section class="card">
    <div class="card__header">
        <div class="card__title">Estado de servicios</div>
        <div style="font-size:var(--fs-sm);color:var(--color-text-tertiary);">
            Última lectura desde <code>system_health_checks</code>
        </div>
    </div>
    <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:var(--space-4);">
        <?php foreach ($services as $svcKey => $svcMeta):
            $chk = $checksByService[$svcKey] ?? null;
            $status = $chk['status'] ?? 'unknown';
            $latency = $chk['latency_ms'] ?? null;
            $checkedAt = $chk['checked_at'] ?? null;
            $details = null;
            if (!empty($chk['details'])) {
                $details = json_decode($chk['details'], true);
                if (!is_array($details)) $details = null;
            }
        ?>
            <div class="kpi-card <?= $status === 'error' ? 'kpi-card--danger' : ($status === 'warning' ? 'kpi-card--warning' : 'kpi-card--success') ?>"
                 style="padding:var(--space-4);">
                <div class="kpi-card__header">
                    <div class="kpi-card__title"><?= sp_h($svcMeta['label']) ?></div>
                    <div class="kpi-card__icon"><?= $svcMeta['icon'] ?></div>
                </div>
                <div style="font-size:var(--fs-xl);font-weight:800;display:flex;align-items:center;gap:var(--space-2);">
                    <?= $sevDot($status) ?>
                    <?= sp_h($sevLabel($status)) ?>
                </div>
                <div style="margin-top:var(--space-2);font-size:var(--fs-sm);color:var(--color-text-secondary);">
                    Latencia:
                    <strong><?= $latency !== null ? admin_fmt_int((int)$latency) . ' ms' : '—' ?></strong>
                </div>
                <div style="font-size:var(--fs-xs);color:var(--color-text-tertiary);margin-top:var(--space-1);">
                    <?= $checkedAt ? 'Actualizado ' . admin_fmt_tiempo_relativo($checkedAt) : 'Sin datos aún' ?>
                </div>
                <?php if (!empty($details['http_code'])): ?>
                    <div style="font-size:var(--fs-xs);color:var(--color-text-tertiary);margin-top:var(--space-1);">
                        HTTP <code><?= (int)$details['http_code'] ?></code>
                    </div>
                <?php endif; ?>
            </div>
        <?php endforeach; ?>
    </div>
</section>

<section class="card">
    <div class="card__header">
        <div class="card__title">Logs críticos recientes</div>
        <span class="badge badge--danger"><?= count($recentLogs) ?> entradas</span>
    </div>
    <?php if (empty($recentLogs)): ?>
        <div class="empty-state">
            <div class="empty-state__icon">📭</div>
            <div class="empty-state__title">Sin logs críticos recientes</div>
        </div>
    <?php else: ?>
        <div style="max-height:400px;overflow-y:auto;">
        <table class="data-table">
            <thead>
                <tr>
                    <th>ID</th><th>Origen</th><th>Severidad</th><th>Mensaje</th><th>Fecha</th><th>Estado</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($recentLogs as $log): ?>
                    <tr>
                        <td>#<?= (int)$log['id'] ?></td>
                        <td><code style="font-size:11px"><?= sp_h($log['source'] ?? '—') ?></code></td>
                        <td>
                            <?php
                            $sevBadge = match ($log['severity'] ?? '') {
                                'critical' => 'danger',
                                'error'    => 'danger',
                                'warning'  => 'warning',
                                'info'     => 'info',
                                default    => 'gray',
                            };
                            ?>
                            <span class="badge badge--<?= $sevBadge ?>"><?= sp_h($log['severity'] ?? '—') ?></span>
                        </td>
                        <td style="max-width:520px;font-size:12px;color:#475569;word-break:break-word;">
                            <?= sp_h(mb_substr($log['message'] ?? '', 0, 300)) ?>
                        </td>
                        <td style="font-size:11px;white-space:nowrap;"><?= sp_h($log['created_at'] ?? '—') ?></td>
                        <td>
                            <?php if ((int)($log['resolved'] ?? 0) === 1): ?>
                                <span class="badge badge--success">resuelto</span>
                            <?php else: ?>
                                <span class="badge badge--warning">abierto</span>
                            <?php endif; ?>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
        </div>
    <?php endif; ?>
</section>

<section class="card">
    <div class="card__header">
        <div class="card__title">Estado de colas</div>
    </div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:var(--space-5);">
        <div>
            <h3 style="font-size:var(--fs-md);margin-bottom:var(--space-3);font-weight:700;">
                📣 Campañas de notificación (draft/sending)
            </h3>
            <?php if (empty($pendingCampaigns)): ?>
                <div class="empty-state" style="padding:var(--space-4);">
                    <div class="empty-state__message">No hay campañas pendientes.</div>
                </div>
            <?php else: ?>
                <table class="data-table">
                    <thead>
                        <tr><th>ID</th><th>Título</th><th>Estado</th><th>Enviadas/Total</th></tr>
                    </thead>
                    <tbody>
                        <?php foreach ($pendingCampaigns as $c): ?>
                            <tr>
                                <td>#<?= (int)$c['id'] ?></td>
                                <td><?= sp_h($c['title']) ?></td>
                                <td><span class="badge badge--warning"><?= sp_h($c['status']) ?></span></td>
                                <td><?= admin_fmt_int((int)$c['total_sent']) ?>/<?= admin_fmt_int((int)$c['total_targeted']) ?></td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            <?php endif; ?>
        </div>

        <div>
            <h3 style="font-size:var(--fs-md);margin-bottom:var(--space-3);font-weight:700;">
                ⏰ Últimas ejecuciones de cron
            </h3>
            <?php if (empty($cronChecks)): ?>
                <div class="empty-state" style="padding:var(--space-4);">
                    <div class="empty-state__message">Sin registros de cron aún.</div>
                </div>
            <?php else: ?>
                <table class="data-table">
                    <thead>
                        <tr><th>Servicio</th><th>Estado</th><th>Cuándo</th></tr>
                    </thead>
                    <tbody>
                        <?php foreach ($cronChecks as $cr): ?>
                            <tr>
                                <td><code style="font-size:11px"><?= sp_h($cr['service']) ?></code></td>
                                <td><?= $sevDot($cr['status']) ?> <?= sp_h($sevLabel($cr['status'])) ?></td>
                                <td style="font-size:11px;color:#475569;white-space:nowrap;"><?= admin_fmt_tiempo_relativo($cr['checked_at']) ?></td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            <?php endif; ?>
        </div>
    </div>
</section>

<section class="card">
    <div class="card__header">
        <div class="card__title">Información del servidor</div>
    </div>
    <table class="data-table" style="max-width:680px;">
        <tbody>
            <tr><td style="width:240px"><strong>PHP version</strong></td><td><?= sp_h($phpVersion) ?></td></tr>
            <tr><td><strong>MySQL version</strong></td><td><?= sp_h($mysqlVersion) ?></td></tr>
            <tr><td><strong>Uso de disco <code>/home</code></strong></td>
                <td>
                    <?php if ($diskPct !== null): ?>
                        <div style="display:flex;align-items:center;gap:var(--space-2);">
                            <div style="flex:1;height:10px;background:var(--color-surface-variant);border-radius:5px;overflow:hidden;max-width:200px;">
                                <div style="width:<?= min(100, $diskPct) ?>%;height:100%;background:<?= $diskPct > 85 ? 'var(--color-danger)' : ($diskPct > 70 ? 'var(--color-warning)' : 'var(--color-success)') ?>;"></div>
                            </div>
                            <strong><?= admin_fmt_pct($diskPct) ?></strong>
                            <?php if ($diskFree !== false && $diskTotal !== false): ?>
                                <span style="font-size:11px;color:#94A3B8;">
                                    (<?= round($diskFree / 1024 / 1024 / 1024, 1) ?> GB libres de <?= round($diskTotal / 1024 / 1024 / 1024, 1) ?> GB)
                                </span>
                            <?php endif; ?>
                        </div>
                    <?php else: ?>
                        No disponible
                    <?php endif; ?>
                </td>
            </tr>
            <tr><td><strong>Uptime del servidor</strong></td><td><?= sp_h($uptimeStr) ?></td></tr>
            <tr><td><strong>Zona horaria PHP</strong></td><td><?= sp_h(date_default_timezone_get()) ?></td></tr>
            <tr><td><strong>Servidor</strong></td><td><?= sp_h($_SERVER['SERVER_SOFTWARE'] ?? php_uname('s') . ' ' . php_uname('r')) ?></td></tr>
        </tbody>
    </table>
</section>

<?php
render_footer();
