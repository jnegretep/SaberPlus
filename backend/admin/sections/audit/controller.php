<?php
declare(strict_types=1);

/**
 * SPRINT 7 — Sección Auditoría
 *
 * Vista profesional del log de auditoría administrativa:
 *  - Tabla paginada (50/página) con filtros avanzados
 *  - Buscador por entity_id o details LIKE
 *  - Orden por created_at (default), admin_user, action
 *  - Vista detalle (?action=view&id=X) con diff visual before/after
 *  - Export CSV de resultados filtrados (límite 5000)
 *  - Gráfico SVG de actividad por día (últimos 30 días)
 *  - Restricción: solo superadmin ve entradas module='auth' (logins)
 *
 * Permiso requerido: audit.read
 */

require_once __DIR__ . '/../../bootstrap.php';
require_once __DIR__ . '/../../includes/layout.php';

require_permission('audit.read');

$isAdminSuper = (current_admin_role() === 'superadmin');

// ── Parámetros de entrada ──
$viewAction = $_GET['action'] ?? '';
$viewId      = isset($_GET['id']) ? (int)$_GET['id'] : 0;
$exportCsv   = isset($_GET['export']) && $_GET['export'] === 'csv';

$filters = [
    'admin_user' => trim((string)($_GET['admin_user'] ?? '')),
    'module'      => trim((string)($_GET['module'] ?? '')),
    'action'      => trim((string)($_GET['action'] ?? '')),
    'entity'      => trim((string)($_GET['entity'] ?? '')),
    'from'        => trim((string)($_GET['from'] ?? '')),
    'to'          => trim((string)($_GET['to'] ?? '')),
    'success'     => trim((string)($_GET['success'] ?? '')), // ''|'1'|'0'
    'entity_id'   => trim((string)($_GET['entity_id'] ?? '')),
    'details_q'   => trim((string)($_GET['details_q'] ?? '')),
];

$sort        = $_GET['sort'] ?? 'created_at';
$sortDir     = (($_GET['dir'] ?? 'desc') === 'asc') ? 'ASC' : 'DESC';
$allowedSort = ['created_at', 'admin_user', 'action', 'module', 'entity'];
if (!in_array($sort, $allowedSort, true)) $sort = 'created_at';
$page = max(1, (int)($_GET['page'] ?? 1));
$perPage = 50;

// ── Construir cláusula WHERE dinámica ──
$where  = [];
$params = [];

// Restricción: solo superadmin ve módulo auth (logins)
if (!$isAdminSuper) {
    $where[] = "(module IS NULL OR module <> 'auth')";
}

if ($filters['admin_user'] !== '') {
    $where[] = 'admin_user LIKE :au';
    $params[':au'] = '%' . $filters['admin_user'] . '%';
}
if ($filters['module'] !== '') {
    $where[] = 'module = :mo';
    $params[':mo'] = $filters['module'];
}
if ($filters['action'] !== '') {
    $where[] = 'action = :ac';
    $params[':ac'] = $filters['action'];
}
if ($filters['entity'] !== '') {
    $where[] = 'entity LIKE :en';
    $params[':en'] = '%' . $filters['entity'] . '%';
}
if ($filters['from'] !== '' && preg_match('/^\d{4}-\d{2}-\d{2}$/', $filters['from'])) {
    $where[] = 'created_at >= :from';
    $params[':from'] = $filters['from'] . ' 00:00:00';
}
if ($filters['to'] !== '' && preg_match('/^\d{4}-\d{2}-\d{2}$/', $filters['to'])) {
    $where[] = 'created_at <= :to';
    $params[':to'] = $filters['to'] . ' 23:59:59';
}
if ($filters['success'] === '1' || $filters['success'] === '0') {
    $where[] = 'success = :su';
    $params[':su'] = (int)$filters['success'];
}
if ($filters['entity_id'] !== '' && ctype_digit($filters['entity_id'])) {
    $where[] = 'entity_id = :eid';
    $params[':eid'] = (int)$filters['entity_id'];
}
if ($filters['details_q'] !== '') {
    $where[] = 'details LIKE :dq';
    $params[':dq'] = '%' . $filters['details_q'] . '%';
}

