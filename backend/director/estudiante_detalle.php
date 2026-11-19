<?php
/**
 * estudiante_detalle.php — Ficha completa de un estudiante (Panel del Director)
 *
 * - Valida que el estudiante pertenezca AL COLEGIO de la sesión (si no → 403).
 * - Muestra: datos personales, todos sus simulacros con puntajes por área
 *   (>=70 verde · 50-69 naranja · <50 rojo), promedios por área, XP/nivel/racha
 *   y evolución del puntaje global.
 */

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/ui.php';

$director = require_director($conexion);
$colegio  = $director['colegio'];

$id = (int)($_GET['id'] ?? 0);
if ($id <= 0) {
    http_response_code(404);
    exit('Estudiante no encontrado.');
}

try {
    // 🔒 Scoped por colegio de sesión + tipo estudiante
    $stmt = $conexion->prepare(
        "SELECT id_usuario, moodle_id, nombre, email, telefono, departamento, ciudad,
                colegio, grado, email_verificado, registration_date, ultimo_login, activo
         FROM usuarios
         WHERE id_usuario = :id AND colegio = :colegio AND tipo_usuario = 'estudiante'
         LIMIT 1"
    );
    $stmt->execute([':id' => $id, ':colegio' => $colegio]);
    $estudiante = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$estudiante) {
        http_response_code(403);
        exit('Acceso denegado: este estudiante no pertenece a tu colegio.');
    }

    // Gamificación (user_gamification.user_id → usuarios.id_usuario)
    $gam = ['total_xp' => 0, 'current_level' => 1, 'current_streak' => 0];
    $stmt = $conexion->prepare(
        "SELECT total_xp, current_level, current_streak
         FROM user_gamification
         WHERE user_id = :uid
         LIMIT 1"
    );
    $stmt->execute([':uid' => $id]);
    $fila = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($fila) {
        $gam = [
            'total_xp'       => (int)$fila['total_xp'],
            'current_level'  => (int)$fila['current_level'],
            'current_streak' => (int)$fila['current_streak'],
        ];
    }

    // Todos los simulacros del estudiante (usuario_id → moodle_id)
    $stmt = $conexion->prepare(
        "SELECT sr.id, sr.puntaje_global, sr.lectura_puntaje, sr.matematicas_puntaje,
                sr.sociales_puntaje, sr.naturales_puntaje, sr.ingles_puntaje, sr.fecha_realizacion
         FROM simulacro_resultados sr
         WHERE sr.usuario_id = :moodle_id
         ORDER BY sr.fecha_realizacion ASC, sr.id ASC"
    );
    $stmt->execute([':moodle_id' => (int)$estudiante['moodle_id']]);
    $simulacros = $stmt->fetchAll(PDO::FETCH_ASSOC);
} catch (PDOException $ex) {
    error_log('[DIRECTOR] estudiante_detalle: ' . $ex->getMessage());
    http_response_code(500);
    exit('Error cargando los datos del estudiante. Intenta más tarde.');
}

// ── Cálculos en PHP sobre los simulacros ──
$numSim = count($simulacros);
$mejor  = null;
$suma   = 0.0;
$columnas = [
    'lectura'     => 'lectura_puntaje',
    'matematicas' => 'matematicas_puntaje',
    'sociales'    => 'sociales_puntaje',
    'naturales'   => 'naturales_puntaje',
    'ingles'      => 'ingles_puntaje',
];
$sumas      = array_fill_keys(array_keys($columnas), 0.0);
$contadores = array_fill_keys(array_keys($columnas), 0);
$proms      = array_fill_keys(array_keys($columnas), null);

foreach ($simulacros as $s) {
    $global = (float)$s['puntaje_global'];
    $suma += $global;
    if ($mejor === null || $global > $mejor) {
        $mejor = $global;
    }
    foreach ($columnas as $clave => $col) {
        if ($s[$col] !== null) {
            $sumas[$clave]      += (float)$s[$col];
            $contadores[$clave] += 1;
        }
    }
}
foreach ($columnas as $clave => $col) {
    $proms[$clave] = $contadores[$clave] > 0
        ? round($sumas[$clave] / $contadores[$clave], 1)
        : null;
}
$promedioGlobal = $numSim > 0 ? round($suma / $numSim, 1) : null;
$maxGlobal      = ($mejor !== null && $mejor > 0) ? $mejor : 1; // escala para las barras

