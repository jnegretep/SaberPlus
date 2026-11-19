<?php
declare(strict_types=1);

/**
 * Layout principal del Command Center.
 * Sidebar lateral + header + footer.
 *
 * Uso:
 *   render_header('Dashboard Ejecutivo', ['dashboard' => true]);
 *   // ... contenido HTML
 *   render_footer();
 *
 * O con sidebar automático:
 *   $page = render_page('Dashboard', 'sections/dashboard/view.php', ['data' => $data]);
 *   echo $page;
 */

function admin_asset_url(string $path): string {
    // Asume que el admin se sirve en /admin/ (debe coincir con el backoffice web)
    return '/api/prepsaber/backend/admin/assets/' . ltrim($path, '/');
}

function admin_section_url(string $section, array $params = []): string {
    $q = $params ? '&' . http_build_query($params) : '';
    return 'index.php?section=' . urlencode($section) . $q;
}

function admin_nav_items(): array {
    return [
        'dashboard' => [
            'label' => 'Dashboard', 'icon' => '📊', 'group' => 'negocio',
            'perm' => null,
        ],
        'users' => [
            'label' => 'Usuarios', 'icon' => '👥', 'group' => 'negocio',
            'perm' => 'users.read',
        ],
        'plans' => [
            'label' => 'Planes', 'icon' => '💳', 'group' => 'negocio',
            'perm' => 'plans.read',
        ],
        'feature_flags' => [
            'label' => 'Feature Flags', 'icon' => '🚩', 'group' => 'producto',
            'perm' => 'feature_flags.manage',
        ],
        'gamification' => [
            'label' => 'Gamificación', 'icon' => '🏆', 'group' => 'producto',
            'perm' => null,
        ],
        'content' => [
            'label' => 'Contenido', 'icon' => '📚', 'group' => 'producto',
            'perm' => null,
        ],
        'ai' => [
            'label' => 'Centro IA', 'icon' => '🤖', 'group' => 'producto',
            'perm' => 'ia.monitor',
        ],
        'communications' => [
            'label' => 'Comunicaciones', 'icon' => '📣', 'group' => 'operaciones',
            'perm' => 'communications.history',
        ],
        'alerts' => [
            'label' => 'Alertas CEO', 'icon' => '🚨', 'group' => 'operaciones',
            'perm' => null,
        ],
        'system' => [
            'label' => 'System Health', 'icon' => '⚙️', 'group' => 'operaciones',
            'perm' => 'system.health',
        ],
        'audit' => [
            'label' => 'Auditoría', 'icon' => '📝', 'group' => 'sistema',
            'perm' => 'audit.read',
        ],
        'exports' => [
            'label' => 'Exportaciones', 'icon' => '📤', 'group' => 'sistema',
            'perm' => null,
        ],
    ];
}

function render_sidebar(string $currentSection): string {
    $items = admin_nav_items();
    $groups = [
        'negocio'    => 'Negocio',
        'producto'   => 'Producto',
        'operaciones' => 'Operaciones',
        'sistema'    => 'Sistema',
    ];

    $html = '<aside class="sidebar" id="sidebar">';
    $html .= '<div class="sidebar__brand">';
    $html .= '<div class="sidebar__logo">S<span>+</span></div>';
    $html .= '<div class="sidebar__title">Command<br><small>Center</small></div>';
    $html .= '</div>';

    foreach ($groups as $groupKey => $groupLabel) {
        $groupItems = array_filter($items, fn($i) => $i['group'] === $groupKey);
        if (empty($groupItems)) continue;

        $html .= '<div class="sidebar__group">';
        $html .= '<div class="sidebar__group-label">' . sp_h($groupLabel) . '</div>';
        foreach ($groupItems as $key => $item) {
            if ($item['perm'] !== null && !admin_has_permission($item['perm'])) continue;
            $active = $key === $currentSection ? ' is-active' : '';
            $badge  = '';
            if ($key === 'alerts') {
                $count = admin_unresolved_alerts_count();
                if ($count > 0) $badge = '<span class="badge-count">' . $count . '</span>';
            }
            $html .= sprintf(
                '<a href="%s" class="sidebar__item%s"><span class="sidebar__icon">%s</span><span class="sidebar__label">%s</span>%s</a>',
                admin_section_url($key),
                $active,
                $item['icon'],
                sp_h($item['label']),
                $badge
            );
        }
        $html .= '</div>';
    }

    $html .= '<div class="sidebar__footer">';
    $html .= '<div class="sidebar__user">';
    $html .= '<div class="sidebar__user-avatar">' . strtoupper(substr(current_admin_email() ?? '?', 0, 1)) . '</div>';
    $html .= '<div class="sidebar__user-info">';
    $html .= '<div class="sidebar__user-name">' . sp_h(current_admin_name() ?? 'Admin') . '</div>';
    $html .= '<div class="sidebar__user-role">' . sp_h(current_admin_role() ?? '') . '</div>';
    $html .= '</div></div>';

    // Logout form POST con CSRF
    $html .= '<form method="post" action="logout.php" class="sidebar__logout-form">';
    $html .= admin_csrf_field();
    $html .= '<button type="submit" class="sidebar__logout">Cerrar sesión</button>';
    $html .= '</form>';

    $html .= '</div>';
    $html .= '</aside>';
    return $html;
}

