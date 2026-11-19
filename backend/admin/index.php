<?php
declare(strict_types=1);

/**
 * SABER+ COMMAND CENTER — Router principal
 *
 * Punto de entrada único del panel. Lee ?section= y delega al controlador
 * correspondiente en sections/[modulo]/controller.php
 *
 * El legacy admin/index.php original queda en index.legacy.php para referencia.
 */

require_once __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/includes/layout.php';

// Auth: si no logueado, redirect a login
require_admin_auth();

// Resolver sección solicitada
$section = $_GET['section'] ?? 'dashboard';
$section = preg_replace('/[^a-z0-9_]/', '', $section);

// Whitelist de secciones válidas
$validSections = [
    'dashboard', 'users', 'plans', 'feature_flags', 'gamification', 'content',
    'ai', 'communications', 'alerts', 'system', 'audit', 'exports',
];

if (!in_array($section, $validSections, true)) {
    $section = 'dashboard';
}

$sectionFile = __DIR__ . "/sections/$section/controller.php";

if (!file_exists($sectionFile)) {
    http_response_code(404);
    require_admin_auth();
    render_header('Sección no encontrada');
    echo '<div class="empty-state">';
    echo '<div class="empty-state__icon">🔍</div>';
    echo '<div class="empty-state__title">Sección no implementada</div>';
    echo '<div class="empty-state__message">La sección <code>' . sp_h($section) . '</code> aún no está disponible.</div>';
    echo '<p style="margin-top:16px"><a href="index.php?section=dashboard" class="btn btn--primary">Volver al Dashboard</a></p>';
    echo '</div>';
    render_footer();
    exit;
}

// El controlador de sección se encarga de procesar POST, preparar datos
// y llamar a render_header/render_footer + incluir view.php
require $sectionFile;