$nombresAreas = [
    'lectura'     => 'Lectura Crítica',
    'matematicas' => 'Matemáticas',
    'sociales'    => 'Sociales y Ciudadanas',
    'naturales'   => 'Ciencias Naturales',
    'ingles'      => 'Inglés',
];

panel_head('Detalle del estudiante', 'estudiantes', $director);
?>

<a href="estudiantes.php" class="btn btn-outline" style="margin-bottom:20px;">&laquo; Volver al listado</a>

<!-- Cabecera del estudiante -->
<div class="section-card">
    <div style="display:flex;align-items:center;gap:16px;flex-wrap:wrap;margin-bottom:20px;">
        <?= avatar_inicial($estudiante['nombre']) ?>
        <div>
            <h3 class="section-title" style="margin-bottom:2px;"><?= e($estudiante['nombre']) ?></h3>
            <span class="muted"><?= e($estudiante['email']) ?></span>
        </div>
        <div style="margin-left:auto;display:flex;gap:8px;align-items:center;">
            <?= badge_estado($estudiante['activo']) ?>
            <a href="export_csv.php?tipo=detalle&amp;user_id=<?= $id ?>" class="btn btn-success">&#11015; Exportar CSV</a>
        </div>
    </div>
    <div class="grid-2">
        <table>
            <tbody>
                <tr><td class="muted" style="width:180px;">Grado</td><td><strong><?= e($estudiante['grado'] !== '' && $estudiante['grado'] !== null ? $estudiante['grado'] : '—') ?></strong></td></tr>
                <tr><td class="muted">Teléfono</td><td><?= trim((string)($estudiante['telefono'] ?? '')) !== '' ? e($estudiante['telefono']) : '—' ?></td></tr>
                <tr><td class="muted">Departamento</td><td><?= trim((string)($estudiante['departamento'] ?? '')) !== '' ? e($estudiante['departamento']) : '—' ?></td></tr>
                <tr><td class="muted">Ciudad</td><td><?= trim((string)($estudiante['ciudad'] ?? '')) !== '' ? e($estudiante['ciudad']) : '—' ?></td></tr>
            </tbody>
        </table>
        <table>
            <tbody>
                <tr><td class="muted" style="width:180px;">Colegio</td><td><?= e($estudiante['colegio']) ?></td></tr>
                <tr><td class="muted">Email verificado</td><td><?= ((int)$estudiante['email_verificado'] === 1) ? '<span class="badge badge-green">Sí</span>' : '<span class="badge badge-orange">No</span>' ?></td></tr>
                <tr><td class="muted">Registro</td><td><?= fecha_corta($estudiante['registration_date']) ?></td></tr>
                <tr><td class="muted">Último login</td><td><?= fecha_hora_corta($estudiante['ultimo_login']) ?></td></tr>
            </tbody>
        </table>
    </div>
</div>

<!-- Métricas clave -->
<div class="stats-grid">
    <div class="stat-card">
        <div class="stat-icon" style="background: #DBEAFE;">&#9889;</div>
        <div class="stat-value"><?= number_format($gam['total_xp'], 0, ',', '.') ?></div>
        <div class="stat-label">XP total</div>
    </div>
    <div class="stat-card">
        <div class="stat-icon" style="background: #E9D5FF;">&#127942;</div>
        <div class="stat-value">Nivel <?= $gam['current_level'] ?></div>
        <div class="stat-label">Nivel actual</div>
    </div>
    <div class="stat-card">
        <div class="stat-icon" style="background: #FED7AA;">&#128293;</div>
        <div class="stat-value"><?= $gam['current_streak'] ?> días</div>
        <div class="stat-label">Racha actual</div>
    </div>
    <div class="stat-card">
        <div class="stat-icon" style="background: #FEF3C7;">&#128221;</div>
        <div class="stat-value"><?= $numSim ?></div>
        <div class="stat-label">Simulacros realizados</div>
    </div>
    <div class="stat-card">
        <div class="stat-icon" style="background: #D1FAE5;">&#128200;</div>
        <div class="stat-value"><?= $promedioGlobal !== null ? number_format($promedioGlobal, 1, ',', '.') : '—' ?></div>
        <div class="stat-label">Promedio global</div>
    </div>
    <div class="stat-card">
        <div class="stat-icon" style="background: #FEE2E2;">&#11088;</div>
        <div class="stat-value"><?= $mejor !== null ? number_format($mejor, 0, ',', '.') : '—' ?></div>
        <div class="stat-label">Mejor puntaje global</div>
    </div>
