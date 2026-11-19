<?php
declare(strict_types=1);

/**
 * SPRINT 7 — Sección Alertas CEO
 *
 * Centro de alertas operativas del sistema:
 *  - Lista de `system_alerts` ordenada por severidad y fecha
 *  - Filtros: severity, category, is_resolved
 *  - Contadores rápidos en top (críticas, altas, totales)
 *  - Acción "Marcar como resuelta" (POST, CSRF, requiere system.health)
 *  - Modal "Ver detalle" con context JSON pretty-print
 *  - Badge de severidad con color: critical=rojo, high=naranja, medium=amarillo, info=azul
 *  - Estado vacío si no hay alertas
 *
 * Visualización abierta a cualquier admin autenticado (matches layout perm=null).
 * Resolver requiere permiso `system.health`.
 */

require_once __DIR__ . '/../../bootstrap.php';
require_once __DIR__ . '/../../includes/layout.php';

require_admin_auth();

// ── Procesar POST: marcar alerta como resuelta ──
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $postAction = $_POST['post_action'] ?? '';

    if ($postAction === 'resolve_alert') {
        require_permission('system.health');

        $alertId = (int)($_POST['alert_id'] ?? 0);
        if ($alertId <= 0) {
            admin_flash('error', 'ID de alerta inválido.');
            header('Location: ' . admin_section_url('alerts'));
            exit;
        }

        // Capturar before para auditoría
        $stmt = $conexion->prepare("SELECT * FROM system_alerts WHERE id = :id LIMIT 1");
        $stmt->execute([':id' => $alertId]);
        $before = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$before) {
            admin_flash('error', 'Alerta no encontrada.');
            header('Location: ' . admin_section_url('alerts'));
            exit;
        }

        if ((int)$before['is_resolved'] === 1) {
            admin_flash('info', 'La alerta ya estaba resuelta.');
            header('Location: ' . admin_section_url('alerts'));
            exit;
        }

        try {
            $upd = $conexion->prepare(
                "UPDATE system_alerts
                 SET is_resolved = 1, resolved_at = NOW(), resolved_by = :uid
                 WHERE id = :id"
            );
            $upd->execute([
                ':uid' => current_admin_id(),
                ':id'  => $alertId,
            ]);

            // Auditar
            $after = $before;
            $after['is_resolved'] = 1;
            $after['resolved_at'] = date('Y-m-d H:i:s');
            $after['resolved_by'] = current_admin_id();
            admin_audit_change(
                $conexion,
                'alerts',
                'resolve_alert',
                'system_alert',
                $alertId,
                $before,
                $after
            );

            admin_flash('success', "Alerta #{$alertId} marcada como resuelta.");
        } catch (Throwable $e) {
            error_log('[ALERTS] Error al resolver alerta: ' . $e->getMessage());
            admin_flash('error', 'Error interno al resolver la alerta.');
        }
        header('Location: ' . admin_section_url('alerts'));
        exit;
    }
}

// ── Filtros ──
$fSeverity    = trim((string)($_GET['severity'] ?? ''));
$fCategory    = trim((string)($_GET['category'] ?? ''));
$fResolved    = trim((string)($_GET['is_resolved'] ?? '')); // ''|'open'|'resolved'

$where  = [];
$params = [];
if (in_array($fSeverity, ['critical', 'high', 'medium', 'info'], true)) {
    $where[] = 'severity = :sev';
    $params[':sev'] = $fSeverity;
}
if ($fCategory !== '') {
    $where[] = 'category = :cat';
    $params[':cat'] = $fCategory;
}
if ($fResolved === 'open') {
    $where[] = 'is_resolved = 0';
} elseif ($fResolved === 'resolved') {
    $where[] = 'is_resolved = 1';
}
$whereSql = $where ? ('WHERE ' . implode(' AND ', $where)) : '';

// ── Contadores rápidos ──
$criticalOpen = (int)safeScalar($conexion,
    "SELECT COUNT(*) FROM system_alerts WHERE is_resolved = 0 AND severity = 'critical'");
