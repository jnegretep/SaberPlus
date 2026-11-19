<?php
declare(strict_types=1);

/**
 * SABER+ COMMAND CENTER — Logout
 * POST con CSRF. Evita CSRF-driven logout (vía GET).
 */

require_once __DIR__ . '/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    admin_csrf_verify();
    admin_audit_log($conexion, 'logout', 'admin_users', current_admin_id(), 'Logout', 'auth');
    admin_logout();
}

header('Location: login.php');
exit;