</div>

<div class="grid-2">
    <!-- Promedios por área (barras) -->
    <div class="section-card">
        <h3 class="section-title">Promedios por área (0-100)</h3>
        <?php foreach ($nombresAreas as $clave => $nombreArea): ?>
            <?php $valor = $proms[$clave]; ?>
            <div class="bar-row">
                <div class="bar-label"><?= e($nombreArea) ?></div>
                <div class="bar-track">
                    <div class="bar-fill <?= $valor !== null ? (($valor >= 70) ? 'green' : (($valor >= 50) ? 'orange' : '')) : '' ?>"
                         style="width: <?= $valor !== null ? max(1, (int)round($valor)) : 0 ?>%;"></div>
                </div>
                <div class="bar-value"><span class="<?= clase_puntaje($valor) ?>"><?= $valor !== null ? number_format($valor, 1, ',', '.') : '—' ?></span></div>
            </div>
        <?php endforeach; ?>
    </div>

    <!-- Evolución del puntaje global -->
    <div class="section-card">
        <h3 class="section-title">Evolución del puntaje global</h3>
        <?php if ($numSim === 0): ?>
            <p class="empty-state">Este estudiante aún no ha realizado simulacros.</p>
        <?php else: ?>
            <div class="chart-wrap">
                <?php foreach ($simulacros as $s): ?>
                    <?php $altura = max(3, (int)round(((float)$s['puntaje_global'] / $maxGlobal) * 150)); ?>
                    <div class="chart-col">
                        <div class="chart-bar-val"><?= number_format((float)$s['puntaje_global'], 0, ',', '.') ?></div>
                        <div class="chart-bar" style="height: <?= $altura ?>px;"></div>
                        <div class="chart-bar-label"><?= fecha_corta($s['fecha_realizacion']) ?></div>
                    </div>
                <?php endforeach; ?>
            </div>
        <?php endif; ?>
    </div>
</div>

<!-- Tabla de todos los simulacros -->
<div class="section-card">
    <h3 class="section-title">Historial de simulacros</h3>
    <?php if ($numSim === 0): ?>
        <p class="empty-state">Este estudiante aún no ha realizado simulacros.</p>
    <?php else: ?>
        <div class="table-container">
            <table>
                <thead>
                    <tr>
                        <th>#</th>
                        <th>Fecha</th>
                        <th>Global</th>
                        <th>Lectura Crítica</th>
                        <th>Matemáticas</th>
                        <th>Sociales</th>
                        <th>Naturales</th>
                        <th>Inglés</th>
                    </tr>
                </thead>
                <tbody>
                <?php foreach ($simulacros as $i => $s): ?>
                    <tr>
                        <td><?= $i + 1 ?></td>
                        <td><?= fecha_hora_corta($s['fecha_realizacion']) ?></td>
                        <td><strong><?= number_format((float)$s['puntaje_global'], 0, ',', '.') ?></strong></td>
                        <td class="<?= clase_puntaje($s['lectura_puntaje']) ?>"><?= $s['lectura_puntaje'] !== null ? number_format((float)$s['lectura_puntaje'], 0, ',', '.') : '—' ?></td>
                        <td class="<?= clase_puntaje($s['matematicas_puntaje']) ?>"><?= $s['matematicas_puntaje'] !== null ? number_format((float)$s['matematicas_puntaje'], 0, ',', '.') : '—' ?></td>
                        <td class="<?= clase_puntaje($s['sociales_puntaje']) ?>"><?= $s['sociales_puntaje'] !== null ? number_format((float)$s['sociales_puntaje'], 0, ',', '.') : '—' ?></td>
                        <td class="<?= clase_puntaje($s['naturales_puntaje']) ?>"><?= $s['naturales_puntaje'] !== null ? number_format((float)$s['naturales_puntaje'], 0, ',', '.') : '—' ?></td>
                        <td class="<?= clase_puntaje($s['ingles_puntaje']) ?>"><?= $s['ingles_puntaje'] !== null ? number_format((float)$s['ingles_puntaje'], 0, ',', '.') : '—' ?></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>
    <?php endif; ?>
</div>

<?php panel_footer(); ?>