$whereSql = $where ? ('WHERE ' . implode(' AND ', $where)) : '';

// ── Mapeo seguro de sort ──
$sortMap = [
    'created_at' => 'created_at',
    'admin_user' => 'admin_user',
    'action'     => 'action',
    'module'     => 'module',
    'entity'     => 'entity',
];
$sortCol = $sortMap[$sort] ?? 'created_at';
$orderSql = "ORDER BY $sortCol $sortDir, id DESC";

// ── Vista detalle (?action=view&id=X) ──
if ($viewAction === 'view' && $viewId > 0) {
    $stmt = $conexion->prepare("SELECT * FROM admin_audit_log WHERE id = :id LIMIT 1");
    $stmt->execute([':id' => $viewId]);
    $entry = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$entry) {
        admin_flash('error', 'Registro de auditoría no encontrado.');
        header('Location: ' . admin_section_url('audit'));
        exit;
    }

    // Restricción módulo auth
    if (!$isAdminSuper && ($entry['module'] ?? '') === 'auth') {
        http_response_code(403);
        exit('Permisos insuficientes para ver este registro.');
    }

    // Parsear before/after para diff
    $beforeData = null;
    $afterData  = null;
    if (!empty($entry['before_value'])) {
        $beforeData = json_decode($entry['before_value'], true);
        if (!is_array($beforeData)) $beforeData = null;
    }
    if (!empty($entry['after_value'])) {
        $afterData = json_decode($entry['after_value'], true);
        if (!is_array($afterData)) $afterData = null;
    }

    // Construir diff
    $diffRows = [];
    if ($beforeData !== null || $afterData !== null) {
        $allKeys = array_unique(array_merge(
            $beforeData !== null ? array_keys($beforeData) : [],
            $afterData  !== null ? array_keys($afterData)  : []
        ));
        foreach ($allKeys as $k) {
            $b = $beforeData[$k] ?? null;
            $a = $afterData[$k] ?? null;
            $changed = (json_encode($b) !== json_encode($a));
            $diffRows[] = [
                'field'   => $k,
                'before'  => $b,
                'after'   => $a,
                'changed' => $changed,
            ];
        }
    }

    $referer = $_SERVER['HTTP_REFERER'] ?? admin_section_url('audit');

    render_header('Auditoría · Detalle #' . $viewId, ['section' => 'audit']);
    ?>
    <div class="section-header">
        <div>
            <div class="section-header__title">Registro de auditoría #<?= $viewId ?></div>
            <div class="section-header__subtitle">
                <a href="<?= admin_section_url('audit') ?>">← Volver a la lista</a>
            </div>
        </div>
        <div class="quick-stats">
            <div class="quick-stat">
                <div class="quick-stat__value" style="font-size:var(--fs-lg)"><?= sp_h($entry['action'] ?? '—') ?></div>
                <div class="quick-stat__label">Acción</div>
            </div>
        </div>
    </div>

    <section class="card">
        <div class="card__header">
            <div class="card__title">Información del evento</div>
        </div>
        <table class="data-table">
            <tbody>
                <tr><td style="width:200px"><strong>ID</strong></td><td><?= (int)$entry['id'] ?></td></tr>
                <tr><td><strong>Fecha</strong></td><td><?= sp_h($entry['created_at'] ?? '—') ?></td></tr>
                <tr><td><strong>Admin</strong></td><td><?= sp_h($entry['admin_user'] ?? '—') ?> (ID: <?= sp_h((string)($entry['admin_user_id'] ?? '—')) ?>)</td></tr>
                <tr><td><strong>Módulo</strong></td><td><?= sp_h($entry['module'] ?? '—') ?></td></tr>
                <tr><td><strong>Acción</strong></td><td><code><?= sp_h($entry['action'] ?? '—') ?></code></td></tr>
                <tr><td><strong>Entidad</strong></td><td><?= sp_h($entry['entity'] ?? '—') ?> <?= !empty($entry['entity_id']) ? '#' . (int)$entry['entity_id'] : '' ?></td></tr>
                <tr><td><strong>Resultado</strong></td>
                    <td>
                        <?php if ((int)($entry['success'] ?? 0) === 1): ?>
                            <span class="badge badge--success">OK</span>
                        <?php else: ?>
                            <span class="badge badge--danger">Falló</span>
                        <?php endif; ?>
                    </td>
                </tr>
                <tr><td><strong>IP</strong></td><td><?= sp_h($entry['ip'] ?? '—') ?></td></tr>
                <tr><td><strong>User Agent</strong></td><td style="font-size:12px;color:#475569"><?= sp_h($entry['user_agent'] ?? '—') ?></td></tr>
                <tr><td><strong>Session ID</strong></td><td><code style="font-size:11px"><?= sp_h($entry['session_id'] ?? '—') ?></code></td></tr>
                <?php if (!empty($entry['details'])): ?>
                <tr><td><strong>Details</strong></td><td><code style="font-size:12px;white-space:pre-wrap;word-break:break-all"><?= sp_h($entry['details']) ?></code></td></tr>
                <?php endif; ?>
            </tbody>
        </table>
    </section>

    <?php if (!empty($diffRows)): ?>
    <section class="card">
        <div class="card__header">
            <div class="card__title">Diff before / after</div>
        </div>
        <table class="data-table">
            <thead>
                <tr>
                    <th style="width:25%">Campo</th>
                    <th style="width:37.5%">Antes</th>
                    <th style="width:37.5%">Después</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($diffRows as $row): ?>
                    <tr style="<?= $row['changed'] ? 'background:#FFFBEB;' : '' ?>">
                        <td><strong><?= sp_h((string)$row['field']) ?></strong></td>
                        <td>
                            <?php if ($row['before'] === null): ?>
                                <em style="color:#94A3B8">null</em>
                            <?php else: ?>
                                <code style="font-size:12px;white-space:pre-wrap;word-break:break-all"><?= sp_h(is_scalar($row['before']) ? (string)$row['before'] : json_encode($row['before'], JSON_UNESCAPED_UNICODE)) ?></code>
                            <?php endif; ?>
                        </td>
                        <td>
                            <?php if ($row['after'] === null): ?>
                                <em style="color:#94A3B8">null</em>
                            <?php else: ?>
                                <code style="font-size:12px;white-space:pre-wrap;word-break:break-all;<?= $row['changed'] ? 'background:#ECFDF5;padding:2px 4px;border-radius:3px;' : '' ?>"><?= sp_h(is_scalar($row['after']) ? (string)$row['after'] : json_encode($row['after'], JSON_UNESCAPED_UNICODE)) ?></code>
                            <?php endif; ?>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </section>
    <?php endif; ?>

    <p style="margin-top:16px"><a href="<?= sp_h($referer) ?>" class="btn btn--outline">← Volver</a></p>

    <?php
    render_footer();
    exit;
}

