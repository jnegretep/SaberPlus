<?php
declare(strict_types=1);

/**
 * SPRINT 3 — Gestión avanzada de usuarios
 * SABER+ Command Center · Sección "users"
 *
 * Funcionalidades:
 *  - Listado paginado (50/página) con búsqueda, filtros y orden.
 *  - Vista detalle por sub-página (?action=view&id=X): datos básicos,
 *    gamificación, últimos 5 simulacros y activity feed (app_events).
 *  - Acciones administrativas (POST + CSRF + RBAC users.write):
 *      · change_access_level  · toggle_active
 *      · verify_email          · mark_early_bird
 *    Cada acción se audita con admin_audit_change() (before/after).
 *
 * Seguridad:
 *  - require_permission('users.read') al inicio del controller.
 *  - require_permission('users.write') antes de cualquier POST action.
 *  - Prepared statements en TODAS las consultas con input del usuario.
 *  - Enums validados con in_array(..., true) y IDs con (int).
 *  - Columna `activo` detectada dinámicamente (migración 005 opcional).
 */

require_once __DIR__ . '/../../bootstrap.php';
require_once __DIR__ . '/../../includes/layout.php';

require_permission('users.read');

// ── Constantes ────────────────────────────────────────────────────
const USERS_PER_PAGE       = 50;
const USERS_VALID_PLANS    = ['free', 'premium', 'trial', 'early_bird'];
const USERS_VALID_SORT_COL = ['id_usuario', 'nombre', 'email', 'registration_date', 'ultimo_login'];
const USERS_VALID_DIR      = ['asc', 'desc'];

// ── Helpers locales ───────────────────────────────────────────────

/** Devuelve la clase CSS del badge según el plan. */
function users_plan_badge_class(string $plan): string {
    return match ($plan) {
        'premium'    => 'badge badge--purple',
        'trial'      => 'badge badge--warning',
        'early_bird' => 'badge badge--success',
        default      => 'badge badge--gray',
    };
}

/** Etiqueta legible del plan. */
function users_plan_label(string $plan): string {
    return match ($plan) {
        'premium'    => 'Premium',
        'trial'      => 'Trial',
        'early_bird' => 'Early Bird',
        default      => 'Free',
    };
}

/** Detecta (cacheado) si una columna existe en `usuarios`. */
function users_column_exists(PDO $db, string $column): bool {
    static $cache = [];
    if (isset($cache[$column])) return $cache[$column];
    try {
        $stmt = $db->prepare("SHOW COLUMNS FROM usuarios LIKE ?");
        $stmt->execute([$column]);
        $cache[$column] = $stmt->fetch() !== false;
    } catch (Throwable $e) {
        $cache[$column] = false;
    }
    return $cache[$column];
}

/** Render del avatar: imagen si avatar_path válido, si no, inicial del nombre. */
function users_avatar_html(array $u, int $size = 36): string {
    $name     = $u['nombre'] ?? '?';
    $initial  = mb_substr(trim($name) ?: '?', 0, 1);
    $path     = (string)($u['avatar_path'] ?? '');
    $allowed  = preg_match('#^https?://#', $path) || preg_match('#^/api/prepsaber/#', $path);
    if ($path !== '' && $allowed) {
        return sprintf(
            '<img src="%s" alt="" width="%d" height="%d" style="border-radius:50%%;object-fit:cover;flex-shrink:0;">',
            sp_h($path), $size, $size
        );
    }
    return sprintf(
        '<span class="user-avatar-initial" style="width:%dpx;height:%dpx;border-radius:50%%;display:inline-flex;align-items:center;justify-content:center;background:linear-gradient(135deg,var(--color-primary),var(--color-purple));color:#fff;font-weight:700;font-size:%dpx;flex-shrink:0;">%s</span>',
        $size, $size, max(12, intdiv($size, 2)), sp_h(mb_strtoupper($initial))
    );
}

/** Construye una URL del listado preservando los filtros base + overrides. */
function users_list_url(array $base, array $overrides = []): string {
    $params = array_merge($base, $overrides);
    $params = array_filter($params, fn($v) => $v !== '' && $v !== null);
    return admin_section_url('users', $params);
}

/** Flecha de orden (▲/▼) para encabezados de tabla clicables. */
function users_sort_arrow(string $col, string $current, string $dir): string {
    if ($col !== $current) return '';
    return $dir === 'asc' ? ' ▲' : ' ▼';
}

// ── Captura de filtros del listado (también usados tras POST) ─────
$listFilters = [
    'page'             => max(1, (int)($_GET['page'] ?? 1)),
    'q'                => trim((string)($_GET['q'] ?? '')),
    'access_level'     => (string)($_GET['access_level'] ?? ''),
    'email_verificado' => (string)($_GET['email_verificado'] ?? ''),
    'activo'           => (string)($_GET['activo'] ?? ''),
    'departamento'     => trim((string)($_GET['departamento'] ?? '')),
    'sort'             => (string)($_GET['sort'] ?? ''),
    'dir'              => (string)($_GET['dir'] ?? ''),
];

