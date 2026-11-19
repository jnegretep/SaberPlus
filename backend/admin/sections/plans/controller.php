<?php
declare(strict_types=1);

/**
 * SPRINT 4 — Sección Planes (Command Center)
 *
 * CRUD completo de planes Saber+:
 *  - Listado con conteo de usuarios por plan
 *  - Vista detalle (info + features + content_access_levels)
 *  - Editar / Crear (con auditoría before/after)
 *  - Toggle activo/inactivo
 *  - CRUD inline de plan_features dentro de la vista detalle
 *
 * Seguridad:
 *  - No se permite borrar planes (solo desactivar).
 *  - Prepared statements en TODA consulta con input externo.
 *  - CSRF verificado automáticamente por bootstrap.php (form POST).
 *  - RBAC: plans.read mínimo, plans.create/plans.update para escritura.
 *
 * Rutas (todas dentro de ?section=plans):
 *  - ?action=list            (default) — Listado
 *  - ?action=view&id=X       — Vista detalle
 *  - ?action=edit&id=X       — Formulario editar
 *  - ?action=create          — Formulario crear
 *  - POST action=save_plan   — Guardar (create/edit)
 *  - POST action=toggle_active — Toggle is_active
 *  - POST action=save_feature   — Crear/editar plan_feature
 *  - POST action=delete_feature — Borrar plan_feature
 */

require_once __DIR__ . '/../../bootstrap.php';
require_once __DIR__ . '/../../includes/layout.php';

// Permiso mínimo para todo el módulo (cualquier acceso requiere plans.read)
require_permission('plans.read');

// ── Resolver acción GET ──
$action = $_GET['action'] ?? 'list';
$action = preg_replace('/[^a-z_]/', '', $action);

// ── Dispatcher POST ──
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $postAction = $_POST['action'] ?? '';
    switch ($postAction) {
        case 'save_plan':       handle_save_plan();       break;
        case 'toggle_active':   handle_toggle_active();   break;
        case 'save_feature':    handle_save_feature();    break;
        case 'delete_feature':  handle_delete_feature();  break;
        default:
            admin_flash('error', 'Acción POST no reconocida.');
            header('Location: ' . admin_section_url('plans'));
            exit;
    }
    exit;
}

// ── Dispatcher GET ──
switch ($action) {
    case 'view':   render_plan_view();   break;
    case 'edit':   render_plan_form(true);  break;
    case 'create': render_plan_form(false); break;
    case 'list':
    default:       render_plans_list();   break;
}


// ════════════════════════════════════════════════════════════
//  POST HANDLERS
// ════════════════════════════════════════════════════════════

/**
 * Guardar plan (create o edit). Recibe los campos del formulario.
 */