// ── Export CSV ──
if ($exportCsv) {
    $csvLimit = 5000;
    $sql = "SELECT id, admin_user, admin_user_id, module, action, entity, entity_id,
                   details, before_value, after_value, success, ip, user_agent,
                   session_id, created_at
            FROM admin_audit_log
            $whereSql
            $orderSql
            LIMIT $csvLimit";
    $stmt = $conexion->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Auditar exportación
    admin_audit_log(
        $conexion,
        'audit_export_csv',
        'admin_audit_log',
        null,
        json_encode([
            'filters' => $filters,
            'rows'    => count($rows),
        ], JSON_UNESCAPED_UNICODE),
        'audit'
    );

    $filename = 'auditoria_' . date('Ymd_His') . '.csv';
    header('Content-Type: text/csv; charset=UTF-8');
    header('Content-Disposition: attachment; filename="' . $filename . '"');
    header('Cache-Control: no-store, no-cache, must-revalidate');
    $fh = fopen('php://output', 'w');
    // BOM UTF-8 para Excel
    fwrite($fh, "\xEF\xBB\xBF");
    fputcsv($fh, ['ID', 'Admin', 'Admin ID', 'Módulo', 'Acción', 'Entidad', 'Entidad ID',
                  'Details', 'Before', 'After', 'OK', 'IP', 'User Agent', 'Session ID', 'Fecha']);

    $sanitizeCell = function ($v): string {
        $s = (string)$v;
        if ($s !== '' && in_array($s[0], ['=', '+', '-', '@'], true)) {
            return "'" . $s;
        }
        return $s;
    };
    foreach ($rows as $r) {
        fputcsv($fh, array_map($sanitizeCell, [
            $r['id'], $r['admin_user'], $r['admin_user_id'], $r['module'], $r['action'],
            $r['entity'], $r['entity_id'], $r['details'], $r['before_value'], $r['after_value'],
            $r['success'], $r['ip'], $r['user_agent'], $r['session_id'], $r['created_at'],
        ]));
    }
    fclose($fh);
    exit;
}

