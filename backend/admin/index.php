<?php
/**
 * admin/index.php - Saber+ Panel de Administracion
 */

session_start();

require_once __DIR__ . '/../includes/conexion.php';
require_once __DIR__ . '/../includes/config.php';
require_once __DIR__ . '/../env.php';

// ── Configuracion de acceso admin (desde backend/.env) ──
$ADMIN_USER = env('ADMIN_USER', '');
$ADMIN_PASS = env('ADMIN_PASS', '');

// Fail-closed: sin credenciales configuradas, el panel queda cerrado
if ($ADMIN_USER === '' || $ADMIN_PASS === '') {
    http_response_code(503);
    exit('Panel de administracion no configurado. Define ADMIN_USER y ADMIN_PASS en backend/.env');
}

// ── Login ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['login'])) {
    $user = $_POST['username'] ?? '';
    $pass = $_POST['password'] ?? '';

    if ($user === $ADMIN_USER && $pass === $ADMIN_PASS) {
        $_SESSION['admin_logged_in'] = true;
        header('Location: index.php');
        exit;
    } else {
        $loginError = 'Credenciales incorrectas';
    }
}

// ── Logout ──
if (isset($_GET['logout'])) {
    session_destroy();
    header('Location: index.php');
    exit;
}

// ── Verificar sesion ──
if (!isset($_SESSION['admin_logged_in']) || $_SESSION['admin_logged_in'] !== true) {
    ?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Saber+ Admin - Login</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; display: flex; align-items: center; justify-content: center; }
        .login-card { background: white; border-radius: 24px; padding: 40px; width: 100%; max-width: 400px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); }
        .logo { text-align: center; margin-bottom: 24px; }
        .logo h1 { font-size: 28px; font-weight: 800; color: #1E4ED8; }
        .logo p { font-size: 13px; color: #999; }
        .form-group { margin-bottom: 16px; }
        label { display: block; font-size: 14px; font-weight: 600; color: #555; margin-bottom: 6px; }
        input { width: 100%; padding: 12px 16px; border: 2px solid #e2e8f0; border-radius: 12px; font-size: 15px; }
        input:focus { outline: none; border-color: #1E4ED8; }
        .btn-login { width: 100%; padding: 14px; background: #1E4ED8; color: white; border: none; border-radius: 12px; font-size: 16px; font-weight: 700; cursor: pointer; transition: 0.2s; }
        .btn-login:hover { background: #1E3A8A; }
        .error { color: #EF4444; font-size: 14px; margin-bottom: 16px; text-align: center; }
    </style>
</head>
<body>
    <div class="login-card">
        <div class="logo">
            <h1>Saber+ Admin</h1>
            <p>Panel de Administracion</p>
        </div>
        <?php if (isset($loginError)): ?>
            <div class="error"><?= htmlspecialchars($loginError) ?></div>
        <?php endif; ?>
        <form method="POST">
            <div class="form-group">
                <label>Usuario</label>
                <input type="text" name="username" required autofocus>
            </div>
            <div class="form-group">
                <label>Contraseña</label>
                <input type="password" name="password" required>
            </div>
            <button type="submit" name="login" class="btn-login">Ingresar</button>
        </form>
    </div>
</body>
</html>
    <?php
    exit;
}

// ── Router de secciones ──
 $section = $_GET['section'] ?? 'dashboard';

// ── Acciones POST del admin (v1.6.0) ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['resolve_error'])) {
    $errId = (int)$_POST['resolve_error'];
    try {
        $stmt = $conexion->prepare("UPDATE error_logs SET resolved = 1 WHERE id = ?");
        $stmt->execute([$errId]);
    } catch (Exception $e) {
        error_log('[ADMIN] resolve_error: ' . $e->getMessage());
    }
    header('Location: index.php?section=errors');
    exit;
}

// ── CSRF del panel admin (formularios de la sección Colegios, v1.7.0 B2B) ──
if (empty($_SESSION['admin_csrf'])) {
    $_SESSION['admin_csrf'] = bin2hex(random_bytes(32));
}

function admin_csrf_field(): string
{
    return '<input type="hidden" name="csrf" value="' . htmlspecialchars($_SESSION['admin_csrf'], ENT_QUOTES, 'UTF-8') . '">';
}

function admin_csrf_verify(): void
{
    $token = (string)($_POST['csrf'] ?? '');
    if ($token === '' || !hash_equals($_SESSION['admin_csrf'], $token)) {
        http_response_code(403);
        exit('Token CSRF invalido');
    }
}

// ── Sección Colegios (B2B): crear director ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['crear_director'])) {
    admin_csrf_verify();
    $nombre     = trim((string)($_POST['nombre'] ?? ''));
    $email      = strtolower(trim((string)($_POST['email'] ?? '')));
    $colegioDir = trim((string)($_POST['colegio'] ?? ''));
    $telefono   = trim((string)($_POST['telefono'] ?? ''));
    $password   = (string)($_POST['password'] ?? '');

    if ($nombre === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)
        || $colegioDir === '' || strlen($password) < 8) {
        header('Location: index.php?section=colegios&msg=datos_invalidos');
        exit;
    }
    try {
        $ins = $conexion->prepare("
            INSERT INTO directores (nombre, email, contrasena_hash, colegio, telefono)
            VALUES (:n, :e, :p, :c, :t)
        ");
        $ins->execute([
            ':n' => $nombre,
            ':e' => $email,
            ':p' => password_hash($password, PASSWORD_DEFAULT),
            ':c' => $colegioDir,
            ':t' => ($telefono !== '' ? $telefono : null),
        ]);
        header('Location: index.php?section=colegios&msg=director_creado');
        exit;
    } catch (PDOException $ex) {
        if ($ex->getCode() === '23000') {
            header('Location: index.php?section=colegios&msg=email_duplicado');
            exit;
        }
        error_log('[ADMIN] crear_director: ' . $ex->getMessage());
        header('Location: index.php?section=colegios&msg=error_bd');
        exit;
    }
}

// ── Sección Colegios (B2B): activar/desactivar director ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['toggle_director'])) {
    admin_csrf_verify();
    $idDirector = (int)($_POST['director_id'] ?? 0);
    try {
        $stmt = $conexion->prepare("UPDATE directores SET activo = 1 - activo WHERE id = :id");
        $stmt->execute([':id' => $idDirector]);
    } catch (PDOException $ex) {
        error_log('[ADMIN] toggle_director: ' . $ex->getMessage());
    }
    header('Location: index.php?section=colegios&msg=estado_actualizado');
    exit;
}

// ── Sección Colegios (B2B): reset de contraseña de director ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['reset_director_pass'])) {
    admin_csrf_verify();
    $idDirector = (int)($_POST['director_id'] ?? 0);
    $pool = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    $nueva = '';
    for ($i = 0; $i < 12; $i++) {
        $nueva .= $pool[random_int(0, strlen($pool) - 1)];
    }
    try {
        $stmt = $conexion->prepare("UPDATE directores SET contrasena_hash = :h WHERE id = :id");
        $stmt->execute([':h' => password_hash($nueva, PASSWORD_DEFAULT), ':id' => $idDirector]);
        $_SESSION['admin_flash_pass'] = ['id' => $idDirector, 'pass' => $nueva];
    } catch (PDOException $ex) {
        error_log('[ADMIN] reset_director_pass: ' . $ex->getMessage());
    }
    header('Location: index.php?section=colegios&msg=pass_reset');
    exit;
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN PROMOCIONES (v1.7.0): crear / editar / activar / eliminar
// ═══════════════════════════════════════════════════════════════

// ── Promociones: guardar (crear o actualizar) ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['promo_save'])) {
    admin_csrf_verify();
    $id          = (int)($_POST['promo_id'] ?? 0);
    $titulo      = trim((string)($_POST['titulo'] ?? ''));
    $descripcion = mb_substr(trim((string)($_POST['descripcion'] ?? '')), 0, 255);
    $tipo        = in_array($_POST['tipo'] ?? '', ['banner', 'codigo'], true) ? $_POST['tipo'] : 'banner';
    $codigo      = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string)($_POST['codigo'] ?? '')));
    $dtoTipo     = ($_POST['descuento_tipo'] ?? '') === 'monto' ? 'monto' : 'porcentaje';
    $dtoValor    = (float)($_POST['descuento_valor'] ?? 0);
    $planId      = (int)($_POST['plan_id'] ?? 0);
    $fechaInicio = (string)($_POST['fecha_inicio'] ?? '');
    $fechaFin    = (string)($_POST['fecha_fin'] ?? '');
    $maxUsos     = trim((string)($_POST['max_usos'] ?? ''));
    $activo      = isset($_POST['activo']) ? 1 : 0;

    $errores = [];
    if ($titulo === '')                              $errores[] = 'titulo';
    if ($dtoValor <= 0)                              $errores[] = 'descuento';
    if ($dtoTipo === 'porcentaje' && $dtoValor > 100) $errores[] = 'descuento';
    if ($tipo === 'codigo' && strlen($codigo) < 4)    $errores[] = 'codigo';
    $tsIni = strtotime($fechaInicio);
    $tsFin = strtotime($fechaFin);
    if ($tsIni === false || $tsFin === false || $tsFin <= $tsIni) $errores[] = 'fechas';

    if (!empty($errores)) {
        header('Location: index.php?section=promociones&msg=promo_datos_invalidos');
        exit;
    }

    $fechaInicio = date('Y-m-d H:i:s', $tsIni);
    $fechaFin    = date('Y-m-d H:i:s', $tsFin);
    $planIdSql   = $planId > 0 ? $planId : null;
    $maxUsosSql  = ($maxUsos !== '' && (int)$maxUsos > 0) ? (int)$maxUsos : null;

    try {
        if ($id > 0) {
            $stmt = $conexion->prepare("
                UPDATE promociones SET
                    titulo = :t, descripcion = :d, tipo = :ti, codigo = :c,
                    descuento_tipo = :dt, descuento_valor = :dv, plan_id = :p,
                    fecha_inicio = :fi, fecha_fin = :ff, max_usos = :mu, activo = :a
                WHERE id = :id
            ");
            $stmt->execute([
                ':t' => $titulo, ':d' => ($descripcion !== '' ? $descripcion : null),
                ':ti' => $tipo, ':c' => ($tipo === 'codigo' ? $codigo : null),
                ':dt' => $dtoTipo, ':dv' => $dtoValor, ':p' => $planIdSql,
                ':fi' => $fechaInicio, ':ff' => $fechaFin, ':mu' => $maxUsosSql,
                ':a' => $activo, ':id' => $id,
            ]);
            header('Location: index.php?section=promociones&msg=promo_actualizada');
        } else {
            $stmt = $conexion->prepare("
                INSERT INTO promociones
                    (titulo, descripcion, tipo, codigo, descuento_tipo, descuento_valor,
                     plan_id, fecha_inicio, fecha_fin, max_usos, activo)
                VALUES
                    (:t, :d, :ti, :c, :dt, :dv, :p, :fi, :ff, :mu, :a)
            ");
            $stmt->execute([
                ':t' => $titulo, ':d' => ($descripcion !== '' ? $descripcion : null),
                ':ti' => $tipo, ':c' => ($tipo === 'codigo' ? $codigo : null),
                ':dt' => $dtoTipo, ':dv' => $dtoValor, ':p' => $planIdSql,
                ':fi' => $fechaInicio, ':ff' => $fechaFin, ':mu' => $maxUsosSql,
                ':a' => $activo,
            ]);
            header('Location: index.php?section=promociones&msg=promo_creada');
        }
        exit;
    } catch (PDOException $ex) {
        if ($ex->getCode() === '23000') {
            header('Location: index.php?section=promociones&msg=promo_codigo_duplicado');
            exit;
        }
        error_log('[ADMIN] promo_save: ' . $ex->getMessage());
        header('Location: index.php?section=promociones&msg=promo_error_bd');
        exit;
    }
}

// ── Promociones: activar/desactivar ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['promo_toggle'])) {
    admin_csrf_verify();
    try {
        $stmt = $conexion->prepare("UPDATE promociones SET activo = 1 - activo WHERE id = :id");
        $stmt->execute([':id' => (int)($_POST['promo_id'] ?? 0)]);
    } catch (PDOException $ex) {
        error_log('[ADMIN] promo_toggle: ' . $ex->getMessage());
    }
    header('Location: index.php?section=promociones&msg=promo_estado');
    exit;
}

// ── Promociones: eliminar ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['promo_delete'])) {
    admin_csrf_verify();
    try {
        $stmt = $conexion->prepare("DELETE FROM promociones WHERE id = :id");
        $stmt->execute([':id' => (int)($_POST['promo_id'] ?? 0)]);
    } catch (PDOException $ex) {
        error_log('[ADMIN] promo_delete: ' . $ex->getMessage());
    }
    header('Location: index.php?section=promociones&msg=promo_eliminada');
    exit;
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN SOPORTE (v1.7.0): responder / cambiar estado de quejas
// ═══════════════════════════════════════════════════════════════
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['queja_update'])) {
    admin_csrf_verify();
    $id        = (int)($_POST['queja_id'] ?? 0);
    $respuesta = trim((string)($_POST['respuesta'] ?? ''));
    $estado    = in_array($_POST['estado'] ?? '', ['nuevo', 'en_proceso', 'resuelto', 'descartado'], true)
        ? $_POST['estado'] : 'en_proceso';

    if ($id > 0) {
        try {
            $stmt = $conexion->prepare("
                UPDATE quejas_sugerencias
                SET estado = :e,
                    respuesta_admin = :r
                WHERE id = :id
            ");
            $stmt->execute([
                ':e' => $estado,
                ':r' => ($respuesta !== '' ? mb_substr($respuesta, 0, 2000) : null),
                ':id' => $id,
            ]);
            header('Location: index.php?section=soporte&msg=queja_actualizada&view=' . $id);
            exit;
        } catch (PDOException $ex) {
            error_log('[ADMIN] queja_update: ' . $ex->getMessage());
            header('Location: index.php?section=soporte&msg=queja_error');
            exit;
        }
    }
    header('Location: index.php?section=soporte');
    exit;
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN USUARIOS (v1.7.0): editar perfil de cualquier usuario
// ═══════════════════════════════════════════════════════════════
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['user_save'])) {
    admin_csrf_verify();
    $idUsuario = (int)($_POST['user_id'] ?? 0);

    $nombre       = trim((string)($_POST['nombre'] ?? ''));
    $email        = strtolower(trim((string)($_POST['email'] ?? '')));
    $telefono     = trim((string)($_POST['telefono'] ?? ''));
    $departamento = trim((string)($_POST['departamento'] ?? ''));
    $ciudad       = trim((string)($_POST['ciudad'] ?? ''));
    $colegio      = trim((string)($_POST['colegio'] ?? ''));
    $grado        = trim((string)($_POST['grado'] ?? ''));

    $tiposValidos  = ['estudiante', 'profesor', 'admin'];
    $nivelesValidos = ['free', 'premium', 'early_bird'];
    $tipoUsuario   = in_array($_POST['tipo_usuario'] ?? '', $tiposValidos, true) ? $_POST['tipo_usuario'] : 'estudiante';
    $accessLevel   = in_array($_POST['access_level'] ?? '', $nivelesValidos, true) ? $_POST['access_level'] : 'free';
    $emailVerif    = isset($_POST['email_verificado']) ? 1 : 0;
    $activo        = isset($_POST['activo']) ? 1 : 0;

    if ($idUsuario <= 0 || $nombre === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
        header('Location: index.php?section=users&msg=user_datos_invalidos');
        exit;
    }

    try {
        $stmt = $conexion->prepare("
            UPDATE usuarios SET
                nombre = :n, email = :e, telefono = :t, departamento = :dep,
                ciudad = :c, colegio = :col, grado = :g,
                tipo_usuario = :tu, access_level = :al, email_verificado = :ev
            WHERE id_usuario = :id
        ");
        $stmt->execute([
            ':n' => $nombre, ':e' => $email,
            ':t' => ($telefono !== '' ? $telefono : null),
            ':dep' => ($departamento !== '' ? $departamento : null),
            ':c' => ($ciudad !== '' ? $ciudad : null),
            ':col' => ($colegio !== '' ? $colegio : null),
            ':g' => ($grado !== '' ? $grado : null),
            ':tu' => $tipoUsuario, ':al' => $accessLevel, ':ev' => $emailVerif,
            ':id' => $idUsuario,
        ]);

        // Columna activo (migración 005): puede no existir aún → reintento sin ella
        try {
            $stmtA = $conexion->prepare("UPDATE usuarios SET activo = :a WHERE id_usuario = :id");
            $stmtA->execute([':a' => $activo, ':id' => $idUsuario]);
        } catch (PDOException $exA) {
            error_log('[ADMIN] user_save activo (columna inexistente): ' . $exA->getMessage());
        }

        header('Location: index.php?section=users&edit=' . $idUsuario . '&msg=user_guardado');
        exit;
    } catch (PDOException $ex) {
        if ($ex->getCode() === '23000') {
            header('Location: index.php?section=users&edit=' . $idUsuario . '&msg=user_email_duplicado');
            exit;
        }
        error_log('[ADMIN] user_save: ' . $ex->getMessage());
        header('Location: index.php?section=users&edit=' . $idUsuario . '&msg=user_error_bd');
        exit;
    }
}

// ── Obtener estadisticas globales ──
// 🔧 FIX: cada stat en su propio try/catch. Si una query falla (columna
// inexistente, tabla ausente, etc.), las demás siguen calculándose en
// lugar de dejar todo el array $stats vacío.
$stats = [];

$safeStat = function (string $key, callable $fn, $default = 0) use (&$stats) {
    try {
        $stats[$key] = $fn();
    } catch (Throwable $e) {
        error_log("[ADMIN] stat '$key' falló: " . $e->getMessage());
        $stats[$key] = $default;
    }
};

$safeStat('total_users', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE email_verificado = 1")->fetchColumn());

$safeStat('active_users_7d', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE ultimo_login >= DATE_SUB(NOW(), INTERVAL 7 DAY)")->fetchColumn());

$safeStat('active_users_today', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE ultimo_login >= CURDATE()")->fetchColumn());

$safeStat('total_simulacros', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM simulacro_resultados")->fetchColumn());

$safeStat('avg_score', fn() =>
    round((float)$conexion->query("SELECT AVG(puntaje_global) FROM simulacro_resultados")->fetchColumn(), 1));

$safeStat('premium_users', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE access_level IN ('premium', 'early_bird')")->fetchColumn());

$safeStat('free_users', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE access_level = 'free'")->fetchColumn());

// 🔧 FIX: la tabla `challenges` usa `status` (enum en español), no `estado`.
// Valores válidos: 'pendiente','en_curso','finalizado','eliminado'.
$safeStat('total_challenges', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM challenges WHERE status = 'finalizado'")->fetchColumn());

$safeStat('total_xp', fn() =>
    (int)$conexion->query("SELECT COALESCE(SUM(total_xp), 0) FROM user_gamification")->fetchColumn());

$safeStat('notifications_today', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM notifications WHERE DATE(created_at) = CURDATE()")->fetchColumn());

$safeStat('new_users_today', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE DATE(registration_date) = CURDATE()")->fetchColumn());

$safeStat('new_users_week', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE registration_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)")->fetchColumn());
?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Saber+ Admin</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f4f6fa; color: #1a1a2e; }
        .sidebar { position: fixed; left: 0; top: 0; width: 240px; height: 100vh; background: #1E4ED8; color: white; padding: 24px 0; overflow-y: auto; z-index: 100; }
        .sidebar-header { text-align: center; margin-bottom: 32px; }
        .sidebar-header h1 { font-size: 22px; font-weight: 800; }
        .sidebar-header p { font-size: 11px; opacity: 0.7; }
        .nav-item { display: flex; align-items: center; gap: 12px; padding: 12px 24px; color: rgba(255,255,255,0.8); text-decoration: none; font-size: 14px; font-weight: 500; transition: 0.2s; border-left: 3px solid transparent; }
        .nav-item:hover, .nav-item.active { background: rgba(255,255,255,0.1); color: white; border-left-color: #FACC15; }
        .nav-icon { font-size: 18px; width: 24px; text-align: center; }
        .main-content { margin-left: 240px; padding: 32px; min-height: 100vh; }
        .header-bar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 32px; }
        .header-bar h2 { font-size: 24px; font-weight: 800; }
        .logout-btn { background: #EF4444; color: white; padding: 8px 16px; border-radius: 8px; text-decoration: none; font-size: 13px; font-weight: 600; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; margin-bottom: 32px; }
        .stat-card { background: white; border-radius: 16px; padding: 24px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }
        .stat-card .stat-icon { width: 48px; height: 48px; border-radius: 12px; display: flex; align-items: center; justify-content: center; font-size: 24px; margin-bottom: 12px; }
        .stat-card .stat-value { font-size: 32px; font-weight: 800; }
        .stat-card .stat-label { font-size: 13px; color: #888; margin-top: 4px; }
        .stat-card .stat-change { font-size: 12px; margin-top: 8px; }
        .stat-up { color: #22C55E; }
        .stat-down { color: #EF4444; }
        .table-container { background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.06); margin-bottom: 24px; }
        table { width: 100%; border-collapse: collapse; }
        th { background: #f8fafc; padding: 12px 16px; text-align: left; font-size: 12px; font-weight: 700; color: #64748b; text-transform: uppercase; }
        td { padding: 12px 16px; border-top: 1px solid #f1f5f9; font-size: 14px; }
        tr:hover td { background: #f8fafc; }
        .badge { display: inline-block; padding: 4px 10px; border-radius: 20px; font-size: 11px; font-weight: 700; }
        .badge-green { background: #D1FAE5; color: #065F46; }
        .badge-blue { background: #DBEAFE; color: #1E40AF; }
        .badge-orange { background: #FED7AA; color: #9A3412; }
        .badge-purple { background: #E9D5FF; color: #6B21A8; }
        .section-card { background: white; border-radius: 16px; padding: 24px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); margin-bottom: 24px; }
        .section-title { font-size: 18px; font-weight: 700; margin-bottom: 16px; }
        .btn { display: inline-block; padding: 10px 20px; border-radius: 10px; font-size: 14px; font-weight: 600; text-decoration: none; cursor: pointer; border: none; transition: 0.2s; }
        .btn-primary { background: #1E4ED8; color: white; }
        .btn-success { background: #22C55E; color: white; }
        .btn-danger { background: #EF4444; color: white; }
        .btn:hover { opacity: 0.9; }
        .form-group { margin-bottom: 16px; }
        .form-group label { display: block; font-size: 13px; font-weight: 600; margin-bottom: 6px; color: #555; }
        .form-group input, .form-group select, .form-group textarea { width: 100%; padding: 10px 14px; border: 2px solid #e2e8f0; border-radius: 10px; font-size: 14px; }
        .form-group input:focus, .form-group select:focus { outline: none; border-color: #1E4ED8; }
        .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }
        .badge-red { background: #FEE2E2; color: #991B1B; }
        .badge-gray { background: #E5E7EB; color: #374151; }
        .badge-yellow { background: #FEF3C7; color: #92400E; }
        .mono { font-family: ui-monospace, 'SF Mono', Menlo, Consolas, monospace; font-size: 12px; }
        .bar-row { display: flex; align-items: center; gap: 10px; margin-bottom: 6px; }
        .bar-label { width: 84px; font-size: 12px; color: #64748b; text-align: right; flex-shrink: 0; }
        .bar-track { flex: 1; background: #f1f5f9; border-radius: 6px; height: 18px; overflow: hidden; }
        .bar-fill { height: 100%; background: #1E4ED8; border-radius: 6px; min-width: 2px; }
        .bar-fill.green { background: #22C55E; }
        .bar-value { width: 46px; font-size: 12px; font-weight: 700; color: #334155; flex-shrink: 0; }
        .muted { color: #94A3B8; font-size: 13px; }
        .flash { padding: 12px 18px; border-radius: 12px; margin-bottom: 20px; font-size: 14px; font-weight: 600; }
        .flash-ok { background: #D1FAE5; color: #065F46; }
        .flash-err { background: #FEE2E2; color: #991B1B; }
        @media (max-width: 768px) { .sidebar { display: none; } .main-content { margin-left: 0; padding: 16px; } .grid-2 { grid-template-columns: 1fr; } }
    </style>
</head>
<body>

<!-- Sidebar -->
<div class="sidebar">
    <div class="sidebar-header">
        <h1>Saber+</h1>
        <p>Panel Admin</p>
    </div>
    <a href="index.php" class="nav-item <?= $section === 'dashboard' ? 'active' : '' ?>"><span class="nav-icon">&#128202;</span> Dashboard</a>
    <a href="index.php?section=users" class="nav-item <?= $section === 'users' ? 'active' : '' ?>"><span class="nav-icon">&#128100;</span> Usuarios</a>
    <a href="index.php?section=colegios" class="nav-item <?= $section === 'colegios' ? 'active' : '' ?>"><span class="nav-icon">&#127979;</span> Colegios</a>
    <a href="index.php?section=ads" class="nav-item <?= $section === 'ads' ? 'active' : '' ?>"><span class="nav-icon">&#128227;</span> Anuncios</a>
    <a href="index.php?section=plans" class="nav-item <?= $section === 'plans' ? 'active' : '' ?>"><span class="nav-icon">&#128179;</span> Planes</a>
    <a href="index.php?section=promociones" class="nav-item <?= $section === 'promociones' ? 'active' : '' ?>"><span class="nav-icon">&#127873;</span> Promociones</a>
    <a href="index.php?section=notifications" class="nav-item <?= $section === 'notifications' ? 'active' : '' ?>"><span class="nav-icon">&#128276;</span> Notificaciones</a>
    <a href="index.php?section=soporte" class="nav-item <?= $section === 'soporte' ? 'active' : '' ?>"><span class="nav-icon">&#128172;</span> Soporte</a>
    <a href="index.php?section=analytics" class="nav-item <?= $section === 'analytics' ? 'active' : '' ?>"><span class="nav-icon">&#128200;</span> Analítica</a>
    <a href="index.php?section=errors" class="nav-item <?= $section === 'errors' ? 'active' : '' ?>"><span class="nav-icon">&#9888;</span> Errores</a>
    <a href="index.php?section=activity" class="nav-item <?= $section === 'activity' ? 'active' : '' ?>"><span class="nav-icon">&#128293;</span> Actividad</a>
    <a href="index.php?section=rankings" class="nav-item <?= $section === 'rankings' ? 'active' : '' ?>"><span class="nav-icon">&#127942;</span> Rankings Inst.</a>
    <a href="index.php?section=reports" class="nav-item <?= $section === 'reports' ? 'active' : '' ?>"><span class="nav-icon">&#128196;</span> Reportes</a>
    <a href="index.php?logout=1" class="nav-item" style="margin-top: 32px; color: rgba(255,255,255,0.5);"><span class="nav-icon">&#10148;</span> Cerrar Sesion</a>
</div>

<!-- Main Content -->
<div class="main-content">
    <div class="header-bar">
        <h2><?= ucfirst($section === 'dashboard' ? 'Dashboard' : $section) ?></h2>
        <a href="index.php?logout=1" class="logout-btn">Cerrar Sesion</a>
    </div>

    <?php if ($section === 'dashboard'): ?>
        <!-- DASHBOARD -->
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-icon" style="background: #DBEAFE;">&#128100;</div>
                <div class="stat-value"><?= $stats['total_users'] ?></div>
                <div class="stat-label">Usuarios Registrados</div>
                <div class="stat-change stat-up">+<?= $stats['new_users_week'] ?> esta semana</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #D1FAE5;">&#128640;</div>
                <div class="stat-value"><?= $stats['active_users_today'] ?></div>
                <div class="stat-label">Activos Hoy</div>
                <div class="stat-change">Activos 7 dias: <?= $stats['active_users_7d'] ?></div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #FEF3C7;">&#128221;</div>
                <div class="stat-value"><?= $stats['total_simulacros'] ?></div>
                <div class="stat-label">Simulacros Realizados</div>
                <div class="stat-change">Promedio: <?= $stats['avg_score'] ?></div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #E9D5FF;">&#11088;</div>
                <div class="stat-value"><?= $stats['premium_users'] ?></div>
                <div class="stat-label">Usuarios Premium</div>
                <div class="stat-change">Free: <?= $stats['free_users'] ?></div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #FED7AA;">&#9889;</div>
                <div class="stat-value"><?= number_format($stats['total_xp']) ?></div>
                <div class="stat-label">XP Distribuida</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #FEE2E2;">&#128276;</div>
                <div class="stat-value"><?= $stats['notifications_today'] ?></div>
                <div class="stat-label">Notificaciones Hoy</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #DBEAFE;">&#128101;</div>
                <div class="stat-value"><?= $stats['new_users_today'] ?></div>
                <div class="stat-label">Nuevos Hoy</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #D1FAE5;">&#127942;</div>
                <div class="stat-value"><?= $stats['total_challenges'] ?></div>
                <div class="stat-label">Retos Completados</div>
            </div>
        </div>

        <!-- Top 10 usuarios -->
        <div class="table-container">
            <table>
                <thead><tr><th>#</th><th>Usuario</th><th>Email</th><th>XP</th><th>Nivel</th><th>Racha</th><th>Plan</th><th>Ultimo Login</th></tr></thead>
                <tbody>
                <?php
                $topUsers = $conexion->query("
                    SELECT u.nombre, u.email, u.access_level, u.ultimo_login,
                           COALESCE(ug.total_xp, 0) as xp, COALESCE(ug.current_level, 1) as level,
                           COALESCE(ug.current_streak, 0) as streak
                    FROM usuarios u
                    LEFT JOIN user_gamification ug ON u.id_usuario = ug.user_id
                    WHERE u.email_verificado = 1
                    ORDER BY xp DESC LIMIT 10
                ")->fetchAll(PDO::FETCH_ASSOC);
                foreach ($topUsers as $i => $u):
                ?>
                    <tr>
                        <td><?= $i + 1 ?></td>
                        <td><?= htmlspecialchars($u['nombre']) ?></td>
                        <td><?= htmlspecialchars($u['email']) ?></td>
                        <td><strong><?= number_format($u['xp']) ?></strong></td>
                        <td>Nivel <?= $u['level'] ?></td>
                        <td><?= $u['streak'] ?> dias</td>
                        <td><span class="badge <?= $u['access_level'] === 'premium' ? 'badge-purple' : 'badge-blue' ?>"><?= ucfirst($u['access_level']) ?></span></td>
                        <td><?= $u['ultimo_login'] ?? 'Nunca' ?></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>

    <?php elseif ($section === 'users'):
        // ── USUARIOS (v1.7.0: búsqueda + edición de perfil) ──
        $q = trim((string)($_GET['q'] ?? ''));
        $editId = (int)($_GET['edit'] ?? 0);

        // Mensajes flash
        $msgsUsers = [
            'user_guardado'        => ['ok',  'Perfil actualizado correctamente.'],
            'user_datos_invalidos' => ['err', 'Datos inválidos: nombre y correo válido son obligatorios.'],
            'user_email_duplicado' => ['err', 'Ya existe otro usuario con ese correo.'],
            'user_error_bd'        => ['err', 'Error de base de datos. Revisa el log del servidor.'],
        ];
        $msgKeyU = (string)($_GET['msg'] ?? '');
        if ($msgKeyU !== '' && isset($msgsUsers[$msgKeyU])): ?>
            <div class="flash flash-<?= $msgsUsers[$msgKeyU][0] ?>"><?= $msgsUsers[$msgKeyU][1] ?></div>
        <?php endif;

        if ($editId > 0):
            // ── Formulario de edición de usuario ──
            $stmt = $conexion->prepare("
                SELECT id_usuario, moodle_id, nombre, email, telefono, departamento, ciudad,
                       colegio, grado, tipo_usuario, access_level, email_verificado,
                       registration_date, ultimo_login
                FROM usuarios WHERE id_usuario = :id LIMIT 1
            ");
            $stmt->execute([':id' => $editId]);
            $eu = $stmt->fetch(PDO::FETCH_ASSOC);
            $euActivo = 1;
            if ($eu) {
                try {
                    $stmtA = $conexion->prepare("SELECT activo FROM usuarios WHERE id_usuario = :id");
                    $stmtA->execute([':id' => $editId]);
                    $euActivo = (int)($stmtA->fetchColumn() ?: 1);
                } catch (Exception $exA) { /* columna aún no migrada */ }
            }
        ?>
        <?php if (!$eu): ?>
            <div class="section-card"><p>Usuario no encontrado. <a href="index.php?section=users">Volver al listado</a>.</p></div>
        <?php else: ?>
            <div class="section-card">
                <h3 class="section-title">&#9998; Editar usuario #<?= (int)$eu['id_usuario'] ?></h3>
                <p class="muted" style="margin-bottom:16px;">
                    Registro: <?= htmlspecialchars((string)$eu['registration_date']) ?> ·
                    Último login: <?= htmlspecialchars((string)($eu['ultimo_login'] ?? 'Nunca')) ?> ·
                    Moodle ID: <?= (int)($eu['moodle_id'] ?? 0) ?>
                </p>
                <form method="POST">
                    <?= admin_csrf_field() ?>
                    <input type="hidden" name="user_id" value="<?= (int)$eu['id_usuario'] ?>">
                    <div class="grid-2">
                        <div class="form-group"><label>Nombre completo</label>
                            <input type="text" name="nombre" required value="<?= htmlspecialchars($eu['nombre']) ?>"></div>
                        <div class="form-group"><label>Correo electrónico</label>
                            <input type="email" name="email" required value="<?= htmlspecialchars($eu['email']) ?>"></div>
                        <div class="form-group"><label>Teléfono</label>
                            <input type="text" name="telefono" value="<?= htmlspecialchars($eu['telefono'] ?? '') ?>"></div>
                        <div class="form-group"><label>Departamento</label>
                            <input type="text" name="departamento" value="<?= htmlspecialchars($eu['departamento'] ?? '') ?>"></div>
                        <div class="form-group"><label>Ciudad</label>
                            <input type="text" name="ciudad" value="<?= htmlspecialchars($eu['ciudad'] ?? '') ?>"></div>
                        <div class="form-group"><label>Colegio</label>
                            <input type="text" name="colegio" value="<?= htmlspecialchars($eu['colegio'] ?? '') ?>"></div>
                        <div class="form-group"><label>Grado</label>
                            <input type="text" name="grado" value="<?= htmlspecialchars($eu['grado'] ?? '') ?>"></div>
                        <div class="form-group"><label>Tipo de usuario</label>
                            <select name="tipo_usuario">
                                <?php foreach (['estudiante', 'profesor', 'admin'] as $tp): ?>
                                    <option value="<?= $tp ?>" <?= $eu['tipo_usuario'] === $tp ? 'selected' : '' ?>><?= ucfirst($tp) ?></option>
                                <?php endforeach; ?>
                            </select></div>
                        <div class="form-group"><label>Nivel de acceso (plan)</label>
                            <select name="access_level">
                                <?php foreach (['free', 'premium', 'early_bird'] as $al): ?>
                                    <option value="<?= $al ?>" <?= $eu['access_level'] === $al ? 'selected' : '' ?>><?= ucfirst($al) ?></option>
                                <?php endforeach; ?>
                            </select></div>
                        <div class="form-group" style="display:flex; align-items:center; gap:24px; padding-top:26px;">
                            <label style="display:flex; align-items:center; gap:8px; margin:0;">
                                <input type="checkbox" name="email_verificado" style="width:auto;" <?= $eu['email_verificado'] ? 'checked' : '' ?>> Email verificado
                            </label>
                            <label style="display:flex; align-items:center; gap:8px; margin:0;">
                                <input type="checkbox" name="activo" style="width:auto;" <?= $euActivo ? 'checked' : '' ?>> Cuenta activa
                            </label>
                        </div>
                    </div>
                    <div style="display:flex; gap:12px; margin-top:8px;">
                        <button type="submit" name="user_save" value="1" class="btn btn-primary">Guardar cambios</button>
                        <a href="index.php?section=users&q=<?= urlencode($q) ?>" class="btn" style="background:#e2e8f0; color:#334155;">Cancelar</a>
                    </div>
                </form>
            </div>
        <?php endif; ?>

        <?php else: ?>
        <!-- Listado con búsqueda -->
        <div class="section-card" style="padding:16px 20px;">
            <form method="GET" action="index.php" style="display:flex; gap:12px; align-items:center; flex-wrap:wrap;">
                <input type="hidden" name="section" value="users">
                <input type="text" name="q" placeholder="Buscar por nombre, correo o ID..." value="<?= htmlspecialchars($q) ?>" style="flex:1; min-width:220px; padding:10px 14px; border:2px solid #e2e8f0; border-radius:10px; font-size:14px;">
                <button type="submit" class="btn btn-primary">Buscar</button>
                <?php if ($q !== ''): ?>
                    <a href="index.php?section=users" class="btn" style="background:#e2e8f0; color:#334155;">Limpiar</a>
                <?php endif; ?>
            </form>
        </div>
        <div class="table-container">
            <table>
                <thead><tr><th>ID</th><th>Nombre</th><th>Email</th><th>Tipo</th><th>Plan</th><th>Verificado</th><th>Ciudad</th><th>Colegio</th><th>Registro</th><th>Ultimo Login</th><th></th></tr></thead>
                <tbody>
                <?php
                try {
                    if ($q !== '') {
                        $stmt = $conexion->prepare("
                            SELECT id_usuario, nombre, email, tipo_usuario, access_level,
                                   email_verificado, ciudad, colegio, registration_date, ultimo_login
                            FROM usuarios
                            WHERE nombre LIKE :q OR email LIKE :q OR id_usuario = :qid
                            ORDER BY id_usuario DESC LIMIT 100
                        ");
                        $stmt->execute([':q' => '%' . $q . '%', ':qid' => (int)$q]);
                    } else {
                        $stmt = $conexion->prepare("
                            SELECT id_usuario, nombre, email, tipo_usuario, access_level,
                                   email_verificado, ciudad, colegio, registration_date, ultimo_login
                            FROM usuarios ORDER BY id_usuario DESC LIMIT 100
                        ");
                        $stmt->execute();
                    }
                    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);
                } catch (Exception $exU) {
                    $users = $conexion->query("
                        SELECT id_usuario, nombre, email, tipo_usuario, access_level,
                               email_verificado, ciudad, colegio, registration_date, ultimo_login
                        FROM usuarios ORDER BY id_usuario DESC LIMIT 100
                    ")->fetchAll(PDO::FETCH_ASSOC);
                }
                foreach ($users as $u):
                ?>
                    <tr>
                        <td><?= $u['id_usuario'] ?></td>
                        <td><?= htmlspecialchars($u['nombre']) ?></td>
                        <td><?= htmlspecialchars($u['email']) ?></td>
                        <td><?= ucfirst($u['tipo_usuario']) ?></td>
                        <td><span class="badge <?= $u['access_level'] === 'premium' ? 'badge-purple' : 'badge-blue' ?>"><?= ucfirst($u['access_level']) ?></span></td>
                        <td><?= $u['email_verificado'] ? '<span class="badge badge-green">Si</span>' : '<span class="badge badge-orange">No</span>' ?></td>
                        <td><?= htmlspecialchars($u['ciudad'] ?? '-') ?></td>
                        <td><?= htmlspecialchars($u['colegio'] ?? '-') ?></td>
                        <td><?= $u['registration_date'] ?? '-' ?></td>
                        <td><?= $u['ultimo_login'] ?? 'Nunca' ?></td>
                        <td><a class="btn btn-primary" style="padding:6px 12px; font-size:12px;" href="index.php?section=users&edit=<?= $u['id_usuario'] ?>&q=<?= urlencode($q) ?>">Editar</a></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>
        <?php endif; ?>

    <?php elseif ($section === 'promociones'):
        // ── PROMOCIONES (v1.7.0) ──
        $promoEdit = null;
        $editPromoId = (int)($_GET['edit'] ?? 0);
        $promosDisponibles = true;
        try {
            $promos = $conexion->query("SELECT * FROM promociones ORDER BY id DESC")->fetchAll(PDO::FETCH_ASSOC);
            $planesLista = $conexion->query("SELECT id, name FROM plans ORDER BY price ASC")->fetchAll(PDO::FETCH_ASSOC);
            if ($editPromoId > 0) {
                $stmtPE = $conexion->prepare("SELECT * FROM promociones WHERE id = :id");
                $stmtPE->execute([':id' => $editPromoId]);
                $promoEdit = $stmtPE->fetch(PDO::FETCH_ASSOC);
            }
        } catch (Exception $exP) {
            $promosDisponibles = false;
            $promos = [];
            $planesLista = [];
        }

        $msgsPromo = [
            'promo_creada'          => ['ok',  'Promoción creada. Se verá en la app de inmediato.'],
            'promo_actualizada'     => ['ok',  'Promoción actualizada.'],
            'promo_eliminada'       => ['ok',  'Promoción eliminada.'],
            'promo_estado'          => ['ok',  'Estado de la promoción actualizado.'],
            'promo_datos_invalidos' => ['err', 'Datos inválidos. Revisa título, descuento, código (mín. 4 caracteres) y fechas (fin > inicio).'],
            'promo_codigo_duplicado'=> ['err', 'Ya existe una promoción con ese código.'],
            'promo_error_bd'        => ['err', 'Error de base de datos. Revisa el log del servidor.'],
        ];
        $msgKeyP = (string)($_GET['msg'] ?? '');
        if ($msgKeyP !== '' && isset($msgsPromo[$msgKeyP])): ?>
            <div class="flash flash-<?= $msgsPromo[$msgKeyP][0] ?>"><?= $msgsPromo[$msgKeyP][1] ?></div>
        <?php endif; ?>

        <?php if (!$promosDisponibles): ?>
            <div class="section-card">
                <h3 class="section-title">Migración pendiente</h3>
                <p class="muted">Ejecuta <code>backend/migrations/006_promociones_quejas.sql</code> en MySQL para habilitar esta sección.</p>
            </div>
        <?php else: ?>

        <!-- Formulario crear/editar -->
        <div class="section-card">
            <h3 class="section-title"><?= $promoEdit ? '&#9998; Editar promoción #' . (int)$promoEdit['id'] : '&#127873; Nueva promoción' ?></h3>
            <p class="muted" style="margin-bottom:16px;">
                Los <strong>banners</strong> con descuento aparecen en la pantalla Premium del app al instante y se aplican automáticamente al pagar en la web (Wompi).
                Los <strong>códigos</strong> los escribe el usuario al pagar en la web.
                <em>Nota Google Play: en Android los precios los fija Play Console — usa los códigos promociales de Play para equivalentes.</em>
            </p>
            <form method="POST">
                <?= admin_csrf_field() ?>
                <input type="hidden" name="promo_id" value="<?= (int)($promoEdit['id'] ?? 0) ?>">
                <div class="grid-2">
                    <div class="form-group"><label>Título *</label>
                        <input type="text" name="titulo" required maxlength="120" value="<?= htmlspecialchars($promoEdit['titulo'] ?? '') ?>" placeholder="Ej: Vuelta al cole -30%"></div>
                    <div class="form-group"><label>Descripción (opcional)</label>
                        <input type="text" name="descripcion" maxlength="255" value="<?= htmlspecialchars($promoEdit['descripcion'] ?? '') ?>" placeholder="Ej: 30% de descuento en el plan anual por inicio de clases"></div>
                    <div class="form-group"><label>Tipo</label>
                        <select name="tipo" id="promoTipo">
                            <option value="banner" <?= ($promoEdit['tipo'] ?? '') === 'banner' ? 'selected' : '' ?>>Banner (visible en el app)</option>
                            <option value="codigo" <?= ($promoEdit['tipo'] ?? '') === 'codigo' ? 'selected' : '' ?>>Código canjeable (web)</option>
                        </select></div>
                    <div class="form-group"><label>Código (solo tipo código)</label>
                        <div style="display:flex; gap:8px;">
                            <input type="text" name="codigo" id="promoCodigo" maxlength="40" value="<?= htmlspecialchars($promoEdit['codigo'] ?? '') ?>" placeholder="Ej: VUELTAALCOLE30">
                            <button type="button" class="btn" style="background:#e2e8f0; color:#334155; white-space:nowrap;" onclick="generarCodigo()">Generar</button>
                        </div></div>
                    <div class="form-group"><label>Tipo de descuento</label>
                        <select name="descuento_tipo">
                            <option value="porcentaje" <?= ($promoEdit['descuento_tipo'] ?? '') === 'porcentaje' ? 'selected' : '' ?>>Porcentaje (%)</option>
                            <option value="monto" <?= ($promoEdit['descuento_tipo'] ?? '') === 'monto' ? 'selected' : '' ?>>Monto fijo (COP)</option>
                        </select></div>
                    <div class="form-group"><label>Valor del descuento *</label>
                        <input type="number" name="descuento_valor" step="any" min="1" required value="<?= htmlspecialchars((string)($promoEdit['descuento_valor'] ?? '')) ?>" placeholder="Ej: 30"></div>
                    <div class="form-group"><label>Aplica a</label>
                        <select name="plan_id">
                            <option value="0">Todos los planes</option>
                            <?php foreach ($planesLista as $pl): ?>
                                <option value="<?= (int)$pl['id'] ?>" <?= (int)($promoEdit['plan_id'] ?? 0) === (int)$pl['id'] ? 'selected' : '' ?>><?= htmlspecialchars($pl['name']) ?></option>
                            <?php endforeach; ?>
                        </select></div>
                    <div class="form-group"><label>Usos máximos (vacío = ilimitado)</label>
                        <input type="number" name="max_usos" min="1" value="<?= htmlspecialchars((string)($promoEdit['max_usos'] ?? '')) ?>" placeholder="Ej: 100"></div>
                    <div class="form-group"><label>Fecha inicio *</label>
                        <input type="datetime-local" name="fecha_inicio" required value="<?= !empty($promoEdit['fecha_inicio']) ? date('Y-m-d\TH:i', strtotime($promoEdit['fecha_inicio'])) : date('Y-m-d\TH:i') ?>"></div>
                    <div class="form-group"><label>Fecha fin *</label>
                        <input type="datetime-local" name="fecha_fin" required value="<?= !empty($promoEdit['fecha_fin']) ? date('Y-m-d\TH:i', strtotime($promoEdit['fecha_fin'])) : date('Y-m-d\TH:i', strtotime('+30 days')) ?>"></div>
                </div>
                <div class="form-group" style="display:flex; align-items:center; gap:8px;">
                    <input type="checkbox" name="activo" id="promoActivo" style="width:auto;" <?= (int)($promoEdit['activo'] ?? 1) ? 'checked' : '' ?>>
                    <label for="promoActivo" style="margin:0;">Activa (visible y aplicable)</label>
                </div>
                <div style="display:flex; gap:12px;">
                    <button type="submit" name="promo_save" value="1" class="btn btn-primary"><?= $promoEdit ? 'Guardar cambios' : 'Crear promoción' ?></button>
                    <?php if ($promoEdit): ?>
                        <a href="index.php?section=promociones" class="btn" style="background:#e2e8f0; color:#334155;">Cancelar</a>
                    <?php endif; ?>
                </div>
            </form>
            <script>
                function generarCodigo() {
                    var pool = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
                    var out = '';
                    for (var i = 0; i < 10; i++) out += pool.charAt(Math.floor(Math.random() * pool.length));
                    document.getElementById('promoCodigo').value = out;
                }
            </script>
        </div>

        <!-- Listado -->
        <div class="table-container">
            <table>
                <thead><tr><th>ID</th><th>Título</th><th>Tipo</th><th>Descuento</th><th>Plan</th><th>Vigencia</th><th>Estado</th><th>Usos</th><th>Acciones</th></tr></thead>
                <tbody>
                <?php if (empty($promos)): ?>
                    <tr><td colspan="9" class="muted" style="text-align:center;padding:24px;">Aún no hay promociones. Crea la primera arriba.</td></tr>
                <?php else: foreach ($promos as $pr):
                    $ahora = time();
                    $tsIni = strtotime($pr['fecha_inicio']);
                    $tsFin = strtotime($pr['fecha_fin']);
                    $sinCupo = $pr['max_usos'] !== null && (int)$pr['usos'] >= (int)$pr['max_usos'];
                    if (!$pr['activo']) { $estadoTxt = 'Inactiva'; $estadoCls = 'badge-gray'; }
                    elseif ($sinCupo)  { $estadoTxt = 'Sin cupo'; $estadoCls = 'badge-red'; }
                    elseif ($ahora < $tsIni) { $estadoTxt = 'Programada'; $estadoCls = 'badge-blue'; }
                    elseif ($ahora > $tsFin) { $estadoTxt = 'Vencida'; $estadoCls = 'badge-orange'; }
                    else { $estadoTxt = 'Vigente'; $estadoCls = 'badge-green'; }
                ?>
                    <tr>
                        <td><?= (int)$pr['id'] ?></td>
                        <td><strong><?= htmlspecialchars($pr['titulo']) ?></strong><?= $pr['descripcion'] ? '<br><span class="muted">' . htmlspecialchars($pr['descripcion']) . '</span>' : '' ?></td>
                        <td><?= $pr['tipo'] === 'codigo'
                            ? '<span class="badge badge-purple">Código</span><br><code class="mono">' . htmlspecialchars($pr['codigo'] ?? '') . '</code>'
                            : '<span class="badge badge-blue">Banner</span>' ?></td>
                        <td><strong><?= $pr['descuento_tipo'] === 'porcentaje' ? rtrim(rtrim((string)$pr['descuento_valor'], '0'), '.') . '%' : '$' . number_format((float)$pr['descuento_valor']) . ' COP' ?></strong></td>
                        <td><?= $pr['plan_id'] ? 'Plan #' . (int)$pr['plan_id'] : 'Todos' ?></td>
                        <td class="muted" style="font-size:12px;"><?= date('d/m/Y H:i', $tsIni) ?><br>a <?= date('d/m/Y H:i', $tsFin) ?></td>
                        <td><span class="badge <?= $estadoCls ?>"><?= $estadoTxt ?></span></td>
                        <td><?= (int)$pr['usos'] ?><?= $pr['max_usos'] !== null ? ' / ' . (int)$pr['max_usos'] : '' ?></td>
                        <td style="white-space:nowrap;">
                            <a class="btn btn-primary" style="padding:6px 12px; font-size:12px;" href="index.php?section=promociones&edit=<?= (int)$pr['id'] ?>">Editar</a>
                            <form method="POST" style="display:inline;" onsubmit="return confirm('¿<?= $pr['activo'] ? 'Desactivar' : 'Activar' ?> esta promoción?');">
                                <?= admin_csrf_field() ?>
                                <input type="hidden" name="promo_id" value="<?= (int)$pr['id'] ?>">
                                <button type="submit" name="promo_toggle" value="1" class="btn <?= $pr['activo'] ? 'btn-danger' : 'btn-success' ?>" style="padding:6px 12px; font-size:12px;"><?= $pr['activo'] ? 'Desactivar' : 'Activar' ?></button>
                            </form>
                            <form method="POST" style="display:inline;" onsubmit="return confirm('¿ELIMINAR definitivamente esta promoción?');">
                                <?= admin_csrf_field() ?>
                                <input type="hidden" name="promo_id" value="<?= (int)$pr['id'] ?>">
                                <button type="submit" name="promo_delete" value="1" class="btn btn-danger" style="padding:6px 12px; font-size:12px;">Eliminar</button>
                            </form>
                        </td>
                    </tr>
                <?php endforeach; endif; ?>
                </tbody>
            </table>
        </div>
        <?php endif; ?>

    <?php elseif ($section === 'soporte'):
        // ── SOPORTE: quejas y sugerencias de los usuarios (v1.7.0) ──
        $soporteDisponible = true;
        $filtroEstado = (string)($_GET['estado'] ?? '');
        $verQuejaId = (int)($_GET['view'] ?? 0);
        $quejaDetalle = null;
        try {
            $estadosValidos = ['nuevo', 'en_proceso', 'resuelto', 'descartado'];
            if ($filtroEstado !== '' && in_array($filtroEstado, $estadosValidos, true)) {
                $stmt = $conexion->prepare("
                    SELECT q.*, u.nombre AS user_nombre, u.email AS user_email
                    FROM quejas_sugerencias q
                    JOIN usuarios u ON u.id_usuario = q.user_id
                    WHERE q.estado = :e
                    ORDER BY q.creado_en DESC LIMIT 200
                ");
                $stmt->execute([':e' => $filtroEstado]);
            } else {
                $stmt = $conexion->prepare("
                    SELECT q.*, u.nombre AS user_nombre, u.email AS user_email
                    FROM quejas_sugerencias q
                    JOIN usuarios u ON u.id_usuario = q.user_id
                    ORDER BY q.creado_en DESC LIMIT 200
                ");
                $stmt->execute();
            }
            $quejas = $stmt->fetchAll(PDO::FETCH_ASSOC);

            $contadorEstados = ['nuevo' => 0, 'en_proceso' => 0, 'resuelto' => 0, 'descartado' => 0];
            foreach ($quejas as $qq) {
                if (isset($contadorEstados[$qq['estado']])) $contadorEstados[$qq['estado']]++;
            }

            if ($verQuejaId > 0) {
                $stmtQ = $conexion->prepare("
                    SELECT q.*, u.nombre AS user_nombre, u.email AS user_email
                    FROM quejas_sugerencias q
                    JOIN usuarios u ON u.id_usuario = q.user_id
                    WHERE q.id = :id LIMIT 1
                ");
                $stmtQ->execute([':id' => $verQuejaId]);
                $quejaDetalle = $stmtQ->fetch(PDO::FETCH_ASSOC);
            }
        } catch (Exception $exQ) {
            $soporteDisponible = false;
            $quejas = [];
            $contadorEstados = ['nuevo' => 0, 'en_proceso' => 0, 'resuelto' => 0, 'descartado' => 0];
        }

        $msgsSoporte = [
            'queja_actualizada' => ['ok',  'Respuesta guardada. El usuario la verá en la app al instante.'],
            'queja_error'       => ['err', 'Error de base de datos al actualizar.'],
        ];
        $msgKeyS = (string)($_GET['msg'] ?? '');
        if ($msgKeyS !== '' && isset($msgsSoporte[$msgKeyS])): ?>
            <div class="flash flash-<?= $msgsSoporte[$msgKeyS][0] ?>"><?= $msgsSoporte[$msgKeyS][1] ?></div>
        <?php endif; ?>

        <?php if (!$soporteDisponible): ?>
            <div class="section-card">
                <h3 class="section-title">Migración pendiente</h3>
                <p class="muted">Ejecuta <code>backend/migrations/006_promociones_quejas.sql</code> en MySQL para habilitar esta sección.</p>
            </div>
        <?php else: ?>

        <?php if ($quejaDetalle): ?>
            <!-- Detalle de la queja -->
            <div class="section-card">
                <div style="display:flex; justify-content:space-between; align-items:flex-start; gap:16px; flex-wrap:wrap; margin-bottom:16px;">
                    <div>
                        <h3 class="section-title" style="margin-bottom:4px;">&#128172; Ticket #<?= (int)$quejaDetalle['id'] ?> — <?= htmlspecialchars($quejaDetalle['user_nombre']) ?></h3>
                        <p class="muted"><?= htmlspecialchars($quejaDetalle['user_email']) ?> · <?= htmlspecialchars((string)$quejaDetalle['creado_en']) ?></p>
                    </div>
                    <a href="index.php?section=soporte" class="btn" style="background:#e2e8f0; color:#334155;">&larr; Volver</a>
                </div>
                <div style="background:#f8fafc; border-radius:12px; padding:16px; margin-bottom:16px;">
                    <p style="margin-bottom:8px;">
                        <span class="badge badge-purple"><?= htmlspecialchars(strtoupper($quejaDetalle['tipo'])) ?></span>
                        <?php if (!empty($quejaDetalle['asunto'])): ?><strong><?= htmlspecialchars($quejaDetalle['asunto']) ?></strong><?php endif; ?>
                    </p>
                    <p style="white-space:pre-wrap; line-height:1.6;"><?= htmlspecialchars($quejaDetalle['mensaje']) ?></p>
                </div>
                <form method="POST">
                    <?= admin_csrf_field() ?>
                    <input type="hidden" name="queja_id" value="<?= (int)$quejaDetalle['id'] ?>">
                    <div class="form-group">
                        <label>Respuesta para el estudiante (la verá en el app en "Mis envíos")</label>
                        <textarea name="respuesta" rows="4" maxlength="2000" style="width:100%; padding:10px 14px; border:2px solid #e2e8f0; border-radius:10px; font-size:14px; font-family:inherit;" placeholder="Ej: ¡Gracias por reportarnos! Ya corregimos el error..."><?= htmlspecialchars($quejaDetalle['respuesta_admin'] ?? '') ?></textarea>
                    </div>
                    <div style="display:flex; gap:12px; align-items:center; flex-wrap:wrap;">
                        <div class="form-group" style="margin:0;">
                            <select name="estado">
                                <option value="nuevo" <?= $quejaDetalle['estado'] === 'nuevo' ? 'selected' : '' ?>>Recibido</option>
                                <option value="en_proceso" <?= $quejaDetalle['estado'] === 'en_proceso' ? 'selected' : '' ?>>En revisión</option>
                                <option value="resuelto" <?= $quejaDetalle['estado'] === 'resuelto' ? 'selected' : '' ?>>Resuelto</option>
                                <option value="descartado" <?= $quejaDetalle['estado'] === 'descartado' ? 'selected' : '' ?>>Cerrado</option>
                            </select>
                        </div>
                        <button type="submit" name="queja_update" value="1" class="btn btn-primary">Guardar respuesta</button>
                    </div>
                </form>
            </div>
        <?php else: ?>
            <!-- Bandeja -->
            <div class="stats-grid" style="grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));">
                <div class="stat-card"><div class="stat-value" style="color:#EF4444;"><?= (int)$contadorEstados['nuevo'] ?></div><div class="stat-label">Nuevos</div></div>
                <div class="stat-card"><div class="stat-value" style="color:#F59E0B;"><?= (int)$contadorEstados['en_proceso'] ?></div><div class="stat-label">En revisión</div></div>
                <div class="stat-card"><div class="stat-value" style="color:#22C55E;"><?= (int)$contadorEstados['resuelto'] ?></div><div class="stat-label">Resueltos</div></div>
                <div class="stat-card"><div class="stat-value" style="color:#94A3B8;"><?= (int)$contadorEstados['descartado'] ?></div><div class="stat-label">Cerrados</div></div>
            </div>
            <div class="section-card" style="padding:12px 20px;">
                <div style="display:flex; gap:8px; flex-wrap:wrap;">
                    <a class="btn <?= $filtroEstado === '' ? 'btn-primary' : '' ?>" style="<?= $filtroEstado === '' ? '' : 'background:#e2e8f0; color:#334155;' ?>" href="index.php?section=soporte">Todos</a>
                    <?php foreach (['nuevo' => 'Nuevos', 'en_proceso' => 'En revisión', 'resuelto' => 'Resueltos', 'descartado' => 'Cerrados'] as $estK => $estL): ?>
                        <a class="btn <?= $filtroEstado === $estK ? 'btn-primary' : '' ?>" style="<?= $filtroEstado === $estK ? '' : 'background:#e2e8f0; color:#334155;' ?>" href="index.php?section=soporte&estado=<?= $estK ?>"><?= $estL ?></a>
                    <?php endforeach; ?>
                </div>
            </div>
            <div class="table-container">
                <table>
                    <thead><tr><th>#</th><th>Fecha</th><th>Usuario</th><th>Tipo</th><th>Asunto / Mensaje</th><th>Estado</th><th>Respuesta</th><th></th></tr></thead>
                    <tbody>
                    <?php if (empty($quejas)): ?>
                        <tr><td colspan="8" class="muted" style="text-align:center;padding:24px;">No hay mensajes todavía. Los que envíen los estudiantes desde el app aparecen aquí.</td></tr>
                    <?php else: foreach ($quejas as $qj):
                        $badgeEst = ['nuevo' => 'badge-red', 'en_proceso' => 'badge-yellow', 'resuelto' => 'badge-green', 'descartado' => 'badge-gray'][$qj['estado']] ?? 'badge-gray';
                        $txtEst = ['nuevo' => 'Recibido', 'en_proceso' => 'En revisión', 'resuelto' => 'Resuelto', 'descartado' => 'Cerrado'][$qj['estado']] ?? $qj['estado'];
                    ?>
                        <tr>
                            <td><?= (int)$qj['id'] ?></td>
                            <td class="muted" style="font-size:12px;"><?= date('d/m/Y H:i', strtotime($qj['creado_en'])) ?></td>
                            <td><strong><?= htmlspecialchars($qj['user_nombre']) ?></strong><br><span class="muted" style="font-size:12px;"><?= htmlspecialchars($qj['user_email']) ?></span></td>
                            <td><span class="badge badge-purple"><?= htmlspecialchars(strtoupper($qj['tipo'])) ?></span></td>
                            <td style="max-width:320px;"><strong><?= htmlspecialchars($qj['asunto'] ?? '(sin asunto)') ?></strong><br><span class="muted" style="font-size:12px;"><?= htmlspecialchars(mb_substr($qj['mensaje'], 0, 90)) ?><?= mb_strlen($qj['mensaje']) > 90 ? '...' : '' ?></span></td>
                            <td><span class="badge <?= $badgeEst ?>"><?= $txtEst ?></span></td>
                            <td><?= !empty($qj['respuesta_admin']) ? '<span class="badge badge-green">Sí</span>' : '<span class="badge badge-gray">No</span>' ?></td>
                            <td><a class="btn btn-primary" style="padding:6px 12px; font-size:12px;" href="index.php?section=soporte&view=<?= (int)$qj['id'] ?>">Ver</a></td>
                        </tr>
                    <?php endforeach; endif; ?>
                    </tbody>
                </table>
            </div>
        <?php endif; ?>
        <?php endif; ?>

    <?php elseif ($section === 'ads'): ?>
        <!-- ANUNCIOS -->
        <div class="section-card">
            <h3 class="section-title">Gestionar Anuncios</h3>
            <p style="color: #666; margin-bottom: 16px;">
                Los anuncios se gestionan desde la tabla <code>ads</code> en la base de datos.
                Sube las imagenes a <code>backend/uploads/ads/</code> y registra el anuncio aqui.
            </p>
        </div>
        <div class="table-container">
            <table>
                <thead><tr><th>ID</th><th>Titulo</th><th>Imagen</th><th>URL Destino</th><th>Estado</th><th>Impresiones</th><th>Clicks</th><th>CTR</th></tr></thead>
                <tbody>
                <?php
                $ads = $conexion->query("SELECT * FROM ads ORDER BY id DESC")->fetchAll(PDO::FETCH_ASSOC);
                foreach ($ads as $ad):
                    $impressions = (int)($ad['impressions'] ?? 0);
                    $clicks = (int)($ad['clicks'] ?? 0);
                    $ctr = $impressions > 0 ? round(($clicks / $impressions) * 100, 1) : 0;
                ?>
                    <tr>
                        <td><?= $ad['id'] ?></td>
                        <td><?= htmlspecialchars($ad['title'] ?? '') ?></td>
                        <td><?= htmlspecialchars($ad['image_url'] ?? '') ?></td>
                        <td><?= htmlspecialchars($ad['click_url'] ?? '-') ?></td>
                        <td><?= ($ad['is_active'] ?? 0) ? '<span class="badge badge-green">Activo</span>' : '<span class="badge badge-orange">Inactivo</span>' ?></td>
                        <td><?= number_format($impressions) ?></td>
                        <td><?= number_format($clicks) ?></td>
                        <td><?= $ctr ?>%</td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>

    <?php elseif ($section === 'plans'): ?>
        <!-- PLANES -->
        <div class="section-card">
            <h3 class="section-title">Planes y Precios</h3>
            <p style="color: #666; margin-bottom: 16px;">
                Gestiona los planes desde la tabla <code>plans</code> y <code>plan_features</code>.
                Los precios se configuran en COP (Pesos Colombianos).
            </p>
        </div>
        <div class="table-container">
            <table>
                <thead><tr><th>ID</th><th>Codigo</th><th>Nombre</th><th>Precio Mensual</th><th>Precio Anual</th><th>Estado</th></tr></thead>
                <tbody>
                <?php
                $plans = $conexion->query("SELECT * FROM plans ORDER BY id")->fetchAll(PDO::FETCH_ASSOC);
                foreach ($plans as $p):
                ?>
                    <tr>
                        <td><?= $p['id'] ?></td>
                        <td><?= htmlspecialchars($p['code'] ?? '') ?></td>
                        <td><?= htmlspecialchars($p['name'] ?? '') ?></td>
                        <td>$<?= number_format($p['price_monthly'] ?? 0) ?></td>
                        <td>$<?= number_format($p['price_yearly'] ?? 0) ?></td>
                        <td><?= ($p['is_active'] ?? 0) ? '<span class="badge badge-green">Activo</span>' : '<span class="badge badge-orange">Inactivo</span>' ?></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>

    <?php elseif ($section === 'notifications'): ?>
        <!-- NOTIFICACIONES -->
        <div class="section-card">
            <h3 class="section-title">Enviar Notificacion Masiva</h3>
            <form method="POST" action="send_bulk.php">
                <div class="form-group">
                    <label>Titulo</label>
                    <input type="text" name="title" required>
                </div>
                <div class="form-group">
                    <label>Mensaje</label>
                    <textarea name="body" rows="3" required style="width:100%;padding:10px 14px;border:2px solid #e2e8f0;border-radius:10px;font-size:14px;"></textarea>
                </div>
                <div class="form-group">
                    <label>Tipo</label>
                    <select name="type">
                        <option value="info">Informacion</option>
                        <option value="promo">Promocion</option>
                        <option value="update">Actualizacion</option>
                    </select>
                </div>
                <button type="submit" class="btn btn-primary">Enviar a todos los usuarios</button>
            </form>
        </div>
        <div class="section-card">
            <h3 class="section-title">Notificaciones Recientes</h3>
            <div class="table-container">
                <table>
                    <thead><tr><th>Fecha</th><th>Usuario</th><th>Titulo</th><th>Tipo</th></tr></thead>
                    <tbody>
                    <?php
                    $notifs = $conexion->query("
                        SELECT n.created_at, u.nombre, n.title, n.type
                        FROM notifications n
                        LEFT JOIN usuarios u ON n.user_id = u.id_usuario
                        ORDER BY n.id DESC LIMIT 20
                    ")->fetchAll(PDO::FETCH_ASSOC);
                    foreach ($notifs as $n):
                    ?>
                        <tr>
                            <td><?= $n['created_at'] ?></td>
                            <td><?= htmlspecialchars($n['nombre'] ?? 'N/A') ?></td>
                            <td><?= htmlspecialchars($n['title']) ?></td>
                            <td><span class="badge badge-blue"><?= $n['type'] ?></span></td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>

    <?php elseif ($section === 'reports'): ?>
        <!-- REPORTES -->
        <div class="section-card">
            <h3 class="section-title">Reportes Generales</h3>
            <div class="grid-2">
                <div>
                    <h4 style="margin-bottom:12px;">Usuarios por Ciudad</h4>
                    <div class="table-container">
                        <table>
                            <thead><tr><th>Ciudad</th><th>Usuarios</th></tr></thead>
                            <tbody>
                            <?php
                            $cities = $conexion->query("SELECT ciudad, COUNT(*) as count FROM usuarios WHERE ciudad IS NOT NULL AND ciudad != '' GROUP BY ciudad ORDER BY count DESC LIMIT 10")->fetchAll(PDO::FETCH_ASSOC);
                            foreach ($cities as $c):
                            ?>
                                <tr><td><?= htmlspecialchars($c['ciudad']) ?></td><td><?= $c['count'] ?></td></tr>
                            <?php endforeach; ?>
                            </tbody>
                        </table>
                    </div>
                </div>
                <div>
                    <h4 style="margin-bottom:12px;">Promedio por Area</h4>
                    <div class="table-container">
                        <table>
                            <thead><tr><th>Area</th><th>Promedio</th></tr></thead>
                            <tbody>
                            <?php
                            $areas = $conexion->query("SELECT ROUND(AVG(lectura_puntaje),1) as lectura, ROUND(AVG(matematicas_puntaje),1) as matematicas, ROUND(AVG(sociales_puntaje),1) as sociales, ROUND(AVG(naturales_puntaje),1) as naturales, ROUND(AVG(ingles_puntaje),1) as ingles FROM simulacro_resultados")->fetch(PDO::FETCH_ASSOC);
                            $areaNames = ['Lectura Critica' => 'lectura', 'Matematicas' => 'matematicas', 'Sociales' => 'sociales', 'Naturales' => 'naturales', 'Ingles' => 'ingles'];
                            foreach ($areaNames as $name => $key):
                            ?>
                                <tr><td><?= $name ?></td><td><?= $areas[$key] ?? 0 ?></td></tr>
                            <?php endforeach; ?>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>
        <div class="section-card">
            <h3 class="section-title">Crecimiento de Usuarios (ultimos 30 dias)</h3>
            <div class="table-container">
                <table>
                    <thead><tr><th>Fecha</th><th>Nuevos Usuarios</th></tr></thead>
                    <tbody>
                    <?php
                    $growth = $conexion->query("SELECT DATE(registration_date) as fecha, COUNT(*) as count FROM usuarios WHERE registration_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) GROUP BY DATE(registration_date) ORDER BY fecha DESC")->fetchAll(PDO::FETCH_ASSOC);
                    foreach ($growth as $g):
                    ?>
                        <tr><td><?= $g['fecha'] ?></td><td><?= $g['count'] ?></td></tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
    <?php elseif ($section === 'analytics'): ?>
        <!-- ANALITICA (v1.6.0) -->
        <?php
        $analyticsAvailable = true;
        $an = [];
        try {
            $an['eventos_hoy']    = (int)$conexion->query("SELECT COUNT(*) FROM app_events WHERE created_at >= CURDATE()")->fetchColumn();
            $an['eventos_7d']     = (int)$conexion->query("SELECT COUNT(*) FROM app_events WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)")->fetchColumn();
            $an['usuarios_act_hoy'] = (int)$conexion->query("SELECT COUNT(DISTINCT user_id) FROM app_events WHERE created_at >= CURDATE() AND user_id IS NOT NULL")->fetchColumn();
            $an['usuarios_act_7d']  = (int)$conexion->query("SELECT COUNT(DISTINCT user_id) FROM app_events WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY) AND user_id IS NOT NULL")->fetchColumn();
            $an['errores_app_7d']   = (int)$conexion->query("SELECT COUNT(*) FROM error_logs WHERE source = 'app' AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)")->fetchColumn();
        } catch (Exception $e) {
            $analyticsAvailable = false;
        }
        ?>
        <?php if (!$analyticsAvailable): ?>
            <div class="section-card">
                <h3 class="section-title">Analítica no disponible</h3>
                <p class="muted">Las tablas <code>app_events</code> / <code>error_logs</code> no existen todavía.
                Ejecuta la migración: <code>mysql -u jnegretep -p prepsaber &lt; backend/migrations/003_analytics_admin.sql</code></p>
            </div>
        <?php else: ?>
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-icon" style="background: #DBEAFE;">&#128200;</div>
                <div class="stat-value"><?= number_format($an['eventos_hoy']) ?></div>
                <div class="stat-label">Eventos Hoy</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #D1FAE5;">&#128640;</div>
                <div class="stat-value"><?= number_format($an['eventos_7d']) ?></div>
                <div class="stat-label">Eventos 7 días</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #FEF3C7;">&#128100;</div>
                <div class="stat-value"><?= $an['usuarios_act_hoy'] ?></div>
                <div class="stat-label">Usuarios Activos Hoy (eventos)</div>
                <div class="stat-change">7 días: <?= $an['usuarios_act_7d'] ?></div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #FEE2E2;">&#9888;</div>
                <div class="stat-value"><?= $an['errores_app_7d'] ?></div>
                <div class="stat-label">Errores de App (7 días)</div>
            </div>
        </div>

        <div class="section-card">
            <h3 class="section-title">Eventos por Tipo (últimos 7 días)</h3>
            <?php
            $topEvents = $conexion->query("
                SELECT event_name, COUNT(*) as total
                FROM app_events
                WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
                GROUP BY event_name ORDER BY total DESC LIMIT 12
            ")->fetchAll(PDO::FETCH_ASSOC);
            $maxEvent = max(1, (int)($topEvents[0]['total'] ?? 1));
            if (!$topEvents): ?>
                <p class="muted">Aún no hay eventos registrados. Los eventos llegan desde la app v1.6.0+.</p>
            <?php else: foreach ($topEvents as $ev): ?>
                <div class="bar-row">
                    <div class="bar-label"><?= htmlspecialchars($ev['event_name']) ?></div>
                    <div class="bar-track"><div class="bar-fill" style="width: <?= round($ev['total'] / $maxEvent * 100) ?>%"></div></div>
                    <div class="bar-value"><?= number_format($ev['total']) ?></div>
                </div>
            <?php endforeach; endif; ?>
        </div>

        <div class="grid-2">
            <div class="section-card">
                <h3 class="section-title">Plataformas (30 días)</h3>
                <?php
                $platforms = $conexion->query("
                    SELECT platform, COUNT(*) as total
                    FROM app_events
                    WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                    GROUP BY platform ORDER BY total DESC
                ")->fetchAll(PDO::FETCH_ASSOC);
                $maxPlat = max(1, (int)($platforms[0]['total'] ?? 1));
                if (!$platforms): ?>
                    <p class="muted">Sin datos aún.</p>
                <?php else: foreach ($platforms as $p): ?>
                    <div class="bar-row">
                        <div class="bar-label"><?= htmlspecialchars($p['platform']) ?></div>
                        <div class="bar-track"><div class="bar-fill green" style="width: <?= round($p['total'] / $maxPlat * 100) ?>%"></div></div>
                        <div class="bar-value"><?= number_format($p['total']) ?></div>
                    </div>
                <?php endforeach; endif; ?>
            </div>
            <div class="section-card">
                <h3 class="section-title">Retención aproximada</h3>
                <?php
                try {
                    $act1 = (int)$conexion->query("SELECT COUNT(DISTINCT user_id) FROM app_events WHERE user_id IS NOT NULL AND created_at >= CURDATE()")->fetchColumn();
                    $act7 = (int)$conexion->query("SELECT COUNT(DISTINCT user_id) FROM app_events WHERE user_id IS NOT NULL AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)")->fetchColumn();
                    $total = (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE email_verificado = 1")->fetchColumn();
                    $retencion = $act7 > 0 ? round(($act1 / $act7) * 100, 1) : 0;
                } catch (Exception $e) { $act1 = $act7 = $total = 0; $retencion = 0; }
                ?>
                <div class="bar-row"><div class="bar-label">DAU/WAU</div><div class="bar-track"><div class="bar-fill" style="width: <?= min(100, $retencion) ?>%"></div></div><div class="bar-value"><?= $retencion ?>%</div></div>
                <p class="muted" style="margin-top:12px;">DAU (hoy): <strong><?= $act1 ?></strong> · WAU (7d): <strong><?= $act7 ?></strong> · Verificados: <strong><?= $total ?></strong></p>
                <p class="muted">Ratio calculado con usuarios que generaron eventos (app v1.6.0+). Complementa con Firebase Analytics para datos completos.</p>
            </div>
        </div>
        <?php endif; ?>

    <?php elseif ($section === 'errors'): ?>
        <!-- ERRORES (v1.6.0) -->
        <?php
        $errorsAvailable = true;
        $errStats = [];
        try {
            $errStats['total'] = (int)$conexion->query("SELECT COUNT(*) FROM error_logs")->fetchColumn();
            $errStats['unresolved'] = (int)$conexion->query("SELECT COUNT(*) FROM error_logs WHERE resolved = 0")->fetchColumn();
            $errStats['fatal_7d'] = (int)$conexion->query("SELECT COUNT(*) FROM error_logs WHERE severity = 'fatal' AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)")->fetchColumn();
        } catch (Exception $e) {
            $errorsAvailable = false;
        }
        ?>
        <?php if (!$errorsAvailable): ?>
            <div class="section-card">
                <h3 class="section-title">Visor de errores no disponible</h3>
                <p class="muted">Ejecuta la migración 003: <code>backend/migrations/003_analytics_admin.sql</code></p>
            </div>
        <?php else: ?>
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-icon" style="background: #FEE2E2;">&#128680;</div>
                <div class="stat-value"><?= number_format($errStats['total']) ?></div>
                <div class="stat-label">Errores Totales</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #FEF3C7;">&#9888;</div>
                <div class="stat-value"><?= number_format($errStats['unresolved']) ?></div>
                <div class="stat-label">Sin Resolver</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #FED7AA;">&#128165;</div>
                <div class="stat-value"><?= number_format($errStats['fatal_7d']) ?></div>
                <div class="stat-label">Fatales (7 días)</div>
            </div>
        </div>
        <div class="table-container">
            <table>
                <thead><tr><th>Fecha</th><th>Origen</th><th>Severidad</th><th>Código</th><th>Mensaje</th><th>Usuario</th><th>Plataforma</th><th>Estado</th><th></th></tr></thead>
                <tbody>
                <?php
                $errores = $conexion->query("
                    SELECT e.*, u.nombre
                    FROM error_logs e
                    LEFT JOIN usuarios u ON e.user_id = u.id_usuario
                    ORDER BY e.created_at DESC LIMIT 100
                ")->fetchAll(PDO::FETCH_ASSOC);
                foreach ($errores as $er):
                    $sevBadge = match($er['severity']) {
                        'fatal' => 'badge-red',
                        'warning' => 'badge-yellow',
                        'info' => 'badge-gray',
                        default => 'badge-orange',
                    };
                ?>
                    <tr>
                        <td class="mono"><?= $er['created_at'] ?></td>
                        <td><span class="badge badge-blue"><?= htmlspecialchars($er['source']) ?></span></td>
                        <td><span class="badge <?= $sevBadge ?>"><?= htmlspecialchars($er['severity']) ?></span></td>
                        <td class="mono"><?= htmlspecialchars($er['error_code'] ?? '-') ?></td>
                        <td title="<?= htmlspecialchars(mb_substr($er['message'], 0, 300)) ?>"><?= htmlspecialchars(mb_substr($er['message'], 0, 90)) ?><?= mb_strlen($er['message']) > 90 ? '...' : '' ?></td>
                        <td><?= $er['user_id'] ? htmlspecialchars($er['nombre'] ?? ('#' . $er['user_id'])) : '-' ?></td>
                        <td><?= htmlspecialchars($er['platform'] ?? '-') ?></td>
                        <td><?= $er['resolved'] ? '<span class="badge badge-green">Resuelto</span>' : '<span class="badge badge-orange">Abierto</span>' ?></td>
                        <td>
                            <?php if (!$er['resolved']): ?>
                            <form method="POST" style="display:inline;">
                                <input type="hidden" name="resolve_error" value="<?= $er['id'] ?>">
                                <button type="submit" class="btn btn-success" style="padding:4px 10px;font-size:11px;">✓</button>
                            </form>
                            <?php endif; ?>
                        </td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>
        <?php endif; ?>

    <?php elseif ($section === 'activity'): ?>
        <!-- ACTIVIDAD (v1.6.0) -->
        <?php
        $activityAvailable = true;
        $eventos = [];
        try {
            $eventos = $conexion->query("
                SELECT e.*, u.nombre
                FROM app_events e
                LEFT JOIN usuarios u ON e.user_id = u.id_usuario
                ORDER BY e.created_at DESC LIMIT 100
            ")->fetchAll(PDO::FETCH_ASSOC);
        } catch (Exception $e) {
            $activityAvailable = false;
        }
        ?>
        <?php if (!$activityAvailable): ?>
            <div class="section-card">
                <h3 class="section-title">Actividad no disponible</h3>
                <p class="muted">Ejecuta la migración 003: <code>backend/migrations/003_analytics_admin.sql</code></p>
            </div>
        <?php else: ?>
        <div class="table-container">
            <table>
                <thead><tr><th>Fecha</th><th>Usuario</th><th>Evento</th><th>Plataforma</th><th>Versión</th><th>Parámetros</th></tr></thead>
                <tbody>
                <?php if (!$eventos): ?>
                    <tr><td colspan="6" class="muted" style="text-align:center;padding:24px;">Sin eventos aún — llegarán desde la app v1.6.0+</td></tr>
                <?php else: foreach ($eventos as $ev): ?>
                    <tr>
                        <td class="mono"><?= $ev['created_at'] ?></td>
                        <td><?= $ev['user_id'] ? htmlspecialchars($ev['nombre'] ?? ('#' . $ev['user_id'])) : '<span class="muted">anónimo</span>' ?></td>
                        <td><span class="badge badge-blue"><?= htmlspecialchars($ev['event_name']) ?></span></td>
                        <td><?= htmlspecialchars($ev['platform'] ?? '-') ?></td>
                        <td class="mono"><?= htmlspecialchars($ev['app_version'] ?? '-') ?></td>
                        <td class="mono" title="<?= htmlspecialchars((string)$ev['params']) ?>"><?= htmlspecialchars(mb_substr((string)$ev['params'], 0, 60)) ?><?= mb_strlen((string)$ev['params']) > 60 ? '...' : '' ?></td>
                    </tr>
                <?php endforeach; endif; ?>
                </tbody>
            </table>
        </div>
        <?php endif; ?>

    <?php elseif ($section === 'rankings'): ?>
        <!-- RANKINGS INSTITUCIONALES (v1.6.0) -->
        <div class="grid-2">
            <div class="section-card">
                <h3 class="section-title">🏆 Top Colegios por XP</h3>
                <div class="table-container">
                    <table>
                        <thead><tr><th>#</th><th>Colegio</th><th>Depto</th><th>Usuarios</th><th>XP Total</th><th>Nivel Prom.</th></tr></thead>
                        <tbody>
                        <?php
                        $colegiosTop = $conexion->query("
                            SELECT TRIM(u.colegio) as colegio, MAX(TRIM(u.departamento)) as depto,
                                   COUNT(DISTINCT u.id_usuario) as usuarios,
                                   SUM(ug.total_xp) as xp, ROUND(AVG(ug.current_level),1) as nivel
                            FROM usuarios u JOIN user_gamification ug ON ug.user_id = u.id_usuario
                            WHERE u.colegio IS NOT NULL AND TRIM(u.colegio) <> '' AND u.email_verificado = 1 AND ug.total_xp > 0
                            GROUP BY TRIM(u.colegio) ORDER BY xp DESC LIMIT 25
                        ")->fetchAll(PDO::FETCH_ASSOC);
                        if (!$colegiosTop): ?>
                            <tr><td colspan="6" class="muted" style="text-align:center;padding:24px;">Sin datos aún.</td></tr>
                        <?php else: foreach ($colegiosTop as $i => $c): ?>
                            <tr>
                                <td><?= $i + 1 ?></td>
                                <td><?= htmlspecialchars($c['colegio']) ?></td>
                                <td><?= htmlspecialchars($c['depto'] ?? '-') ?></td>
                                <td><?= $c['usuarios'] ?></td>
                                <td><strong><?= number_format((float)$c['xp']) ?></strong></td>
                                <td><?= $c['nivel'] ?></td>
                            </tr>
                        <?php endforeach; endif; ?>
                        </tbody>
                    </table>
                </div>
            </div>
            <div class="section-card">
                <h3 class="section-title">🗺️ Top Departamentos por XP</h3>
                <div class="table-container">
                    <table>
                        <thead><tr><th>#</th><th>Departamento</th><th>Usuarios</th><th>XP Total</th><th>Nivel Prom.</th></tr></thead>
                        <tbody>
                        <?php
                        $deptosTop = $conexion->query("
                            SELECT TRIM(u.departamento) as depto,
                                   COUNT(DISTINCT u.id_usuario) as usuarios,
                                   SUM(ug.total_xp) as xp, ROUND(AVG(ug.current_level),1) as nivel
                            FROM usuarios u JOIN user_gamification ug ON ug.user_id = u.id_usuario
                            WHERE u.departamento IS NOT NULL AND TRIM(u.departamento) <> '' AND u.email_verificado = 1 AND ug.total_xp > 0
                            GROUP BY TRIM(u.departamento) ORDER BY xp DESC LIMIT 25
                        ")->fetchAll(PDO::FETCH_ASSOC);
                        if (!$deptosTop): ?>
                            <tr><td colspan="5" class="muted" style="text-align:center;padding:24px;">Sin datos aún.</td></tr>
                        <?php else: foreach ($deptosTop as $i => $d): ?>
                            <tr>
                                <td><?= $i + 1 ?></td>
                                <td><?= htmlspecialchars($d['depto']) ?></td>
                                <td><?= $d['usuarios'] ?></td>
                                <td><strong><?= number_format((float)$d['xp']) ?></strong></td>
                                <td><?= $d['nivel'] ?></td>
                            </tr>
                        <?php endforeach; endif; ?>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

    <?php elseif ($section === 'colegios'): ?>
        <!-- COLEGIOS (B2B, v1.7.0): gestión de directores -->
        <?php
        $colegiosAvailable = true;
        $directores = [];
        $colegiosDatalist = [];
        $sugerenciaPass = '';
        try {
            $stmtDir = $conexion->prepare("
                SELECT d.id, d.nombre, d.email, d.colegio, d.telefono, d.activo, d.ultimo_login,
                       (SELECT COUNT(*) FROM usuarios u
                         WHERE u.colegio = d.colegio AND u.tipo_usuario = 'estudiante') AS estudiantes
                FROM directores d
                ORDER BY d.activo DESC, d.id DESC
            ");
            $stmtDir->execute();
            $directores = $stmtDir->fetchAll(PDO::FETCH_ASSOC);

            $stmtCol = $conexion->prepare("
                SELECT DISTINCT colegio
                FROM usuarios
                WHERE colegio IS NOT NULL AND colegio <> ''
                ORDER BY colegio
            ");
            $stmtCol->execute();
            $colegiosDatalist = $stmtCol->fetchAll(PDO::FETCH_COLUMN);

            // Sugerencia de contraseña segura (10 aleatorios + 2 fijos = 12)
            $pool = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
            for ($i = 0; $i < 10; $i++) {
                $sugerenciaPass .= $pool[random_int(0, strlen($pool) - 1)];
            }
            $sugerenciaPass .= '!7a';
        } catch (Exception $e) {
            $colegiosAvailable = false;
        }
        ?>
        <?php if (!$colegiosAvailable): ?>
            <div class="section-card">
                <h3 class="section-title">Sección Colegios no disponible</h3>
                <p class="muted">La tabla <code>directores</code> no existe todavía.
                Ejecuta la migración: <code>mysql -u jnegretep -p prepsaber &lt; backend/migrations/005_directores.sql</code></p>
            </div>
        <?php else: ?>

            <?php
            // Mensajes flash por querystring
            $msgs = [
                'director_creado'   => ['ok',  'Director creado correctamente. Comparte las credenciales de forma segura.'],
                'email_duplicado'   => ['err', 'Ya existe un director con ese correo.'],
                'datos_invalidos'   => ['err', 'Datos inválidos: nombre, correo y colegio son obligatorios; la contraseña debe tener al menos 8 caracteres.'],
                'estado_actualizado'=> ['ok',  'Estado del director actualizado.'],
                'error_bd'          => ['err', 'Error de base de datos. Revisa el log del servidor.'],
            ];
            $msgKey = (string)($_GET['msg'] ?? '');
            if ($msgKey !== '' && isset($msgs[$msgKey])): ?>
                <div class="flash flash-<?= $msgs[$msgKey][0] ?>"><?= $msgs[$msgKey][1] ?></div>
            <?php endif; ?>

            <?php if (!empty($_SESSION['admin_flash_pass'])):
                $flashPass = $_SESSION['admin_flash_pass'];
                unset($_SESSION['admin_flash_pass']); // se muestra UNA sola vez ?>
                <div class="section-card" style="border: 2px solid #22C55E;">
                    <h3 class="section-title">&#128273; Contraseña restablecida (Director #<?= (int)$flashPass['id'] ?>)</h3>
                    <p style="margin-bottom: 12px;">Guarda esta contraseña ahora — <strong>no volverá a mostrarse</strong>:</p>
                    <div style="display:flex; gap:12px; align-items:center; flex-wrap:wrap;">
                        <code class="mono" id="passGenerada" style="font-size: 18px; background: #f1f5f9; padding: 10px 16px; border-radius: 8px;"><?= htmlspecialchars($flashPass['pass'], ENT_QUOTES, 'UTF-8') ?></code>
                        <button type="button" class="btn btn-primary" id="btnCopiarPass">Copiar</button>
                    </div>
                    <script>
                        document.getElementById('btnCopiarPass').addEventListener('click', function () {
                            var texto = document.getElementById('passGenerada').textContent;
                            function ok() { var b = document.getElementById('btnCopiarPass'); b.textContent = '¡Copiada!'; b.disabled = true; }
                            if (navigator.clipboard && navigator.clipboard.writeText) {
                                navigator.clipboard.writeText(texto).then(ok);
                            } else {
                                var tmp = document.createElement('input');
                                document.body.appendChild(tmp);
                                tmp.value = texto;
                                tmp.select();
                                document.execCommand('copy');
                                document.body.removeChild(tmp);
                                ok();
                            }
                        });
                    </script>
                </div>
            <?php endif; ?>

            <!-- Listado de directores -->
            <div class="table-container">
                <table>
                    <thead><tr><th>ID</th><th>Nombre</th><th>Email</th><th>Colegio</th><th>Estudiantes</th><th>Estado</th><th>Último login</th><th>Acciones</th></tr></thead>
                    <tbody>
                    <?php if (!$directores): ?>
                        <tr><td colspan="8" class="muted" style="text-align:center;padding:24px;">Aún no hay directores. Crea el primero con el formulario de abajo.</td></tr>
                    <?php else: foreach ($directores as $d): ?>
                        <tr>
                            <td><?= (int)$d['id'] ?></td>
                            <td><?= htmlspecialchars($d['nombre']) ?></td>
                            <td><?= htmlspecialchars($d['email']) ?></td>
                            <td><?= htmlspecialchars($d['colegio']) ?></td>
                            <td><strong><?= (int)$d['estudiantes'] ?></strong></td>
                            <td><?= ((int)$d['activo'] === 1) ? '<span class="badge badge-green">Activo</span>' : '<span class="badge badge-red">Inactivo</span>' ?></td>
                            <td><?= $d['ultimo_login'] ?? 'Nunca' ?></td>
                            <td style="white-space:nowrap;">
                                <form method="POST" style="display:inline;">
                                    <?= admin_csrf_field() ?>
                                    <input type="hidden" name="toggle_director" value="1">
                                    <input type="hidden" name="director_id" value="<?= (int)$d['id'] ?>">
                                    <button type="submit" class="btn <?= ((int)$d['activo'] === 1) ? 'btn-danger' : 'btn-success' ?>" style="padding:6px 12px;font-size:12px;"><?= ((int)$d['activo'] === 1) ? 'Desactivar' : 'Activar' ?></button>
                                </form>
                                <form method="POST" style="display:inline;" onsubmit="return confirm('¿Restablecer la contraseña de este director?');">
                                    <?= admin_csrf_field() ?>
                                    <input type="hidden" name="reset_director_pass" value="1">
                                    <input type="hidden" name="director_id" value="<?= (int)$d['id'] ?>">
                                    <button type="submit" class="btn btn-primary" style="padding:6px 12px;font-size:12px;">Reset contraseña</button>
                                </form>
                            </td>
                        </tr>
                    <?php endforeach; endif; ?>
                    </tbody>
                </table>
            </div>

            <!-- Crear director -->
            <div class="section-card">
                <h3 class="section-title">&#10133; Crear director de colegio</h3>
                <p class="muted" style="margin-bottom:16px;">
                    El director solo verá los estudiantes cuyo colegio coincida exactamente con el asignado.
                    Podrá consultar reportes de simulacros y activar/desactivar estudiantes de su colegio
                    (ingresa en <code>backend/director/login.php</code>).
                </p>
                <form method="POST">
                    <?= admin_csrf_field() ?>
                    <input type="hidden" name="crear_director" value="1">
                    <div class="grid-2">
                        <div class="form-group">
                            <label>Nombre completo</label>
                            <input type="text" name="nombre" required maxlength="120">
                        </div>
                        <div class="form-group">
                            <label>Email</label>
                            <input type="email" name="email" required maxlength="190">
                        </div>
                        <div class="form-group">
                            <label>Colegio (selecciona uno existente o escribe uno nuevo)</label>
                            <input type="text" name="colegio" list="listaColegios" required maxlength="190">
                            <datalist id="listaColegios">
                                <?php foreach ($colegiosDatalist as $col): ?>
                                    <option value="<?= htmlspecialchars((string)$col) ?>"></option>
                                <?php endforeach; ?>
                            </datalist>
                        </div>
                        <div class="form-group">
                            <label>Teléfono (opcional)</label>
                            <input type="tel" name="telefono" maxlength="30">
                        </div>
                        <div class="form-group" style="grid-column: 1 / -1;">
                            <label>Contraseña (sugerencia segura autogenerada — puedes cambiarla, mínimo 8 caracteres)</label>
                            <input type="text" name="password" value="<?= htmlspecialchars($sugerenciaPass, ENT_QUOTES, 'UTF-8') ?>" minlength="8" required autocomplete="off" class="mono">
                        </div>
                    </div>
                    <button type="submit" class="btn btn-primary">Crear director</button>
                </form>
            </div>

        <?php endif; ?>

    <?php endif; ?>
</div>
</body>
</html>