function admin_unresolved_alerts_count(): int {
    static $count = null;
    if ($count !== null) return $count;
    try {
        $count = (int)safeScalar($GLOBALS['admin_conn'],
            "SELECT COUNT(*) FROM system_alerts WHERE is_resolved = 0 AND severity IN ('critical','high')");
    } catch (Throwable $e) {
        $count = 0;
    }
    return $count;
}

function render_header(string $title, array $opts = []) {
    $currentSection = $opts['section'] ?? $_GET['section'] ?? 'dashboard';
    $flash = admin_render_flash();
    ?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="robots" content="noindex,nofollow">
    <title><?= sp_h($title) ?> · Saber+ Command Center</title>
    <link rel="stylesheet" href="<?= admin_asset_url('css/admin.css') ?>">
    <link rel="stylesheet" href="<?= admin_asset_url('css/components.css') ?>">
    <link rel="stylesheet" href="<?= admin_asset_url('css/dashboard.css') ?>">
</head>
<body>
<div class="app-shell">
    <?= render_sidebar($currentSection) ?>
    <div class="main-area">
        <header class="app-header">
            <button class="app-header__toggle" id="sidebarToggle" aria-label="Menú">☰</button>
            <h1 class="app-header__title"><?= sp_h($title) ?></h1>
            <div class="app-header__actions">
                <a href="<?= admin_section_url('alerts') ?>" class="header-action" title="Alertas">
                    🚨 <span id="headerAlertsCount"><?= admin_unresolved_alerts_count() ?></span>
                </a>
                <span class="header-action header-action--time" id="clock"><?= date('H:i') ?></span>
            </div>
        </header>
        <main class="app-content">
            <?= $flash ?>
    <?php
}

function render_footer() {
    ?>
        </main>
        <footer class="app-footer">
            <div>Saber+ Command Center · v3.0 · <?= date('Y') ?></div>
            <div class="app-footer__version">Sesión: <?= sp_h(current_admin_email() ?? '') ?></div>
        </footer>
    </div>
</div>
<script src="<?= admin_asset_url('js/admin.js') ?>"></script>
</body>
</html>
    <?php
}

// ── Flash messages ──

function admin_flash(string $type, string $message): void {
    if (!isset($_SESSION['admin_flash'])) $_SESSION['admin_flash'] = [];
    $_SESSION['admin_flash'][] = ['type' => $type, 'message' => $message];
}

function admin_render_flash(): string {
    if (empty($_SESSION['admin_flash'])) return '';
    $html = '';
    foreach ($_SESSION['admin_flash'] as $f) {
        $html .= sprintf(
            '<div class="flash flash--%s">%s<button class="flash__close" onclick="this.parentElement.remove()">×</button></div>',
            sp_h($f['type']), sp_h($f['message'])
        );
    }
    unset($_SESSION['admin_flash']);
    return $html;
}

// ── Página completa (helper) ──

function render_page(string $title, string $viewFile, array $data = []): string {
    // Extraer variables para la vista
    if (!empty($data)) extract($data, EXTR_SKIP);

    ob_start();
    render_header($title, ['section' => $_GET['section'] ?? 'dashboard']);
    require $viewFile;
    render_footer();
    return ob_get_clean();
}
