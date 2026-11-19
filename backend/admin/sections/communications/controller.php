<?php
declare(strict_types=1);

/**
 * SABER+ COMMAND CENTER — Sección Comunicaciones
 *
 * Gestión profesional de campañas masivas con segmentación, previsualización,
 * programación y procesamiento asíncrono vía cron (cron_send_campaigns.php).
 *
 * Flujo de estados:
 *   draft  → previewed → sending → completed
 *                ↘ cancelled      ↘ failed
 *
 * Permisos:
 *   - communications.history  → listar y ver detalle
 *   - communications.send     → crear/editar/previsualizar/enviar/cancelar
 *
 * Rutas (vía index.php?section=communications):
 *   - (sin action)               → lista paginada con filtros
 *   - &action=create             → form nueva campaña
 *   - &action=edit&id=X          → form editar campaña
 *   - &action=view&id=X          → detalle con destinatarios
 *
 * Acciones POST (todas con CSRF automático de bootstrap.php):
 *   - do=create | update | preview | send | cancel
 */

require_once __DIR__ . '/../../bootstrap.php';
require_once __DIR__ . '/../../includes/layout.php';
require_once __DIR__ . '/audience_helpers.php';

// Acceso base: cualquier admin con communications.history puede listar y ver
require_permission('communications.history');

$db = $GLOBALS['admin_conn'] ?? $conexion;

$action = $_GET['action'] ?? 'list';
$action = is_string($action) ? preg_replace('/[^a-z_]/', '', $action) : 'list';
$campaignId = isset($_GET['id']) ? (int)$_GET['id'] : 0;

