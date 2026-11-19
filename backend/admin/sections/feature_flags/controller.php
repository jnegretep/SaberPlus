<?php
declare(strict_types=1);

/**
 * SPRINT 4 — Sección Feature Flags (Command Center)
 *
 * Sistema de feature flags para activar/desactivar funcionalidades
 * en producción sin redeploy. Cada flag soporta:
 *
 *   - Global on/off            → is_globally_active
 *   - Scope por plan           → plan_scope (null = todos, 'free', 'premium')
 *   - Rollout percentage 0-100 → rollout_percentage (hash determinístico por usuario)
 *   - Config JSON              → config (payload libre para la feature)
 *   - Auditoría + updated_by   → admin_users.id (FK)
 *
 * Seguridad:
 *  - Permiso requerido para TODO el módulo: feature_flags.manage
 *  - CSRF verificado automáticamente por bootstrap.php
 *  - Prepared statements en TODA consulta
 *  - Toda acción sensible se audita con admin_audit_change()
 *
 * Rutas (todas dentro de ?section=feature_flags):
 *   - ?action=list              (default) — Listado
 *   - ?action=create                     — Formulario crear
 *   - ?action=edit&id=X                  — Formulario editar
 *   - ?action=test                       — Form para elegir usuario a testear
 *   - ?action=test&user_id=X             — Resultado de evaluación de flags
 *   - POST action=save_flag              — Crear/editar flag
 *   - POST action=toggle_flag            — Toggle is_globally_active
 */

require_once __DIR__ . '/../../bootstrap.php';
require_once __DIR__ . '/../../includes/layout.php';

// Permiso mínimo para TODO el módulo de feature flags
require_permission('feature_flags.manage');

// Resolver acción GET
$action = $_GET['action'] ?? 'list';
$action = preg_replace('/[^a-z_]/', '', $action);

// ── Dispatcher POST ──
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $postAction = $_POST['action'] ?? '';
    switch ($postAction) {
        case 'save_flag':   handle_save_flag();   break;
        case 'toggle_flag': handle_toggle_flag(); break;
        default:
            admin_flash('error', 'Acción POST no reconocida.');
            header('Location: ' . admin_section_url('feature_flags'));
            exit;
    }
    exit;
}

// ── Dispatcher GET ──
switch ($action) {
    case 'edit':   render_flag_form(true);  break;
    case 'create': render_flag_form(false); break;
    case 'test':   render_flag_test();       break;
    case 'list':
    default:       render_flags_list();      break;
}


// ════════════════════════════════════════════════════════════
//  POST HANDLERS
// ════════════════════════════════════════════════════════════

/**
 * Guardar flag (crear o editar).
 */