// ── Listado: COUNT para paginación ──
$countSql = "SELECT COUNT(*) FROM admin_audit_log $whereSql";
$stmt = $conexion->prepare($countSql);
$stmt->execute($params);
$total = (int)$stmt->fetchColumn();
$totalPages = max(1, (int)ceil($total / $perPage));
if ($page > $totalPages) $page = $totalPages;
$offset = ($page - 1) * $perPage;

// ── Listado: filas ──
$listSql = "SELECT id, admin_user, admin_user_id, module, action, entity, entity_id,
                   success, ip, created_at
            FROM admin_audit_log
            $whereSql
            $orderSql
            LIMIT $perPage OFFSET $offset";
$stmt = $conexion->prepare($listSql);
$stmt->execute($params);
$entries = $stmt->fetchAll(PDO::FETCH_ASSOC);

// ── Filtros select: módulos y acciones únicas ──
$modules = safeRows($conexion,
    "SELECT DISTINCT module FROM admin_audit_log WHERE module IS NOT NULL AND module <> '' ORDER BY module");
$actions = safeRows($conexion,
    "SELECT DISTINCT action FROM admin_audit_log ORDER BY action");

// ── Serie temporal últimos 30 días ──
$serieActividad = adminSerieNDias($conexion, 30, 'COUNT(*)', 'admin_audit_log', 'created_at');

// ── Helper para links de orden ──
$buildSortUrl = function (string $col) use ($sort, $sortDir, $filters, $page): string {
    $newDir = ($sort === $col && $sortDir === 'DESC') ? 'asc' : 'desc';
    $params = array_filter([
        'section'     => 'audit',
        'admin_user'  => $filters['admin_user'],
        'module'      => $filters['module'],
        'action'      => $filters['action'],
        'entity'      => $filters['entity'],
        'from'        => $filters['from'],
        'to'          => $filters['to'],
        'success'     => $filters['success'],
        'entity_id'   => $filters['entity_id'],
        'details_q'   => $filters['details_q'],
        'sort'        => $col,
        'dir'         => $newDir,
        'page'        => $page,
    ], fn($v) => $v !== '' && $v !== null);
    return 'index.php?' . http_build_query($params);
};

$buildPageUrl = function (int $p) use ($sort, $sortDir, $filters): string {
    $params = array_filter([
        'section'     => 'audit',
        'admin_user'  => $filters['admin_user'],
        'module'      => $filters['module'],
        'action'      => $filters['action'],
        'entity'      => $filters['entity'],
        'from'        => $filters['from'],
        'to'          => $filters['to'],
        'success'     => $filters['success'],
        'entity_id'   => $filters['entity_id'],
        'details_q'   => $filters['details_q'],
        'sort'        => $sort,
        'dir'         => $sortDir === 'ASC' ? 'asc' : 'desc',
        'page'        => $p,
    ], fn($v) => $v !== '' && $v !== null);
    return 'index.php?' . http_build_query($params);
};

$buildExportUrl = function () use ($sort, $sortDir, $filters): string {
    $params = array_filter([
        'section'     => 'audit',
        'export'      => 'csv',
        'admin_user'  => $filters['admin_user'],
        'module'      => $filters['module'],
        'action'      => $filters['action'],
        'entity'      => $filters['entity'],
        'from'        => $filters['from'],
        'to'          => $filters['to'],
        'success'     => $filters['success'],
        'entity_id'   => $filters['entity_id'],
        'details_q'   => $filters['details_q'],
        'sort'        => $sort,
        'dir'         => $sortDir === 'ASC' ? 'asc' : 'desc',
    ], fn($v) => $v !== '' && $v !== null);
    return 'index.php?' . http_build_query($params);
};