$highOpen     = (int)safeScalar($conexion,
    "SELECT COUNT(*) FROM system_alerts WHERE is_resolved = 0 AND severity = 'high'");
$totalAll     = (int)safeScalar($conexion, "SELECT COUNT(*) FROM system_alerts");
$totalOpen    = (int)safeScalar($conexion,
    "SELECT COUNT(*) FROM system_alerts WHERE is_resolved = 0");

// ── Categorías únicas para filtro ──
$categories = safeRows($conexion,
    "SELECT DISTINCT category FROM system_alerts
     WHERE category IS NOT NULL AND category <> ''
     ORDER BY category ASC");

// ── Lista de alertas (ordenada por severidad y fecha) ──
$sql = "SELECT id, severity, category, title, message, context,
               related_entity, related_entity_id, is_resolved,
               resolved_at, resolved_by, created_at
        FROM system_alerts
        $whereSql
        ORDER BY
          is_resolved ASC,
          FIELD(severity, 'critical', 'high', 'medium', 'info'),
          created_at DESC
        LIMIT 200";
$stmt = $conexion->prepare($sql);
$stmt->execute($params);
$alerts = $stmt->fetchAll(PDO::FETCH_ASSOC);

// ── Helpers locales ──
$sevColor = function (string $sev): string {
    return match ($sev) {
        'critical' => 'danger',
        'high'     => 'warning',
        'medium'   => 'info',
        'info'     => 'info',
        default    => 'gray',
    };
};
$sevIcon = function (string $sev): string {
    return match ($sev) {
        'critical' => '🔴',
        'high'     => '🟠',
        'medium'   => '🟡',
        'info'     => '🔵',
        default    => '⚪',
    };
};

render_header('Alertas CEO', ['section' => 'alerts']);
?>

<div class="section-header">
    <div>
        <div class="section-header__title">Centro de Alertas</div>
        <div class="section-header__subtitle">
            Visión única de alertas operativas y de negocio
        </div>
    </div>
    <div class="quick-stats">
        <div class="quick-stat">
            <div class="quick-stat__value" style="color:var(--color-danger)"><?= admin_fmt_int($criticalOpen) ?></div>
            <div class="quick-stat__label">Críticas abiertas</div>
        </div>
        <div class="quick-stat">
            <div class="quick-stat__value" style="color:var(--color-warning)"><?= admin_fmt_int($highOpen) ?></div>
            <div class="quick-stat__label">Altas abiertas</div>
        </div>
        <div class="quick-stat">
            <div class="quick-stat__value"><?= admin_fmt_int($totalAll) ?></div>
            <div class="quick-stat__label">Total</div>
        </div>
    </div>
</div>

<form method="get" action="index.php" class="filters-bar">
    <input type="hidden" name="section" value="alerts">
    <div class="filters-bar__field">
        <label class="filters-bar__label">Severidad</label>
        <select name="severity">
            <option value="" <?= $fSeverity === '' ? 'selected' : '' ?>>todas</option>
            <option value="critical" <?= $fSeverity === 'critical' ? 'selected' : '' ?>>critical</option>
            <option value="high"     <?= $fSeverity === 'high'     ? 'selected' : '' ?>>high</option>
            <option value="medium"   <?= $fSeverity === 'medium'   ? 'selected' : '' ?>>medium</option>
            <option value="info"     <?= $fSeverity === 'info'     ? 'selected' : '' ?>>info</option>
        </select>
    </div>
    <div class="filters-bar__field">
        <label class="filters-bar__label">Categoría</label>
        <select name="category">
            <option value="">todas</option>
            <?php foreach ($categories as $c): ?>
                <option value="<?= sp_h($c['category']) ?>" <?= $fCategory === $c['category'] ? 'selected' : '' ?>>
                    <?= sp_h($c['category']) ?>
                </option>
            <?php endforeach; ?>
        </select>
    </div>
    <div class="filters-bar__field">
        <label class="filters-bar__label">Estado</label>
        <select name="is_resolved">
            <option value=""          <?= $fResolved === ''          ? 'selected' : '' ?>>todas</option>
            <option value="open"      <?= $fResolved === 'open'      ? 'selected' : '' ?>>abiertas</option>
            <option value="resolved"  <?= $fResolved === 'resolved'  ? 'selected' : '' ?>>resueltas</option>
        </select>
    </div>
    <div class="filters-bar__field">
        <button type="submit" class="btn btn--primary btn--sm">🔍 Filtrar</button>
        <a href="index.php?section=alerts" class="btn btn--outline btn--sm">Limpiar</a>
    </div>
</form>

<section class="card">
    <div class="card__header">
        <div class="card__title">Alertas (<?= count($alerts) ?> mostradas · <?= admin_fmt_int($totalOpen) ?> abiertas en total)</div>
    </div>

    <?php if (empty($alerts)): ?>
        <div class="empty-state">
            <div class="empty-state__icon">✅</div>
            <div class="empty-state__title">Sin alertas activas</div>
            <div class="empty-state__message">
                No hay alertas que coincidan con los filtros actuales. Todo en orden.
            </div>
        </div>
    <?php else: ?>
        <div style="display:flex;flex-direction:column;gap:var(--space-3)">
            <?php foreach ($alerts as $a):
                $sev = $a['severity'];
                $ctx = null;
                if (!empty($a['context'])) {
                    $ctx = json_decode($a['context'], true);
                    if (!is_array($ctx)) $ctx = null;
                }
                $isResolved = (int)$a['is_resolved'] === 1;
            ?>
                <div class="alert-row alert-row--<?= sp_h($sev) ?><?= $isResolved ? ' alert-row--resolved' : '' ?>"
                     style="align-items:flex-start;padding:var(--space-4);<?= $isResolved ? 'opacity:0.7;' : '' ?>">
                    <div class="alert-row__icon"><?= $sevIcon($sev) ?></div>
                    <div class="alert-row__content" style="flex:1;min-width:0">
                        <div style="display:flex;align-items:center;gap:var(--space-2);flex-wrap:wrap;">
                            <span class="badge badge--<?= $sevColor($sev) ?>"><?= sp_h($sev) ?></span>
                            <?php if (!empty($a['category'])): ?>
                                <span class="badge badge--gray"><?= sp_h($a['category']) ?></span>
                            <?php endif; ?>
                            <?php if ($isResolved): ?>
                                <span class="badge badge--success">resuelta</span>
                            <?php endif; ?>
                            <strong style="margin-left:auto;font-size:var(--fs-md);"><?= sp_h($a['title']) ?></strong>
                        </div>
                        <div style="margin-top:var(--space-2);color:var(--color-text-secondary);font-size:var(--fs-md);">
                            <?= sp_h(mb_substr($a['message'] ?? '', 0, 400)) ?>
                        </div>
                        <div style="margin-top:var(--space-2);font-size:var(--fs-xs);color:var(--color-text-tertiary);display:flex;gap:var(--space-3);flex-wrap:wrap;">
                            <span>📅 <?= sp_h($a['created_at']) ?></span>
                            <?php if (!empty($a['related_entity'])): ?>
                                <span>🔗 <?= sp_h($a['related_entity']) ?><?= !empty($a['related_entity_id']) ? ' #' . (int)$a['related_entity_id'] : '' ?></span>
                            <?php endif; ?>
                            <?php if ($isResolved && !empty($a['resolved_at'])): ?>
                                <span>✓ resuelta <?= sp_h($a['resolved_at']) ?></span>
                            <?php endif; ?>
                            <button type="button"
                                    onclick="document.getElementById('alert-modal-<?= (int)$a['id'] ?>').style.display='flex'"
                                    class="btn btn--outline btn--sm" style="margin-left:auto;">
                                Ver detalle
                            </button>
                            <?php if (!$isResolved): ?>
                                <form method="post" action="index.php?section=alerts" style="display:inline;">
                                    <?= admin_csrf_field() ?>
                                    <input type="hidden" name="post_action" value="resolve_alert">
                                    <input type="hidden" name="alert_id" value="<?= (int)$a['id'] ?>">
                                    <?php if (admin_has_permission('system.health')): ?>
                                        <button type="submit" class="btn btn--success btn--sm"
                                                onclick="return confirm('¿Marcar esta alerta como resuelta?')">
                                            ✓ Marcar como resuelta
                                        </button>
                                    <?php endif; ?>
                                </form>
                            <?php endif; ?>
                        </div>
                    </div>
                </div>

                <?php if (!empty($a['context']) || !empty($a['message'])): ?>
                <div id="alert-modal-<?= (int)$a['id'] ?>" class="modal-backdrop" style="display:none;">
                    <div class="modal" style="max-width:680px;">
                        <div class="modal__header">
                            <div class="modal__title"><?= $sevIcon($sev) ?> <?= sp_h($a['title']) ?></div>
                            <button class="modal__close"
                                    onclick="document.getElementById('alert-modal-<?= (int)$a['id'] ?>').style.display='none'">×</button>
                        </div>
                        <div class="modal__body">
                            <table class="data-table" style="margin-bottom:var(--space-4);">
                                <tbody>
                                    <tr><td style="width:140px"><strong>ID</strong></td><td>#<?= (int)$a['id'] ?></td></tr>
                                    <tr><td><strong>Severidad</strong></td><td><span class="badge badge--<?= $sevColor($sev) ?>"><?= sp_h($sev) ?></span></td></tr>
                                    <tr><td><strong>Categoría</strong></td><td><?= sp_h($a['category'] ?? '—') ?></td></tr>
                                    <tr><td><strong>Entidad</strong></td><td><?= sp_h($a['related_entity'] ?? '—') ?> <?= !empty($a['related_entity_id']) ? '#' . (int)$a['related_entity_id'] : '' ?></td></tr>
                                    <tr><td><strong>Estado</strong></td><td><?= $isResolved ? '<span class="badge badge--success">resuelta</span>' : '<span class="badge badge--warning">abierta</span>' ?></td></tr>
                                    <tr><td><strong>Creada</strong></td><td><?= sp_h($a['created_at']) ?></td></tr>
                                    <?php if ($isResolved): ?>
                                    <tr><td><strong>Resuelta</strong></td><td><?= sp_h($a['resolved_at'] ?? '—') ?> por admin #<?= (int)($a['resolved_by'] ?? 0) ?></td></tr>
                                    <?php endif; ?>
                                </tbody>
                            </table>

                            <div style="margin-bottom:var(--space-3);">
                                <div style="font-size:var(--fs-sm);color:var(--color-text-secondary);text-transform:uppercase;font-weight:600;margin-bottom:var(--space-1);">Mensaje</div>
                                <div style="background:var(--color-surface-variant);padding:var(--space-3);border-radius:var(--radius-sm);white-space:pre-wrap;"><?= sp_h($a['message']) ?></div>
                            </div>

                            <?php if ($ctx !== null): ?>
                            <div>
                                <div style="font-size:var(--fs-sm);color:var(--color-text-secondary);text-transform:uppercase;font-weight:600;margin-bottom:var(--space-1);">Contexto (JSON)</div>
                                <pre style="background:#0F172A;color:#E2E8F0;padding:var(--space-3);border-radius:var(--radius-sm);font-size:12px;overflow:auto;max-height:300px;"><?= sp_h(json_encode($ctx, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)) ?></pre>
                            </div>
                            <?php elseif (!empty($a['context'])): ?>
                            <div>
                                <div style="font-size:var(--fs-sm);color:var(--color-text-secondary);text-transform:uppercase;font-weight:600;margin-bottom:var(--space-1);">Contexto (raw)</div>
                                <code style="font-size:12px;word-break:break-all;"><?= sp_h($a['context']) ?></code>
                            </div>
                            <?php endif; ?>
                        </div>
                        <div class="modal__footer">
                            <button class="btn btn--outline"
                                    onclick="document.getElementById('alert-modal-<?= (int)$a['id'] ?>').style.display='none'">Cerrar</button>
                        </div>
                    </div>
                </div>
                <?php endif; ?>
            <?php endforeach; ?>
        </div>
    <?php endif; ?>
</section>

<?php
render_footer();