function handle_save_plan(): void {
    global $conexion;

    $id     = (int)($_POST['id'] ?? 0);
    $isEdit = $id > 0;

    // Permiso específico
    if ($isEdit) {
        require_permission('plans.update');
    } else {
        require_permission('plans.create');
    }

    // Recoger y normalizar input
    $name          = trim((string)($_POST['name'] ?? ''));
    $code          = strtolower(trim((string)($_POST['code'] ?? '')));
    $description   = trim((string)($_POST['description'] ?? ''));
    $price         = max(0.0, (float)($_POST['price'] ?? 0));
    $currency      = strtoupper(trim((string)($_POST['currency'] ?? 'COP')) ?: 'COP');
    $isLifetime    = isset($_POST['is_lifetime']) ? 1 : 0;
    $isActive      = isset($_POST['is_active']) ? 1 : 0;
    $sortOrder     = max(0, (int)($_POST['sort_order'] ?? 0));
    $playProductId = trim((string)($_POST['play_product_id'] ?? ''));

    if ($name === '' || $code === '') {
        admin_flash('error', 'Nombre y código son obligatorios.');
        header('Location: ' . admin_section_url('plans',
            $isEdit ? ['action' => 'edit', 'id' => $id] : ['action' => 'create']));
        exit;
    }

    // Construir snapshot "after" para auditoría
    $after = [
        'name'            => $name,
        'code'            => $code,
        'description'     => $description,
        'price'           => $price,
        'currency'        => $currency,
        'is_lifetime'     => $isLifetime,
        'is_active'        => $isActive,
        'sort_order'      => $sortOrder,
        'play_product_id' => $playProductId,
    ];

    if ($isEdit) {
        // Cargar "before"
        $stmt = $conexion->prepare(
            "SELECT id, name, code, description, price, currency, is_lifetime, is_active,
                    sort_order, play_product_id
             FROM plans WHERE id = ? LIMIT 1");
        $stmt->execute([$id]);
        $plan = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$plan) {
            admin_flash('error', 'Plan no encontrado.');
            header('Location: ' . admin_section_url('plans'));
            exit;
        }

        $before = [
            'name'            => $plan['name'],
            'code'            => $plan['code'],
            'description'     => $plan['description'] ?? '',
            'price'           => (float)$plan['price'],
            'currency'        => $plan['currency'] ?? 'COP',
            'is_lifetime'     => (int)$plan['is_lifetime'],
            'is_active'        => (int)$plan['is_active'],
            'sort_order'      => (int)$plan['sort_order'],
            'play_product_id' => $plan['play_product_id'] ?? '',
        ];

        try {
            $upd = $conexion->prepare(
                "UPDATE plans SET
                    name = ?, code = ?, description = ?, price = ?, currency = ?,
                    is_lifetime = ?, is_active = ?, sort_order = ?, play_product_id = ?
                 WHERE id = ?"
            );
            $upd->execute([
                $name, $code, $description, $price, $currency,
                $isLifetime, $isActive, $sortOrder, $playProductId !== '' ? $playProductId : null,
                $id,
            ]);

            admin_audit_change($conexion, 'plans', 'plan.update', 'plans', $id, $before, $after);
            admin_flash('success', 'Plan actualizado correctamente.');
        } catch (Throwable $e) {
            error_log('[PLANS] update: ' . $e->getMessage());
            admin_flash('error', 'Error al actualizar el plan. ¿Código duplicado?');
        }
        header('Location: ' . admin_section_url('plans', ['action' => 'view', 'id' => $id]));
        exit;
    } else {
        // Create
        try {
            $stmt = $conexion->prepare(
                "INSERT INTO plans
                    (name, code, description, price, currency, is_lifetime, is_active, sort_order, play_product_id)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
            );
            $stmt->execute([
                $name, $code, $description, $price, $currency,
                $isLifetime, $isActive, $sortOrder, $playProductId !== '' ? $playProductId : null,
            ]);
            $newId = (int)$conexion->lastInsertId();

            admin_audit_change($conexion, 'plans', 'plan.create', 'plans', $newId, null, $after);
            admin_flash('success', 'Plan creado correctamente.');
            header('Location: ' . admin_section_url('plans', ['action' => 'view', 'id' => $newId]));
            exit;
        } catch (Throwable $e) {
            error_log('[PLANS] create: ' . $e->getMessage());
            admin_flash('error', 'Error al crear el plan. ¿Código duplicado?');
            header('Location: ' . admin_section_url('plans', ['action' => 'create']));
            exit;
        }
    }
}

/**
 * Toggle is_active de un plan (desde listado o vista).
 */
function handle_toggle_active(): void {
    global $conexion;
    require_permission('plans.update');

    $id = (int)($_POST['id'] ?? 0);
    if ($id <= 0) {
        admin_flash('error', 'ID de plan inválido.');
        header('Location: ' . admin_section_url('plans'));
        exit;
    }

    $stmt = $conexion->prepare("SELECT id, name, code, is_active FROM plans WHERE id = ? LIMIT 1");
    $stmt->execute([$id]);
    $plan = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$plan) {
        admin_flash('error', 'Plan no encontrado.');
        header('Location: ' . admin_section_url('plans'));
        exit;
    }

    $before = ['is_active' => (int)$plan['is_active']];
    $newVal = (int)$plan['is_active'] ? 0 : 1;
    $after  = ['is_active' => $newVal];

    try {
        $upd = $conexion->prepare("UPDATE plans SET is_active = ? WHERE id = ?");
        $upd->execute([$newVal, $id]);
        admin_audit_change($conexion, 'plans', 'plan.toggle_active', 'plans', $id, $before, $after);
        admin_flash('success', 'Plan "' . $plan['name'] . '" ' . ($newVal ? 'activado' : 'desactivado') . '.');
    } catch (Throwable $e) {
        error_log('[PLANS] toggle: ' . $e->getMessage());
        admin_flash('error', 'Error al cambiar el estado del plan.');
    }
    header('Location: ' . admin_section_url('plans'));
    exit;
}

/**
 * Guardar (crear o editar) una característica de plan.
 */
