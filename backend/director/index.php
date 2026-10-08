<?php
/**
 * index.php — Dashboard del Panel del Director (Saber+)
 *
 * TODAS las consultas están scoped al colegio del director en sesión
 * ($_SESSION, NUNCA del request) y filtradas por tipo_usuario='estudiante'.
 * Nota: simulacro_resultados.usuario_id referencia a usuarios.moodle_id.
 */

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/ui.php';

$director = require_director($conexion);
$colegio  = $director['colegio'];

// ── Inicialización de métricas ──
$stats = [
    'estudiantes'       => 0,
    'activos'           => 0,
    'simulacros'        => 0,
    'promedio'          => null,
    'xp_total'          => 0,
    'mejor_area'        => null,
    'mejor_area_valor'  => null,
];
$mesesSerie   = []; // ['Y-m' => ['label' => 'Ene', 'total' => 0]]
$porGrado     = [];
$topXp        = [];
$errorDatos   = false;

try {
    // 1) Estudiantes registrados + activos (último login en 7 días)
    $stmt = $conexion->prepare(
        "SELECT COUNT(*) AS total,
                SUM(CASE WHEN ultimo_login >= DATE_SUB(NOW(), INTERVAL 7 DAY) THEN 1 ELSE 0 END) AS activos
         FROM usuarios
         WHERE colegio = :colegio AND tipo_usuario = 'estudiante'"
    );
    $stmt->execute([':colegio' => $colegio]);
    $fila = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($fila) {
        $stats['estudiantes'] = (int)$fila['total'];
        $stats['activos']     = (int)($fila['activos'] ?? 0);
    }

    // 2) Simulacros, promedio global del colegio y promedios por área
    $stmt = $conexion->prepare(
        "SELECT COUNT(sr.id) AS total,
                ROUND(AVG(sr.puntaje_global), 1) AS promedio,
                ROUND(AVG(sr.lectura_puntaje), 1)    AS lectura,
                ROUND(AVG(sr.matematicas_puntaje), 1) AS matematicas,
                ROUND(AVG(sr.sociales_puntaje), 1)    AS sociales,
                ROUND(AVG(sr.naturales_puntaje), 1)   AS naturales,
                ROUND(AVG(sr.ingles_puntaje), 1)      AS ingles
         FROM simulacro_resultados sr
         INNER JOIN usuarios u ON sr.usuario_id = u.moodle_id
         WHERE u.colegio = :colegio AND u.tipo_usuario = 'estudiante'"
    );
    $stmt->execute([':colegio' => $colegio]);
    $fila = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($fila) {
        $stats['simulacros'] = (int)$fila['total'];
        $stats['promedio']   = ($fila['promedio'] !== null) ? (float)$fila['promedio'] : null;

        // Mejor área: mayor promedio entre las 5 áreas
        $areas = [
            'Lectura Crítica'        => $fila['lectura'],
            'Matemáticas'            => $fila['matematicas'],
            'Sociales y Ciudadanas'  => $fila['sociales'],
            'Ciencias Naturales'     => $fila['naturales'],
            'Inglés'                 => $fila['ingles'],
        ];
        foreach ($areas as $nombreArea => $valor) {
            if ($valor !== null
                && ($stats['mejor_area_valor'] === null || (float)$valor > $stats['mejor_area_valor'])) {
                $stats['mejor_area']       = $nombreArea;
                $stats['mejor_area_valor'] = (float)$valor;
            }
        }
    }

    // 3) XP total del colegio
    $stmt = $conexion->prepare(
        "SELECT COALESCE(SUM(ug.total_xp), 0) AS xp
         FROM user_gamification ug
         INNER JOIN usuarios u ON ug.user_id = u.id_usuario
         WHERE u.colegio = :colegio AND u.tipo_usuario = 'estudiante'"
    );
    $stmt->execute([':colegio' => $colegio]);
    $stats['xp_total'] = (int)$stmt->fetchColumn();

    // 4) Simulacros por mes (últimos 6 meses, incluido el actual)
    $stmt = $conexion->prepare(
        "SELECT DATE_FORMAT(sr.fecha_realizacion, '%Y-%m') AS mes, COUNT(*) AS total
         FROM simulacro_resultados sr
         INNER JOIN usuarios u ON sr.usuario_id = u.moodle_id
         WHERE u.colegio = :colegio AND u.tipo_usuario = 'estudiante'
           AND sr.fecha_realizacion >= DATE_SUB(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 5 MONTH)
         GROUP BY DATE_FORMAT(sr.fecha_realizacion, '%Y-%m')"
    );
    $stmt->execute([':colegio' => $colegio]);
    $porMes = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $fila) {
        $porMes[$fila['mes']] = (int)$fila['total'];
    }

    $mesesEs = [1 => 'Ene', 2 => 'Feb', 3 => 'Mar', 4 => 'Abr', 5 => 'May', 6 => 'Jun',
                7 => 'Jul', 8 => 'Ago', 9 => 'Sep', 10 => 'Oct', 11 => 'Nov', 12 => 'Dic'];
    $primerDia = new DateTimeImmutable('first day of this month');
    for ($i = 5; $i >= 0; $i--) {
        $fecha  = $primerDia->modify('-' . $i . ' months');
        $clave  = $fecha->format('Y-m');
        $mesesSerie[$clave] = [
            'label' => $mesesEs[(int)$fecha->format('n')],
            'total' => isset($porMes[$clave]) ? $porMes[$clave] : 0,
        ];
    }

    // 5) Distribución de estudiantes por grado
    $stmt = $conexion->prepare(
        "SELECT COALESCE(NULLIF(TRIM(grado), ''), 'Sin grado') AS grado, COUNT(*) AS total
         FROM usuarios
         WHERE colegio = :colegio AND tipo_usuario = 'estudiante'
         GROUP BY COALESCE(NULLIF(TRIM(grado), ''), 'Sin grado')
         ORDER BY total DESC"
    );
    $stmt->execute([':colegio' => $colegio]);
    $porGrado = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // 6) Top 5 estudiantes por XP
    $stmt = $conexion->prepare(
        "SELECT u.id_usuario, u.nombre,
                COALESCE(NULLIF(TRIM(u.grado), ''), '—') AS grado,
                COALESCE(ug.total_xp, 0) AS xp,
                COALESCE(ug.current_level, 1) AS nivel,
                COALESCE(ug.current_streak, 0) AS racha
         FROM usuarios u
         LEFT JOIN user_gamification ug ON ug.user_id = u.id_usuario
         WHERE u.colegio = :colegio AND u.tipo_usuario = 'estudiante'
         ORDER BY xp DESC, u.nombre ASC
         LIMIT 5"
    );
    $stmt->execute([':colegio' => $colegio]);
    $topXp = $stmt->fetchAll(PDO::FETCH_ASSOC);
} catch (PDOException $ex) {
    error_log('[DIRECTOR] Dashboard: ' . $ex->getMessage());
    $errorDatos = true;
}

