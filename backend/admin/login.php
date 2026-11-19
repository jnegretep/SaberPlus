<?php
declare(strict_types=1);

/**
 * SABER+ COMMAND CENTER — Login
 *
 * Login multi-admin con hash bcrypt y rate-limit.
 * Reemplaza el modelo anterior de ADMIN_USER/ADMIN_PASS en .env.
 *
 * Primera vez: la migración 010 crea el usuario 'jorge@saberplus.app'
 * con contraseña 'SaberPlus2026!' — DEBE cambiarse en el primer login.
 */

require_once __DIR__ . '/bootstrap.php';

// Si ya está logueado, ir al dashboard
if (!empty($_SESSION['admin_logged_in'])) {
    header('Location: index.php?section=dashboard');
    exit;
}

$error = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    admin_csrf_verify();

    $email = trim($_POST['email'] ?? '');
    $password = $_POST['password'] ?? '';

    $result = admin_login($conexion, $email, $password);

    if ($result['ok']) {
        // Auditar login exitoso
        admin_audit_log($conexion, 'login', 'admin_users', current_admin_id(), 'Login exitoso', 'auth');
        header('Location: index.php?section=dashboard');
        exit;
    } else {
        $error = $result['error'];
        // Auditar intento fallido (sin admin_user_id real)
        admin_audit_log($conexion, 'login_failed', 'admin_users', null,
            json_encode(['email' => $email, 'ip' => admin_client_ip()]), 'auth', null, null, false);
    }
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="robots" content="noindex,nofollow">
    <title>Acceso · Saber+ Command Center</title>
    <link rel="stylesheet" href="css/admin.css">
    <link rel="stylesheet" href="css/components.css">
</head>
<body>
<div class="login-shell">
    <div class="login-card">
        <div class="login-logo">S+</div>
        <h1 class="login-title">Command Center</h1>
        <p class="login-subtitle">Saber+ Executive Panel</p>

        <?php if ($error): ?>
            <div class="flash flash--error"><?= sp_h($error) ?></div>
        <?php endif; ?>

        <form method="post" action="login.php">
            <?= admin_csrf_field() ?>
            <div class="form-group">
                <label class="form-label" for="email">Email</label>
                <input type="email" id="email" name="email" class="form-input"
                       value="<?= sp_h($_POST['email'] ?? '') ?>"
                       required autofocus autocomplete="email">
            </div>
            <div class="form-group">
                <label class="form-label" for="password">Contraseña</label>
                <input type="password" id="password" name="password" class="form-input"
                       required autocomplete="current-password">
            </div>
            <button type="submit" class="btn btn--primary btn--block btn--lg">
                Acceder
            </button>
        </form>

        <p style="margin-top:24px;font-size:11px;color:#94A3B8;text-align:center;line-height:1.5;">
            Acceso restringido a administradores autorizados.<br>
            Todas las acciones quedan registradas en auditoría.
        </p>
    </div>
</div>
</body>
</html>