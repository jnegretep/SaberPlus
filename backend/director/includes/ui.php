<?php
/**
 * includes/ui.php — Layout y helpers visuales del Panel del Director (Saber+)
 *
 * MISMA identidad visual que backend/admin/index.php:
 * sidebar azul #1E4ED8 de 240px, tarjetas blancas radius 16, badges, botones.
 *
 * Uso en cada página:
 *     panel_head('Título de la página', 'clave_de_seccion', $director);
 *     ... HTML de la página ...
 *     panel_footer();
 */

require_once __DIR__ . '/auth.php';

/**
 * Abre el documento HTML: <head> con estilos, sidebar de navegación y
 * header con el nombre del colegio y el nombre del director.
 * $activo: 'dashboard' | 'estudiantes' | 'simulacros'.
 */
function panel_head($titulo, $activo, $director)
{
    $items = [
        'dashboard'   => ['index.php',       '&#128202;', 'Dashboard'],
        'estudiantes' => ['estudiantes.php', '&#128101;', 'Estudiantes'],
        'simulacros'  => ['simulacros.php', '&#128196;', 'Simulacros y Reportes'],
    ];
?><!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= e($titulo) ?> — Saber+ Director</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f4f6fa; color: #1a1a2e; }
        .sidebar { position: fixed; left: 0; top: 0; width: 240px; height: 100vh; background: #1E4ED8; color: white; padding: 24px 0; overflow-y: auto; z-index: 100; display: flex; flex-direction: column; }
        .sidebar-header { text-align: center; margin-bottom: 32px; }
        .logo-box img { width: 56px; height: 56px; object-fit: contain; border-radius: 14px; background: white; padding: 5px; }
        .logo-box h1 { display: none; font-size: 22px; font-weight: 800; }
        .logo-box.sin-logo img { display: none; }
        .logo-box.sin-logo h1 { display: block; }
        .sidebar-header p { font-size: 11px; opacity: 0.7; margin-top: 8px; }
        .nav-item { display: flex; align-items: center; gap: 12px; padding: 12px 24px; color: rgba(255,255,255,0.8); text-decoration: none; font-size: 14px; font-weight: 500; transition: 0.2s; border-left: 3px solid transparent; }
        .nav-item:hover, .nav-item.active { background: rgba(255,255,255,0.1); color: white; border-left-color: #FACC15; }
        .nav-icon { font-size: 18px; width: 24px; text-align: center; }
        .nav-footer { margin-top: auto; color: rgba(255,255,255,0.5); }
        .main-content { margin-left: 240px; padding: 32px; min-height: 100vh; }
        .header-bar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 28px; flex-wrap: wrap; gap: 12px; }
        .header-bar h2 { font-size: 24px; font-weight: 800; }
        .colegio-line { font-size: 13px; color: #64748b; margin-top: 2px; }
        .header-right { display: flex; align-items: center; gap: 14px; flex-wrap: wrap; }
        .director-chip { font-size: 13px; font-weight: 600; color: #334155; background: white; padding: 8px 14px; border-radius: 20px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }
        .logout-btn { background: #EF4444; color: white; padding: 8px 16px; border-radius: 8px; text-decoration: none; font-size: 13px; font-weight: 600; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(210px, 1fr)); gap: 16px; margin-bottom: 32px; }
        .stat-card { background: white; border-radius: 16px; padding: 24px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }
        .stat-card .stat-icon { width: 48px; height: 48px; border-radius: 12px; display: flex; align-items: center; justify-content: center; font-size: 24px; margin-bottom: 12px; }
        .stat-card .stat-value { font-size: 30px; font-weight: 800; }
        .stat-card .stat-label { font-size: 13px; color: #888; margin-top: 4px; }
        .stat-card .stat-change { font-size: 12px; margin-top: 8px; color: #64748b; }
        .table-container { background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.06); margin-bottom: 24px; overflow-x: auto; }
        table { width: 100%; border-collapse: collapse; }
        th { background: #f8fafc; padding: 12px 16px; text-align: left; font-size: 12px; font-weight: 700; color: #64748b; text-transform: uppercase; white-space: nowrap; }
        td { padding: 12px 16px; border-top: 1px solid #f1f5f9; font-size: 14px; }
        tr:hover td { background: #f8fafc; }
        .badge { display: inline-block; padding: 4px 10px; border-radius: 20px; font-size: 11px; font-weight: 700; }
        .badge-green { background: #D1FAE5; color: #065F46; }
        .badge-blue { background: #DBEAFE; color: #1E40AF; }
        .badge-orange { background: #FED7AA; color: #9A3412; }
        .badge-purple { background: #E9D5FF; color: #6B21A8; }
        .badge-red { background: #FEE2E2; color: #991B1B; }
        .section-card { background: white; border-radius: 16px; padding: 24px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); margin-bottom: 24px; }
        .section-title { font-size: 18px; font-weight: 700; margin-bottom: 16px; }
        .btn { display: inline-block; padding: 10px 20px; border-radius: 10px; font-size: 14px; font-weight: 600; text-decoration: none; cursor: pointer; border: none; transition: 0.2s; font-family: inherit; }
        .btn-primary { background: #1E4ED8; color: white; }
        .btn-success { background: #22C55E; color: white; }
        .btn-danger { background: #EF4444; color: white; }
        .btn-outline { background: white; color: #1E4ED8; border: 2px solid #1E4ED8; }
        .btn-sm { padding: 6px 12px; font-size: 12px; border-radius: 8px; }
        .btn:hover { opacity: 0.9; }
        .form-group { margin-bottom: 16px; }
        .form-group label { display: block; font-size: 13px; font-weight: 600; margin-bottom: 6px; color: #555; }
        .form-group input, .form-group select { width: 100%; padding: 10px 14px; border: 2px solid #e2e8f0; border-radius: 10px; font-size: 14px; background: white; font-family: inherit; }
        .form-group input:focus, .form-group select:focus { outline: none; border-color: #1E4ED8; }
        .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }
        .muted { color: #94A3B8; font-size: 13px; }
        .mono { font-family: ui-monospace, 'SF Mono', Menlo, Consolas, monospace; font-size: 12px; }
        .empty-state { text-align: center; padding: 36px; color: #94A3B8; font-size: 14px; }
        .flash-ok { background: #D1FAE5; color: #065F46; border-radius: 12px; padding: 12px 18px; margin-bottom: 20px; font-size: 14px; font-weight: 600; }
        .flash-err { background: #FEE2E2; color: #991B1B; border-radius: 12px; padding: 12px 18px; margin-bottom: 20px; font-size: 14px; font-weight: 600; }
        /* Avatar circular con inicial coloreada */
        .user-cell { display: flex; align-items: center; gap: 10px; }
        .avatar-circle { width: 34px; height: 34px; border-radius: 50%; color: white; display: inline-flex; align-items: center; justify-content: center; font-size: 14px; font-weight: 700; flex-shrink: 0; }
        /* Gráfico de barras verticales (CSS puro, sin JS) */
        .chart-wrap { display: flex; align-items: flex-end; gap: 14px; height: 190px; padding: 10px 4px 0; }
        .chart-col { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: flex-end; height: 100%; min-width: 0; }
        .chart-bar { width: 68%; max-width: 52px; background: linear-gradient(180deg, #3B82F6, #1E4ED8); border-radius: 8px 8px 4px 4px; min-height: 3px; }
        .chart-bar-val { font-size: 12px; font-weight: 700; color: #334155; margin-bottom: 6px; }
        .chart-bar-label { font-size: 12px; color: #64748b; margin-top: 8px; text-align: center; }
        /* Barras horizontales */
        .bar-row { display: flex; align-items: center; gap: 10px; margin-bottom: 6px; }
        .bar-label { width: 130px; font-size: 12px; color: #64748b; text-align: right; flex-shrink: 0; }
        .bar-track { flex: 1; background: #f1f5f9; border-radius: 6px; height: 18px; overflow: hidden; }
        .bar-fill { height: 100%; background: #1E4ED8; border-radius: 6px; min-width: 2px; }
        .bar-fill.green { background: #22C55E; }
        .bar-fill.orange { background: #F59E0B; }
        .bar-value { width: 60px; font-size: 12px; font-weight: 700; color: #334155; flex-shrink: 0; }
        /* Colores de puntaje por área (escala 0-100) */
        .score-verde { color: #16A34A; font-weight: 700; }
        .score-naranja { color: #EA580C; font-weight: 700; }
        .score-rojo { color: #DC2626; font-weight: 700; }
        /* Barra de filtros */
        .filters-bar { display: flex; gap: 12px; flex-wrap: wrap; align-items: flex-end; background: white; border-radius: 16px; padding: 16px 20px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); margin-bottom: 24px; }
        .filters-bar .form-group { margin: 0; min-width: 150px; flex: 1; max-width: 230px; }
        .filters-bar .btn { flex-shrink: 0; }
        /* Paginación */
        .pagination { display: flex; gap: 8px; align-items: center; margin-top: 16px; flex-wrap: wrap; }
        .pagination a, .pagination span { padding: 8px 14px; border-radius: 10px; background: white; color: #1E4ED8; text-decoration: none; font-size: 13px; font-weight: 600; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }
        .pagination .current { background: #1E4ED8; color: white; }
        @media (max-width: 768px) {
            .sidebar { position: static; width: 100%; height: auto; padding: 14px 0; }
            .sidebar-header { margin-bottom: 10px; }
            .nav-item { display: inline-flex; border-left: none; border-bottom: 3px solid transparent; padding: 8px 14px; }
            .nav-item:hover, .nav-item.active { border-left-color: transparent; border-bottom-color: #FACC15; }
            .nav-footer { margin-top: 0; }
            .main-content { margin-left: 0; padding: 16px; }
            .grid-2 { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>

<!-- Sidebar -->
<div class="sidebar">
    <div class="sidebar-header">
        <div class="logo-box">
            <img src="../logo.jpg" alt="Saber+" onerror="this.parentElement.classList.add('sin-logo')">
            <h1>Saber+</h1>
        </div>
        <p>Panel del Director</p>
    </div>
    <?php foreach ($items as $clave => $item): ?>
        <a href="<?= e($item[0]) ?>" class="nav-item<?= $clave === $activo ? ' active' : '' ?>"><span class="nav-icon"><?= $item[1] ?></span> <?= e($item[2]) ?></a>
    <?php endforeach; ?>
    <a href="logout.php" class="nav-item nav-footer"><span class="nav-icon">&#10148;</span> Cerrar sesión</a>
</div>

<!-- Contenido principal -->
<div class="main-content">
    <div class="header-bar">
        <div>
            <h2><?= e($titulo) ?></h2>
            <p class="colegio-line"><?= e($director['colegio']) ?></p>
        </div>
        <div class="header-right">
            <span class="director-chip">Director: <?= e($director['nombre']) ?></span>
            <a href="logout.php" class="logout-btn">Cerrar sesión</a>
        </div>
    </div>
<?php
}

/** Cierra el documento HTML abierto por panel_head(). */
function panel_footer()
{
    echo "</div>\n</body>\n</html>";
}

/** Badge de estado del estudiante (activo/inactivo). */
function badge_estado($activo)
{
    return ((int)$activo === 1)
        ? '<span class="badge badge-green">Activo</span>'
        : '<span class="badge badge-red">Inactivo</span>';
}

/** Círculo con la inicial del nombre, color estable por hash del nombre. */
function avatar_inicial($nombre)
{
    $limpio = trim((string)$nombre);
    $inicial = mb_strtoupper(mb_substr($limpio !== '' ? $limpio : '?', 0, 1));
    $paleta = ['#1E4ED8', '#0891B2', '#7C3AED', '#DB2777', '#EA580C', '#16A34A', '#B45309', '#4F46E5'];
    $color = $paleta[crc32($limpio) % count($paleta)];
    return '<span class="avatar-circle" style="background: ' . $color . '">' . e($inicial) . '</span>';
}

/**
 * Clase CSS según puntaje de área (escala 0-100):
 * >= 70 verde · 50-69 naranja · < 50 rojo · null → muted.
 */
function clase_puntaje($puntaje)
{
    if ($puntaje === null) {
        return 'muted';
    }
    $p = (float)$puntaje;
    if ($p >= 70) {
        return 'score-verde';
    }
    if ($p >= 50) {
        return 'score-naranja';
    }
    return 'score-rojo';
}

/** Formatea 'YYYY-MM-DD HH:MM:SS' como 'DD/MM/YYYY' (o '—' si vacío). */
function fecha_corta($fecha)
{
    $ts = strtotime((string)$fecha);
    return $ts ? date('d/m/Y', $ts) : '—';
}

/** Formatea 'YYYY-MM-DD HH:MM:SS' como 'DD/MM/YYYY HH:MM' (o '—'). */
function fecha_hora_corta($fecha)
{
    $ts = strtotime((string)$fecha);
    return $ts ? date('d/m/Y H:i', $ts) : '—';
}