// ════════════════════════════════════════════════════════════════
//  1. PROCESAMIENTO POST — Acciones administrativas
//     (CSRF ya verificado automáticamente en bootstrap.php para POST)
// ════════════════════════════════════════════════════════════════
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_permission('users.write'); // RBAC estricto para escritura

    $action = (string)($_POST['action'] ?? '');
    $userId = (int)($_POST['user_id'] ?? 0);

    if ($userId <= 0) {
        admin_flash('error', 'ID de usuario inválido.');
    } else {
        // Cargar estado ANTES del cambio (snapshot para auditoría before/after)
        $beforeRow = safeRows($conexion,
            "SELECT id_usuario, nombre, email, access_level, email_verificado, activo
             FROM usuarios WHERE id_usuario = ? LIMIT 1", [$userId]);
        $before = $beforeRow[0] ?? null;

        if (!$before) {
            admin_flash('error', 'Usuario no encontrado (id=' . $userId . ').');
        } else {
            switch ($action) {

                // ── Cambiar access_level ──
                case 'change_access_level':
                    $newLevel = (string)($_POST['access_level'] ?? '');
                    if (!in_array($newLevel, USERS_VALID_PLANS, true)) {
                        admin_flash('error', 'Plan inválido: ' . sp_h($newLevel));
                        break;
                    }
                    if ($newLevel === $before['access_level']) {
                        admin_flash('info', 'El usuario ya tiene el plan "' . users_plan_label($newLevel) . '".');
                        break;
                    }
                    try {
                        $stmt = $conexion->prepare("UPDATE usuarios SET access_level = ? WHERE id_usuario = ?");
                        $ok   = $stmt->execute([$newLevel, $userId]);
                        $after = array_merge($before, ['access_level' => $newLevel]);
                        admin_audit_change($conexion, 'users', 'change_access_level', 'usuarios', $userId, $before, $after, (bool)$ok);
                        admin_flash(
                            $ok ? 'success' : 'error',
                            $ok ? 'Plan actualizado a "' . users_plan_label($newLevel) . '" para ' . sp_h($before['email'])
                                : 'No se pudo actualizar el plan.'
                        );
                    } catch (Throwable $e) {
                        error_log('[users.change_access_level] ' . $e->getMessage());
                        admin_audit_change($conexion, 'users', 'change_access_level', 'usuarios', $userId, $before, $before, false);
                        admin_flash('error', 'Error interno al cambiar el plan.');
                    }
                    break;

                // ── Toggle activo/inactivo ──
                case 'toggle_active':
                    if (!users_column_exists($conexion, 'activo')) {
                        admin_flash('error', 'La columna "activo" no existe en la BD (¿migración 005 pendiente?).');
                        break;
                    }
                    $newActivo = ((int)$before['activo']) === 1 ? 0 : 1;
                    try {
                        $stmt = $conexion->prepare("UPDATE usuarios SET activo = ? WHERE id_usuario = ?");
                        $ok   = $stmt->execute([$newActivo, $userId]);
                        $after = array_merge($before, ['activo' => $newActivo]);
                        admin_audit_change($conexion, 'users', 'toggle_active', 'usuarios', $userId, $before, $after, (bool)$ok);
                        admin_flash(
                            $ok ? 'success' : 'error',
                            $ok ? ('Usuario ' . ($newActivo ? 'activado' : 'desactivado') . ': ' . sp_h($before['email']))
                                : 'No se pudo cambiar el estado.'
                        );
                    } catch (Throwable $e) {
                        error_log('[users.toggle_active] ' . $e->getMessage());
                        admin_audit_change($conexion, 'users', 'toggle_active', 'usuarios', $userId, $before, $before, false);
                        admin_flash('error', 'Error interno al cambiar el estado.');
                    }
                    break;

                // ── Verificar email ──
                case 'verify_email':
                    if (((int)$before['email_verificado']) === 1) {
                        admin_flash('info', 'El email ya estaba verificado.');
                        break;
                    }
                    try {
                        $stmt = $conexion->prepare("UPDATE usuarios SET email_verificado = 1 WHERE id_usuario = ?");
                        $ok   = $stmt->execute([$userId]);
                        $after = array_merge($before, ['email_verificado' => 1]);
                        admin_audit_change($conexion, 'users', 'verify_email', 'usuarios', $userId, $before, $after, (bool)$ok);
                        admin_flash(
                            $ok ? 'success' : 'error',
                            $ok ? 'Email verificado manualmente para ' . sp_h($before['email'])
                                : 'No se pudo verificar el email.'
                        );
                    } catch (Throwable $e) {
                        error_log('[users.verify_email] ' . $e->getMessage());
                        admin_audit_change($conexion, 'users', 'verify_email', 'usuarios', $userId, $before, $before, false);
                        admin_flash('error', 'Error interno al verificar email.');
                    }
                    break;

                // ── Marcar como Early Bird ──
                case 'mark_early_bird':
                    if ($before['access_level'] === 'early_bird') {
                        admin_flash('info', 'El usuario ya es Early Bird.');
                        break;
                    }
                    try {
                        $stmt = $conexion->prepare("UPDATE usuarios SET access_level = 'early_bird' WHERE id_usuario = ?");
                        $ok   = $stmt->execute([$userId]);
                        $after = array_merge($before, ['access_level' => 'early_bird']);
                        admin_audit_change($conexion, 'users', 'mark_early_bird', 'usuarios', $userId, $before, $after, (bool)$ok);
                        admin_flash(
                            $ok ? 'success' : 'error',
                            $ok ? 'Usuario marcado como Early Bird: ' . sp_h($before['email'])
                                : 'No se pudo marcar como Early Bird.'
                        );
                    } catch (Throwable $e) {
                        error_log('[users.mark_early_bird] ' . $e->getMessage());
                        admin_audit_change($conexion, 'users', 'mark_early_bird', 'usuarios', $userId, $before, $before, false);
                        admin_flash('error', 'Error interno al marcar Early Bird.');
                    }
                    break;

                default:
                    admin_flash('error', 'Acción no reconocida.');
            }
        }
    }

    // PRG: volver al detalle si la acción se ejecutó desde ahí, si no, al listado.
    $retAction = (string)($_POST['return_action'] ?? '');
    $redirect = ($retAction === 'view' && $userId > 0)
        ? admin_section_url('users', ['action' => 'view', 'id' => $userId])
        : users_list_url($listFilters);
    header('Location: ' . $redirect);
    exit;
}