function handle_save_feature(): void {
    global $conexion;
    require_permission('plans.update');

    $featureId = (int)($_POST['feature_id'] ?? 0);
    $planId    = (int)($_POST['plan_id'] ?? 0);
    $text      = trim((string)($_POST['text'] ?? ''));
    $included  = isset($_POST['included']) ? 1 : 0;
    $sortOrder = max(0, (int)($_POST['sort_order'] ?? 0));

    if ($planId <= 0) {
        admin_flash('error', 'ID de plan inválido.');
        header('Location: ' . admin_section_url('plans'));
        exit;
    }
    if ($text === '') {
        admin_flash('error', 'El texto de la característica es obligatorio.');
        header('Location: ' . admin_section_url('plans', ['action' => 'view', 'id' => $planId]));
        exit;
    }

    $after = [
        'plan_id'    => $planId,
        'text'       => $text,
        'included'   => $included,
        'sort_order' => $sortOrder,
    ];

    if ($featureId > 0) {
        // Edit
        $stmt = $conexion->prepare(
            "SELECT id, plan_id, text, included, sort_order FROM plan_features WHERE id = ? LIMIT 1");
        $stmt->execute([$featureId]);
        $feat = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$feat) {
            admin_flash('error', 'Característica no encontrada.');
            header('Location: ' . admin_section_url('plans', ['action' => 'view', 'id' => $planId]));
            exit;
        }

        $before = [
            'plan_id'    => (int)$feat['plan_id'],
            'text'       => $feat['text'],
            'included'   => (int)$feat['included'],
            'sort_order' => (int)$feat['sort_order'],
        ];

        try {
            $upd = $conexion->prepare(
                "UPDATE plan_features SET text = ?, included = ?, sort_order = ? WHERE id = ?");
            $upd->execute([$text, $included, $sortOrder, $featureId]);
            admin_audit_change($conexion, 'plans', 'plan_feature.update', 'plan_features', $featureId, $before, $after);
            admin_flash('success', 'Característica actualizada.');
        } catch (Throwable $e) {
            error_log('[PLANS] feature update: ' . $e->getMessage());
            admin_flash('error', 'Error al actualizar la característica.');
        }
    } else {
        // Create
        try {
            $stmt = $conexion->prepare(
                "INSERT INTO plan_features (plan_id, text, included, sort_order) VALUES (?, ?, ?, ?)");
            $stmt->execute([$planId, $text, $included, $sortOrder]);
            $newId = (int)$conexion->lastInsertId();
            admin_audit_change($conexion, 'plans', 'plan_feature.create', 'plan_features', $newId, null, $after);
            admin_flash('success', 'Característica añadida.');
        } catch (Throwable $e) {
            error_log('[PLANS] feature create: ' . $e->getMessage());
            admin_flash('error', 'Error al crear la característica.');
        }
    }
    header('Location: ' . admin_section_url('plans', ['action' => 'view', 'id' => $planId]));
    exit;
}

/**
 * Borrar una característica de plan.
 */
function handle_delete_feature(): void {
    global $conexion;
    require_permission('plans.update');

    $featureId = (int)($_POST['feature_id'] ?? 0);
    $planId    = (int)($_POST['plan_id'] ?? 0);
    if ($featureId <= 0) {
        admin_flash('error', 'ID de característica inválido.');
        header('Location: ' . admin_section_url('plans', ['action' => 'view', 'id' => $planId]));
        exit;
    }

    $stmt = $conexion->prepare(
        "SELECT id, plan_id, text, included, sort_order FROM plan_features WHERE id = ? LIMIT 1");
    $stmt->execute([$featureId]);
    $feat = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$feat) {
        admin_flash('error', 'Característica no encontrada.');
        header('Location: ' . admin_section_url('plans', ['action' => 'view', 'id' => $planId]));
        exit;
    }

    $before = [
        'plan_id'    => (int)$feat['plan_id'],
        'text'       => $feat['text'],
        'included'   => (int)$feat['included'],
        'sort_order' => (int)$feat['sort_order'],
    ];

    try {
        $del = $conexion->prepare("DELETE FROM plan_features WHERE id = ?");
        $del->execute([$featureId]);
        admin_audit_change($conexion, 'plans', 'plan_feature.delete', 'plan_features', $featureId, $before, []);
        admin_flash('success', 'Característica eliminada.');
    } catch (Throwable $e) {
        error_log('[PLANS] feature delete: ' . $e->getMessage());
        admin_flash('error', 'Error al eliminar la característica.');
    }
    header('Location: ' . admin_section_url('plans', ['action' => 'view', 'id' => $planId]));
    exit;
}


// ════════════════════════════════════════════════════════════
//  VIEWS (GET)
// ════════════════════════════════════════════════════════════

/**
 * Listado de planes con conteo de usuarios.
 */
