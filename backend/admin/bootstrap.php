<?php
declare(strict_types=1);

/**
 * SABER+ COMMAND CENTER — Bootstrap
 *
 * Punto de entrada común para TODOS los scripts del nuevo panel admin.
 * Carga:
 *  - Composer autoload
 *  - Conexión BD (PDO)
 *  - Configuración centralizada
 *  - Helper de auditoría
 *  - Helpers compartidos (sp_h, safeStat, etc.)
 *  - Headers de seguridad HTTP
 *  - Sesión PHP hardenizada
 *  - Middleware de autenticación + RBAC
 *
 * Uso:
 *   require_once __DIR__ . '/bootstrap.php';
 *   require_permission('users.read');
 *   // ... lógica del script
 */

// ── 1. Cargar dependencias ──
require_once __DIR__ . '/../vendor/autoload.php';
require_once __DIR__ . '/../includes/conexion.php';
require_once __DIR__ . '/../includes/config.php';
require_once __DIR__ . '/../includes/moodle.php';
require_once __DIR__ . '/../env.php';

// Helpers compartidos
require_once __DIR__ . '/includes/admin_helpers.php';
require_once __DIR__ . '/includes/admin_auth.php';
require_once __DIR__ . '/includes/admin_audit.php';
require_once __DIR__ . '/includes/admin_security_headers.php';

// ── 2. Headers de seguridad HTTP (antes de cualquier output) ──
admin_security_headers();

// ── 3. Sesión PHP hardenizada ──
if (session_status() === PHP_SESSION_NONE) {
    session_set_cookie_params([
        'lifetime'     => 0,
        'httponly'     => true,
        'secure'       => isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off',
        'samesite'     => 'Lax',
    ]);
    session_name('SABERPLUS_ADMIN');
    session_start();
}

// ── 4. CSRF helper (necesario para cualquier form POST) ──
// Definido en admin_helpers.php: admin_csrf_field(), admin_csrf_verify()

// ── 5. CSRF check automático para POST ──
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Endpoints API REST aceptan JSON; validan CSRF aparte vía X-CSRF-Token
    // Para formularios HTML clásicos, verificamos automáticamente.
    $isApiCall = (
        isset($_SERVER['CONTENT_TYPE']) &&
        stripos($_SERVER['CONTENT_TYPE'], 'application/json') !== false
    );
    if (!$isApiCall) {
        admin_csrf_verify();
    }
}

// ── 6. Rate-limit login (helper) ──
// Definido en admin_auth.php: admin_login_rate_limit_*

// ── 7. Exponer variables globales convenientes ──
$GLOBALS['admin_conn'] = $conexion;  // alias corto
