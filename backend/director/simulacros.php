<?php
/**
 * simulacros.php — Reportes agregados de simulacros (Panel del Director)
 *
 * - Filtros por rango de fechas (date inputs) y grado.
 * - Query agrupada por DATE(fecha_realizacion): participantes del colegio,
 *   promedio global, promedio por área, mínimo y máximo.
 * - Siempre scoped al colegio de la sesión + tipo_usuario='estudiante'.
 */

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/ui.php';

$director = require_director($conexion);
$colegio  = $director['colegio'];

// ── Filtros GET (validados) ──
$desde = (string)($_GET['desde'] ?? '');
$hasta = (string)($_GET['hasta'] ?? '');
$grado = trim((string)($_GET['grado'] ?? ''));

if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $desde)) {
    $desde = '';
}
if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $hasta)) {
    $hasta = '';
}

// Clausulas fijas (sin input del usuario) + parámetros bind
$where  = ['u.colegio = :colegio', "u.tipo_usuario = 'estudiante'"];
$params = [':colegio' => $colegio];

if ($desde !== '') {
    $where[] = 'sr.fecha_realizacion >= :desde';
    $params[':desde'] = $desde . ' 00:00:00';
}
if ($hasta !== '') {
    $where[] = 'sr.fecha_realizacion <= :hasta';
    $params[':hasta'] = $hasta . ' 23:59:59';
}
if ($grado !== '') {
    $where[] = 'u.grado = :grado';
    $params[':grado'] = $grado;
}
$whereSql = implode(' AND ', $where);

$filas       = [];
$grados      = [];
$totalSim    = 0;
$participantes = 0;
$promedioRango = null;
$errorDatos  = false;

try {
    // Grados disponibles (para el filtro)
    $stmt = $conexion->prepare(
        "SELECT DISTINCT grado
         FROM usuarios
         WHERE colegio = :colegio AND tipo_usuario = 'estudiante'
           AND grado IS NOT NULL AND TRIM(grado) <> ''
         ORDER BY grado"
    );
    $stmt->execute([':colegio' => $colegio]);
    $grados = $stmt->fetchAll(PDO::FETCH_COLUMN);

    // Reporte agrupado por fecha
    $stmt = $conexion->prepare(
        "SELECT DATE(sr.fecha_realizacion) AS fecha,
                COUNT(*) AS total,
                COUNT(DISTINCT sr.usuario_id) AS participantes,
                ROUND(AVG(sr.puntaje_global), 1) AS promedio,
                MIN(sr.puntaje_global) AS minimo,
                MAX(sr.puntaje_global) AS maximo,
                ROUND(AVG(sr.lectura_puntaje), 1)    AS lectura,
                ROUND(AVG(sr.matematicas_puntaje), 1) AS matematicas,
                ROUND(AVG(sr.sociales_puntaje), 1)    AS sociales,
                ROUND(AVG(sr.naturales_puntaje), 1)   AS naturales,
                ROUND(AVG(sr.ingles_puntaje), 1)      AS ingles
         FROM simulacro_resultados sr
         INNER JOIN usuarios u ON sr.usuario_id = u.moodle_id
         WHERE " . $whereSql . "
         GROUP BY DATE(sr.fecha_realizacion)
         ORDER BY fecha DESC
         LIMIT 366"
    );
    foreach ($params as $k => $v) {
        $stmt->bindValue($k, $v);
    }
    $stmt->execute();
    $filas = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Resumen del rango: total, participantes únicos y promedio global
    $stmt = $conexion->prepare(
        "SELECT COUNT(*) AS total,
                COUNT(DISTINCT sr.usuario_id) AS participantes,
                ROUND(AVG(sr.puntaje_global), 1) AS promedio
         FROM simulacro_resultados sr
         INNER JOIN usuarios u ON sr.usuario_id = u.moodle_id
         WHERE " . $whereSql
    );
    foreach ($params as $k => $v) {
        $stmt->bindValue($k, $v);
    }
    $stmt->execute();
    $resumen = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($resumen) {
        $totalSim      = (int)$resumen['total'];
        $participantes = (int)$resumen['participantes'];
        $promedioRango = ($resumen['promedio'] !== null) ? (float)$resumen['promedio'] : null;
    }
} catch (PDOException $ex) {
    error_log('[DIRECTOR] simulacros: ' . $ex->getMessage());
    $errorDatos = true;
}

// Querystring de filtros para exportar y reutilizar enlaces
$filtros = [];
if ($desde !== '') { $filtros['desde'] = $desde; }
if ($hasta !== '') { $filtros['hasta'] = $hasta; }
if ($grado !== '') { $filtros['grado'] = $grado; }
$urlExport = 'export_csv.php?' . http_build_query(array_merge(['tipo' => 'simulacros'], $filtros));