function render_plans_list(): void {
    global $conexion;

    // Planes + conteo de usuarios (JOIN lógico: access_level = plan.code,
    // con fallback para plan 'free' cubriendo access_level NULL/vacío).
    $plans = safeRows($conexion,
        "SELECT p.*,
                (SELECT COUNT(*)
                   FROM usuarios u
                  WHERE u.access_level = p.code
                     OR (p.code = 'free' AND (u.access_level IS NULL OR u.access_level = ''))
                ) AS user_count
           FROM plans p
          ORDER BY p.sort_order ASC, p.id ASC");

    $totalActive = 0;
    $totalUsers  = 0;
    foreach ($plans as $p) {
        if ((int)$p['is_active']) $totalActive++;
        $totalUsers += (int)$p['user_count'];
    }

    $canCreate = admin_has_permission('plans.create');
    $canEdit   = admin_has_permission('plans.update');

    render_header('Planes', ['section' => 'plans']);
    ?>

    <div class="section-header">
        <div>
            <div class="section-header__title">Planes y Precios</div>
            <div class="section-header__subtitle">Gestiona los planes de suscripción Saber+</div>
        </div>
        <div class="quick-stats">
            <div class="quick-stat">
                <div class="quick-stat__value"><?= count($plans) ?></div>
                <div class="quick-stat__label">Planes</div>
            </div>
            <div class="quick-stat">
                <div class="quick-stat__value"><?= $totalActive ?></div>
                <div class="quick-stat__label">Activos</div>
            </div>
            <div class="quick-stat">
                <div class="quick-stat__value"><?= admin_fmt_int($totalUsers) ?></div>
                <div class="quick-stat__label">Usuarios</div>
            </div>
        </div>
    </div>

    <section class="card">
        <div class="card__header">
            <div class="card__title">Listado de planes</div>
            <div class="card__actions">
                <?php if ($canCreate): ?>
                <a href="<?= admin_section_url('plans', ['action' => 'create']) ?>" class="btn btn--primary btn--sm">+ Nuevo plan</a>
                <?php endif; ?>
            </div>
        </div>

        <?php if (empty($plans)): ?>
            <div class="empty-state">
                <div class="empty-state__icon">💳</div>
                <div class="empty-state__title">No hay planes configurados</div>
                <div class="empty-state__message">Crea tu primer plan para empezar.</div>
            </div>
        <?php else: ?>
        <table class="data-table">
            <thead>
                <tr>
                    <th>Nombre</th>
                    <th>Código</th>
                    <th>Precio</th>
                    <th>Vitalicio</th>
                    <th>Estado</th>
                    <th>Usuarios</th>
                    <th>Acciones</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($plans as $p):
                    $userCount = (int)$p['user_count'];
                ?>
                <tr>
                    <td>
                        <strong><?= sp_h($p['name']) ?></strong>
                        <?php if (!empty($p['description'])): ?>
                            <div style="font-size:12px;color:#64748B;margin-top:2px;">
                                <?= sp_h(mb_substr((string)$p['description'], 0, 80)) ?>
                                <?= mb_strlen((string)$p['description']) > 80 ? '…' : '' ?>
                            </div>
                        <?php endif; ?>
                    </td>
                    <td><code><?= sp_h($p['code']) ?></code></td>
                    <td>
                        <strong><?= admin_fmt_cop((float)$p['price']) ?></strong>
                        <?php if (!empty($p['currency']) && $p['currency'] !== 'COP'): ?>
                            <div style="font-size:11px;color:#94A3B8;"><?= sp_h($p['currency']) ?></div>
                        <?php endif; ?>
                    </td>
                    <td>
                        <?php if ((int)$p['is_lifetime']): ?>
                            <span class="badge badge--purple">Vitalicio</span>
                        <?php else: ?>
                            <span class="badge badge--gray">Recurrente</span>
                        <?php endif; ?>
                    </td>
                    <td>
                        <?php if ((int)$p['is_active']): ?>
                            <span class="badge badge--success">Activo</span>
                        <?php else: ?>
                            <span class="badge badge--warning">Inactivo</span>
                        <?php endif; ?>
                    </td>
                    <td>
                        <a href="<?= admin_section_url('users', ['filter_plan' => $p['code']]) ?>"
                           style="font-weight:700;color:var(--color-primary);"
                           title="Ver usuarios con access_level=<?= sp_h($p['code']) ?>">
                            <?= admin_fmt_int($userCount) ?>
                        </a>
                    </td>
                    <td>
                        <div style="display:flex;gap:6px;flex-wrap:wrap;">
                            <a href="<?= admin_section_url('plans', ['action' => 'view', 'id' => $p['id']]) ?>"
                               class="btn btn--sm btn--outline">Ver</a>
                            <?php if ($canEdit): ?>
                            <a href="<?= admin_section_url('plans', ['action' => 'edit', 'id' => $p['id']]) ?>"
                               class="btn btn--sm btn--outline">Editar</a>
                            <form method="post" action="<?= admin_section_url('plans') ?>" style="display:inline;">
                                <?= admin_csrf_field() ?>
                                <input type="hidden" name="action" value="toggle_active">
                                <input type="hidden" name="id" value="<?= (int)$p['id'] ?>">
                                <button type="submit" class="btn btn--sm <?= (int)$p['is_active'] ? 'btn--danger' : 'btn--success' ?>"
                                        onclick="return confirm('¿<?= (int)$p['is_active'] ? 'Desactivar' : 'Activar' ?> el plan &quot;<?= sp_h($p['name']) ?>&quot;?');">
                                    <?= (int)$p['is_active'] ? 'Desactivar' : 'Activar' ?>
                                </button>
                            </form>
                            <?php endif; ?>
                        </div>
                    </td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
        <?php endif; ?>

        <div style="margin-top:var(--space-3);padding:var(--space-3);background:var(--color-surface-variant);border-radius:var(--radius-md);font-size:12px;color:#475569;">
            <strong>Política de borrado:</strong> Por seguridad, los planes no se pueden eliminar. Si necesitas retirar un plan del catálogo público, desactívalo (botón <em>Desactivar</em>). Los usuarios existentes conservan su acceso_level hasta que se cambie manualmente.
        </div>
    </section>

    <?php
    render_footer();
}

/**
 * Vista detalle de un plan: info completa + plan_features + content_access_levels.
 */
function render_plan_view(): void {
    global $conexion;

    $id = (int)($_GET['id'] ?? 0);
    if ($id <= 0) {
        admin_flash('error', 'ID de plan inválido.');
        header('Location: ' . admin_section_url('plans'));
        exit;
    }

    $stmt = $conexion->prepare("SELECT * FROM plans WHERE id = ? LIMIT 1");
    $stmt->execute([$id]);
    $plan = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$plan) {
        admin_flash('error', 'Plan no encontrado.');
        header('Location: ' . admin_section_url('plans'));
        exit;
    }

    // Conteo de usuarios para este plan
    $userCount = (int)safeScalar($conexion,
        "SELECT COUNT(*) FROM usuarios
          WHERE access_level = ?
             OR (? = 'free' AND (access_level IS NULL OR access_level = ''))",
        [$plan['code'], $plan['code']]);

    // Features
    $features = safeRows($conexion,
        "SELECT id, text, included, sort_order
           FROM plan_features
          WHERE plan_id = ?
          ORDER BY sort_order ASC, id ASC",
        [$id]);

    // Content access levels restringidos a este plan (por code)
    $accessLevels = safeRows($conexion,
        "SELECT id, content_type, content_id, min_plan, order_index, is_active
           FROM content_access_levels
          WHERE min_plan = ?
          ORDER BY content_type ASC, order_index ASC",
        [$plan['code']]);

    $canEdit = admin_has_permission('plans.update');

    render_header('Plan: ' . $plan['name'], ['section' => 'plans']);
    ?>

    <div class="section-header">
        <div>
            <div class="section-header__title">💳 <?= sp_h($plan['name']) ?></div>
            <div class="section-header__subtitle">
                Código <code><?= sp_h($plan['code']) ?></code> ·
                <?= admin_fmt_int($userCount) ?> usuarios con este plan
            </div>
        </div>
        <div class="quick-stats">
            <?php if ($canEdit): ?>
            <a href="<?= admin_section_url('plans', ['action' => 'edit', 'id' => $id]) ?>" class="btn btn--primary btn--sm">Editar plan</a>
            <?php endif; ?>
            <a href="<?= admin_section_url('plans') ?>" class="btn btn--outline btn--sm">← Volver</a>
        </div>
    </div>

    <!-- Info básica -->
    <section class="card">
        <div class="card__header">
            <div class="card__title">Información general</div>
        </div>
        <div class="grid-3" style="margin-bottom:var(--space-4);">
            <div>
                <div class="form-label">Precio</div>
                <div style="font-size:var(--fs-2xl);font-weight:800;color:var(--color-text);">
                    <?= admin_fmt_cop((float)$plan['price']) ?>
                </div>
                <div style="font-size:12px;color:#94A3B8;"><?= sp_h($plan['currency'] ?? 'COP') ?></div>
            </div>
            <div>
                <div class="form-label">Tipo</div>
                <div>
                    <?php if ((int)$plan['is_lifetime']): ?>
                        <span class="badge badge--purple">Vitalicio</span>
                    <?php else: ?>
                        <span class="badge badge--info">Suscripción</span>
                    <?php endif; ?>
                </div>
                <div style="font-size:12px;color:#94A3B8;margin-top:4px;">
                    <?= (int)$plan['is_lifetime'] ? 'Sin renovación' : 'Recurrente' ?>
                </div>
            </div>
            <div>
                <div class="form-label">Estado</div>
                <div>
                    <?php if ((int)$plan['is_active']): ?>
                        <span class="badge badge--success">Activo</span>
                    <?php else: ?>
                        <span class="badge badge--warning">Inactivo</span>
                    <?php endif; ?>
                </div>
                <div style="font-size:12px;color:#94A3B8;margin-top:4px;">
                    <?= (int)$plan['is_active'] ? 'Visible para usuarios' : 'Oculto al público' ?>
                </div>
            </div>
        </div>
        <div class="grid-3">
            <div>
                <div class="form-label">Orden de despliegue</div>
                <div>#<?= (int)$plan['sort_order'] ?></div>
            </div>
            <div>
                <div class="form-label">Play Product ID</div>
                <div><?= !empty($plan['play_product_id']) ? sp_h($plan['play_product_id']) : '<span style="color:#94A3B8;">—</span>' ?></div>
            </div>
            <div>
                <div class="form-label">ID interno</div>
                <div>#<?= (int)$plan['id'] ?></div>
            </div>
        </div>

        <?php if (!empty($plan['description'])): ?>
        <div style="margin-top:var(--space-4);padding-top:var(--space-4);border-top:1px solid var(--color-border);">
            <div class="form-label">Descripción</div>
            <p style="margin:0;color:#475569;line-height:1.5;"><?= nl2br(sp_h($plan['description'])) ?></p>
        </div>
        <?php endif; ?>

        <?php
        $caps = [];
        if (!empty($plan['capabilities'])) {
            $decoded = json_decode($plan['capabilities'], true);
            if (is_array($decoded)) $caps = $decoded;
        }
        if (!empty($caps)):
        ?>
        <div style="margin-top:var(--space-4);padding-top:var(--space-4);border-top:1px solid var(--color-border);">
            <div class="form-label">Capabilities (JSON)</div>
            <div style="display:flex;gap:6px;flex-wrap:wrap;">
                <?php foreach ($caps as $c): ?>
                    <span class="badge badge--info"><?= sp_h((string)$c) ?></span>
                <?php endforeach; ?>
            </div>
        </div>
        <?php endif; ?>
    </section>

    <!-- Características -->
    <section class="card">
        <div class="card__header">
            <div class="card__title">Características del plan (<?= count($features) ?>)</div>
            <?php if ($canEdit): ?>
            <button type="button" class="btn btn--primary btn--sm"
                    onclick="var f=document.getElementById('feat-form-add');f.style.display=(f.style.display==='none'?'block':'none');">
                + Añadir característica
            </button>
            <?php endif; ?>
        </div>

        <?php if (empty($features)): ?>
            <div class="empty-state">
                <div class="empty-state__icon">📋</div>
                <div class="empty-state__message">Sin características registradas para este plan.</div>
            </div>
        <?php else: ?>
        <table class="data-table">
            <thead>
                <tr>
                    <th>Texto</th>
                    <th>Incluida</th>
                    <th>Orden</th>
                    <?php if ($canEdit): ?><th style="text-align:right;">Acciones</th><?php endif; ?>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($features as $f): ?>
                <tr>
                    <td><?= sp_h($f['text']) ?></td>
                    <td>
                        <?php if ((int)$f['included']): ?>
                            <span class="badge badge--success">Sí</span>
                        <?php else: ?>
                            <span class="badge badge--gray">No</span>
                        <?php endif; ?>
                    </td>
                    <td>#<?= (int)$f['sort_order'] ?></td>
                    <?php if ($canEdit): ?>
                    <td>
                        <div style="display:flex;gap:6px;justify-content:flex-end;flex-wrap:wrap;">
                            <button type="button" class="btn btn--sm btn--outline"
                                    onclick="var r=document.getElementById('feat-row-<?= (int)$f['id'] ?>');r.style.display=(r.style.display==='none'?'table-row':'none');">
                                Editar
                            </button>
                            <form method="post" action="<?= admin_section_url('plans') ?>" style="display:inline;">
                                <?= admin_csrf_field() ?>
                                <input type="hidden" name="action" value="delete_feature">
                                <input type="hidden" name="feature_id" value="<?= (int)$f['id'] ?>">
                                <input type="hidden" name="plan_id" value="<?= (int)$id ?>">
                                <button type="submit" class="btn btn--sm btn--danger"
                                        onclick="return confirm('¿Eliminar la característica &quot;<?= sp_h($f['text']) ?>&quot;?');">
                                    Borrar
                                </button>
                            </form>
                        </div>
                    </td>
                    <?php endif; ?>
                </tr>
                <?php if ($canEdit): ?>
                <tr id="feat-row-<?= (int)$f['id'] ?>" style="display:none;background:var(--color-surface-variant);">
                    <td colspan="4">
                        <form method="post" action="<?= admin_section_url('plans') ?>" style="display:flex;gap:8px;flex-wrap:wrap;align-items:flex-end;">
                            <?= admin_csrf_field() ?>
                            <input type="hidden" name="action" value="save_feature">
                            <input type="hidden" name="feature_id" value="<?= (int)$f['id'] ?>">
                            <input type="hidden" name="plan_id" value="<?= (int)$id ?>">
                            <div class="form-group" style="flex:1;min-width:240px;margin:0;">
                                <label class="form-label">Texto</label>
                                <input type="text" name="text" class="form-input" value="<?= sp_h($f['text']) ?>" required>
                            </div>
                            <div class="form-group" style="margin:0;">
                                <label class="form-label">Orden</label>
                                <input type="number" name="sort_order" class="form-input" style="width:80px;" value="<?= (int)$f['sort_order'] ?>">
                            </div>
                            <div class="form-group" style="margin:0;">
                                <label class="form-label" style="display:block;">Incluida</label>
                                <label style="display:inline-flex;gap:6px;align-items:center;font-weight:600;">
                                    <input type="checkbox" name="included" <?= (int)$f['included'] ? 'checked' : '' ?>> Sí
                                </label>
                            </div>
                            <button type="submit" class="btn btn--primary btn--sm">Guardar</button>
                            <button type="button" class="btn btn--outline btn--sm"
                                    onclick="document.getElementById('feat-row-<?= (int)$f['id'] ?>').style.display='none';">Cancelar</button>
                        </form>
                    </td>
                </tr>
                <?php endif; ?>
                <?php endforeach; ?>
            </tbody>
        </table>
        <?php endif; ?>

        <?php if ($canEdit): ?>
        <div id="feat-form-add" style="display:none;margin-top:var(--space-4);padding:var(--space-4);background:var(--color-surface-variant);border-radius:var(--radius-md);">
            <h4 style="margin:0 0 var(--space-3) 0;font-size:var(--fs-md);">Nueva característica</h4>
            <form method="post" action="<?= admin_section_url('plans') ?>" style="display:flex;gap:8px;flex-wrap:wrap;align-items:flex-end;">
                <?= admin_csrf_field() ?>
                <input type="hidden" name="action" value="save_feature">
                <input type="hidden" name="plan_id" value="<?= (int)$id ?>">
                <div class="form-group" style="flex:1;min-width:240px;margin:0;">
                    <label class="form-label">Texto</label>
                    <input type="text" name="text" class="form-input" required placeholder="Ej: Simulacros ilimitados">
                </div>
                <div class="form-group" style="margin:0;">
                    <label class="form-label">Orden</label>
                    <input type="number" name="sort_order" class="form-input" style="width:80px;" value="0">
                </div>
                <div class="form-group" style="margin:0;">
                    <label class="form-label" style="display:block;">Incluida</label>
                    <label style="display:inline-flex;gap:6px;align-items:center;font-weight:600;">
                        <input type="checkbox" name="included" checked> Sí
                    </label>
                </div>
                <button type="submit" class="btn btn--primary btn--sm">Añadir</button>
                <button type="button" class="btn btn--outline btn--sm"
                        onclick="document.getElementById('feat-form-add').style.display='none';">Cancelar</button>
            </form>
        </div>
        <?php endif; ?>
    </section>

    <!-- Content access levels -->
    <section class="card">
        <div class="card__header">
            <div class="card__title">Contenido restringido a este plan (<?= count($accessLevels) ?>)</div>
            <div class="card__actions">
                <a href="<?= admin_section_url('content') ?>" class="btn btn--outline btn--sm">Gestionar contenido →</a>
            </div>
        </div>

        <?php if (empty($accessLevels)): ?>
            <div class="empty-state">
                <div class="empty-state__icon">🔓</div>
                <div class="empty-state__message">No hay contenido cuyo plan mínimo sea "<?= sp_h($plan['code']) ?>".</div>
            </div>
        <?php else: ?>
        <table class="data-table table-compact">
            <thead>
                <tr>
                    <th>Tipo</th>
                    <th>Content ID</th>
                    <th>Plan mínimo</th>
                    <th>Orden</th>
                    <th>Estado</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($accessLevels as $a): ?>
                <tr>
                    <td><span class="badge badge--info"><?= sp_h($a['content_type']) ?></span></td>
                    <td><?= $a['content_id'] !== null ? sp_h((string)$a['content_id']) : '<span style="color:#94A3B8;">—</span>' ?></td>
                    <td><code><?= sp_h($a['min_plan']) ?></code></td>
                    <td>#<?= (int)$a['order_index'] ?></td>
                    <td>
                        <?php if ((int)$a['is_active']): ?>
                            <span class="badge badge--success">Activo</span>
                        <?php else: ?>
                            <span class="badge badge--gray">Inactivo</span>
                        <?php endif; ?>
                    </td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
        <?php endif; ?>
    </section>

    <?php
    render_footer();
}

