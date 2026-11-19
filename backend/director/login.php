<?php
/**
 * login.php — Acceso al Panel del Director (Saber+)
 *
 * - Solo directores con activo = 1 pueden entrar.
 * - Rate-limit básico por sesión: máx. 5 fallos → bloqueo de 10 minutos.
 * - Tras un login exitoso: session_regenerate_id(true) + rotación del
 *   token CSRF + actualización de ultimo_login.
 */

require_once __DIR__ . '/includes/auth.php';

// ¿Ya hay una sesión de director válida y activa? → directo al dashboard
if (!empty($_SESSION['director_id'])) {
    try {
        $chk = $conexion->prepare("SELECT id FROM directores WHERE id = :id AND activo = 1 LIMIT 1");
        $chk->execute([':id' => (int)$_SESSION['director_id']]);
        if ($chk->fetch()) {
            header('Location: index.php');
            exit;
        }
    } catch (PDOException $ex) {
        error_log('[DIRECTOR] login (recheck): ' . $ex->getMessage());
    }
}

// ── Rate-limit: contador de fallos y lock por timestamp ──
$fallos    = (int)($_SESSION['dir_fallos'] ?? 0);
$lockHasta = (int)($_SESSION['dir_lock_hasta'] ?? 0);
$bloqueado = ($lockHasta > time());

$error = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && !$bloqueado) {
    $email    = trim((string)($_POST['email'] ?? ''));
    $password = (string)($_POST['password'] ?? '');

    if ($email === '' || $password === '') {
        $error = 'Ingresa tu correo y tu contraseña.';
    } else {
        try {
            $stmt = $conexion->prepare(
                "SELECT id, nombre, contrasena_hash
                 FROM directores
                 WHERE email = :email AND activo = 1
                 LIMIT 1"
            );
            $stmt->execute([':email' => $email]);
            $dir = $stmt->fetch(PDO::FETCH_ASSOC);

            if ($dir && password_verify($password, $dir['contrasena_hash'])) {
                // ✅ Login correcto: rotar ID de sesión y token CSRF
                session_regenerate_id(true);
                $_SESSION['director_id'] = (int)$dir['id'];
                $_SESSION['csrf'] = bin2hex(random_bytes(32));
                unset($_SESSION['dir_fallos'], $_SESSION['dir_lock_hasta']);

                $upd = $conexion->prepare("UPDATE directores SET ultimo_login = NOW() WHERE id = :id");
                $upd->execute([':id' => (int)$dir['id']]);

                header('Location: index.php');
                exit;
            }

            // ❌ Credencial inválida → contar el fallo
            $fallos++;
            $_SESSION['dir_fallos'] = $fallos;
            if ($fallos >= 5) {
                $_SESSION['dir_lock_hasta'] = time() + 600; // 10 minutos
                unset($_SESSION['dir_fallos']);
                $lockHasta = $_SESSION['dir_lock_hasta'];
                $bloqueado = true;
                $error = 'Demasiados intentos fallidos. Acceso bloqueado por 10 minutos.';
            } else {
                $error = 'Correo o contraseña incorrectos.';
            }
            error_log('[DIRECTOR] Login fallido (intento ' . $fallos . ') para: ' . $email);
        } catch (PDOException $ex) {
            error_log('[DIRECTOR] Error en login: ' . $ex->getMessage());
            $error = 'El panel no está disponible en este momento. Intenta más tarde.';
        }
    }
}

$minutosRestantes = $bloqueado ? max(1, (int)ceil(($lockHasta - time()) / 60)) : 0;
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Acceso Director — Saber+</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: linear-gradient(135deg, #1E4ED8 0%, #3B82F6 100%); min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px; }
        .login-card { background: white; border-radius: 24px; padding: 40px; width: 100%; max-width: 420px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); }
        .logo { text-align: center; margin-bottom: 24px; }
        .logo img { width: 76px; height: 76px; object-fit: contain; border-radius: 18px; background: #EFF6FF; padding: 8px; }
        .logo h1 { display: none; font-size: 28px; font-weight: 800; color: #1E4ED8; }
        .logo.sin-logo img { display: none; }
        .logo.sin-logo h1 { display: block; }
        .logo p { font-size: 13px; color: #999; margin-top: 10px; }
        .form-group { margin-bottom: 16px; }
        label { display: block; font-size: 14px; font-weight: 600; color: #555; margin-bottom: 6px; }
        input { width: 100%; padding: 12px 16px; border: 2px solid #e2e8f0; border-radius: 12px; font-size: 15px; font-family: inherit; }
        input:focus { outline: none; border-color: #1E4ED8; }
        .btn-login { width: 100%; padding: 14px; background: #1E4ED8; color: white; border: none; border-radius: 12px; font-size: 16px; font-weight: 700; cursor: pointer; transition: 0.2s; font-family: inherit; }
        .btn-login:hover { background: #1E3A8A; }
        .btn-login:disabled { background: #94A3B8; cursor: not-allowed; }
        .error { color: #EF4444; font-size: 14px; margin-bottom: 16px; text-align: center; background: #FEE2E2; border-radius: 10px; padding: 10px 14px; }
        .foot { text-align: center; font-size: 12px; color: #94A3B8; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="login-card">
        <div class="logo" id="logoBox">
            <img src="../logo.jpg" alt="Saber+" onerror="document.getElementById('logoBox').classList.add('sin-logo')">
            <h1>Saber+</h1>
            <p>Panel del Director</p>
        </div>

        <?php if ($bloqueado): ?>
            <div class="error">Acceso bloqueado temporalmente. Intenta de nuevo en <?= $minutosRestantes ?> minuto(s).</div>
        <?php elseif ($error !== ''): ?>
            <div class="error"><?= htmlspecialchars($error, ENT_QUOTES, 'UTF-8') ?></div>
        <?php endif; ?>

        <form method="POST" action="login.php">
            <div class="form-group">
                <label for="email">Correo electrónico</label>
                <input type="email" id="email" name="email" required autofocus autocomplete="email" placeholder="director@colegio.edu.co">
            </div>
            <div class="form-group">
                <label for="password">Contraseña</label>
                <input type="password" id="password" name="password" required autocomplete="current-password">
            </div>
            <button type="submit" class="btn-login"<?= $bloqueado ? ' disabled' : '' ?>>Ingresar</button>
        </form>

        <p class="foot">¿Problemas para ingresar? Contacta al administrador de Saber+.</p>
    </div>
</body>
</html>