// ════════════════════════════════════════════════════════════════
//  2. VISTA DETALLE (sub-página ?action=view&id=X)
// ════════════════════════════════════════════════════════════════
if (($_GET['action'] ?? '') === 'view') {
    $viewId = (int)($_GET['id'] ?? 0);

    $userRows = $viewId > 0 ? safeRows($conexion,
        "SELECT u.id_usuario, u.nombre, u.email, u.telefono, u.departamento, u.ciudad,
                u.colegio, u.grado, u.tipo_usuario, u.access_level, u.email_verificado,
                u.moodle_id, u.registration_date, u.ultimo_login, u.avatar_path, u.fcm_token,
                u.codigo_referido"
        . (users_column_exists($conexion, 'activo') ? ", u.activo" : "")
        . ", g.total_xp, g.current_level, g.current_streak, g.max_streak
           FROM usuarios u
           LEFT JOIN user_gamification g ON g.user_id = u.id_usuario
           WHERE u.id_usuario = ? LIMIT 1", [$viewId]) : [];

    if (empty($userRows)) {
        render_header('Usuario no encontrado', ['section' => 'users']);
        echo '<div class="empty-state">';
        echo '<div class="empty-state__icon">🔍</div>';
        echo '<div class="empty-state__title">Usuario no encontrado</div>';
        echo '<div class="empty-state__message">El usuario con ID <code>' . sp_h((string)$viewId) . '</code> no existe.</div>';
        echo '<p style="margin-top:16px"><a href="' . admin_section_url('users') . '" class="btn btn--primary">Volver a Usuarios</a></p>';
        echo '</div>';
        render_footer();
        exit;
    }

    $u = $userRows[0];
    $canWrite    = admin_has_permission('users.write');
    $hasActivoCol = users_column_exists($conexion, 'activo');

    $simulacros = safeRows($conexion,
        "SELECT fecha_realizacion, puntaje_global, lectura_puntaje, matematicas_puntaje,
                sociales_puntaje, naturales_puntaje, ingles_puntaje, tiempo_empleado
         FROM simulacro_resultados
         WHERE usuario_id = ?
         ORDER BY fecha_realizacion DESC LIMIT 5", [$viewId]);

    $events = safeRows($conexion,
        "SELECT event_name, platform, app_version, params, created_at
         FROM app_events
         WHERE user_id = ?
         ORDER BY created_at DESC LIMIT 5", [$viewId]);

    $totalSimulacros = (int)safeScalar($conexion,
        "SELECT COUNT(*) FROM simulacro_resultados WHERE usuario_id = ?", [$viewId]);

    render_header('Detalle de usuario · ' . $u['nombre'], ['section' => 'users']);
    ?>
<div class="section-header">
    <div>
        <div class="section-header__title">Detalle de usuario</div>
        <div class="section-header__subtitle">ID #<?= (int)$u['id_usuario'] ?> · <?= sp_h($u['email']) ?></div>
    </div>
    <div class="card__actions">
        <a href="<?= users_list_url($listFilters) ?>" class="btn btn--outline btn--sm">← Volver al listado</a>
    </div>
</div>

<div class="grid-2" style="grid-template-columns: 1fr 2fr; align-items:start;">
    <!-- Perfil + gamificación -->
    <section class="card">
        <div style="display:flex;flex-direction:column;align-items:center;text-align:center;gap:8px;margin-bottom:16px;">
            <?= users_avatar_html($u, 84) ?>
            <div>
                <div style="font-size:var(--fs-lg);font-weight:700;"><?= sp_h($u['nombre']) ?></div>
                <div style="color:var(--color-text-tertiary);font-size:var(--fs-sm);"><?= sp_h($u['email']) ?></div>
            </div>
            <span class="<?= users_plan_badge_class((string)$u['access_level']) ?>">
                <?= users_plan_label((string)$u['access_level']) ?>
            </span>
            <div style="display:flex;gap:6px;flex-wrap:wrap;justify-content:center;">
                <?php if (((int)$u['email_verificado']) === 1): ?>
                    <span class="badge badge--success">Email verificado</span>
                <?php else: ?>
                    <span class="badge badge--warning">Email sin verificar</span>
                <?php endif; ?>
                <?php if ($hasActivoCol): ?>
                    <?php if (((int)$u['activo']) === 1): ?>
                        <span class="badge badge--success">Cuenta activa</span>
                    <?php else: ?>
                        <span class="badge badge--danger">Cuenta inactiva</span>
                    <?php endif; ?>
                <?php endif; ?>
            </div>
        </div>

        <div style="display:flex;flex-direction:column;gap:8px;font-size:var(--fs-sm);">
            <div style="display:flex;justify-content:space-between;"><span style="color:var(--color-text-tertiary);">Teléfono</span><strong><?= sp_h($u['telefono'] ?: '—') ?></strong></div>
            <div style="display:flex;justify-content:space-between;"><span style="color:var(--color-text-tertiary);">Departamento</span><strong><?= sp_h($u['departamento'] ?: '—') ?></strong></div>
            <div style="display:flex;justify-content:space-between;"><span style="color:var(--color-text-tertiary);">Ciudad</span><strong><?= sp_h($u['ciudad'] ?: '—') ?></strong></div>
            <div style="display:flex;justify-content:space-between;"><span style="color:var(--color-text-tertiary);">Colegio</span><strong><?= sp_h($u['colegio'] ?: '—') ?></strong></div>
            <div style="display:flex;justify-content:space-between;"><span style="color:var(--color-text-tertiary);">Grado</span><strong><?= sp_h($u['grado'] ?: '—') ?></strong></div>
            <div style="display:flex;justify-content:space-between;"><span style="color:var(--color-text-tertiary);">Tipo</span><strong><?= sp_h($u['tipo_usuario'] ?: '—') ?></strong></div>
            <div style="display:flex;justify-content:space-between;"><span style="color:var(--color-text-tertiary);">Moodle ID</span><strong><?= sp_h((string)($u['moodle_id'] ?? '')) ?: '—' ?></strong></div>
            <div style="display:flex;justify-content:space-between;"><span style="color:var(--color-text-tertiary);">Registro</span><strong><?= admin_fmt_fecha($u['registration_date']) ?></strong></div>
            <div style="display:flex;justify-content:space-between;"><span style="color:var(--color-text-tertiary);">Último login</span><strong><?= admin_fmt_tiempo_relativo($u['ultimo_login']) ?></strong></div>
            <?php if (!empty($u['codigo_referido'])): ?>
            <div style="display:flex;justify-content:space-between;"><span style="color:var(--color-text-tertiary);">Código referido</span><strong><?= sp_h($u['codigo_referido']) ?></strong></div>
            <?php endif; ?>
        </div>

        <div style="border-top:1px solid var(--color-border);margin-top:16px;padding-top:16px;">
            <div style="font-size:var(--fs-sm);font-weight:600;color:var(--color-text-secondary);text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px;">Gamificación</div>
            <div class="grid-3" style="gap:8px;text-align:center;">
                <div>
                    <div style="font-size:var(--fs-xl);font-weight:800;color:var(--color-purple);"><?= admin_fmt_int((int)($u['total_xp'] ?? 0)) ?></div>
                    <div style="font-size:var(--fs-xs);color:var(--color-text-tertiary);">XP TOTAL</div>
                </div>
                <div>
                    <div style="font-size:var(--fs-xl);font-weight:800;color:var(--color-primary);">Nv. <?= admin_fmt_int((int)($u['current_level'] ?? 0)) ?></div>
                    <div style="font-size:var(--fs-xs);color:var(--color-text-tertiary);">NIVEL</div>
                </div>
                <div>
                    <div style="font-size:var(--fs-xl);font-weight:800;color:var(--color-warning);"><?= admin_fmt_int((int)($u['current_streak'] ?? 0)) ?></div>
                    <div style="font-size:var(--fs-xs);color:var(--color-text-tertiary);">RACHA</div>
                </div>
            </div>
        </div>
    </section>

    <!-- Simulacros + activity feed + acciones -->
    <div style="display:flex;flex-direction:column;gap:16px;">

        <?php if ($canWrite): ?>
        <section class="card">
            <div class="card__header">
                <div class="card__title">Acciones administrativas</div>
            </div>
            <div style="display:flex;flex-wrap:wrap;gap:12px;align-items:end;">
                <form method="post" action="<?= admin_section_url('users') ?>" class="filters-bar__field" style="flex-direction:row;align-items:end;gap:8px;">
                    <?= admin_csrf_field() ?>
                    <input type="hidden" name="action" value="change_access_level">
                    <input type="hidden" name="user_id" value="<?= (int)$u['id_usuario'] ?>">
                    <input type="hidden" name="return_action" value="view">
                    <div class="filters-bar__field">
                        <label class="filters-bar__label">Cambiar plan</label>
                        <select name="access_level" class="form-select" style="min-width:160px;">
                            <?php foreach (USERS_VALID_PLANS as $p): ?>
                                <option value="<?= sp_h($p) ?>" <?= $p === $u['access_level'] ? 'selected' : '' ?>>
                                    <?= users_plan_label($p) ?>
                                </option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <button type="submit" class="btn btn--primary btn--sm">Aplicar</button>
                </form>

                <?php if ($hasActivoCol): ?>
                <form method="post" action="<?= admin_section_url('users') ?>">
                    <?= admin_csrf_field() ?>
                    <input type="hidden" name="action" value="toggle_active">
                    <input type="hidden" name="user_id" value="<?= (int)$u['id_usuario'] ?>">
                    <input type="hidden" name="return_action" value="view">
                    <?php $uActivo = ((int)($u['activo'] ?? 1)) === 1; ?>
                    <button type="submit" class="btn <?= $uActivo ? 'btn--danger' : 'btn--success' ?> btn--sm"
                            data-confirm="<?= $uActivo ? '¿Desactivar esta cuenta de usuario?' : '¿Reactivar esta cuenta de usuario?' ?>">
                        <?= $uActivo ? 'Desactivar cuenta' : 'Reactivar cuenta' ?>
                    </button>
                </form>
                <?php endif; ?>

                <?php if (((int)$u['email_verificado']) !== 1): ?>
                <form method="post" action="<?= admin_section_url('users') ?>">
                    <?= admin_csrf_field() ?>
                    <input type="hidden" name="action" value="verify_email">
                    <input type="hidden" name="user_id" value="<?= (int)$u['id_usuario'] ?>">
                    <input type="hidden" name="return_action" value="view">
                    <button type="submit" class="btn btn--success btn--sm" data-confirm="¿Marcar el email como verificado?">Verificar email</button>
                </form>
                <?php endif; ?>

                <?php if ($u['access_level'] !== 'early_bird'): ?>
                <form method="post" action="<?= admin_section_url('users') ?>">
                    <?= admin_csrf_field() ?>
                    <input type="hidden" name="action" value="mark_early_bird">
                    <input type="hidden" name="user_id" value="<?= (int)$u['id_usuario'] ?>">
                    <input type="hidden" name="return_action" value="view">
                    <button type="submit" class="btn btn--outline btn--sm" data-confirm="¿Marcar este usuario como Early Bird?">Marcar Early Bird</button>
                </form>
                <?php endif; ?>
            </div>
        </section>
        <?php endif; ?>

        <!-- Últimos simulacros -->
        <section class="card">
            <div class="card__header">
                <div class="card__title">Últimos simulacros</div>
                <span class="badge badge--gray"><?= admin_fmt_int($totalSimulacros) ?> en total</span>
            </div>
            <?php if (empty($simulacros)): ?>
                <div class="empty-state" style="padding:24px;">
                    <div class="empty-state__icon">📝</div>
                    <div class="empty-state__message">Este usuario aún no ha realizado simulacros.</div>
                </div>
            <?php else: ?>
                <div style="overflow-x:auto;">
                <table class="data-table table-compact">
                    <thead>
                        <tr>
                            <th>Fecha</th>
                            <th>Global</th>
                            <th>Lectura</th>
                            <th>Mat.</th>
                            <th>Soc.</th>
                            <th>Nat.</th>
                            <th>Ing.</th>
                            <th>Tiempo</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($simulacros as $s): ?>
                            <tr>
                                <td><?= admin_fmt_fecha($s['fecha_realizacion']) ?></td>
                                <td><strong><?= sp_h((string)($s['puntaje_global'] ?? '—')) ?></strong></td>
                                <td><?= sp_h((string)($s['lectura_puntaje'] ?? '—')) ?></td>
                                <td><?= sp_h((string)($s['matematicas_puntaje'] ?? '—')) ?></td>
                                <td><?= sp_h((string)($s['sociales_puntaje'] ?? '—')) ?></td>
                                <td><?= sp_h((string)($s['naturales_puntaje'] ?? '—')) ?></td>
                                <td><?= sp_h((string)($s['ingles_puntaje'] ?? '—')) ?></td>
                                <td><?= sp_h((string)($s['tiempo_empleado'] ?? '—')) ?></td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
                </div>
            <?php endif; ?>
        </section>

        <!-- Activity feed -->
        <section class="card">
            <div class="card__header">
                <div class="card__title">Actividad reciente (app_events)</div>
            </div>
            <?php if (empty($events)): ?>
                <div class="empty-state" style="padding:24px;">
                    <div class="empty-state__icon">⚡</div>
                    <div class="empty-state__message">Sin eventos registrados para este usuario.</div>
                </div>
            <?php else: ?>
                <div class="activity-feed">
                    <?php foreach ($events as $ev): ?>
                        <div class="activity-item">
                            <div class="activity-item__icon">📱</div>
                            <div class="activity-item__content">
                                <div class="activity-item__title"><code><?= sp_h($ev['event_name']) ?></code>
                                    <?php if (!empty($ev['platform'])): ?>
                                        <span class="badge badge--gray" style="margin-left:4px;"><?= sp_h($ev['platform']) ?></span>
                                    <?php endif; ?>
                                </div>
                                <div class="activity-item__time"><?= admin_fmt_tiempo_relativo($ev['created_at']) ?><?php if (!empty($ev['app_version'])): ?> · v<?= sp_h($ev['app_version']) ?><?php endif; ?></div>
                            </div>
                        </div>
                    <?php endforeach; ?>
                </div>
            <?php endif; ?>
        </section>
    </div>
</div>

    <?php
    render_footer();
    exit;
}

// ════════════════════════════════════════════════════════════════
//  3. LISTADO — query dinámica con filtros + sort + paginación
// ════════════════════════════════════════════════════════════════
$hasActivoCol = users_column_exists($conexion, 'activo');

$where  = [];
$params = [];
if ($listFilters['q'] !== '') {
    $where[] = "(u.nombre LIKE ? OR u.email LIKE ? OR CAST(u.moodle_id AS CHAR) LIKE ? OR u.colegio LIKE ?)";
    $kw = '%' . $listFilters['q'] . '%';
    array_push($params, $kw, $kw, $kw, $kw);
}
if (in_array($listFilters['access_level'], USERS_VALID_PLANS, true)) {
    $where[] = "u.access_level = ?";
    $params[] = $listFilters['access_level'];
}
if ($listFilters['email_verificado'] === '0' || $listFilters['email_verificado'] === '1') {
    $where[] = "u.email_verificado = ?";
    $params[] = (int)$listFilters['email_verificado'];
}
if ($hasActivoCol && ($listFilters['activo'] === '0' || $listFilters['activo'] === '1')) {
    $where[] = "u.activo = ?";
    $params[] = (int)$listFilters['activo'];
}
if ($listFilters['departamento'] !== '') {
    $where[] = "u.departamento LIKE ?";
    $params[] = '%' . $listFilters['departamento'] . '%';
}
$whereSql = $where ? ('WHERE ' . implode(' AND ', $where)) : '';

// Sort (whitelist estricta → inyección SQL imposible)
$sortCol = in_array($listFilters['sort'], USERS_VALID_SORT_COL, true) ? $listFilters['sort'] : 'registration_date';
$sortDir = in_array($listFilters['dir'], USERS_VALID_DIR, true) ? $listFilters['dir'] : 'desc';
$sortSql = "ORDER BY u." . $sortCol . " " . strtoupper($sortDir) . ", u.id_usuario ASC";

// Count total
$total = (int)safeScalar($conexion, "SELECT COUNT(*) FROM usuarios u $whereSql", $params);

// Paginación
$perPage     = USERS_PER_PAGE;
$totalPages  = max(1, (int)ceil($total / $perPage));
$page        = max(1, min($listFilters['page'], $totalPages));
$offset      = ($page - 1) * $perPage;
$fromRow     = $total > 0 ? $offset + 1 : 0;
$toRow       = min($offset + $perPage, $total);

// Query de datos (LEFT JOIN user_gamification)
$selectCols = "u.id_usuario, u.nombre, u.email, u.access_level, u.email_verificado,
               u.registration_date, u.ultimo_login, u.avatar_path"
    . ($hasActivoCol ? ", u.activo" : "")
    . ", g.total_xp, g.current_level";

$listSql = "SELECT $selectCols
            FROM usuarios u
            LEFT JOIN user_gamification g ON g.user_id = u.id_usuario
            $whereSql
            $sortSql
            LIMIT $perPage OFFSET $offset";
$rows = safeRows($conexion, $listSql, $params);

// KPIs rápidos para el encabezado
$kpis = [
    'total'     => $total,
    'premium'   => (int)safeScalar($conexion, "SELECT COUNT(*) FROM usuarios WHERE access_level = 'premium'"),
    'verificados' => (int)safeScalar($conexion, "SELECT COUNT(*) FROM usuarios WHERE email_verificado = 1"),
    'inactivos' => $hasActivoCol ? (int)safeScalar($conexion, "SELECT COUNT(*) FROM usuarios WHERE activo = 0") : 0,
];

// ── Render ────────────────────────────────────────────────────────
render_header('Gestión de usuarios', ['section' => 'users']);
$canWrite = admin_has_permission('users.write');
?>

<div class="section-header">
    <div>
        <div class="section-header__title">Gestión de usuarios</div>
        <div class="section-header__subtitle">Administra cuentas, planes y verificaciones</div>
    </div>
    <div class="quick-stats">
        <div class="quick-stat">
            <div class="quick-stat__value"><?= admin_fmt_int($kpis['total']) ?></div>
            <div class="quick-stat__label">Filtrados</div>
        </div>
        <div class="quick-stat">
            <div class="quick-stat__value"><?= admin_fmt_int($kpis['premium']) ?></div>
            <div class="quick-stat__label">Premium</div>
        </div>
        <div class="quick-stat">
            <div class="quick-stat__value"><?= admin_fmt_int($kpis['verificados']) ?></div>
            <div class="quick-stat__label">Verificados</div>
        </div>
        <?php if ($hasActivoCol): ?>
        <div class="quick-stat">
            <div class="quick-stat__value"><?= admin_fmt_int($kpis['inactivos']) ?></div>
            <div class="quick-stat__label">Inactivos</div>
        </div>
        <?php endif; ?>
    </div>
</div>

<!-- Barra de filtros -->
<form method="get" action="<?= admin_section_url('users') ?>" class="filters-bar">
    <input type="hidden" name="section" value="users">
    <div class="filters-bar__field" style="flex:1;min-width:220px;">
        <label class="filters-bar__label" for="fltr-q">Buscar</label>
        <input type="text" id="fltr-q" name="q" value="<?= sp_h($listFilters['q']) ?>"
               placeholder="email, nombre, moodle_id o colegio…" class="form-input">
    </div>
    <div class="filters-bar__field">
        <label class="filters-bar__label" for="fltr-plan">Plan</label>
        <select id="fltr-plan" name="access_level" class="form-select">
            <option value="">Todos</option>
            <?php foreach (USERS_VALID_PLANS as $p): ?>
                <option value="<?= sp_h($p) ?>" <?= $listFilters['access_level'] === $p ? 'selected' : '' ?>>
                    <?= users_plan_label($p) ?>
                </option>
            <?php endforeach; ?>
        </select>
    </div>
    <div class="filters-bar__field">
        <label class="filters-bar__label" for="fltr-ev">Email verificado</label>
        <select id="fltr-ev" name="email_verificado" class="form-select">
            <option value="">Todos</option>
            <option value="1" <?= $listFilters['email_verificado'] === '1' ? 'selected' : '' ?>>Verificados</option>
            <option value="0" <?= $listFilters['email_verificado'] === '0' ? 'selected' : '' ?>>Sin verificar</option>
        </select>
    </div>
    <?php if ($hasActivoCol): ?>
    <div class="filters-bar__field">
        <label class="filters-bar__label" for="fltr-act">Estado cuenta</label>
        <select id="fltr-act" name="activo" class="form-select">
            <option value="">Todos</option>
            <option value="1" <?= $listFilters['activo'] === '1' ? 'selected' : '' ?>>Activos</option>
            <option value="0" <?= $listFilters['activo'] === '0' ? 'selected' : '' ?>>Inactivos</option>
        </select>
    </div>
    <?php endif; ?>
    <div class="filters-bar__field">
        <label class="filters-bar__label" for="fltr-dep">Departamento</label>
        <input type="text" id="fltr-dep" name="departamento" value="<?= sp_h($listFilters['departamento']) ?>"
               placeholder="Ej: Antioquia" class="form-input" style="min-width:150px;">
    </div>
    <div class="filters-bar__field">
        <button type="submit" class="btn btn--primary">Filtrar</button>
    </div>
    <div class="filters-bar__field">
        <a href="<?= admin_section_url('users') ?>" class="btn btn--outline">Limpiar</a>
    </div>
</form>

<!-- Tabla de usuarios -->
<section class="card" style="padding:0;overflow:hidden;">
    <?php if (empty($rows)): ?>
        <div class="empty-state">
            <div class="empty-state__icon">🔍</div>
            <div class="empty-state__title">Sin resultados</div>
            <div class="empty-state__message">No hay usuarios que coincidan con los filtros seleccionados.</div>
        </div>
    <?php else: ?>
        <div style="overflow-x:auto;">
        <table class="data-table">
            <thead>
                <tr>
                    <th data-sort="id_usuario" style="cursor:pointer;">ID <?= users_sort_arrow('id_usuario', $sortCol, $sortDir) ?></th>
                    <th>Usuario</th>
                    <th data-sort="email" style="cursor:pointer;">Email <?= users_sort_arrow('email', $sortCol, $sortDir) ?></th>
                    <th>Plan</th>
                    <th>Verificado</th>
                    <?php if ($hasActivoCol): ?><th>Estado</th><?php endif; ?>
                    <th>XP</th>
                    <th data-sort="registration_date" style="cursor:pointer;">Registro <?= users_sort_arrow('registration_date', $sortCol, $sortDir) ?></th>
                    <th data-sort="ultimo_login" style="cursor:pointer;">Último login <?= users_sort_arrow('ultimo_login', $sortCol, $sortDir) ?></th>
                    <th style="text-align:right;">Acciones</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($rows as $r): ?>
                    <?php
                        $dataAttrs = sprintf(
                            'data-id="%d" data-name="%s" data-email="%s" data-plan="%s" data-verificado="%d" data-activo="%d"',
                            (int)$r['id_usuario'],
                            sp_h($r['nombre']),
                            sp_h($r['email']),
                            sp_h((string)$r['access_level']),
                            (int)$r['email_verificado'],
                            (int)($r['activo'] ?? 1)
                        );
                    ?>
                    <tr>
                        <td>#<?= (int)$r['id_usuario'] ?></td>
                        <td>
                            <div style="display:flex;align-items:center;gap:10px;">
                                <?= users_avatar_html($r, 32) ?>
                                <div>
                                    <div style="font-weight:600;"><?= sp_h($r['nombre']) ?></div>
                                    <?php if (!empty($r['current_level'])): ?>
                                        <div style="font-size:var(--fs-xs);color:var(--color-text-tertiary);">Nv. <?= (int)$r['current_level'] ?></div>
                                    <?php endif; ?>
                                </div>
                            </div>
                        </td>
                        <td><?= sp_h($r['email']) ?></td>
                        <td><span class="<?= users_plan_badge_class((string)$r['access_level']) ?>"><?= users_plan_label((string)$r['access_level']) ?></span></td>
                        <td>
                            <?php if (((int)$r['email_verificado']) === 1): ?>
                                <span class="badge badge--success">Sí</span>
                            <?php else: ?>
                                <span class="badge badge--warning">No</span>
                            <?php endif; ?>
                        </td>
                        <?php if ($hasActivoCol): ?>
                        <td>
                            <?php if (((int)$r['activo']) === 1): ?>
                                <span class="badge badge--success">Activo</span>
                            <?php else: ?>
                                <span class="badge badge--danger">Inactivo</span>
                            <?php endif; ?>
                        </td>
                        <?php endif; ?>
                        <td style="font-variant-numeric:tabular-nums;color:var(--color-purple);font-weight:600;"><?= admin_fmt_int((int)($r['total_xp'] ?? 0)) ?></td>
                        <td style="white-space:nowrap;"><?= admin_fmt_fecha($r['registration_date']) ?></td>
                        <td style="white-space:nowrap;"><?= admin_fmt_tiempo_relativo($r['ultimo_login']) ?></td>
                        <td style="text-align:right;white-space:nowrap;">
                            <a href="<?= admin_section_url('users', ['action' => 'view', 'id' => (int)$r['id_usuario']]) ?>"
                               class="btn btn--outline btn--sm">Ver detalle</a>
                            <?php if ($canWrite): ?>
                                <button type="button" class="btn btn--primary btn--sm js-user-edit" <?= $dataAttrs ?>
                                        onclick="openUserEditModal(this)">Editar</button>
                            <?php endif; ?>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
        </div>
    <?php endif; ?>
</section>

<!-- Paginación -->
<?php if ($totalPages > 1): ?>
<div class="pagination">
    <div>
        Mostrando <strong><?= admin_fmt_int($fromRow) ?>–<?= admin_fmt_int($toRow) ?></strong>
        de <strong><?= admin_fmt_int($total) ?></strong> usuarios
    </div>
    <div class="pagination__pages">
        <?php
        // Ventana de páginas alrededor de la actual
        $win = 2;
        $startPage = max(1, $page - $win);
        $endPage   = min($totalPages, $page + $win);
        if ($startPage > 1) {
            echo '<a class="pagination__page" href="' . users_list_url($listFilters, ['page' => 1]) . '">«</a>';
            if ($startPage > 2) echo '<span class="pagination__page" style="border:none;">…</span>';
        }
        for ($i = $startPage; $i <= $endPage; $i++) {
            $cls = $i === $page ? 'pagination__page is-active' : 'pagination__page';
            echo '<a class="' . $cls . '" href="' . users_list_url($listFilters, ['page' => $i]) . '">' . $i . '</a>';
        }
        if ($endPage < $totalPages) {
            if ($endPage < $totalPages - 1) echo '<span class="pagination__page" style="border:none;">…</span>';
            echo '<a class="pagination__page" href="' . users_list_url($listFilters, ['page' => $totalPages]) . '">' . $totalPages . ' »</a>';
        }
        ?>
    </div>
</div>
<?php elseif ($total > 0): ?>
<div class="pagination">
    <div>Mostrando <strong><?= admin_fmt_int($fromRow) ?>–<?= admin_fmt_int($toRow) ?></strong> de <strong><?= admin_fmt_int($total) ?></strong> usuarios</div>
</div>
<?php endif; ?>

<!-- Modal de edición rápida (usuarios.write) -->
<?php if ($canWrite && !empty($rows)): ?>
<div class="modal-backdrop" id="userEditModal" style="display:none;">
    <div class="modal" role="dialog" aria-modal="true" aria-labelledby="userEditTitle">
        <div class="modal__header">
            <div class="modal__title" id="userEditTitle">Editar usuario</div>
            <button type="button" class="modal__close" onclick="closeModal('userEditModal')" aria-label="Cerrar">×</button>
        </div>
        <div class="modal__body">
            <div id="userEditSummary" style="display:flex;align-items:center;gap:12px;margin-bottom:16px;padding:12px;background:var(--color-surface-variant);border-radius:var(--radius-md);">
                <span id="userEditAvatar" class="user-avatar-initial" style="width:40px;height:40px;border-radius:50%;display:inline-flex;align-items:center;justify-content:center;background:linear-gradient(135deg,var(--color-primary),var(--color-purple));color:#fff;font-weight:700;">?</span>
                <div>
                    <div id="userEditName" style="font-weight:700;">—</div>
                    <div id="userEditEmail" style="font-size:var(--fs-sm);color:var(--color-text-tertiary);">—</div>
                </div>
            </div>

            <!-- Cambiar plan -->
            <form method="post" action="<?= admin_section_url('users') ?>">
                <?= admin_csrf_field() ?>
                <input type="hidden" name="action" value="change_access_level">
                <input type="hidden" name="user_id" id="uePlanUserId" value="">
                <div class="form-group">
                    <label class="form-label" for="uePlan">Plan de acceso</label>
                    <select id="uePlan" name="access_level" class="form-select">
                        <?php foreach (USERS_VALID_PLANS as $p): ?>
                            <option value="<?= sp_h($p) ?>"><?= users_plan_label($p) ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <button type="submit" class="btn btn--primary btn--block">Aplicar cambio de plan</button>
            </form>

            <div style="border-top:1px solid var(--color-border);margin:16px 0;"></div>

            <!-- Acciones rápidas -->
            <div style="display:flex;flex-direction:column;gap:8px;">
                <form method="post" action="<?= admin_section_url('users') ?>">
                    <?= admin_csrf_field() ?>
                    <input type="hidden" name="action" value="toggle_active">
                    <input type="hidden" name="user_id" id="ueToggleUserId" value="">
                    <button type="submit" id="ueToggleBtn" class="btn btn--danger btn--block"
                            data-confirm-base="¿Cambiar el estado de esta cuenta?">Desactivar cuenta</button>
                </form>

                <form method="post" action="<?= admin_section_url('users') ?>">
                    <?= admin_csrf_field() ?>
                    <input type="hidden" name="action" value="verify_email">
                    <input type="hidden" name="user_id" id="ueVerifyUserId" value="">
                    <button type="submit" id="ueVerifyBtn" class="btn btn--success btn--outline btn--block"
                            data-confirm="¿Marcar el email como verificado?">Verificar email</button>
                </form>

                <form method="post" action="<?= admin_section_url('users') ?>">
                    <?= admin_csrf_field() ?>
                    <input type="hidden" name="action" value="mark_early_bird">
                    <input type="hidden" name="user_id" id="ueEbUserId" value="">
                    <button type="submit" id="ueEbBtn" class="btn btn--outline btn--block"
                            data-confirm="¿Marcar este usuario como Early Bird?">Marcar como Early Bird</button>
                </form>
            </div>
        </div>
        <div class="modal__footer">
            <button type="button" class="btn btn--outline" onclick="closeModal('userEditModal')">Cerrar</button>
            <a id="ueViewDetailLink" href="#" class="btn btn--primary">Ver detalle completo</a>
        </div>
    </div>
</div>

<script>
(function() {
    'use strict';
    /**
     * Rellena el modal de edición rápida con los data-* del botón clicado.
     * openModal/closeModal vienen de admin.js (ya cargado en el footer).
     */
    window.openUserEditModal = function(btn) {
        var id        = btn.getAttribute('data-id');
        var name      = btn.getAttribute('data-name') || '(sin nombre)';
        var email     = btn.getAttribute('data-email') || '';
        var plan      = btn.getAttribute('data-plan') || 'free';
        var verificado= btn.getAttribute('data-verificado');
        var activo    = btn.getAttribute('data-activo');

        // Avatar (inicial)
        var initial = (name.trim().charAt(0) || '?').toUpperCase();
        var avEl = document.getElementById('userEditAvatar');
        if (avEl) avEl.textContent = initial;

        document.getElementById('userEditName').textContent  = name;
        document.getElementById('userEditEmail').textContent = email;

        // IDs en todos los forms
        ['uePlanUserId','ueToggleUserId','ueVerifyUserId','ueEbUserId'].forEach(function(fid){
            var el = document.getElementById(fid);
            if (el) el.value = id;
        });

        // Plan select
        var sel = document.getElementById('uePlan');
        if (sel) {
            for (var i = 0; i < sel.options.length; i++) {
                sel.options[i].selected = sel.options[i].value === plan;
            }
        }

        // Toggle button: cambia texto/clase según estado
        var tBtn = document.getElementById('ueToggleBtn');
        if (tBtn) {
            var isActive = activo === '1';
            tBtn.textContent = isActive ? 'Desactivar cuenta' : 'Reactivar cuenta';
            tBtn.className = 'btn btn--block ' + (isActive ? 'btn--danger' : 'btn--success');
            tBtn.setAttribute('data-confirm', isActive ? '¿Desactivar esta cuenta de usuario?' : '¿Reactivar esta cuenta de usuario?');
        }

        // Verify button: ocultar si ya está verificado
        var vBtn = document.getElementById('ueVerifyBtn');
        if (vBtn) {
            vBtn.style.display = verificado === '1' ? 'none' : '';
        }

        // Early Bird button: ocultar si ya es early_bird
        var ebBtn = document.getElementById('ueEbBtn');
        if (ebBtn) {
            ebBtn.style.display = plan === 'early_bird' ? 'none' : '';
        }

        // Link a detalle
        var link = document.getElementById('ueViewDetailLink');
        if (link) link.href = '<?= admin_section_url('users', ['action' => 'view']) ?>&id=' + encodeURIComponent(id);

        if (typeof window.openModal === 'function') {
            window.openModal('userEditModal');
        } else {
            var m = document.getElementById('userEditModal');
            if (m) m.style.display = 'flex';
        }
    };
})();
</script>
<?php endif; ?>

<?php
render_footer();