render_header('Auditoría', ['section' => 'audit']);
?>

<div class="section-header">
    <div>
        <div class="section-header__title">Auditoría administrativa</div>
        <div class="section-header__subtitle">
            Registro inmutable de acciones administrativas ·
            <strong><?= admin_fmt_int($total) ?></strong> eventos coinciden con los filtros
            <?php if (!$isAdminSuper): ?>
            · <em>Eventos de autenticación (module=auth) ocultos</em>
            <?php endif; ?>
        </div>
    </div>
    <div class="quick-stats">
        <a href="<?= sp_h($buildExportUrl()) ?>" class="btn btn--outline btn--sm">📥 Exportar CSV</a>
    </div>
</div>

<section class="card">
    <div class="card__header">
        <div class="card__title">Actividad (últimos 30 días)</div>
    </div>
    <div style="padding:var(--space-4) var(--space-5)">
        <?= admin_svg_serie($serieActividad, 900, 100, '#1E4ED8') ?>
    </div>
</section>

<form method="get" action="index.php" class="filters-bar">
    <input type="hidden" name="section" value="audit">
    <div class="filters-bar__field">
        <label class="filters-bar__label">Admin</label>
        <input type="text" name="admin_user" value="<?= sp_h($filters['admin_user']) ?>" placeholder="email o nombre">
    </div>
    <div class="filters-bar__field">
        <label class="filters-bar__label">Módulo</label>
        <select name="module">
            <option value="">— todos —</option>
            <?php foreach ($modules as $m): ?>
                <option value="<?= sp_h($m['module']) ?>" <?= $filters['module'] === $m['module'] ? 'selected' : '' ?>>
                    <?= sp_h($m['module']) ?>
                </option>
            <?php endforeach; ?>
        </select>
    </div>
    <div class="filters-bar__field">
        <label class="filters-bar__label">Acción</label>
        <select name="action">
            <option value="">— todas —</option>
            <?php foreach ($actions as $a): ?>
                <option value="<?= sp_h($a['action']) ?>" <?= $filters['action'] === $a['action'] ? 'selected' : '' ?>>
                    <?= sp_h($a['action']) ?>
                </option>
            <?php endforeach; ?>
        </select>
    </div>
    <div class="filters-bar__field">
        <label class="filters-bar__label">Entidad</label>
        <input type="text" name="entity" value="<?= sp_h($filters['entity']) ?>" placeholder="user, plan, ...">
    </div>
    <div class="filters-bar__field">
        <label class="filters-bar__label">Entidad ID</label>
        <input type="number" name="entity_id" value="<?= sp_h($filters['entity_id']) ?>" placeholder="123">
    </div>
    <div class="filters-bar__field">
        <label class="filters-bar__label">Buscar en details</label>
        <input type="text" name="details_q" value="<?= sp_h($filters['details_q']) ?>" placeholder="texto en details">
    </div>
    <div class="filters-bar__field">
        <label class="filters-bar__label">Desde</label>
        <input type="date" name="from" value="<?= sp_h($filters['from']) ?>">
    </div>
    <div class="filters-bar__field">
        <label class="filters-bar__label">Hasta</label>
        <input type="date" name="to" value="<?= sp_h($filters['to']) ?>">
    </div>
    <div class="filters-bar__field">
        <label class="filters-bar__label">Resultado</label>
        <select name="success">
            <option value=""  <?= $filters['success'] === ''  ? 'selected' : '' ?>>todos</option>
            <option value="1" <?= $filters['success'] === '1' ? 'selected' : '' ?>>sí</option>
            <option value="0" <?= $filters['success'] === '0' ? 'selected' : '' ?>>no</option>
        </select>
    </div>
    <div class="filters-bar__field">
        <button type="submit" class="btn btn--primary btn--sm">🔍 Filtrar</button>
        <a href="index.php?section=audit" class="btn btn--outline btn--sm">Limpiar</a>
    </div>