$maxMes = 0;
foreach ($mesesSerie as $m) {
    if ($m['total'] > $maxMes) {
        $maxMes = $m['total'];
    }
}
$totalGrados = 0;
foreach ($porGrado as $g) {
    $totalGrados += (int)$g['total'];
}

panel_head('Dashboard', 'dashboard', $director);
?>

<?php if ($errorDatos): ?>
    <div class="flash-err">No se pudieron cargar todas las métricas en este momento. Intenta de nuevo más tarde.</div>
<?php endif; ?>

<!-- Tarjetas de resumen -->
<div class="stats-grid">
    <div class="stat-card">
        <div class="stat-icon" style="background: #DBEAFE;">&#128101;</div>
        <div class="stat-value"><?= number_format($stats['estudiantes'], 0, ',', '.') ?></div>
        <div class="stat-label">Estudiantes registrados</div>
    </div>
    <div class="stat-card">
        <div class="stat-icon" style="background: #D1FAE5;">&#128640;</div>
        <div class="stat-value"><?= number_format($stats['activos'], 0, ',', '.') ?></div>
        <div class="stat-label">Activos (últimos 7 días)</div>
    </div>
    <div class="stat-card">
        <div class="stat-icon" style="background: #FEF3C7;">&#128221;</div>
        <div class="stat-value"><?= number_format($stats['simulacros'], 0, ',', '.') ?></div>
        <div class="stat-label">Simulacros realizados</div>
    </div>
    <div class="stat-card">
        <div class="stat-icon" style="background: #E9D5FF;">&#127942;</div>
        <div class="stat-value"><?= $stats['promedio'] !== null ? number_format($stats['promedio'], 1, ',', '.') : '—' ?></div>
        <div class="stat-label">Promedio global del colegio</div>
    </div>
    <div class="stat-card">
        <div class="stat-icon" style="background: #FED7AA;">&#11088;</div>
        <div class="stat-value"><?= $stats['mejor_area'] !== null ? e($stats['mejor_area']) : '—' ?></div>
        <div class="stat-label">Mejor área<?= $stats['mejor_area_valor'] !== null ? ' · ' . number_format($stats['mejor_area_valor'], 1, ',', '.') . '/100' : '' ?></div>
    </div>
    <div class="stat-card">
        <div class="stat-icon" style="background: #FEE2E2;">&#9889;</div>
        <div class="stat-value"><?= number_format($stats['xp_total'], 0, ',', '.') ?></div>
        <div class="stat-label">XP total del colegio</div>
    </div>