// ────────────────────────────────────────────────────────────────────────
//  POST ACTIONS
// ────────────────────────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $do = $_POST['do'] ?? '';
    if (!is_string($do)) $do = '';

    // Todas las acciones POST requieren permiso de envío
    require_permission('communications.send');

    switch ($do) {
        case 'create':
            $campaignId = handle_campaign_create($db);
            if ($campaignId > 0) {
                admin_audit_log($db, 'campaign.create', 'notification_campaign', $campaignId,
                    'Campaña creada: ' . substr(trim($_POST['title'] ?? ''), 0, 200),
                    'communications', null, null, true);
                admin_flash('success', 'Campaña creada como borrador. Configura la audiencia y previsualiza.');
                redirect_to_edit($campaignId);
            }
            admin_flash('error', 'No se pudo crear la campaña.');
            redirect_to_list();
            break;

        case 'update':
            $id = (int)($_POST['id'] ?? 0);
            if ($id <= 0) {
                admin_flash('error', 'ID de campaña inválido.');
                redirect_to_list();
            }
            $before = fetch_campaign($db, $id);
            $ok = handle_campaign_update($db, $id);
            $after = fetch_campaign($db, $id);
            admin_audit_change($db, 'communications', 'campaign.update',
                'notification_campaign', $id, $before ?: null, $after ?: [], $ok);
            if ($ok) {
                admin_flash('success', 'Campaña actualizada.');
            } else {
                admin_flash('error', 'No se pudo actualizar la campaña.');
            }
            redirect_to_edit($id);
            break;

        case 'preview':
            $id = (int)($_POST['id'] ?? 0);
            // Si no hay ID (form de nueva campaña), primero INSERTAR el draft
            if ($id <= 0) {
                $id = handle_campaign_create($db);
                if ($id <= 0) {
                    admin_flash('error', 'No se pudo crear la campaña para previsualizar.');
                    redirect_to_list();
                }
                admin_audit_log($db, 'campaign.create', 'notification_campaign', $id,
                    'Campaña creada vía preview', 'communications', null, null, true);
                $before = null;
            } else {
                $before = fetch_campaign($db, $id);
                if (!$before) {
                    admin_flash('error', 'Campaña no encontrada.');
                    redirect_to_list();
                }
                // Actualizar campos primero (auditable)
                handle_campaign_update($db, $id);
            }
            // Calcular audiencia con el filtro recién guardado
            $after = fetch_campaign($db, $id);
            if (!$after) {
                admin_flash('error', 'No se pudo recargar la campaña tras guardar.');
                redirect_to_list();
            }
            $filter = json_decode((string)$after['audience_filter'], true) ?: [];
            $total = admin_campaign_count_audience($db, $filter);
            try {
                $stmt = $db->prepare(
                    'UPDATE notification_campaigns
                     SET total_targeted = ?, status = ?
                     WHERE id = ? AND status IN (\'draft\',\'previewed\')'
                );
                $stmt->execute([$total, 'previewed', $id]);
                $ok = $stmt->rowCount() >= 0;
            } catch (Throwable $e) {
                error_log('[communications.preview] ' . $e->getMessage());
                $ok = false;
            }
            $after = fetch_campaign($db, $id);
            admin_audit_change($db, 'communications', 'campaign.preview',
                'notification_campaign', $id, $before, $after ?: [], $ok);
            if ($ok) {
                admin_flash('success', "Audiencia calculada: {$total} destinatarios. Campaña lista para enviar.");
                header('Location: ' . admin_section_url('communications', ['action' => 'edit', 'id' => $id, 'show_sample' => 1]));
                exit;
            }
            admin_flash('error', 'No se pudo previsualizar la campaña. Verifica que esté en estado draft o previewed.');
            redirect_to_edit($id);
            break;

        case 'send':
            $id = (int)($_POST['id'] ?? 0);
            if ($id <= 0) {
                admin_flash('error', 'ID de campaña inválido.');
                redirect_to_list();
            }
            $camp = fetch_campaign($db, $id);
            if (!$camp) {
                admin_flash('error', 'Campaña no encontrada.');
                redirect_to_list();
            }
            if ($camp['status'] !== 'previewed') {
                admin_flash('error', 'Solo se pueden enviar campañas en estado "previewed". Estado actual: ' . $camp['status']);
                redirect_to_edit($id);
            }
            try {
                $stmt = $db->prepare(
                    'UPDATE notification_campaigns
                     SET status = \'sending\'
                     WHERE id = ? AND status = \'previewed\''
                );
                $stmt->execute([$id]);
                $ok = $stmt->rowCount() > 0;
            } catch (Throwable $e) {
                error_log('[communications.send] ' . $e->getMessage());
                $ok = false;
            }
            admin_audit_log($db, 'campaign.send', 'notification_campaign', $id,
                'Campaña marcada para envío. destinatarios=' . (int)$camp['total_targeted'],
                'communications', null, null, $ok);
            if ($ok) {
                admin_flash('success', 'Campaña encolada para envío. El cron la procesará en los próximos segundos.');
                header('Location: ' . admin_section_url('communications', ['action' => 'view', 'id' => $id]));
                exit;
            }
            admin_flash('error', 'No se pudo encolar el envío.');
            redirect_to_edit($id);
            break;

        case 'cancel':
            $id = (int)($_POST['id'] ?? 0);
            if ($id <= 0) {
                admin_flash('error', 'ID de campaña inválido.');
                redirect_to_list();
            }
            $camp = fetch_campaign($db, $id);
            if (!$camp) {
                admin_flash('error', 'Campaña no encontrada.');
                redirect_to_list();
            }
            if (!in_array($camp['status'], ['draft', 'previewed', 'sending'], true)) {
                admin_flash('error', 'La campaña no puede cancelarse en su estado actual: ' . $camp['status']);
                redirect_to_view($id);
            }
            try {
                $stmt = $db->prepare(
                    'UPDATE notification_campaigns
                     SET status = \'cancelled\'
                     WHERE id = ? AND status IN (\'draft\',\'previewed\',\'sending\')'
                );
                $stmt->execute([$id]);
                $ok = $stmt->rowCount() > 0;
            } catch (Throwable $e) {
                error_log('[communications.cancel] ' . $e->getMessage());
                $ok = false;
            }
            admin_audit_log($db, 'campaign.cancel', 'notification_campaign', $id,
                'Campaña cancelada por admin. estado_previo=' . $camp['status'],
                'communications', null, null, $ok);
            if ($ok) {
                admin_flash('info', 'Campaña cancelada.');
            } else {
                admin_flash('error', 'No se pudo cancelar la campaña (quizá ya cambió de estado).');
            }
            redirect_to_view($id);
            break;

        default:
            admin_flash('error', 'Acción POST no reconocida.');
            redirect_to_list();
    }
}

// ────────────────────────────────────────────────────────────────────────
//  GET ROUTES
// ────────────────────────────────────────────────────────────────────────
switch ($action) {
    case 'create':
        require_permission('communications.send');
        render_campaign_form($db, null);
        break;

    case 'edit':
        require_permission('communications.send');
        if ($campaignId <= 0) {
            admin_flash('error', 'ID de campaña inválido.');
            redirect_to_list();
        }
        $camp = fetch_campaign($db, $campaignId);
        if (!$camp) {
            admin_flash('error', 'Campaña no encontrada.');
            redirect_to_list();
        }
        render_campaign_form($db, $camp);
        break;

    case 'view':
        if ($campaignId <= 0) {
            admin_flash('error', 'ID de campaña inválido.');
            redirect_to_list();
        }
        $camp = fetch_campaign($db, $campaignId);
        if (!$camp) {
            admin_flash('error', 'Campaña no encontrada.');
            redirect_to_list();
        }
        render_campaign_detail($db, $camp);
        break;

    default:
        render_campaign_list($db);
        break;
}

exit;

// ══════════════════════════════════════════════════════════════════════
//  HANDLERS
// ══════════════════════════════════════════════════════════════════════

function handle_campaign_create(PDO $db): int {
    $title = trim((string)($_POST['title'] ?? ''));
    $body  = trim((string)($_POST['body'] ?? ''));
    $type  = trim((string)($_POST['type'] ?? 'info'));
    $channel = trim((string)($_POST['channel'] ?? 'push'));
    $filterRaw = admin_campaign_normalize_filter($_POST);
    $scheduledAt = trim((string)($_POST['scheduled_at'] ?? ''));

    if ($title === '' || $body === '') {
        return 0;
    }
    if (!in_array($type, ['info', 'promo', 'update'], true)) $type = 'info';
    if (!in_array($channel, ['push', 'in_app', 'email_future'], true)) $channel = 'push';

    $scheduledSql = null;
    if ($scheduledAt !== '') {
        $ts = strtotime($scheduledAt);
        if ($ts !== false && $ts > time()) {
            $scheduledSql = date('Y-m-d H:i:s', $ts);
        }
    }

    try {
        $stmt = $db->prepare(
            'INSERT INTO notification_campaigns
                (title, body, type, channel, audience_filter, total_targeted,
                 total_sent, total_failed, status, scheduled_at, admin_user_id, created_at)
             VALUES
                (:title, :body, :type, :channel, :filter, 0, 0, 0,
                 :status, :scheduled, :admin_id, NOW())'
        );
        $stmt->execute([
            ':title'     => mb_substr($title, 0, 200),
            ':body'      => $body,
            ':type'      => $type,
            ':channel'   => $channel,
            ':filter'    => json_encode($filterRaw, JSON_UNESCAPED_UNICODE),
            ':status'    => 'draft',
            ':scheduled' => $scheduledSql,
            ':admin_id'  => current_admin_id() ?? 0,
        ]);
        return (int)$db->lastInsertId();
    } catch (Throwable $e) {
        error_log('[communications.create] ' . $e->getMessage());
        return 0;
    }
}

function handle_campaign_update(PDO $db, int $id): bool {
    $title = trim((string)($_POST['title'] ?? ''));
    $body  = trim((string)($_POST['body'] ?? ''));
    $type  = trim((string)($_POST['type'] ?? 'info'));
    $channel = trim((string)($_POST['channel'] ?? 'push'));
    $filterRaw = admin_campaign_normalize_filter($_POST);
    $scheduledAt = trim((string)($_POST['scheduled_at'] ?? ''));

    if ($title === '' || $body === '') return false;
    if (!in_array($type, ['info', 'promo', 'update'], true)) $type = 'info';
    if (!in_array($channel, ['push', 'in_app', 'email_future'], true)) $channel = 'push';

    $scheduledSql = null;
    if ($scheduledAt !== '') {
        $ts = strtotime($scheduledAt);
        if ($ts !== false && $ts > time()) {
            $scheduledSql = date('Y-m-d H:i:s', $ts);
        }
    }

    try {
        $stmt = $db->prepare(
            'UPDATE notification_campaigns
             SET title = :title,
                 body = :body,
                 type = :type,
                 channel = :channel,
                 audience_filter = :filter,
                 scheduled_at = :scheduled
             WHERE id = :id'
        );
        $stmt->execute([
            ':title'     => mb_substr($title, 0, 200),
            ':body'      => $body,
            ':type'      => $type,
            ':channel'   => $channel,
            ':filter'    => json_encode($filterRaw, JSON_UNESCAPED_UNICODE),
            ':scheduled' => $scheduledSql,
            ':id'        => $id,
        ]);
        return true;
    } catch (Throwable $e) {
        error_log('[communications.update] ' . $e->getMessage());
        return false;
    }
}

// ══════════════════════════════════════════════════════════════════════
//  FETCHERS
// ══════════════════════════════════════════════════════════════════════

function fetch_campaign(PDO $db, int $id): ?array {
    try {
        $stmt = $db->prepare(
            'SELECT c.*, u.email AS admin_email, u.name AS admin_name
             FROM notification_campaigns c
             LEFT JOIN admin_users u ON u.id = c.admin_user_id
             WHERE c.id = ?
             LIMIT 1'
        );
        $stmt->execute([$id]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        return $row ?: null;
    } catch (Throwable $e) {
        error_log('[communications.fetch_campaign] ' . $e->getMessage());
        return null;
    }
}

function fetch_segments(PDO $db): array {
    return safeRows($db, 'SELECT id, name, description FROM notification_segments ORDER BY name ASC');
}

// ══════════════════════════════════════════════════════════════════════
//  REDIRECT HELPERS
// ══════════════════════════════════════════════════════════════════════

function redirect_to_list(): void {
    header('Location: ' . admin_section_url('communications'));
    exit;
}
function redirect_to_edit(int $id): void {
    header('Location: ' . admin_section_url('communications', ['action' => 'edit', 'id' => $id]));
    exit;
}
function redirect_to_view(int $id): void {
    header('Location: ' . admin_section_url('communications', ['action' => 'view', 'id' => $id]));
    exit;
}

// ══════════════════════════════════════════════════════════════════════
//  VIEWS
// ══════════════════════════════════════════════════════════════════════

/** Vista: lista de campañas con filtros + paginación 30/página. */
function render_campaign_list(PDO $db): void {
    $perPage = 30;
    $page = max(1, (int)($_GET['page'] ?? 1));
    $offset = ($page - 1) * $perPage;

    $fStatus   = trim((string)($_GET['f_status'] ?? ''));
    $fType     = trim((string)($_GET['f_type'] ?? ''));
    $fChannel  = trim((string)($_GET['f_channel'] ?? ''));

    $where = [];
    $params = [];
    if (in_array($fStatus, ['draft','previewed','sending','completed','failed','cancelled'], true)) {
        $where[] = 'c.status = ?';
        $params[] = $fStatus;
    }
    if (in_array($fType, ['info','promo','update'], true)) {
        $where[] = 'c.type = ?';
        $params[] = $fType;
    }
    if (in_array($fChannel, ['push','in_app','email_future'], true)) {
        $where[] = 'c.channel = ?';
        $params[] = $fChannel;
    }
    $whereSql = $where ? 'WHERE ' . implode(' AND ', $where) : '';

    $total = (int)safeScalar($db,
        "SELECT COUNT(*) FROM notification_campaigns c $whereSql", $params);

    $rows = safeRows($db,
        "SELECT c.*, u.email AS admin_email, u.name AS admin_name
         FROM notification_campaigns c
         LEFT JOIN admin_users u ON u.id = c.admin_user_id
         $whereSql
         ORDER BY c.created_at DESC
         LIMIT $perPage OFFSET $offset", $params);

    $totalPages = max(1, (int)ceil($total / $perPage));

    $canSend = admin_has_permission('communications.send');

    render_header('Comunicaciones', ['section' => 'communications']);
    ?>
    <div class="section-header">
        <div>
            <div class="section-header__title">Comunicaciones</div>
            <div class="section-header__subtitle">Campañas masivas segmentadas con FCM v1 + bandeja in-app</div>
        </div>
        <div class="quick-stats">
            <div class="quick-stat">
                <div class="quick-stat__value"><?= admin_fmt_int($total) ?></div>
                <div class="quick-stat__label">Campañas totales</div>
            </div>
        </div>
    </div>

    <div class="filters-bar">
        <form method="get" action="index.php" style="display:flex;flex-wrap:wrap;gap:var(--space-3);align-items:end;">
            <input type="hidden" name="section" value="communications">
            <div class="filters-bar__field">
                <label class="filters-bar__label">Estado</label>
                <select name="f_status">
                    <option value="">Todos</option>
                    <?php foreach (['draft'=>'Borrador','previewed'=>'Previsualizada','sending'=>'Enviando','completed'=>'Completada','failed'=>'Fallida','cancelled'=>'Cancelada'] as $k=>$lbl): ?>
                        <option value="<?= sp_h($k) ?>" <?= $fStatus===$k?'selected':'' ?>><?= sp_h($lbl) ?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="filters-bar__field">
                <label class="filters-bar__label">Tipo</label>
                <select name="f_type">
                    <option value="">Todos</option>
                    <?php foreach (['info'=>'Info','promo'=>'Promo','update'=>'Actualización'] as $k=>$lbl): ?>
                        <option value="<?= sp_h($k) ?>" <?= $fType===$k?'selected':'' ?>><?= sp_h($lbl) ?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="filters-bar__field">
                <label class="filters-bar__label">Canal</label>
                <select name="f_channel">
                    <option value="">Todos</option>
                    <?php foreach (['push'=>'Push','in_app'=>'In-app','email_future'=>'Email (futuro)'] as $k=>$lbl): ?>
                        <option value="<?= sp_h($k) ?>" <?= $fChannel===$k?'selected':'' ?>><?= sp_h($lbl) ?></option>
                    <?php endforeach; ?>
                </select>
            </div>
            <button type="submit" class="btn btn--primary btn--sm">Filtrar</button>
            <a href="<?= admin_section_url('communications') ?>" class="btn btn--outline btn--sm">Limpiar</a>
        </form>
        <?php if ($canSend): ?>
            <a href="<?= admin_section_url('communications', ['action' => 'create']) ?>" class="btn btn--primary">+ Nueva campaña</a>
        <?php endif; ?>
    </div>

    <?php if (empty($rows)): ?>
        <section class="card">
            <div class="empty-state">
                <div class="empty-state__icon">📣</div>
                <div class="empty-state__title">Aún no hay campañas</div>
                <div class="empty-state__message">
                    <?php if ($canSend): ?>
                        Crea tu primera campaña masiva con segmentación profesional.
                        <br>
                        <a href="<?= admin_section_url('communications', ['action' => 'create']) ?>" class="btn btn--primary" style="margin-top:16px;">Crear campaña</a>
                    <?php else: ?>
                        Cuando se creen campañas, aparecerán aquí.
                    <?php endif; ?>
                </div>
            </div>
        </section>
    <?php else: ?>
        <section class="card">
            <div class="card__header">
                <div class="card__title">Campañas (<?= admin_fmt_int($total) ?>)</div>
            </div>
            <div style="overflow-x:auto;">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Título</th>
                            <th>Tipo</th>
                            <th>Canal</th>
                            <th>Audiencia</th>
                            <th>Destinatarios</th>
                            <th>Enviados / Fallidos</th>
                            <th>Estado</th>
                            <th>Creador</th>
                            <th>Creada</th>
                            <th>Acciones</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($rows as $r):
                            $filter = json_decode((string)$r['audience_filter'], true) ?: [];
                            $summary = admin_campaign_filter_summary($filter);
                            $statusBadge = status_badge($r['status']);
                            $totalTargeted = (int)$r['total_targeted'];
                            $totalSent = (int)$r['total_sent'];
                            $totalFailed = (int)$r['total_failed'];
                        ?>
                            <tr>
                                <td>#<?= (int)$r['id'] ?></td>
                                <td><strong><?= sp_h($r['title']) ?></strong></td>
                                <td><?= sp_h(ucfirst($r['type'])) ?></td>
                                <td><span class="badge badge--gray"><?= sp_h(str_replace('_',' ',$r['channel'])) ?></span></td>
                                <td><span title="<?= sp_h($summary) ?>" style="cursor:help;"><?= sp_h(mb_strimwidth($summary, 0, 40, '…')) ?></span></td>
                                <td><?= admin_fmt_int($totalTargeted) ?></td>
                                <td>
                                    <span style="color:var(--color-success);font-weight:600;"><?= admin_fmt_int($totalSent) ?></span>
                                    /
                                    <span style="color:var(--color-danger);font-weight:600;"><?= admin_fmt_int($totalFailed) ?></span>
                                </td>
                                <td><?= $statusBadge ?></td>
                                <td><?= sp_h($r['admin_name'] ?? $r['admin_email'] ?? '—') ?></td>
                                <td><span title="<?= sp_h($r['created_at']) ?>"><?= admin_fmt_tiempo_relativo($r['created_at']) ?></span></td>
                                <td style="white-space:nowrap;">
                                    <a href="<?= admin_section_url('communications', ['action' => 'view', 'id' => $r['id']]) ?>" class="btn btn--outline btn--sm">Ver</a>
                                    <?php if ($canSend && in_array($r['status'], ['draft','previewed'], true)): ?>
                                        <a href="<?= admin_section_url('communications', ['action' => 'edit', 'id' => $r['id']]) ?>" class="btn btn--outline btn--sm">Editar</a>
                                    <?php endif; ?>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </section>

        <?php if ($totalPages > 1):
            $pgBase = $_GET;
            unset($pgBase['section'], $pgBase['action'], $pgBase['id']);
        ?>
            <div class="pagination">
                <div>
                    Página <?= $page ?> de <?= $totalPages ?> · <?= admin_fmt_int($total) ?> campañas
                </div>
                <div class="pagination__pages">
                    <?php if ($page > 1): ?>
                        <a class="pagination__page" href="<?= admin_section_url('communications', array_merge($pgBase, ['page' => $page - 1])) ?>">← Anterior</a>
                    <?php endif; ?>
                    <?php
                    $start = max(1, $page - 2);
                    $end = min($totalPages, $page + 2);
                    for ($i = $start; $i <= $end; $i++):
                        $params = array_merge($pgBase, ['page' => $i]);
                    ?>
                        <a class="pagination__page <?= $i===$page?'is-active':'' ?>" href="<?= admin_section_url('communications', $params) ?>"><?= $i ?></a>
                    <?php endfor; ?>
                    <?php if ($page < $totalPages): ?>
                        <a class="pagination__page" href="<?= admin_section_url('communications', array_merge($pgBase, ['page' => $page + 1])) ?>">Siguiente →</a>
                    <?php endif; ?>
                </div>
            </div>
        <?php endif; ?>
    <?php
    endif;

    render_footer();
}

/** Vista: formulario crear/editar con audiencia configurable + preview. */
function render_campaign_form(PDO $db, ?array $campaign): void {
    $isNew = $campaign === null;
    $id = $isNew ? 0 : (int)$campaign['id'];

    $title   = $campaign['title']   ?? '';
    $body    = $campaign['body']    ?? '';
    $type    = $campaign['type']    ?? 'info';
    $channel = $campaign['channel'] ?? 'push';
    $status  = $campaign['status']  ?? 'draft';
    $scheduledAt = $campaign['scheduled_at'] ?? null;

    $filter = [];
    if (!$isNew && !empty($campaign['audience_filter'])) {
        $decoded = json_decode((string)$campaign['audience_filter'], true);
        if (is_array($decoded)) $filter = $decoded;
    }
    if (empty($filter)) $filter = ['mode' => 'all'];

    $mode = $filter['mode'] ?? 'all';
    $planes = is_array($filter['plan'] ?? null) ? $filter['plan'] : [];
    $departamentos = is_array($filter['departamentos'] ?? null) ? $filter['departamentos'] : [];
    if (!empty($filter['departamento']) && !in_array($filter['departamento'], $departamentos, true)) {
        $departamentos[] = $filter['departamento'];
    }
    $daysInactive = (int)($filter['days_inactive'] ?? 0);
    $userIds = is_array($filter['user_ids'] ?? null) ? $filter['user_ids'] : [];
    $userIdsText = implode("\n", $userIds);
    $segmentId = (int)($filter['segment_id'] ?? 0);

    $segments = fetch_segments($db);

    $showSample = isset($_GET['show_sample']);
    $sample = [];
    $sampleTotal = 0;
    if ($showSample && !$isNew) {
        $sample = admin_campaign_sample_audience($db, $filter, 20);
        $sampleTotal = admin_campaign_count_audience($db, $filter);
    }

    $canSend = admin_has_permission('communications.send');
    $canSendNow = $canSend && $status === 'previewed';

    render_header($isNew ? 'Nueva campaña' : 'Editar campaña', ['section' => 'communications']);
    ?>
    <div class="section-header">
        <div>
            <div class="section-header__title"><?= $isNew ? 'Nueva campaña' : 'Editar campaña #' . $id ?></div>
            <div class="section-header__subtitle">
                Estado actual:
                <?= status_badge($status) ?>
                <?php if (!$isNew && $status === 'previewed' && (int)$campaign['total_targeted'] > 0): ?>
                    · <?= admin_fmt_int((int)$campaign['total_targeted']) ?> destinatarios
                <?php endif; ?>
            </div>
        </div>
        <a href="<?= admin_section_url('communications') ?>" class="btn btn--outline btn--sm">← Volver</a>
    </div>

    <form method="post" action="index.php?section=communications" id="campaignForm">
        <?= admin_csrf_field() ?>
        <input type="hidden" name="id" value="<?= $id ?>">

        <section class="card">
            <div class="card__header">
                <div class="card__title">Contenido del mensaje</div>
            </div>
            <div class="form-group">
                <label class="form-label" for="f_title">Título <span style="color:var(--color-danger)">*</span></label>
                <input id="f_title" name="title" type="text" class="form-input" maxlength="200" required
                       value="<?= sp_h($title) ?>" placeholder="Ej: Nuevo simulacro ICFES disponible">
            </div>
            <div class="form-group">
                <label class="form-label" for="f_body">Mensaje <span style="color:var(--color-danger)">*</span></label>
                <textarea id="f_body" name="body" class="form-textarea" maxlength="500" required
                          placeholder="Cuerpo del mensaje (máx. 500 caracteres)"><?= sp_h($body) ?></textarea>
                <small id="bodyCounter" style="color:var(--color-text-tertiary);">0 / 500</small>
            </div>
            <div class="grid-2">
                <div class="form-group">
                    <label class="form-label" for="f_type">Tipo</label>
                    <select id="f_type" name="type" class="form-select">
                        <?php foreach (['info'=>'Info','promo'=>'Promo','update'=>'Actualización'] as $k=>$lbl): ?>
                            <option value="<?= sp_h($k) ?>" <?= $type===$k?'selected':'' ?>><?= sp_h($lbl) ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div class="form-group">
                    <label class="form-label" for="f_channel">Canal</label>
                    <select id="f_channel" name="channel" class="form-select">
                        <?php foreach (['push'=>'Push (FCM)','in_app'=>'In-app (bandeja + push)','email_future'=>'Email (futuro)'] as $k=>$lbl): ?>
                            <option value="<?= sp_h($k) ?>" <?= $channel===$k?'selected':'' ?>><?= sp_h($lbl) ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
            </div>
        </section>

        <section class="card">
            <div class="card__header">
                <div class="card__title">Audiencia</div>
                <small style="color:var(--color-text-tertiary);">
                    Siempre: usuarios con FCM token + email verificado
                </small>
            </div>

            <div class="form-group">
                <label class="form-label">Modo de segmentación</label>
                <div style="display:flex;flex-direction:column;gap:var(--space-2);">
                    <?php
                    $modes = [
                        'all'            => 'Todos los usuarios con FCM token',
                        'plan'           => 'Por plan',
                        'departamento'   => 'Por departamento',
                        'days_inactive'  => 'Por días de inactividad',
                        'user_ids'       => 'Por IDs específicos',
                        'segment'        => 'Segmento guardado',
                    ];
                    foreach ($modes as $m => $label):
                        $checked = $mode === $m ? 'checked' : '';
                    ?>
                        <label style="display:flex;align-items:center;gap:var(--space-2);padding:var(--space-2);border-radius:var(--radius-sm);<?= $mode===$m?'background:var(--color-surface-variant);':'' ?>">
                            <input type="radio" name="mode" value="<?= sp_h($m) ?>" <?= $checked ?>
                                   onchange="toggleAudiencePanels()">
                            <strong><?= sp_h($label) ?></strong>
                        </label>
                    <?php endforeach; ?>
                </div>
            </div>

            <!-- Panel: Por plan -->
            <div id="panel_plan" class="audience-panel" style="display:<?= $mode==='plan'?'block':'none' ?>;">
                <div class="form-group">
                    <label class="form-label">Planes a incluir</label>
                    <div style="display:flex;flex-wrap:wrap;gap:var(--space-3);">
                        <?php foreach (['free'=>'Free','premium'=>'Premium','trial'=>'Trial','early_bird'=>'Early Bird'] as $p=>$lbl): ?>
                            <label style="display:flex;align-items:center;gap:var(--space-2);">
                                <input type="checkbox" name="plan[]" value="<?= sp_h($p) ?>" <?= in_array($p,$planes,true)?'checked':'' ?>>
                                <?= sp_h($lbl) ?>
                            </label>
                        <?php endforeach; ?>
                    </div>
                </div>
            </div>

            <!-- Panel: Por departamento -->
            <div id="panel_departamento" class="audience-panel" style="display:<?= $mode==='departamento'?'block':'none' ?>;">
                <div class="form-group">
                    <label class="form-label" for="f_dep">Departamentos</label>
                    <input id="f_dep" name="departamento" type="text" class="form-input"
                           value="<?= sp_h(implode(', ', $departamentos)) ?>"
                           placeholder="Separa por coma: Bogotá D.C., Antioquia, Valle del Cauca">
                    <small style="color:var(--color-text-tertiary);">Puedes escribir varios separados por coma.</small>
                </div>
            </div>

            <!-- Panel: Por días de inactividad -->
            <div id="panel_days_inactive" class="audience-panel" style="display:<?= $mode==='days_inactive'?'block':'none' ?>;">
                <div class="form-group">
                    <label class="form-label" for="f_days">Días sin iniciar sesión (>= N días)</label>
                    <input id="f_days" name="days_inactive" type="number" min="1" max="3650" class="form-input"
                           value="<?= $daysInactive > 0 ? $daysInactive : '' ?>"
                           placeholder="Ej: 30 para usuarios inactivos 30+ días">
                </div>
            </div>

            <!-- Panel: Por IDs específicos -->
            <div id="panel_user_ids" class="audience-panel" style="display:<?= $mode==='user_ids'?'block':'none' ?>;">
                <div class="form-group">
                    <label class="form-label" for="f_ids">IDs de usuario (uno por línea o separados por coma)</label>
                    <textarea id="f_ids" name="user_ids_text" class="form-textarea" style="min-height:120px;"
                              placeholder="12&#10;34&#10;56"><?= sp_h($userIdsText) ?></textarea>
                </div>
            </div>

            <!-- Panel: Segmento guardado -->
            <div id="panel_segment" class="audience-panel" style="display:<?= $mode==='segment'?'block':'none' ?>;">
                <div class="form-group">
                    <label class="form-label" for="f_seg">Segmento</label>
                    <select id="f_seg" name="segment_id" class="form-select">
                        <option value="">— selecciona —</option>
                        <?php foreach ($segments as $seg): ?>
                            <option value="<?= (int)$seg['id'] ?>" <?= $segmentId===(int)$seg['id']?'selected':'' ?>>
                                <?= sp_h($seg['name']) ?><?= !empty($seg['description']) ? ' — ' . sp_h($seg['description']) : '' ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                    <?php if (empty($segments)): ?>
                        <small style="color:var(--color-warning);">Aún no hay segmentos guardados. Crea uno desde la BD (notification_segments).</small>
                    <?php endif; ?>
                </div>
            </div>
        </section>

        <section class="card">
            <div class="card__header">
                <div class="card__title">Programación (opcional)</div>
            </div>
            <div class="form-group">
                <label class="form-label" for="f_sched">Enviar automáticamente en (hora del servidor)</label>
                <input id="f_sched" name="scheduled_at" type="datetime-local" class="form-input"
                       value="<?= $scheduledAt ? date('Y-m-d\TH:i', strtotime((string)$scheduledAt)) : '' ?>">
                <small style="color:var(--color-text-tertiary);">
                    Si programas una fecha futura, la campaña quedará en estado <code>draft</code> y el cron la enviará automáticamente.
                    Si dejas vacío, se enviará cuando confirmes el envío.
                </small>
            </div>
        </section>

        <?php if ($showSample && !empty($sample)): ?>
            <section class="card" style="border-left:4px solid var(--color-success);">
                <div class="card__header">
                    <div class="card__title">Previsualización de audiencia</div>
                    <span class="badge badge--success"><?= admin_fmt_int($sampleTotal) ?> destinatarios</span>
                </div>
                <p style="margin-bottom:var(--space-3);color:var(--color-text-secondary);">
                    Muestra de los primeros <?= count($sample) ?> destinatarios:
                </p>
                <div style="overflow-x:auto;">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>Nombre</th>
                                <th>Email</th>
                                <th>Plan</th>
                                <th>Departamento</th>
                                <th>Último login</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($sample as $u): ?>
                                <tr>
                                    <td>#<?= (int)$u['id_usuario'] ?></td>
                                    <td><?= sp_h($u['nombre'] ?? '—') ?></td>
                                    <td><?= sp_h($u['email'] ?? '—') ?></td>
                                    <td><span class="badge badge--gray"><?= sp_h($u['access_level'] ?? 'free') ?></span></td>
                                    <td><?= sp_h($u['departamento'] ?? '—') ?></td>
                                    <td><?= admin_fmt_tiempo_relativo($u['ultimo_login'] ?? null) ?></td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            </section>
        <?php elseif ($showSample && empty($sample) && !$isNew): ?>
            <section class="card" style="border-left:4px solid var(--color-warning);">
                <div class="card__header">
                    <div class="card__title">Previsualización vacía</div>
                </div>
                <p style="color:var(--color-text-secondary);">
                    La audiencia calculada es <strong>0 destinatarios</strong>. Revisa los criterios de segmentación:
                    la campaña solo llegará a usuarios con FCM token + email verificado.
                </p>
            </section>
        <?php endif; ?>

        <section class="card">
            <div class="card__header">
                <div class="card__title">Acciones</div>
            </div>
            <div style="display:flex;flex-wrap:wrap;gap:var(--space-3);">
                <?php if ($isNew): ?>
                    <button type="submit" name="do" value="create" class="btn btn--primary">Guardar borrador</button>
                    <button type="submit" name="do" value="preview" class="btn btn--outline" data-confirm="Se guardará el borrador y se calculará la audiencia. ¿Continuar?">
                        Previsualizar audiencia
                    </button>
                <?php else: ?>
                    <button type="submit" name="do" value="update" class="btn btn--outline">Guardar cambios</button>
                    <button type="submit" name="do" value="preview" class="btn btn--outline"
                            data-confirm="Se guardarán los cambios y se recalculará la audiencia. ¿Continuar?">
                        Previsualizar audiencia
                    </button>

                    <?php if ($canSendNow): ?>
                        <button type="submit" name="do" value="send" class="btn btn--success"
                                data-confirm="⚠️ Vas a enviar esta campaña a <?= admin_fmt_int((int)$campaign['total_targeted']) ?> destinatarios. La acción NO se puede deshacer. ¿Confirmar envío?">
                            ✓ Confirmar y enviar
                        </button>
                    <?php elseif ($status === 'draft'): ?>
                        <span style="color:var(--color-text-tertiary);font-size:var(--fs-sm);">
                            ℹ️ Previsualiza la audiencia antes de enviar.
                        </span>
                    <?php elseif (in_array($status, ['sending','completed','failed','cancelled'], true)): ?>
                        <span style="color:var(--color-text-tertiary);font-size:var(--fs-sm);">
                            ⛔ No se puede enviar en estado actual: <strong><?= sp_h($status) ?></strong>
                        </span>
                    <?php endif; ?>

                    <a href="<?= admin_section_url('communications', ['action' => 'view', 'id' => $id]) ?>" class="btn btn--outline">Ver detalle</a>
                <?php endif; ?>
                <a href="<?= admin_section_url('communications') ?>" class="btn btn--outline">Cancelar</a>
            </div>
        </section>
    </form>

    <script>
    (function() {
        // Body counter
        var body = document.getElementById('f_body');
        var counter = document.getElementById('bodyCounter');
        if (body && counter) {
            function upd() { counter.textContent = body.value.length + ' / 500'; }
            body.addEventListener('input', upd);
            upd();
        }
    })();

    function toggleAudiencePanels() {
        var modes = ['plan','departamento','days_inactive','user_ids','segment'];
        var selected = document.querySelector('input[name="mode"]:checked');
        if (!selected) return;
        var val = selected.value;
        modes.forEach(function(m) {
            var el = document.getElementById('panel_' + m);
            if (el) el.style.display = (m === val) ? 'block' : 'none';
        });
    }
    document.addEventListener('DOMContentLoaded', toggleAudiencePanels);
    </script>

    <?php
    render_footer();
}

/** Vista: detalle de campaña con stats + lista de destinatarios. */
function render_campaign_detail(PDO $db, array $c): void {
    $id = (int)$c['id'];
    $filter = json_decode((string)$c['audience_filter'], true) ?: [];
    $summary = admin_campaign_filter_summary($filter);

    $totalTargeted = (int)$c['total_targeted'];
    $totalSent = (int)$c['total_sent'];
    $totalFailed = (int)$c['total_failed'];
    $totalPending = max(0, $totalTargeted - $totalSent - $totalFailed);
    $successRate = $totalTargeted > 0 ? ($totalSent / $totalTargeted) * 100 : 0;

    // Muestra de destinatarios (limit 50, full en BD)
    $recipients = admin_campaign_sample_audience($db, $filter, 50);

    $canSend = admin_has_permission('communications.send');
    $canCancel = $canSend && in_array($c['status'], ['draft','previewed','sending'], true);

    render_header('Campaña #' . $id, ['section' => 'communications']);
    ?>
    <div class="section-header">
        <div>
            <div class="section-header__title"><?= sp_h($c['title']) ?></div>
            <div class="section-header__subtitle">
                Campaña #<?= $id ?> · <?= status_badge($c['status']) ?>
                · Creada por <?= sp_h($c['admin_name'] ?? $c['admin_email'] ?? '—') ?>
                · <?= admin_fmt_tiempo_relativo($c['created_at']) ?>
            </div>
        </div>
        <div style="display:flex;gap:var(--space-2);flex-wrap:wrap;">
            <a href="<?= admin_section_url('communications') ?>" class="btn btn--outline btn--sm">← Volver</a>
            <?php if ($canSend && in_array($c['status'], ['draft','previewed'], true)): ?>
                <a href="<?= admin_section_url('communications', ['action' => 'edit', 'id' => $id]) ?>" class="btn btn--outline btn--sm">Editar</a>
            <?php endif; ?>
        </div>
    </div>

    <section class="kpi-row">
        <div class="kpi-card">
            <div class="kpi-card__header">
                <div class="kpi-card__title">Destinatarios</div>
                <div class="kpi-card__icon">👥</div>
            </div>
            <div class="kpi-card__value"><?= admin_fmt_int($totalTargeted) ?></div>
            <div class="kpi-card__subtitle"><?= sp_h($summary) ?></div>
        </div>
        <div class="kpi-card kpi-card--success">
            <div class="kpi-card__header">
                <div class="kpi-card__title">Enviados</div>
                <div class="kpi-card__icon">✓</div>
            </div>
            <div class="kpi-card__value"><?= admin_fmt_int($totalSent) ?></div>
            <div class="kpi-card__subtitle"><?= admin_fmt_pct($successRate) ?> éxito</div>
        </div>
        <div class="kpi-card kpi-card--danger">
            <div class="kpi-card__header">
                <div class="kpi-card__title">Fallidos</div>
                <div class="kpi-card__icon">⚠</div>
            </div>
            <div class="kpi-card__value"><?= admin_fmt_int($totalFailed) ?></div>
            <div class="kpi-card__subtitle"><?= $totalTargeted>0 ? admin_fmt_pct(($totalFailed/$totalTargeted)*100) : '—' ?></div>
        </div>
        <div class="kpi-card kpi-card--warning">
            <div class="kpi-card__header">
                <div class="kpi-card__title">Pendientes</div>
                <div class="kpi-card__icon">⏳</div>
            </div>
            <div class="kpi-card__value"><?= admin_fmt_int($totalPending) ?></div>
            <div class="kpi-card__subtitle">
                <?php if ($c['status'] === 'sending'): ?>
                    En progreso…
                <?php elseif ($c['status'] === 'completed'): ?>
                    Finalizada
                <?php else: ?>
                    No iniciada
                <?php endif; ?>
            </div>
        </div>
    </section>

    <section class="card">
        <div class="card__header">
            <div class="card__title">Detalles</div>
        </div>
        <div class="grid-2">
            <div>
                <strong>Tipo:</strong> <?= sp_h(ucfirst($c['type'])) ?><br>
                <strong>Canal:</strong> <?= sp_h(str_replace('_',' ',$c['channel'])) ?><br>
                <strong>Audiencia:</strong> <?= sp_h($summary) ?><br>
                <strong>Programada:</strong> <?= $c['scheduled_at'] ? admin_fmt_fecha($c['scheduled_at']) : 'No' ?><br>
                <strong>Iniciada:</strong> <?= $c['started_at'] ? admin_fmt_fecha($c['started_at']) : '—' ?><br>
                <strong>Completada:</strong> <?= $c['completed_at'] ? admin_fmt_fecha($c['completed_at']) : '—' ?>
            </div>
            <div>
                <strong>Mensaje:</strong>
                <div style="margin-top:var(--space-2);padding:var(--space-3);background:var(--color-surface-variant);border-radius:var(--radius-md);white-space:pre-wrap;"><?= sp_h($c['body']) ?></div>
            </div>
        </div>
    </section>

    <?php if ($canCancel): ?>
        <section class="card" style="border-left:4px solid var(--color-danger);">
            <div class="card__header">
                <div class="card__title">Zona de peligro</div>
            </div>
            <form method="post" action="index.php?section=communications" style="display:inline;">
                <?= admin_csrf_field() ?>
                <input type="hidden" name="id" value="<?= $id ?>">
                <input type="hidden" name="do" value="cancel">
                <button type="submit" class="btn btn--danger"
                        data-confirm="¿Cancelar la campaña #<?= $id ?>? Los destinatarios que ya se enviaron no se desharán, pero se detendrán los pendientes.">
                    Cancelar campaña
                </button>
            </form>
        </section>
    <?php endif; ?>

    <section class="card">
        <div class="card__header">
            <div class="card__title">Destinatarios (muestra de 50)</div>
            <?php if ($totalTargeted > 50): ?>
                <small style="color:var(--color-text-tertiary);">Mostrando primeros 50 de <?= admin_fmt_int($totalTargeted) ?></small>
            <?php endif; ?>
        </div>
        <?php if (empty($recipients)): ?>
            <div class="empty-state">
                <div class="empty-state__icon">📭</div>
                <div class="empty-state__message">
                    Sin destinatarios para mostrar. <?php if ($c['status']==='draft'): ?>Previsualiza la audiencia para calcular destinatarios.<?php endif; ?>
                </div>
            </div>
        <?php else: ?>
            <div style="overflow-x:auto;max-height:480px;overflow-y:auto;">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Nombre</th>
                            <th>Email</th>
                            <th>Plan</th>
                            <th>Departamento</th>
                            <th>Último login</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($recipients as $u): ?>
                            <tr>
                                <td>#<?= (int)$u['id_usuario'] ?></td>
                                <td><?= sp_h($u['nombre'] ?? '—') ?></td>
                                <td><?= sp_h($u['email'] ?? '—') ?></td>
                                <td><span class="badge badge--gray"><?= sp_h($u['access_level'] ?? 'free') ?></span></td>
                                <td><?= sp_h($u['departamento'] ?? '—') ?></td>
                                <td><?= admin_fmt_tiempo_relativo($u['ultimo_login'] ?? null) ?></td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        <?php endif; ?>
    </section>

    <?php
    render_footer();
}

// ══════════════════════════════════════════════════════════════════════
//  HELPERS DE VISTA
// ══════════════════════════════════════════════════════════════════════

function status_badge(string $status): string {
    $map = [
        'draft'     => ['gray',   'Borrador'],
        'previewed' => ['info',   'Previsualizada'],
        'sending'   => ['warning','Enviando'],
        'completed' => ['success','Completada'],
        'failed'    => ['danger', 'Fallida'],
        'cancelled' => ['gray',   'Cancelada'],
    ];
    // Fallback usa el propio status (raw) — el return lo escapa una sola vez.
    [$class, $label] = $map[$status] ?? ['gray', $status];
    return '<span class="badge badge--' . sp_h($class) . '">' . sp_h($label) . '</span>';
}
