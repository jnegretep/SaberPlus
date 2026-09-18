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

// ── Obtener estadisticas globales ──
 $stats = [];
try {
    $stats['total_users'] = (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE email_verificado = 1")->fetchColumn();
    $stats['active_users_7d'] = (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE ultimo_login >= DATE_SUB(NOW(), INTERVAL 7 DAY)")->fetchColumn();
    $stats['active_users_today'] = (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE ultimo_login >= CURDATE()")->fetchColumn();
    $stats['total_simulacros'] = (int)$conexion->query("SELECT COUNT(*) FROM simulacro_resultados")->fetchColumn();
    $stats['avg_score'] = round((float)$conexion->query("SELECT AVG(puntaje_global) FROM simulacro_resultados")->fetchColumn(), 1);
    $stats['premium_users'] = (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE access_level IN ('premium', 'early_bird')")->fetchColumn();
    $stats['free_users'] = (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE access_level = 'free'")->fetchColumn();
    $stats['total_challenges'] = (int)$conexion->query("SELECT COUNT(*) FROM challenges WHERE estado = 'finished'")->fetchColumn();
    $stats['total_xp'] = (int)$conexion->query("SELECT COALESCE(SUM(total_xp), 0) FROM user_gamification")->fetchColumn();
    $stats['notifications_today'] = (int)$conexion->query("SELECT COUNT(*) FROM notifications WHERE DATE(created_at) = CURDATE()")->fetchColumn();
    $stats['new_users_today'] = (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE DATE(registration_date) = CURDATE()")->fetchColumn();
    $stats['new_users_week'] = (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE registration_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)")->fetchColumn();
} catch (Exception $e) {
    error_log("[ADMIN] Error obteniendo stats: " . $e->getMessage());
}
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
    <a href="index.php?section=ads" class="nav-item <?= $section === 'ads' ? 'active' : '' ?>"><span class="nav-icon">&#128227;</span> Anuncios</a>
    <a href="index.php?section=plans" class="nav-item <?= $section === 'plans' ? 'active' : '' ?>"><span class="nav-icon">&#128179;</span> Planes</a>
    <a href="index.php?section=notifications" class="nav-item <?= $section === 'notifications' ? 'active' : '' ?>"><span class="nav-icon">&#128276;</span> Notificaciones</a>
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

    <?php elseif ($section === 'users'): ?>
        <!-- USUARIOS -->
        <div class="table-container">
            <table>
                <thead><tr><th>ID</th><th>Nombre</th><th>Email</th><th>Tipo</th><th>Plan</th><th>Verificado</th><th>Ciudad</th><th>Colegio</th><th>Registro</th><th>Ultimo Login</th></tr></thead>
                <tbody>
                <?php
                $users = $conexion->query("
                    SELECT id_usuario, nombre, email, tipo_usuario, access_level,
                           email_verificado, ciudad, colegio, registration_date, ultimo_login
                    FROM usuarios ORDER BY id_usuario DESC LIMIT 100
                ")->fetchAll(PDO::FETCH_ASSOC);
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
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>

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
    <?php endif; ?>
</div>
</body>
</html>