</form>

<section class="card">
    <?php if (empty($entries)): ?>
        <div class="empty-state">
            <div class="empty-state__icon">📝</div>
            <div class="empty-state__title">Sin resultados</div>
            <div class="empty-state__message">No se encontraron eventos de auditoría con los filtros actuales.</div>
        </div>
    <?php else: ?>
        <div style="overflow-x:auto">
        <table class="data-table">
            <thead>
                <tr>
                    <th>ID</th>
                    <th>
                        <a href="<?= sp_h($buildSortUrl('admin_user')) ?>">Admin</a>
                        <?php if ($sort === 'admin_user'): ?><?= $sortDir === 'ASC' ? '▲' : '▼' ?><?php endif; ?>
                    </th>
                    <th>
                        <a href="<?= sp_h($buildSortUrl('module')) ?>">Módulo</a>
                        <?php if ($sort === 'module'): ?><?= $sortDir === 'ASC' ? '▲' : '▼' ?><?php endif; ?>
                    </th>
                    <th>
                        <a href="<?= sp_h($buildSortUrl('action')) ?>">Acción</a>
                        <?php if ($sort === 'action'): ?><?= $sortDir === 'ASC' ? '▲' : '▼' ?><?php endif; ?>
                    </th>
                    <th>Entidad</th>
                    <th>OK</th>
                    <th>IP</th>
                    <th>
                        <a href="<?= sp_h($buildSortUrl('created_at')) ?>">Fecha</a>
                        <?php if ($sort === 'created_at'): ?><?= $sortDir === 'ASC' ? '▲' : '▼' ?><?php endif; ?>
                    </th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($entries as $e): ?>
                    <tr>
                        <td><a href="index.php?section=audit&action=view&id=<?= (int)$e['id'] ?>" style="font-weight:600">#<?= (int)$e['id'] ?></a></td>
                        <td><?= sp_h($e['admin_user'] ?? '—') ?></td>
                        <td><code style="font-size:11px"><?= sp_h($e['module'] ?? '—') ?></code></td>
                        <td><code style="font-size:11px"><?= sp_h($e['action'] ?? '—') ?></code></td>
                        <td>
                            <?= sp_h($e['entity'] ?? '—') ?>
                            <?php if (!empty($e['entity_id'])): ?>
                                <span style="color:#94A3B8">#<?= (int)$e['entity_id'] ?></span>
                            <?php endif; ?>
                        </td>
                        <td>
                            <?php if ((int)($e['success'] ?? 0) === 1): ?>
                                <span class="badge badge--success">OK</span>
                            <?php else: ?>
                                <span class="badge badge--danger">FAIL</span>
                            <?php endif; ?>
                        </td>
                        <td style="font-size:12px;color:#475569"><?= sp_h($e['ip'] ?? '—') ?></td>
                        <td style="font-size:12px;color:#475569;white-space:nowrap"><?= sp_h($e['created_at'] ?? '—') ?></td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
        </div>

        <div class="pagination">
            <div>
                Mostrando <?= number_format($offset + 1) ?>–<?= number_format(min($offset + $perPage, $total)) ?>
                de <?= number_format($total) ?>
            </div>
            <div class="pagination__pages">
                <?php if ($page > 1): ?>
                    <a class="pagination__page" href="<?= sp_h($buildPageUrl($page - 1)) ?>">← Anterior</a>
                <?php endif; ?>

                <?php
                $start = max(1, $page - 2);
                $end   = min($totalPages, $page + 2);
                for ($i = $start; $i <= $end; $i++):
                ?>
                    <a class="pagination__page <?= $i === $page ? 'is-active' : '' ?>"
                       href="<?= sp_h($buildPageUrl($i)) ?>"><?= $i ?></a>
                <?php endfor; ?>

                <?php if ($page < $totalPages): ?>
                    <a class="pagination__page" href="<?= sp_h($buildPageUrl($page + 1)) ?>">Siguiente →</a>
                <?php endif; ?>
            </div>
        </div>
    <?php endif; ?>
</section>

<?php
render_footer();