/**
 * Formulario de crear/editar plan.
 */
function render_plan_form(bool $isEdit): void {
    global $conexion;

    $plan = null;
    if ($isEdit) {
        require_permission('plans.update');
        $id = (int)($_GET['id'] ?? 0);
        if ($id <= 0) {
            admin_flash('error', 'ID inválido.');
            header('Location: ' . admin_section_url('plans'));
            exit;
        }
        $stmt = $conexion->prepare("SELECT * FROM plans WHERE id = ? LIMIT 1");
        $stmt->execute([$id]);
        $plan = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$plan) {
            admin_flash('error', 'Plan no encontrado.');
            header('Location: ' . admin_section_url('plans'));
            exit;
        }
    } else {
        require_permission('plans.create');
    }

    $v = function($key, $default = '') use ($plan) {
        return $plan[$key] ?? $default;
    };

    $title = $isEdit ? 'Editar plan' : 'Crear nuevo plan';
    render_header($title, ['section' => 'plans']);
    ?>

    <div class="section-header">
        <div>
            <div class="section-header__title"><?= $title ?></div>
            <div class="section-header__subtitle">
                <?php if ($isEdit): ?>
                    Modifica los datos del plan <code><?= sp_h($v('code')) ?></code>
                <?php else: ?>
                    Define un nuevo plan de suscripción Saber+
                <?php endif; ?>
            </div>
        </div>
        <a href="<?= admin_section_url('plans', $isEdit ? ['action' => 'view', 'id' => $v('id')] : []) ?>" class="btn btn--outline btn--sm">← Volver</a>
    </div>

    <form method="post" action="<?= admin_section_url('plans') ?>">
        <?= admin_csrf_field() ?>
        <input type="hidden" name="action" value="save_plan">
        <input type="hidden" name="id" value="<?= $isEdit ? (int)$v('id') : 0 ?>">

        <section class="card">
            <div class="card__header">
                <div class="card__title">Datos del plan</div>
            </div>

            <div class="grid-2">
                <div class="form-group">
                    <label class="form-label" for="f-name">Nombre *</label>
                    <input id="f-name" type="text" name="name" class="form-input" required
                           value="<?= sp_h($v('name')) ?>" placeholder="Ej: Premium">
                </div>
                <div class="form-group">
                    <label class="form-label" for="f-code">Código * <small style="font-weight:400;color:#94A3B8;">(lowercase, sin espacios)</small></label>
                    <input id="f-code" type="text" name="code" class="form-input" required pattern="[a-z0-9_]+"
                           value="<?= sp_h($v('code')) ?>" placeholder="premium">
                </div>
            </div>

            <div class="form-group">
                <label class="form-label" for="f-desc">Descripción</label>
                <textarea id="f-desc" name="description" class="form-textarea" placeholder="Descripción visible para los usuarios..."><?= sp_h($v('description')) ?></textarea>
            </div>

            <div class="grid-3">
                <div class="form-group">
                    <label class="form-label" for="f-price">Precio (COP) *</label>
                    <input id="f-price" type="number" name="price" class="form-input" step="1" min="0" required
                           value="<?= (int)$v('price', 0) ?>">
                </div>
                <div class="form-group">
                    <label class="form-label" for="f-cur">Moneda</label>
                    <select id="f-cur" name="currency" class="form-select">
                        <?php foreach (['COP', 'USD', 'EUR'] as $cur): ?>
                            <option value="<?= $cur ?>" <?= $v('currency', 'COP') === $cur ? 'selected' : '' ?>><?= $cur ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <div class="form-group">
                    <label class="form-label" for="f-sort">Orden de despliegue</label>
                    <input id="f-sort" type="number" name="sort_order" class="form-input" min="0"
                           value="<?= (int)$v('sort_order', 0) ?>">
                </div>
            </div>

            <div class="grid-2">
                <div class="form-group">
                    <label class="form-label" for="f-play">Play Product ID</label>
                    <input id="f-play" type="text" name="play_product_id" class="form-input"
                           value="<?= sp_h($v('play_product_id')) ?>" placeholder="Ej: premium_monthly_001">
                </div>
                <div class="form-group">
                    <label class="form-label">Opciones</label>
                    <div style="display:flex;flex-direction:column;gap:10px;padding-top:6px;">
                        <label style="display:inline-flex;align-items:center;gap:8px;font-weight:600;cursor:pointer;">
                            <input type="checkbox" name="is_lifetime" <?= (int)$v('is_lifetime') ? 'checked' : '' ?>>
                            Plan vitalicio (sin renovación)
                        </label>
                        <label style="display:inline-flex;align-items:center;gap:8px;font-weight:600;cursor:pointer;">
                            <input type="checkbox" name="is_active" <?= $isEdit ? ((int)$v('is_active') ? 'checked' : '') : 'checked' ?>>
                            Plan activo (visible para usuarios)
                        </label>
                    </div>
                </div>
            </div>
        </section>

        <div style="display:flex;gap:var(--space-2);justify-content:flex-end;margin-top:var(--space-4);">
            <a href="<?= admin_section_url('plans', $isEdit ? ['action' => 'view', 'id' => $v('id')] : []) ?>" class="btn btn--outline">Cancelar</a>
            <button type="submit" class="btn btn--primary"><?= $isEdit ? 'Guardar cambios' : 'Crear plan' ?></button>
        </div>
    </form>

    <?php
    render_footer();
}