panel_head('Simulacros y Reportes', 'simulacros', $director);
?>

<?php if ($errorDatos): ?>
    <div class="flash-err">No se pudo cargar el reporte en este momento. Intenta de nuevo más tarde.</div>
<?php endif; ?>

<!-- Resumen del rango -->
<div class="stats-grid">
    <div class="stat-card">
        <div class="stat-icon" style="background: #FEF3C7;">&#128221;</div>
        <div class="stat-value"><?= number_format($totalSim, 0, ',', '.') ?></div>
        <div class="stat-label">Simulacros en el rango</div>
    </div>
    <div class="stat-card">
        <div class="stat-icon" style="background: #DBEAFE;">&#128101;</div>
        <div class="stat-value"><?= number_format($participantes, 0, ',', '.') ?></div>
        <div class="stat-label">Estudiantes participantes</div>
    </div>
    <div class="stat-card">
        <div class="stat-icon" style="background: #D1FAE5;">&#128200;</div>
        <div class="stat-value"><?= $promedioRango !== null ? number_format($promedioRango, 1, ',', '.') : '—' ?></div>
        <div class="stat-label">Promedio global en el rango</div>
    </div>
</div>

<!-- Barra de filtros -->
<form method="GET" action="simulacros.php" class="filters-bar">
    <div class="form-group">
        <label for="desde">Desde</label>
        <input type="date" id="desde" name="desde" value="<?= e($desde) ?>">
    </div>
    <div class="form-group">
        <label for="hasta">Hasta</label>
        <input type="date" id="hasta" name="hasta" value="<?= e($hasta) ?>">
    </div>
    <div class="form-group">
        <label for="f_grado">Grado</label>
        <select id="f_grado" name="grado">
            <option value="">Todos</option>
            <?php foreach ($grados as $g): ?>
                <option value="<?= e($g) ?>"<?= $g === $grado ? ' selected' : '' ?>><?= e($g) ?></option>
            <?php endforeach; ?>
        </select>
    </div>
    <button type="submit" class="btn btn-primary">Aplicar</button>
    <a href="simulacros.php" class="btn btn-outline">Limpiar</a>
    <a href="<?= e($urlExport) ?>" class="btn btn-success">&#11015; Exportar CSV</a>
</form>

<!-- Tabla del reporte -->
<div class="table-container">
    <table>
        <thead>
            <tr>
                <th>Fecha</th>
                <th>Participantes</th>
                <th>Simulacros</th>
                <th>Prom. global</th>
                <th>Lectura</th>
                <th>Matemáticas</th>
                <th>Sociales</th>
                <th>Naturales</th>
                <th>Inglés</th>
                <th>Mín</th>
                <th>Máx</th>
            </tr>
        </thead>
        <tbody>
        <?php if (!$filas): ?>
            <tr><td colspan="11" class="empty-state">No hay simulacros registrados con esos criterios.</td></tr>
        <?php else: foreach ($filas as $f): ?>
            <tr>
                <td><?= fecha_corta($f['fecha']) ?></td>
                <td><?= (int)$f['participantes'] ?></td>
                <td><?= (int)$f['total'] ?></td>
                <td><strong><?= $f['promedio'] !== null ? number_format((float)$f['promedio'], 1, ',', '.') : '—' ?></strong></td>
                <td class="<?= clase_puntaje($f['lectura']) ?>"><?= $f['lectura'] !== null ? number_format((float)$f['lectura'], 1, ',', '.') : '—' ?></td>
                <td class="<?= clase_puntaje($f['matematicas']) ?>"><?= $f['matematicas'] !== null ? number_format((float)$f['matematicas'], 1, ',', '.') : '—' ?></td>
                <td class="<?= clase_puntaje($f['sociales']) ?>"><?= $f['sociales'] !== null ? number_format((float)$f['sociales'], 1, ',', '.') : '—' ?></td>
                <td class="<?= clase_puntaje($f['naturales']) ?>"><?= $f['naturales'] !== null ? number_format((float)$f['naturales'], 1, ',', '.') : '—' ?></td>
                <td class="<?= clase_puntaje($f['ingles']) ?>"><?= $f['ingles'] !== null ? number_format((float)$f['ingles'], 1, ',', '.') : '—' ?></td>
                <td><?= $f['minimo'] !== null ? number_format((float)$f['minimo'], 0, ',', '.') : '—' ?></td>
                <td><?= $f['maximo'] !== null ? number_format((float)$f['maximo'], 0, ',', '.') : '—' ?></td>
            </tr>
        <?php endforeach; endif; ?>
        </tbody>
    </table>
</div>

<?php panel_footer(); ?>