</div>

<div class="grid-2">
    <!-- Gráfico CSS: simulacros por mes (últimos 6 meses) -->
    <div class="section-card">
        <h3 class="section-title">Simulacros por mes (últimos 6 meses)</h3>
        <?php if ($maxMes === 0): ?>
            <p class="empty-state">Aún no hay simulacros registrados en los últimos 6 meses.</p>
        <?php else: ?>
            <div class="chart-wrap">
                <?php foreach ($mesesSerie as $mes): ?>
                    <div class="chart-col">
                        <div class="chart-bar-val"><?= $mes['total'] ?></div>
                        <div class="chart-bar" style="height: <?= max(2, (int)round($mes['total'] * 150 / $maxMes)) ?>px;"></div>
                        <div class="chart-bar-label"><?= e($mes['label']) ?></div>
                    </div>
                <?php endforeach; ?>
            </div>
        <?php endif; ?>
    </div>

    <!-- Distribución por grado -->
    <div class="section-card">
        <h3 class="section-title">Distribución por grado</h3>
        <?php if ($totalGrados === 0): ?>
            <p class="empty-state">Aún no hay estudiantes registrados.</p>
        <?php else: foreach ($porGrado as $g):
            $pct = $totalGrados > 0 ? round((int)$g['total'] * 100 / $totalGrados) : 0;
        ?>
            <div class="bar-row">
                <div class="bar-label"><?= e($g['grado']) ?></div>
                <div class="bar-track"><div class="bar-fill" style="width: <?= $pct ?>%;"></div></div>
                <div class="bar-value"><?= (int)$g['total'] ?> (<?= $pct ?>%)</div>
            </div>
        <?php endforeach; endif; ?>
    </div>
</div>

<!-- Top 5 estudiantes por XP -->
<div class="section-card">
    <h3 class="section-title">Top 5 estudiantes por XP</h3>
    <?php if (!$topXp): ?>
        <p class="empty-state">Aún no hay estudiantes con actividad.</p>
    <?php else: ?>
        <div class="table-container">
            <table>
                <thead>
                    <tr><th>#</th><th>Estudiante</th><th>Grado</th><th>XP</th><th>Nivel</th><th>Racha</th></tr>
                </thead>
                <tbody>
                <?php foreach ($topXp as $i => $t): ?>
                    <tr>
                        <td><?= $i + 1 ?></td>
                        <td>
                            <a href="estudiante_detalle.php?id=<?= (int)$t['id_usuario'] ?>" style="text-decoration:none;color:#1a1a2e;">
                                <span class="user-cell"><?= avatar_inicial($t['nombre']) ?><strong><?= e($t['nombre']) ?></strong></span>
                            </a>
                        </td>
                        <td><?= e($t['grado']) ?></td>
                        <td><strong><?= number_format((int)$t['xp'], 0, ',', '.') ?></strong></td>
                        <td>Nivel <?= (int)$t['nivel'] ?></td>
                        <td><?= (int)$t['racha'] ?> días</td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>
    <?php endif; ?>
</div>

<?php panel_footer(); ?>