function handle_save_flag(): void {
    global $conexion;

    $id     = (int)($_POST['id'] ?? 0);
    $isEdit = $id > 0;

    $code             = trim((string)($_POST['code'] ?? ''));
    $description      = trim((string)($_POST['description'] ?? ''));
    $isGloballyActive = isset($_POST['is_globally_active']) ? 1 : 0;

    // plan_scope: vacío o 'all' → null
    $planScope = trim((string)($_POST['plan_scope'] ?? ''));
    if ($planScope === '' || strtolower($planScope) === 'all') {
        $planScope = null;
    } else {
        $planScope = strtolower($planScope);
    }

    // rollout: 0-100
    $rollout = (int)($_POST['rollout_percentage'] ?? 100);
    $rollout = max(0, min(100, $rollout));

    if (!$isEdit && $code === '') {
        admin_flash('error', 'El código del flag es obligatorio.');
        header('Location: ' . admin_section_url('feature_flags', ['action' => 'create']));
        exit;
    }
    if ($isEdit && $code === '') {
        // En edit no se cambia el code, pero si viene vacío usamos el existente
        $code = '';
    }

    $adminId = current_admin_id();
    $after  = [
        'code'                => $code,
        'description'         => $description,
        'is_globally_active'  => $isGloballyActive,
        'plan_scope'          => $planScope ?? '',
        'rollout_percentage'  => $rollout,
    ];

    if ($isEdit) {
        $stmt = $conexion->prepare(
            "SELECT id, code, description, is_globally_active, plan_scope, rollout_percentage
               FROM feature_flags
              WHERE id = ? LIMIT 1");
        $stmt->execute([$id]);
        $flag = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$flag) {
            admin_flash('error', 'Flag no encontrado.');
            header('Location: ' . admin_section_url('feature_flags'));
            exit;
        }

        $before = [
            'code'                => $flag['code'],
            'description'         => $flag['description'] ?? '',
            'is_globally_active'  => (int)$flag['is_globally_active'],
            'plan_scope'          => $flag['plan_scope'] ?? '',
            'rollout_percentage'  => (int)$flag['rollout_percentage'],
        ];

        // El code no se edita por integridad (se usa en código backend)
        try {
            $upd = $conexion->prepare(
                "UPDATE feature_flags
                    SET description = ?,
                        is_globally_active = ?,
                        plan_scope = ?,
                        rollout_percentage = ?,
                        updated_by = ?,
                        updated_at = NOW()
                  WHERE id = ?");
            $upd->execute([
                $description,
                $isGloballyActive,
                $planScope,
                $rollout,
                $adminId,
                $id,
            ]);

            // Para auditoría, usar code del before (no cambió)
            $after['code'] = $flag['code'];

            admin_audit_change($conexion, 'feature_flags', 'flag.update', 'feature_flags', $id, $before, $after);
            admin_flash('success', 'Flag actualizado correctamente.');
        } catch (Throwable $e) {
            error_log('[FF] update: ' . $e->getMessage());
            admin_flash('error', 'Error al actualizar el flag.');
        }
        header('Location: ' . admin_section_url('feature_flags'));
        exit;
    } else {
        // Create
        try {
            $stmt = $conexion->prepare(
                "INSERT INTO feature_flags
                    (code, description, is_globally_active, plan_scope, rollout_percentage, updated_by)
                 VALUES (?, ?, ?, ?, ?, ?)");
            $stmt->execute([
                $code, $description, $isGloballyActive, $planScope, $rollout, $adminId,
            ]);
            $newId = (int)$conexion->lastInsertId();
            admin_audit_change($conexion, 'feature_flags', 'flag.create', 'feature_flags', $newId, null, $after);
            admin_flash('success', "Flag '{$code}' creado.");
            header('Location: ' . admin_section_url('feature_flags'));
            exit;
        } catch (Throwable $e) {
            error_log('[FF] create: ' . $e->getMessage());
            admin_flash('error', 'Error al crear el flag. ¿Código duplicado?');
            header('Location: ' . admin_section_url('feature_flags', ['action' => 'create']));
            exit;
        }
    }
}

/**
 * Toggle is_globally_active de un flag.
 */
function handle_toggle_flag(): void {
    global $conexion;

    $id = (int)($_POST['id'] ?? 0);
    if ($id <= 0) {
        admin_flash('error', 'ID de flag inválido.');
        header('Location: ' . admin_section_url('feature_flags'));
        exit;
    }

    $stmt = $conexion->prepare(
        "SELECT id, code, is_globally_active FROM feature_flags WHERE id = ? LIMIT 1");
    $stmt->execute([$id]);
    $flag = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$flag) {
        admin_flash('error', 'Flag no encontrado.');
        header('Location: ' . admin_section_url('feature_flags'));
        exit;
    }

    $before = ['is_globally_active' => (int)$flag['is_globally_active']];
    $newVal = (int)$flag['is_globally_active'] ? 0 : 1;
    $after  = ['is_globally_active' => $newVal];

    try {
        $upd = $conexion->prepare(
            "UPDATE feature_flags
                SET is_globally_active = ?, updated_by = ?, updated_at = NOW()
              WHERE id = ?");
        $upd->execute([$newVal, current_admin_id(), $id]);
        admin_audit_change($conexion, 'feature_flags', 'flag.toggle', 'feature_flags', $id, $before, $after);
        admin_flash('success', 'Flag "' . $flag['code'] . '" ' . ($newVal ? 'activado' : 'desactivado') . ' globalmente.');
    } catch (Throwable $e) {
        error_log('[FF] toggle: ' . $e->getMessage());
        admin_flash('error', 'Error al cambiar el flag.');
    }
    header('Location: ' . admin_section_url('feature_flags'));
    exit;
}


// ════════════════════════════════════════════════════════════
//  VIEWS (GET)
// ════════════════════════════════════════════════════════════

/**
 * Listado de feature flags.
 */
function render_flags_list(): void {
    global $conexion;

    $flags = safeRows($conexion,
        "SELECT f.id, f.code, f.description, f.is_globally_active, f.plan_scope,
                f.rollout_percentage, f.config, f.updated_at, u.name AS updated_by_name
           FROM feature_flags f
           LEFT JOIN admin_users u ON u.id = f.updated_by
          ORDER BY f.is_globally_active DESC, f.code ASC");

    $totalActive = 0;
    foreach ($flags as $f) if ((int)$f['is_globally_active']) $totalActive++;

    render_header('Feature Flags', ['section' => 'feature_flags']);
    ?>

    <div class="section-header">
        <div>
            <div class="section-header__title">Feature Flags</div>
            <div class="section-header__subtitle">Activa/desactiva funcionalidades en producción sin redeploy</div>
        </div>
        <div class="quick-stats">
            <div class="quick-stat">
                <div class="quick-stat__value"><?= count($flags) ?></div>
                <div class="quick-stat__label">Total</div>
            </div>
            <div class="quick-stat">
                <div class="quick-stat__value"><?= $totalActive ?></div>
                <div class="quick-stat__label">Activos</div>
            </div>
            <a href="<?= admin_section_url('feature_flags', ['action' => 'test']) ?>" class="btn btn--outline btn--sm">🧪 Test por usuario</a>
            <a href="<?= admin_section_url('feature_flags', ['action' => 'create']) ?>" class="btn btn--primary btn--sm">+ Nuevo flag</a>
        </div>
    </div>

    <section class="card">
        <div class="card__header">
            <div class="card__title">Listado de flags</div>
        </div>

        <?php if (empty($flags)): ?>
            <div class="empty-state">
                <div class="empty-state__icon">🚩</div>
                <div class="empty-state__title">No hay feature flags configurados</div>
                <div class="empty-state__message">Crea tu primer flag para empezar a controlar funcionalidades en runtime.</div>
            </div>
        <?php else: ?>
        <table class="data-table">
            <thead>
                <tr>
                    <th>Estado</th>
                    <th>Código</th>
                    <th>Descripción</th>
                    <th>Plan scope</th>
                    <th>Rollout</th>
                    <th>Última actualización</th>
                    <th>Acciones</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($flags as $f):
                    $scope = $f['plan_scope'] ?? null;
                    $scopeLabel = $scope ? ucfirst($scope) : 'Todos';
                    $scopeClass = $scope ? 'badge--info' : 'badge--gray';
                    $rollout    = (int)$f['rollout_percentage'];
                    $hasConfig  = !empty($f['config']) && $f['config'] !== 'null';
                ?>
                <tr>
                    <td style="font-size:18px;text-align:center;" title="<?= (int)$f['is_globally_active'] ? 'Activo' : 'Inactivo' ?>">
                        <?= (int)$f['is_globally_active'] ? '🟢' : '🔴' ?>
                    </td>
                    <td><code><?= sp_h($f['code']) ?></code></td>
                    <td>
                        <?= sp_h($f['description'] ?? '') ?>
                        <?php if ($hasConfig): ?>
                            <span class="badge badge--gray" style="margin-left:4px;" title="<?= sp_h((string)$f['config']) ?>">config</span>
                        <?php endif; ?>
                    </td>
                    <td><span class="badge <?= $scopeClass ?>"><?= sp_h($scopeLabel) ?></span></td>
                    <td>
                        <div style="display:flex;align-items:center;gap:8px;">
                            <div style="width:60px;height:6px;background:#E5E7EB;border-radius:3px;overflow:hidden;">
                                <div style="width:<?= $rollout ?>%;height:100%;background:var(--color-primary);"></div>
                            </div>
                            <span style="font-weight:700;font-size:12px;"><?= $rollout ?>%</span>
                        </div>
                    </td>
                    <td>
                        <div style="font-size:12px;color:#475569;"><?= admin_fmt_tiempo_relativo($f['updated_at']) ?></div>
                        <?php if (!empty($f['updated_by_name'])): ?>
                            <div style="font-size:11px;color:#94A3B8;">por <?= sp_h($f['updated_by_name']) ?></div>
                        <?php endif; ?>
                    </td>
                    <td>
                        <div style="display:flex;gap:6px;flex-wrap:wrap;">
                            <a href="<?= admin_section_url('feature_flags', ['action' => 'edit', 'id' => $f['id']]) ?>"
                               class="btn btn--sm btn--outline">Editar</a>
                            <form method="post" action="<?= admin_section_url('feature_flags') ?>" style="display:inline;">
                                <?= admin_csrf_field() ?>
                                <input type="hidden" name="action" value="toggle_flag">
                                <input type="hidden" name="id" value="<?= (int)$f['id'] ?>">
                                <button type="submit" class="btn btn--sm <?= (int)$f['is_globally_active'] ? 'btn--danger' : 'btn--success' ?>"
                                        onclick="return confirm('¿<?= (int)$f['is_globally_active'] ? 'Desactivar' : 'Activar' ?> el flag &quot;<?= sp_h($f['code']) ?>&quot; globalmente?');">
                                    <?= (int)$f['is_globally_active'] ? 'Desactivar' : 'Activar' ?>
                                </button>
                            </form>
                        </div>
                    </td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
        <?php endif; ?>

        <div style="margin-top:var(--space-3);padding:var(--space-3);background:var(--color-surface-variant);border-radius:var(--radius-md);font-size:12px;color:#475569;line-height:1.5;">
            <strong>Cómo se evalúa un flag para un usuario:</strong>
            <ol style="margin:6px 0 0 18px;padding:0;">
                <li>Si <code>is_globally_active = 0</code> → <strong>OFF</strong> para todos.</li>
                <li>Si <code>plan_scope</code> está definido y no coincide con el plan del usuario → <strong>OFF</strong>.</li>
                <li>Si <code>rollout_percentage &lt; 100</code> → hash determinístico (crc32 de <code>code:user_id</code>) mod 100; si bucket &lt; rollout → <strong>ON</strong>.</li>
                <li>Si todo pasa → <strong>ON</strong>.</li>
            </ol>
            Usa la vista <a href="<?= admin_section_url('feature_flags', ['action' => 'test']) ?>"><strong>Test por usuario</strong></a> para simular.
        </div>
    </section>

    <?php
    render_footer();
}

/**
 * Formulario crear/editar flag.
 */
function render_flag_form(bool $isEdit): void {
    global $conexion;

    $flag = null;
    if ($isEdit) {
        $id = (int)($_GET['id'] ?? 0);
        if ($id <= 0) {
            admin_flash('error', 'ID inválido.');
            header('Location: ' . admin_section_url('feature_flags'));
            exit;
        }
        $stmt = $conexion->prepare(
            "SELECT id, code, description, is_globally_active, plan_scope, rollout_percentage, config
               FROM feature_flags WHERE id = ? LIMIT 1");
        $stmt->execute([$id]);
        $flag = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$flag) {
            admin_flash('error', 'Flag no encontrado.');
            header('Location: ' . admin_section_url('feature_flags'));
            exit;
        }
    }

    $v = function($key, $default = '') use ($flag) {
        return $flag[$key] ?? $default;
    };

    $title = $isEdit ? 'Editar flag' : 'Crear nuevo flag';
    render_header($title, ['section' => 'feature_flags']);
    ?>

    <div class="section-header">
        <div>
            <div class="section-header__title"><?= $title ?></div>
            <div class="section-header__subtitle">
                <?php if ($isEdit): ?>
                    Modifica el flag <code><?= sp_h($v('code')) ?></code>
                <?php else: ?>
                    Define un nuevo feature flag
                <?php endif; ?>
            </div>
        </div>
        <a href="<?= admin_section_url('feature_flags') ?>" class="btn btn--outline btn--sm">← Volver</a>
    </div>

    <form method="post" action="<?= admin_section_url('feature_flags') ?>">
        <?= admin_csrf_field() ?>
        <input type="hidden" name="action" value="save_flag">
        <input type="hidden" name="id" value="<?= $isEdit ? (int)$v('id') : 0 ?>">

        <section class="card">
            <div class="card__header">
                <div class="card__title">Configuración del flag</div>
            </div>

            <?php if (!$isEdit): ?>
            <div class="form-group">
                <label class="form-label" for="f-code">Código * <small style="font-weight:400;color:#94A3B8;">(lowercase, sin espacios)</small></label>
                <input id="f-code" type="text" name="code" class="form-input" required pattern="[a-z0-9_]+"
                       placeholder="ej: ai_tutor_enabled">
                <small style="color:#94A3B8;font-size:12px;">
                    Identificador único del flag. Se usará en el código backend (<code>is_flag_active($code)</code>).
                </small>
            </div>
            <?php else: ?>
            <div class="form-group">
                <label class="form-label">Código</label>
                <div style="padding:var(--space-3) var(--space-4);background:var(--color-surface-variant);border-radius:var(--radius-md);font-family:monospace;font-weight:700;">
                    <?= sp_h($v('code')) ?>
                    <span style="font-weight:400;color:#94A3B8;margin-left:8px;">(no editable)</span>
                </div>
            </div>
            <?php endif; ?>

            <div class="form-group">
                <label class="form-label" for="f-desc">Descripción</label>
                <textarea id="f-desc" name="description" class="form-textarea" placeholder="¿Qué funcionalidad controla este flag? ¿Cuándo debería estar activo?"><?= sp_h($v('description')) ?></textarea>
            </div>

            <div class="form-group">
                <label style="display:inline-flex;align-items:center;gap:8px;font-weight:600;cursor:pointer;">
                    <input type="checkbox" name="is_globally_active"
                           <?= $isEdit ? ((int)$v('is_globally_active') ? 'checked' : '') : 'checked' ?>>
                    Activo globalmente
                </label>
                <small style="display:block;color:#94A3B8;font-size:12px;margin-top:4px;">
                    Si está apagado, el flag está desactivado para todos sin importar el scope o rollout. Es el "kill switch".
                </small>
            </div>

            <?php if ($isEdit): ?>
            <div class="grid-2">
                <div class="form-group">
                    <label class="form-label" for="f-scope">Plan scope</label>
                    <select id="f-scope" name="plan_scope" class="form-select">
                        <?php
                        $scopes = [
                            'all'     => 'Todos los planes',
                            'free'    => 'Solo Free',
                            'premium' => 'Solo Premium',
                        ];
                        $current = $v('plan_scope') ?? 'all';
                        if ($current === '' || $current === null) $current = 'all';
                        foreach ($scopes as $k => $label):
                        ?>
                            <option value="<?= $k ?>" <?= $current === $k ? 'selected' : '' ?>><?= $label ?></option>
                        <?php endforeach; ?>
                    </select>
                    <small style="color:#94A3B8;font-size:12px;display:block;margin-top:4px;">
                        Restringe el flag a usuarios con un plan concreto.
                    </small>
                </div>
                <div class="form-group">
                    <label class="form-label">
                        Rollout: <span id="rollout-val" style="font-weight:800;color:var(--color-primary);"><?= (int)$v('rollout_percentage', 100) ?>%</span>
                    </label>
                    <input type="range" name="rollout_percentage" min="0" max="100" step="1"
                           value="<?= (int)$v('rollout_percentage', 100) ?>"
                           oninput="document.getElementById('rollout-val').textContent=this.value+'%';"
                           style="width:100%;accent-color:var(--color-primary);">
                    <small style="color:#94A3B8;font-size:12px;display:block;margin-top:4px;">
                        100% = todos los usuarios del scope. 50% = la mitad (hash determinístico por user_id, mismo usuario siempre ve el mismo resultado).
                    </small>
                </div>
            </div>
            <?php else: ?>
            <input type="hidden" name="plan_scope" value="all">
            <input type="hidden" name="rollout_percentage" value="100">
            <?php endif; ?>
        </section>

        <div style="display:flex;gap:var(--space-2);justify-content:flex-end;margin-top:var(--space-4);">
            <a href="<?= admin_section_url('feature_flags') ?>" class="btn btn--outline">Cancelar</a>
            <button type="submit" class="btn btn--primary"><?= $isEdit ? 'Guardar cambios' : 'Crear flag' ?></button>
        </div>
    </form>

    <?php
    render_footer();
}

/**
 * Vista de testeo: simula qué flags ve un usuario específico.
 */
function render_flag_test(): void {
    global $conexion;

    $userId = (int)($_GET['user_id'] ?? 0);
    $user = null;
    $evaluations = [];

    if ($userId > 0) {
        $stmt = $conexion->prepare(
            "SELECT id_usuario, nombre, email, access_level
               FROM usuarios WHERE id_usuario = ? LIMIT 1");
        $stmt->execute([$userId]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$user) {
            admin_flash('error', 'Usuario no encontrado.');
            header('Location: ' . admin_section_url('feature_flags', ['action' => 'test']));
            exit;
        }

        $flags = safeRows($conexion,
            "SELECT id, code, description, is_globally_active, plan_scope, rollout_percentage, config
               FROM feature_flags ORDER BY code ASC");

        foreach ($flags as $f) {
            $evaluations[] = evaluate_flag_for_user($f, $user);
        }
    }

    // Sugerencia de usuarios recientes
    $recentUsers = safeRows($conexion,
        "SELECT id_usuario, nombre, email, access_level
           FROM usuarios
          ORDER BY id_usuario DESC
          LIMIT 10");

    render_header('Test de Feature Flags', ['section' => 'feature_flags']);
    ?>

    <div class="section-header">
        <div>
            <div class="section-header__title">🧪 Test de feature flags por usuario</div>
            <div class="section-header__subtitle">Simula qué flags vería un usuario concreto sin afectar producción</div>
        </div>
        <a href="<?= admin_section_url('feature_flags') ?>" class="btn btn--outline btn--sm">← Volver al listado</a>
    </div>

    <section class="card">
        <div class="card__header">
            <div class="card__title">Seleccionar usuario</div>
        </div>
        <form method="get" action="index.php" style="display:flex;gap:8px;align-items:flex-end;flex-wrap:wrap;">
            <input type="hidden" name="section" value="feature_flags">
            <input type="hidden" name="action" value="test">
            <div class="form-group" style="margin:0;flex:1;min-width:240px;">
                <label class="form-label" for="f-uid">ID de usuario</label>
                <input id="f-uid" type="number" name="user_id" class="form-input" min="1" value="<?= $userId ?: '' ?>" required>
            </div>
            <button type="submit" class="btn btn--primary">Evaluar flags</button>
        </form>

        <?php if (!empty($recentUsers)): ?>
        <div style="margin-top:var(--space-4);padding-top:var(--space-3);border-top:1px solid var(--color-border);">
            <div class="form-label">Usuarios recientes</div>
            <div style="display:flex;gap:6px;flex-wrap:wrap;">
                <?php foreach ($recentUsers as $u): ?>
                <a href="<?= admin_section_url('feature_flags', ['action' => 'test', 'user_id' => $u['id_usuario']]) ?>"
                   class="btn btn--sm btn--outline" title="<?= sp_h($u['email'] ?? '') ?>">
                    #<?= (int)$u['id_usuario'] ?>
                    <?= sp_h(mb_substr((string)($u['nombre'] ?? $u['email'] ?? ''), 0, 24)) ?>
                </a>
                <?php endforeach; ?>
            </div>
        </div>
        <?php endif; ?>
    </section>

    <?php if ($user):
        $userPlan = $user['access_level'] ?: 'free';
    ?>
    <section class="card">
        <div class="card__header">
            <div class="card__title">Resultado: <?= sp_h($user['nombre'] ?? $user['email'] ?? ('#' . $userId)) ?></div>
            <div class="card__actions" style="gap:6px;">
                <span class="badge badge--info">Plan: <?= sp_h($userPlan) ?></span>
                <span class="badge badge--gray">ID: #<?= (int)$user['id_usuario'] ?></span>
            </div>
        </div>

        <?php if (empty($evaluations)): ?>
            <div class="empty-state">
                <div class="empty-state__icon">🚩</div>
                <div class="empty-state__message">No hay flags configurados para evaluar.</div>
            </div>
        <?php else: ?>
        <table class="data-table">
            <thead>
                <tr>
                    <th>Flag</th>
                    <th>Descripción</th>
                    <th>Global</th>
                    <th>Scope</th>
                    <th>Rollout</th>
                    <th>Activa para este usuario</th>
                </tr>
            </thead>
            <tbody>
                <?php
                $activeCount = 0;
                foreach ($evaluations as $ev):
                    if ($ev['active']) $activeCount++;
                ?>
                <tr>
                    <td><code><?= sp_h($ev['code']) ?></code></td>
                    <td style="color:#475569;"><?= sp_h($ev['description']) ?></td>
                    <td>
                        <?= $ev['globally_active']
                            ? '<span class="badge badge--success">ON</span>'
                            : '<span class="badge badge--danger">OFF</span>' ?>
                    </td>
                    <td>
                        <span class="badge <?= $ev['scope'] ? 'badge--info' : 'badge--gray' ?>">
                            <?= sp_h($ev['scope_label']) ?>
                        </span>
                    </td>
                    <td>
                        <div style="display:flex;align-items:center;gap:6px;">
                            <div style="width:50px;height:6px;background:#E5E7EB;border-radius:3px;overflow:hidden;">
                                <div style="width:<?= (int)$ev['rollout'] ?>%;height:100%;background:var(--color-primary);"></div>
                            </div>
                            <span style="font-size:12px;"><?= (int)$ev['rollout'] ?>%</span>
                        </div>
                    </td>
                    <td>
                        <?php if ($ev['active']): ?>
                            <span class="badge badge--success">✓ SÍ</span>
                        <?php else: ?>
                            <span class="badge badge--danger">✗ NO</span>
                        <?php endif; ?>
                        <?php if (!empty($ev['reason'])): ?>
                            <div style="font-size:11px;color:#94A3B8;margin-top:4px;"><?= sp_h($ev['reason']) ?></div>
                        <?php endif; ?>
                    </td>
                </tr>
                <?php endforeach; ?>
            </tbody>
            <tfoot>
                <tr style="background:var(--color-surface-variant);font-weight:700;">
                    <td colspan="5" style="text-align:right;">Total activas para este usuario:</td>
                    <td>
                        <span class="badge badge--success"><?= $activeCount ?></span> / <?= count($evaluations) ?>
                    </td>
                </tr>
            </tfoot>
        </table>
        <?php endif; ?>
    </section>
    <?php endif; ?>

    <?php
    render_footer();
}


// ════════════════════════════════════════════════════════════
//  HELPERS
// ════════════════════════════════════════════════════════════

/**
 * Evalúa un flag para un usuario específico aplicando la lógica:
 *   1. is_globally_active = 0 → OFF
 *   2. plan_scope definido y != plan del usuario → OFF
 *   3. rollout_percentage < 100 → hash determinístico (crc32 de code:user_id) % 100
 *   4. Si todo pasa → ON
 *
 * @param array $flag  Fila de feature_flags
 * @param array $user  Fila de usuarios (con access_level)
 * @return array{code:string,description:string,globally_active:bool,scope:?string,scope_label:string,rollout:int,active:bool,reason:string}
 */
function evaluate_flag_for_user(array $flag, array $user): array {
    $globallyActive = (int)$flag['is_globally_active'];
    $scope  = $flag['plan_scope'] ?? null;
    $rollout = (int)$flag['rollout_percentage'];
    $userPlan = ($user['access_level'] ?? '') ?: 'free';

    $scopeLabel = $scope ? ucfirst($scope) : 'Todos';

    $active = false;
    $reason = '';

    if (!$globallyActive) {
        $active = false;
        $reason = 'Flag globalmente inactivo (kill switch ON)';
    } elseif ($scope !== null && strtolower((string)$scope) !== strtolower($userPlan)) {
        $active = false;
        $reason = "Scope '" . $scope . "' no incluye plan '" . $userPlan . "'";
    } elseif ($rollout < 100) {
        // Hash determinístico: mismo usuario + mismo flag → mismo bucket siempre
        $hash   = crc32($flag['code'] . ':' . $user['id_usuario']);
        $bucket = abs($hash) % 100; // 0-99
        if ($bucket < $rollout) {
            $active = true;
            $reason = "En rollout (bucket {$bucket} < {$rollout})";
        } else {
            $active = false;
            $reason = "Fuera de rollout (bucket {$bucket} >= {$rollout})";
        }
    } else {
        $active = true;
        $reason = 'Activo global + 100% rollout';
    }

    return [
        'code'            => $flag['code'],
        'description'     => $flag['description'] ?? '',
        'globally_active' => (bool)$globallyActive,
        'scope'           => $scope,
        'scope_label'     => $scopeLabel,
        'rollout'         => $rollout,
        'active'          => $active,
        'reason'          => $reason,
    ];
}
