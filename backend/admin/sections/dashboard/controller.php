<?php
declare(strict_types=1);

/**
 * SPRINT 2 — Dashboard Ejecutivo
 *
 * KPIs de negocio, producto, IA y operaciones.
 * El CEO entra y en 30 segundos entiende cómo está Saber+.
 */

require_once __DIR__ . '/../../bootstrap.php';
require_once __DIR__ . '/../../includes/layout.php';

require_permission('users.read'); // cualquier permiso para acceder al dashboard

// ── KPIs de negocio ──
$totalUsuarios   = (int)safeScalar($conexion, "SELECT COUNT(*) FROM usuarios");
$usuariosActivos30d = (int)safeScalar($conexion,
    "SELECT COUNT(DISTINCT user_id) FROM app_events WHERE created_at > NOW() - INTERVAL 30 DAY");
$nuevosUsuarios7d  = (int)safeScalar($conexion,
    "SELECT COUNT(*) FROM usuarios WHERE registration_date > NOW() - INTERVAL 7 DAY");
$nuevosUsuarios30d = (int)safeScalar($conexion,
    "SELECT COUNT(*) FROM usuarios WHERE registration_date > NOW() - INTERVAL 30 DAY");

// Distribución de planes
$distribucionPlanes = safeRows($conexion,
    "SELECT
        COALESCE(NULLIF(access_level, ''), 'free') AS plan,
        COUNT(*) AS total
     FROM usuarios GROUP BY access_level ORDER BY total DESC");

$freeCount    = 0;
$premiumCount = 0;
$trialCount   = 0;
$earlyBirdCount = 0;
foreach ($distribucionPlanes as $row) {
    switch ($row['plan']) {
        case 'free':       $freeCount = (int)$row['total']; break;
        case 'premium':    $premiumCount = (int)$row['total']; break;
        case 'trial':      $trialCount = (int)$row['total']; break;
        case 'early_bird': $earlyBirdCount = (int)$row['total']; break;
    }
}

$conversionPremium = $totalUsuarios > 0
    ? ($premiumCount / $totalUsuarios) * 100
    : 0;

// MRR (ingresos aprobados últimos 30 días)
$mrr30d = (float)safeScalar($conexion,
    "SELECT COALESCE(SUM(amount),0) FROM payments
     WHERE LOWER(status)='approved' AND created_at > NOW() - INTERVAL 30 DAY");
$mrrTotal = (float)safeScalar($conexion,
    "SELECT COALESCE(SUM(amount),0) FROM payments WHERE LOWER(status)='approved'");

// ── KPIs de producto ──
$simulacros7d = (int)safeScalar($conexion,
    "SELECT COUNT(*) FROM simulacro_resultados WHERE fecha_realizacion > NOW() - INTERVAL 7 DAY");
$promedioGlobal = (float)safeScalar($conexion, "SELECT ROUND(AVG(puntaje_global),1) FROM simulacro_resultados");
$erroresPendientes = (int)safeScalar($conexion,
    "SELECT COUNT(*) FROM error_logs WHERE resolved = 0 AND created_at > NOW() - INTERVAL 24 HOUR");

// Promedios por área
$promediosAreas = safeRows($conexion,
    "SELECT
        ROUND(AVG(lectura_puntaje),1)    AS lectura,
        ROUND(AVG(matematicas_puntaje),1) AS matematicas,
        ROUND(AVG(sociales_puntaje),1)    AS sociales,
        ROUND(AVG(naturales_puntaje),1)   AS naturales,
        ROUND(AVG(ingles_puntaje),1)      AS ingles
     FROM simulacro_resultados
     WHERE fecha_realizacion > NOW() - INTERVAL 30 DAY");

// Top features usadas
$topFeatures = safeRows($conexion,
    "SELECT event_name AS label, COUNT(*) AS value
     FROM app_events
     WHERE created_at > NOW() - INTERVAL 7 DAY
     GROUP BY event_name
     ORDER BY value DESC
     LIMIT 6");

// ── KPIs de IA ──
$iaSolicitudes24h = 0;
$iaSolicitudes30d = 0;
$iaTokensMes = 0;
$iaCostoMes = 0.0;
$iaErrorRate = 0.0;
$iaLatenciaP50 = 0;

try {
    $iaSolicitudes24h = (int)safeScalar($conexion,
        "SELECT COUNT(*) FROM ia_mensajes WHERE created_at > NOW() - INTERVAL 1 DAY");
    $iaSolicitudes30d = (int)safeScalar($conexion,
        "SELECT COUNT(*) FROM ia_mensajes WHERE created_at > NOW() - INTERVAL 30 DAY");
    $iaTokensMes = (int)safeScalar($conexion,
        "SELECT COALESCE(SUM(prompt_tokens + completion_tokens),0)
         FROM ia_mensajes WHERE created_at > DATE_FORMAT(NOW(), '%Y-%m-01')");
    $iaCostoMes = (float)safeScalar($conexion,
        "SELECT COALESCE(SUM(cost_usd),0)
         FROM ia_mensajes WHERE created_at > DATE_FORMAT(NOW(), '%Y-%m-01')");
    $iaErrores = (int)safeScalar($conexion,
        "SELECT COUNT(*) FROM ia_mensajes WHERE error_code IS NOT NULL AND created_at > NOW() - INTERVAL 24 HOUR");
    $iaTotal24h = max(1, $iaSolicitudes24h);
    $iaErrorRate = ($iaErrores / $iaTotal24h) * 100;
    $iaLatenciaP50 = (int)safeScalar($conexion,
        "SELECT COALESCE(AVG(latency_ms),0) FROM ia_mensajes
         WHERE created_at > NOW() - INTERVAL 24 HOUR");
} catch (Throwable $e) {
    // Tablas IA pueden no existir aún (migración 010 pendiente)
}

// ── Series temporales ──
$serieNuevosUsuarios = adminSerieNDias($conexion, 30, 'COUNT(*)', 'usuarios', 'registration_date');
$serieSimulacros     = adminSerieNDias($conexion, 30, 'COUNT(*)', 'simulacro_resultados', 'fecha_realizacion');
$serieIA            = [];
try {
    $serieIA = adminSerieNDias($conexion, 14, 'COUNT(*)', 'ia_mensajes');
} catch (Throwable $e) {}

// ── Alertas prioritarias ──
$alertasPrioritarias = safeRows($conexion,
    "SELECT severity, title, message, created_at, related_entity
     FROM system_alerts
     WHERE is_resolved = 0
     ORDER BY
       FIELD(severity,'critical','high','medium','info'),
       created_at DESC
     LIMIT 5");

// ── Actividad reciente (admin) ──
$actividadReciente = safeRows($conexion,
    "SELECT action, entity, admin_user, created_at, ip
     FROM admin_audit_log
     ORDER BY id DESC LIMIT 5");

// ── Pagos pendientes ──
$pagosPendientes = (int)safeScalar($conexion,
    "SELECT COUNT(*) FROM payments WHERE LOWER(status)='pending' AND created_at > NOW() - INTERVAL 24 HOUR");

// ── Render ──
render_header('Dashboard Ejecutivo', ['section' => 'dashboard']);
?>

<div class="section-header">
    <div>
        <div class="section-header__title">Dashboard Ejecutivo</div>
        <div class="section-header__subtitle">Visión 360° de Saber+ en tiempo real</div>
    </div>
    <div class="quick-stats">
        <div class="quick-stat">
            <div class="quick-stat__value"><?= admin_fmt_int($totalUsuarios) ?></div>
            <div class="quick-stat__label">Usuarios</div>
        </div>
        <div class="quick-stat">
            <div class="quick-stat__value"><?= admin_fmt_pct($conversionPremium) ?></div>
            <div class="quick-stat__label">Conversión</div>
        </div>
        <div class="quick-stat">
            <div class="quick-stat__value"><?= admin_fmt_cop($mrr30d) ?></div>
            <div class="quick-stat__label">MRR 30d</div>
        </div>
    </div>
</div>

<?php if (!empty($alertasPrioritarias)): ?>
<section class="card">
    <div class="card__header">
        <div class="card__title">🚨 Alertas prioritarias</div>
        <a href="<?= admin_section_url('alerts') ?>" class="btn btn--sm btn--outline">Ver todas</a>
    </div>
    <div class="alerts-priority">
        <?php foreach ($alertasPrioritarias as $alert): ?>
            <div class="alert-row alert-row--<?= sp_h($alert['severity']) ?>">
                <div class="alert-row__icon">
                    <?php
                    $icon = 'ℹ️';
                    if ($alert['severity'] === 'critical') $icon = '🔴';
                    elseif ($alert['severity'] === 'high') $icon = '🟠';
                    elseif ($alert['severity'] === 'medium') $icon = '🟡';
                    echo $icon;
                    ?>
                </div>
                <div class="alert-row__content">
                    <div class="alert-row__title"><?= sp_h($alert['title']) ?></div>
                    <div class="alert-row__message"><?= sp_h($alert['message']) ?></div>
                </div>
                <div class="alert-row__time"><?= admin_fmt_tiempo_relativo($alert['created_at']) ?></div>
            </div>
        <?php endforeach; ?>
    </div>
</section>
<?php endif; ?>

<section class="kpi-row">
    <div class="kpi-card">
        <div class="kpi-card__header">
            <div class="kpi-card__title">Total usuarios</div>
            <div class="kpi-card__icon">👥</div>
        </div>
        <div class="kpi-card__value"><?= admin_fmt_int($totalUsuarios) ?></div>
        <div class="kpi-card__subtitle">
            <?= admin_fmt_int($nuevosUsuarios7d) ?> nuevos (7d) ·
            <?= admin_fmt_int($nuevosUsuarios30d) ?> nuevos (30d)
        </div>
    </div>

    <div class="kpi-card kpi-card--success">
        <div class="kpi-card__header">
            <div class="kpi-card__title">Activos 30d</div>
            <div class="kpi-card__icon">⚡</div>
        </div>
        <div class="kpi-card__value"><?= admin_fmt_int($usuariosActivos30d) ?></div>
        <div class="kpi-card__subtitle">
            <?= $totalUsuarios > 0 ? admin_fmt_pct(($usuariosActivos30d / $totalUsuarios) * 100) : '0%' ?> del total
        </div>
    </div>

    <div class="kpi-card kpi-card--purple">
        <div class="kpi-card__header">
            <div class="kpi-card__title">Premium</div>
            <div class="kpi-card__icon">💳</div>
        </div>
        <div class="kpi-card__value"><?= admin_fmt_int($premiumCount) ?></div>
        <div class="kpi-card__subtitle"><?= admin_fmt_pct($conversionPremium) ?> conversión</div>
    </div>

    <div class="kpi-card kpi-card--info">
        <div class="kpi-card__header">
            <div class="kpi-card__title">MRR 30d</div>
            <div class="kpi-card__icon">💰</div>
        </div>
        <div class="kpi-card__value" style="font-size:var(--fs-2xl)"><?= admin_fmt_cop($mrr30d) ?></div>
        <div class="kpi-card__subtitle">Total acumulado: <?= admin_fmt_cop($mrrTotal) ?></div>
    </div>
</section>

<section class="dashboard-row">
    <div class="chart-container">
        <div class="chart-container__header">
            <div>
                <div class="chart-container__title">Crecimiento de usuarios (30 días)</div>
                <div class="chart-container__subtitle">Nuevos registros por día</div>
            </div>
        </div>
        <div class="chart-container__body">
            <?= admin_svg_serie($serieNuevosUsuarios, 600, 120) ?>
        </div>
    </div>

    <div class="chart-container">
        <div class="chart-container__header">
            <div>
                <div class="chart-container__title">Distribución de planes</div>
                <div class="chart-container__subtitle">Usuarios por access_level</div>
            </div>
        </div>
        <div class="chart-container__body" style="display:flex;justify-content:center;align-items:center;gap:24px;">
            <?php
            $donutData = [];
            $colors = ['free' => '#94A3B8', 'premium' => '#1E4ED8', 'trial' => '#F59E0B', 'early_bird' => '#10B981'];
            foreach ($distribucionPlanes as $i => $row) {
                $plan = $row['plan'];
                $donutData[] = [
                    'label' => ucfirst(str_replace('_', ' ', $plan)),
                    'value' => (int)$row['total'],
                    'color' => $colors[$plan] ?? '#1E4ED8',
                ];
            }
            if (!empty($donutData)) echo admin_svg_donut($donutData, 130, 20);
            ?>
            <div style="display:flex;flex-direction:column;gap:6px;font-size:13px;">
                <?php foreach ($donutData as $d): ?>
                    <div style="display:flex;align-items:center;gap:8px;">
                        <span style="width:10px;height:10px;border-radius:2px;background:<?= $d['color'] ?>"></span>
                        <strong><?= sp_h($d['label']) ?></strong>:
                        <span style="color:#475569"><?= admin_fmt_int($d['value']) ?></span>
                    </div>
                <?php endforeach; ?>
            </div>
        </div>
    </div>
</section>

<section class="kpi-row">
    <div class="kpi-card kpi-card--success">
        <div class="kpi-card__header">
            <div class="kpi-card__title">Simulacros (7d)</div>
            <div class="kpi-card__icon">📝</div>
        </div>
        <div class="kpi-card__value"><?= admin_fmt_int($simulacros7d) ?></div>
        <div class="kpi-card__subtitle">Promedio ICFES: <?= number_format((float)$promedioGlobal, 1, ',', '.') ?></div>
    </div>

    <div class="kpi-card kpi-card--warning">
        <div class="kpi-card__header">
            <div class="kpi-card__title">Errores 24h</div>
            <div class="kpi-card__icon">⚠️</div>
        </div>
        <div class="kpi-card__value"><?= admin_fmt_int($erroresPendientes) ?></div>
        <div class="kpi-card__subtitle">
            <a href="<?= admin_section_url('system') ?>" style="font-size:12px;">Ver System Health →</a>
        </div>
    </div>

    <div class="kpi-card kpi-card--info">
        <div class="kpi-card__header">
            <div class="kpi-card__title">Solicitudes IA (24h)</div>
            <div class="kpi-card__icon">🤖</div>
        </div>
        <div class="kpi-card__value"><?= admin_fmt_int($iaSolicitudes24h) ?></div>
        <div class="kpi-card__subtitle">
            <?= admin_fmt_int($iaSolicitudes30d) ?> en 30d ·
            <?= admin_fmt_pct($iaErrorRate) ?> error rate
        </div>
    </div>

    <div class="kpi-card kpi-card--purple">
        <div class="kpi-card__header">
            <div class="kpi-card__title">Costo IA (mes)</div>
            <div class="kpi-card__icon">💸</div>
        </div>
        <div class="kpi-card__value" style="font-size:var(--fs-2xl)"><?= admin_fmt_usd($iaCostoMes) ?></div>
        <div class="kpi-card__subtitle"><?= admin_fmt_int($iaTokensMes) ?> tokens consumidos</div>
    </div>
</section>

<section class="dashboard-row">
    <div class="chart-container">
        <div class="chart-container__header">
            <div>
                <div class="chart-container__title">Actividad de simulacros (30 días)</div>
                <div class="chart-container__subtitle">Simulacros completados por día</div>
            </div>
        </div>
        <div class="chart-container__body">
            <?= admin_svg_serie($serieSimulacros, 600, 100, '#10B981') ?>
        </div>
    </div>

    <div class="chart-container">
        <div class="chart-container__header">
            <div>
                <div class="chart-container__title">Promedio por área (30d)</div>
                <div class="chart-container__subtitle">Puntaje ICFES promedio</div>
            </div>
        </div>
        <div class="chart-container__body">
            <?php if (!empty($promediosAreas)): $p = $promediosAreas[0]; ?>
                <div style="display:flex;flex-direction:column;gap:8px;">
                    <?php
                    $areas = [
                        ['Lectura crítica', $p['lectura'] ?? 0, '#3B82F6'],
                        ['Matemáticas', $p['matematicas'] ?? 0, '#EF4444'],
                        ['Sociales', $p['sociales'] ?? 0, '#F59E0B'],
                        ['Naturales', $p['naturales'] ?? 0, '#10B981'],
                        ['Inglés', $p['ingles'] ?? 0, '#8B5CF6'],
                    ];
                    foreach ($areas as $a):
                        $pct = min(100, ((float)$a[1] / 500) * 100); // ICFES max 500 por área
                    ?>
                        <div style="display:flex;align-items:center;gap:8px;">
                            <span style="width:120px;font-size:13px;color:#475569"><?= sp_h($a[0]) ?></span>
                            <div style="flex:1;height:8px;background:#E5E7EB;border-radius:4px;overflow:hidden;">
                                <div style="width:<?= $pct ?>%;height:100%;background:<?= $a[2] ?>;"></div>
                            </div>
                            <span style="font-weight:700;font-size:13px;min-width:40px;text-align:right;"><?= number_format((float)$a[1], 1, ',', '.') ?></span>
                        </div>
                    <?php endforeach; ?>
                </div>
            <?php else: ?>
                <div class="empty-state">
                    <div class="empty-state__icon">📊</div>
                    <div class="empty-state__message">Sin datos suficientes</div>
                </div>
            <?php endif; ?>
        </div>
    </div>
</section>

<section class="dashboard-row">
    <div class="chart-container">
        <div class="chart-container__header">
            <div>
                <div class="chart-container__title">Funcionalidades más usadas (7d)</div>
                <div class="chart-container__subtitle">Top eventos en la app</div>
            </div>
        </div>
        <div class="chart-container__body">
            <?php if (!empty($topFeatures)): ?>
                <?= admin_svg_bars($topFeatures, 580, 22, 6, '#1E4ED8') ?>
            <?php else: ?>
                <div class="empty-state">
                    <div class="empty-state__icon">📱</div>
                    <div class="empty-state__message">Sin eventos en los últimos 7 días</div>
                </div>
            <?php endif; ?>
        </div>
    </div>

    <div class="chart-container">
        <div class="chart-container__header">
            <div>
                <div class="chart-container__title">Actividad reciente</div>
                <div class="chart-container__subtitle">Últimas acciones administrativas</div>
            </div>
        </div>
        <div class="chart-container__body">
            <div class="activity-feed">
                <?php if (empty($actividadReciente)): ?>
                    <div class="empty-state" style="padding:24px;">
                        <div class="empty-state__icon">📝</div>
                        <div class="empty-state__message">Sin actividad reciente</div>
                    </div>
                <?php else: foreach ($actividadReciente as $act):
                    $icon = '⚙️';
                    if (str_contains($act['action'], 'login')) $icon = '🔑';
                    elseif (str_contains($act['action'], 'user')) $icon = '👤';
                    elseif (str_contains($act['action'], 'plan')) $icon = '💳';
                    elseif (str_contains($act['action'], 'campaign')) $icon = '📣';
                    elseif (str_contains($act['action'], 'export')) $icon = '📤';
                ?>
                    <div class="activity-item">
                        <div class="activity-item__icon"><?= $icon ?></div>
                        <div class="activity-item__content">
                            <div class="activity-item__title">
                                <strong><?= sp_h($act['admin_user']) ?></strong>
                                ejecutó <code><?= sp_h($act['action']) ?></code>
                                <?php if (!empty($act['entity'])): ?>en <?= sp_h($act['entity']) ?><?php endif; ?>
                            </div>
                            <div class="activity-item__time">
                                <?= admin_fmt_tiempo_relativo($act['created_at']) ?> ·
                                IP <?= sp_h($act['ip'] ?? '—') ?>
                            </div>
                        </div>
                    </div>
                <?php endforeach; endif; ?>
            </div>
        </div>
    </div>
</section>

<?php if ($pagosPendientes > 0): ?>
<section class="flash flash--warning">
    <div>
        ⚠️ Hay <strong><?= $pagosPendientes ?></strong> pagos pendientes de más de 24 horas.
        <a href="<?= admin_section_url('exports') ?>&type=pagos" style="margin-left:8px;">Ver detalles →</a>
    </div>
</section>
<?php endif; ?>

<?php
render_footer();
