<?php
// teacher_generate_report.php - VERSIÓN REDISEÑADA
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

// UTF-8 robusto
mb_internal_encoding('UTF-8');
mb_http_output('UTF-8');

header('Content-Type: application/json');

// Dependencias y conexión
require_once __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/auth_middleware.php';
require __DIR__ . '/includes/conexion.php';

use Dompdf\Dompdf;
use Dompdf\Options;

// Autenticación
$userData = $GLOBALS['authUser'] ?? null;
if (!$userData || $userData['tipo_usuario'] !== 'profesor') {
    http_response_code(401);
    echo json_encode(['status' => 'error', 'message' => 'No autorizado']);
    exit;
}

// Entrada
$data = json_decode(file_get_contents('php://input'), true);
$simulacroId = (int)($data['simulacro_id'] ?? 0);
$courseId = (int)($data['courseid'] ?? 0);
$colegio = $data['colegio'] ?? ($userData['colegio'] ?? null);
$grado = $data['grado'] ?? null;
$anio = $data['anio'] ?? date('Y');

// Validaciones
if ($simulacroId <= 0) {
    echo json_encode(['status' => 'error', 'message' => 'simulacro_id inválido']);
    exit;
}
if (!$colegio) {
    echo json_encode(['status' => 'error', 'message' => 'colegio requerido']);
    exit;
}

// Función para limpiar UTF-8
function limpiarTexto($texto) {
    if (!is_string($texto)) return $texto;
    
    // Reemplazar emojis problemáticos
    $emojis = [
        '??' => '?', '??' => '?', '??' => '??', '??' => '??',
        '??' => '?', '??' => '?', '??' => '??', '??' => '??',
        '??' => '??', '??' => '??', '??' => '??', '??' => '??',
        '??' => '??', '??' => '??', '??' => '??', '??' => '?',
        '??' => '??', '??' => '??', '??' => '??', '??' => '??'
    ];
    
    $texto = str_replace(array_keys($emojis), array_values($emojis), $texto);
    
    // Asegurar UTF-8
    if (!mb_check_encoding($texto, 'UTF-8')) {
        $texto = mb_convert_encoding($texto, 'UTF-8', 'UTF-8');
    }
    
    return htmlspecialchars($texto, ENT_QUOTES, 'UTF-8');
}

try {
    // 1. OBTENER NOMBRE DESDE MOODLE
    $nombreSimulacro = "Simulacro #{$simulacroId}";
    $descripcionSimulacro = "Resultados del simulacro";
    
    $profesorMoodleId = $userData['moodle_id'] ?? null;
    if ($profesorMoodleId && $courseId > 0) {
        $stmtToken = $conexion->prepare("SELECT moodle_token FROM usuarios WHERE moodle_id = :mid");
        $stmtToken->execute([':mid' => $profesorMoodleId]);
        $tokenRow = $stmtToken->fetch(PDO::FETCH_ASSOC);
        $moodleToken = $tokenRow['moodle_token'] ?? null;
        
        if ($moodleToken) {
            try {
                require_once __DIR__ . '/includes/moodle.php';
                $client = getMoodleClient();
                
                $result = $client->request(
                    $moodleToken,
                    'mod_quiz_get_quizzes_by_courses',
                    ['courseids[0]' => $courseId]
                );
                
                if (isset($result['quizzes']) && is_array($result['quizzes'])) {
                    foreach ($result['quizzes'] as $quiz) {
                        if ($quiz['id'] == $simulacroId) {
                            $nombreSimulacro = $quiz['name'] ?? $nombreSimulacro;
                            $descripcionSimulacro = $quiz['intro'] ?? $descripcionSimulacro;
                            break;
                        }
                    }
                }
            } catch (Exception $e) {
                error_log("?? Error Moodle: " . $e->getMessage());
            }
        }
    }
    
    // 2. ESTADÍSTICAS PRINCIPALES (CONSULTA ÚNICA)
    $query = "
        SELECT 
            COUNT(*) AS total,
            COUNT(DISTINCT sr.usuario_id) AS estudiantes_unicos,
            AVG(sr.puntaje_global) AS promedio_global,
            AVG(sr.lectura_puntaje) AS lectura,
            AVG(sr.matematicas_puntaje) AS matematicas,
            AVG(sr.sociales_puntaje) AS sociales,
            AVG(sr.naturales_puntaje) AS naturales,
            AVG(sr.ingles_puntaje) AS ingles,
            MIN(sr.fecha_realizacion) AS fecha_inicio,
            MAX(sr.fecha_realizacion) AS fecha_fin,
            MAX(sr.puntaje_global) AS max_global,
            MIN(sr.puntaje_global) AS min_global,
            MAX(sr.lectura_puntaje) AS lectura_max,
            MAX(sr.matematicas_puntaje) AS matematicas_max,
            MAX(sr.sociales_puntaje) AS sociales_max,
            MAX(sr.naturales_puntaje) AS naturales_max,
            MAX(sr.ingles_puntaje) AS ingles_max,
            MIN(sr.lectura_puntaje) AS lectura_min,
            MIN(sr.matematicas_puntaje) AS matematicas_min,
            MIN(sr.sociales_puntaje) AS sociales_min,
            MIN(sr.naturales_puntaje) AS naturales_min,
            MIN(sr.ingles_puntaje) AS ingles_min,
            AVG(sr.lectura_correctas) AS lectura_correctas,
            AVG(sr.matematicas_correctas) AS matematicas_correctas,
            AVG(sr.sociales_correctas) AS sociales_correctas,
            AVG(sr.naturales_correctas) AS naturales_correctas,
            AVG(sr.ingles_correctas) AS ingles_correctas,
            AVG(sr.tiempo_empleado) AS tiempo_promedio
        FROM simulacro_resultados sr
        INNER JOIN usuarios u ON sr.usuario_id = u.moodle_id
        WHERE sr.simulacro_id = :simulacro_id
          AND sr.colegio = :colegio
          AND u.tipo_usuario = 'estudiante'
    ";
    
    $params = [
        ':simulacro_id' => $simulacroId,
        ':colegio' => $colegio
    ];
    
    if ($anio && $anio != 'Todos' && is_numeric($anio)) {
        $query .= " AND YEAR(sr.fecha_realizacion) = :anio";
        $params[':anio'] = (int)$anio;
    }
    
    if ($grado && $grado != 'Todos' && !empty(trim($grado))) {
        $query .= " AND u.grado = :grado";
        $params[':grado'] = $grado;
    }
    
    $stmt = $conexion->prepare($query);
    $stmt->execute($params);
    $res = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$res || (int)$res['total'] === 0) {
        echo json_encode(['status' => 'error', 'message' => 'No hay datos para este simulacro']);
        exit;
    }
    
    // 3. PROCESAR DATOS
    $totalEstudiantes = (int)$res['total'];
    $promedioGlobal = round((float)$res['promedio_global'], 1);
    $fechaInicio = $res['fecha_inicio'] ? date('d/m/Y H:i', strtotime($res['fecha_inicio'])) : '-';
    $fechaFin = $res['fecha_fin'] ? date('d/m/Y H:i', strtotime($res['fecha_fin'])) : '-';
    $fechaGeneracion = date('d/m/Y H:i');
    
    // Datos por área
    $areas = [
        'Lectura Crítica' => [
            'promedio' => round((float)$res['lectura'], 1),
            'max' => round((float)$res['lectura_max'], 1),
            'min' => round((float)$res['lectura_min'], 1),
            'correctas' => round((float)$res['lectura_correctas'], 0),
            'porcentaje' => min(100, round(((float)$res['lectura'] / 500) * 100, 0)),
            'color' => '#3B82F6'
        ],
        'Matemáticas' => [
            'promedio' => round((float)$res['matematicas'], 1),
            'max' => round((float)$res['matematicas_max'], 1),
            'min' => round((float)$res['matematicas_min'], 1),
            'correctas' => round((float)$res['matematicas_correctas'], 0),
            'porcentaje' => min(100, round(((float)$res['matematicas'] / 500) * 100, 0)),
            'color' => '#10B981'
        ],
        'Sociales' => [
            'promedio' => round((float)$res['sociales'], 1),
            'max' => round((float)$res['sociales_max'], 1),
            'min' => round((float)$res['sociales_min'], 1),
            'correctas' => round((float)$res['sociales_correctas'], 0),
            'porcentaje' => min(100, round(((float)$res['sociales'] / 500) * 100, 0)),
            'color' => '#8B5CF6'
        ],
        'Naturales' => [
            'promedio' => round((float)$res['naturales'], 1),
            'max' => round((float)$res['naturales_max'], 1),
            'min' => round((float)$res['naturales_min'], 1),
            'correctas' => round((float)$res['naturales_correctas'], 0),
            'porcentaje' => min(100, round(((float)$res['naturales'] / 500) * 100, 0)),
            'color' => '#EF4444'
        ],
        'Inglés' => [
            'promedio' => round((float)$res['ingles'], 1),
            'max' => round((float)$res['ingles_max'], 1),
            'min' => round((float)$res['ingles_min'], 1),
            'correctas' => round((float)$res['ingles_correctas'], 0),
            'porcentaje' => min(100, round(((float)$res['ingles'] / 500) * 100, 0)),
            'color' => '#F59E0B'
        ]
    ];
    
    // Áreas fuertes y débiles
    uasort($areas, function($a, $b) {
        return $b['porcentaje'] <=> $a['porcentaje'];
    });
    
    $areasFuertes = array_slice($areas, 0, 2, true);
    $areasDebiles = array_slice($areas, -2, 2, true);
    
    // 4. TOP ESTUDIANTES
    $rankingQuery = "
        SELECT 
            u.nombre,
            u.grado,
            sr.puntaje_global,
            sr.lectura_puntaje,
            sr.matematicas_puntaje,
            sr.sociales_puntaje,
            sr.naturales_puntaje,
            sr.ingles_puntaje,
            sr.fecha_realizacion
        FROM simulacro_resultados sr
        INNER JOIN usuarios u ON sr.usuario_id = u.moodle_id
        WHERE sr.simulacro_id = :simulacro_id
          AND sr.colegio = :colegio
          AND u.tipo_usuario = 'estudiante'
    ";
    
    $rankingParams = [
        ':simulacro_id' => $simulacroId,
        ':colegio' => $colegio
    ];
    
    if ($anio && $anio != 'Todos' && is_numeric($anio)) {
        $rankingQuery .= " AND YEAR(sr.fecha_realizacion) = :anio";
        $rankingParams[':anio'] = (int)$anio;
    }
    
    if ($grado && $grado != 'Todos' && !empty(trim($grado))) {
        $rankingQuery .= " AND u.grado = :grado";
        $rankingParams[':grado'] = $grado;
    }
    
    $rankingQuery .= " ORDER BY sr.puntaje_global DESC LIMIT 10";
    
    $rankingStmt = $conexion->prepare($rankingQuery);
    $rankingStmt->execute($rankingParams);
    $ranking = $rankingStmt->fetchAll(PDO::FETCH_ASSOC);
    
    // 5. DISTRIBUCIÓN POR GRADO
    $distQuery = "
        SELECT 
            u.grado,
            COUNT(*) AS total,
            AVG(sr.puntaje_global) AS promedio,
            MAX(sr.puntaje_global) AS maximo,
            MIN(sr.puntaje_global) AS minimo
        FROM simulacro_resultados sr
        INNER JOIN usuarios u ON sr.usuario_id = u.moodle_id
        WHERE sr.simulacro_id = :simulacro_id
          AND sr.colegio = :colegio
          AND u.tipo_usuario = 'estudiante'
    ";
    
    $distParams = [
        ':simulacro_id' => $simulacroId,
        ':colegio' => $colegio
    ];
    
    if ($anio && $anio != 'Todos' && is_numeric($anio)) {
        $distQuery .= " AND YEAR(sr.fecha_realizacion) = :anio";
        $distParams[':anio'] = (int)$anio;
    }
    
    $distQuery .= " GROUP BY u.grado ORDER BY u.grado";
    
    $distStmt = $conexion->prepare($distQuery);
    $distStmt->execute($distParams);
    $distribucionGrados = $distStmt->fetchAll(PDO::FETCH_ASSOC);
    
    // 6. PREPARAR HTML COMPLETO CON DISEÑO MEJORADO
    $nombreSimulacroSafe = limpiarTexto($nombreSimulacro);
    $descripcionSimulacroSafe = limpiarTexto($descripcionSimulacro);
    $colegioSafe = limpiarTexto($colegio);
    
    // Logos
    $logoAppPath = __DIR__ . '/logo.jpg';
    $logoColegioPath = __DIR__ . '/colegio_logo.jpg';
    
    $logoAppBase64 = '';
    $logoColegioBase64 = '';
    
    if (file_exists($logoAppPath) && is_readable($logoAppPath)) {
        $logoAppBase64 = 'data:image/jpeg;base64,' . base64_encode(file_get_contents($logoAppPath));
    }
    
    if (file_exists($logoColegioPath) && is_readable($logoColegioPath)) {
        $logoColegioBase64 = 'data:image/jpeg;base64,' . base64_encode(file_get_contents($logoColegioPath));
    }
    
    // Construir ranking
    $rankingRows = '';
    $posicion = 1;
    foreach ($ranking as $r) {
        $claseFila = $posicion <= 3 ? "top-{$posicion}" : '';
        $nombreEstudiante = limpiarTexto($r['nombre']);
        $gradoEstudiante = limpiarTexto($r['grado']);
        
        $rankingRows .= "
            <tr class='{$claseFila}'>
                <td>{$nombreEstudiante}</td>
                <td>{$gradoEstudiante}</td>
                <td>" . round((float)$r['puntaje_global'], 1) . "</td>
                <td>" . round((float)$r['lectura_puntaje'], 1) . "</td>
                <td>" . round((float)$r['matematicas_puntaje'], 1) . "</td>
                <td>" . round((float)$r['sociales_puntaje'], 1) . "</td>
                <td>" . round((float)$r['naturales_puntaje'], 1) . "</td>
                <td>" . round((float)$r['ingles_puntaje'], 1) . "</td>
            </tr>";
        $posicion++;
    }
    
    if ($rankingRows === '') {
        $rankingRows = "<tr><td colspan='8'>No hay ranking disponible</td></tr>";
    }
    
    // Construir distribución por grado
    $distRows = '';
    foreach ($distribucionGrados as $d) {
        $gradoText = limpiarTexto($d['grado']);
        $distRows .= "
            <tr>
                <td>{$gradoText}</td>
                <td>" . (int)$d['total'] . "</td>
                <td>" . round((float)$d['promedio'], 1) . "</td>
                <td>" . round((float)$d['maximo'], 1) . "</td>
                <td>" . round((float)$d['minimo'], 1) . "</td>
            </tr>";
    }
    
    if ($distRows === '') {
        $distRows = "<tr><td colspan='5'>No hay distribución por grado</td></tr>";
    }
    
    // HTML COMPLETO CON DISEÑO PROFESIONAL
    $html = <<<HTML
<!DOCTYPE html>
<html lang='es'>
<head>
    <meta charset='UTF-8'>
    <title>Reporte de Simulacro - {$colegioSafe}</title>
    <style>
        @page { 
            margin: 10mm;
            size: A4 landscape;
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'DejaVu Sans', 'Segoe UI', sans-serif;
            color: #1e293b;
            font-size: 9pt;
            line-height: 1.3;
        }
        
        /* ENCABEZADO COMPACTO */
        .header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding-bottom: 8px;
            margin-bottom: 12px;
            border-bottom: 2px solid #3b82f6;
        }
        
        .header-left, .header-right {
            width: 120px;
            text-align: center;
        }
        
        .logo {
            max-height: 50px;
            max-width: 120px;
            object-fit: contain;
        }
        
        .header-center {
            flex: 1;
            text-align: center;
            padding: 0 15px;
        }
        
        .header-title {
            font-size: 14pt;
            font-weight: 700;
            color: #1e40af;
            margin-bottom: 2px;
        }
        
        .header-subtitle {
            font-size: 10pt;
            color: #64748b;
            margin-bottom: 4px;
        }
        
        /* INFORMACIÓN DEL SIMULACRO */
        .simulacro-info {
            background: #f1f5f9;
            border-radius: 6px;
            padding: 12px;
            margin-bottom: 12px;
        }
        
        .simulacro-title {
            font-size: 12pt;
            font-weight: 600;
            color: #1e293b;
            margin-bottom: 6px;
        }
        
        .simulacro-meta {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            font-size: 8pt;
        }
        
        .meta-item {
            background: #e2e8f0;
            padding: 4px 8px;
            border-radius: 4px;
            display: flex;
            align-items: center;
            gap: 4px;
        }
        
        /* ESTADÍSTICAS */
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 12px;
            margin-bottom: 12px;
        }
        
        .stat-card {
            background: white;
            border: 1px solid #e2e8f0;
            border-radius: 6px;
            padding: 12px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.05);
        }
        
        .card-title {
            font-size: 10pt;
            font-weight: 600;
            color: #334155;
            margin-bottom: 8px;
            padding-bottom: 4px;
            border-bottom: 1px solid #e2e8f0;
        }
        
        /* TABLAS */
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 8pt;
        }
        
        th {
            background: #3b82f6;
            color: white;
            font-weight: 600;
            padding: 6px 4px;
            text-align: center;
            border: 1px solid #2563eb;
        }
        
        td {
            padding: 5px 4px;
            border: 1px solid #e2e8f0;
            text-align: center;
        }
        
        tr:nth-child(even) {
            background: #f8fafc;
        }
        
        /* PROGRESS BARS */
        .progress-container {
            width: 100%;
            background: #e2e8f0;
            border-radius: 4px;
            overflow: hidden;
            height: 18px;
            position: relative;
        }
        
        .progress-fill {
            height: 100%;
            border-radius: 4px;
            text-align: center;
            line-height: 18px;
            font-size: 7pt;
            font-weight: 600;
            color: white;
            min-width: 20%;
        }
        
        .progress-text {
            position: absolute;
            width: 100%;
            text-align: center;
            font-size: 7pt;
            font-weight: 600;
            color: #1e293b;
            line-height: 18px;
        }
        
        /* COLORS */
        .lectura { background: linear-gradient(90deg, #3b82f6, #60a5fa); }
        .matematicas { background: linear-gradient(90deg, #10b981, #34d399); }
        .sociales { background: linear-gradient(90deg, #8b5cf6, #a78bfa); }
        .naturales { background: linear-gradient(90deg, #ef4444, #f87171); }
        .ingles { background: linear-gradient(90deg, #f59e0b, #fbbf24); }
        
        /* RANKING */
        .top-1 { background: #fef3c7 !important; font-weight: 600; }
        .top-2 { background: #f3f4f6 !important; }
        .top-3 { background: #ecfdf5 !important; }
        
        /* ÁREAS FUERTES/DÉBILES */
        .areas-container {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 8px;
            margin-top: 8px;
        }
        
        .area-box {
            padding: 8px;
            border-radius: 4px;
            border: 1px solid;
        }
        
        .area-fuerte {
            background: #d1fae5;
            border-color: #10b981;
        }
        
        .area-debil {
            background: #fee2e2;
            border-color: #ef4444;
        }
        
        .area-label {
            font-size: 8pt;
            font-weight: 600;
            margin-bottom: 4px;
        }
        
        .area-item {
            font-size: 7pt;
            margin: 2px 0;
        }
        
        /* PIE DE PÁGINA */
        .footer {
            margin-top: 15px;
            padding-top: 8px;
            border-top: 1px solid #e2e8f0;
            font-size: 7pt;
            color: #64748b;
            text-align: center;
        }
        
        /* UTILIDADES */
        .text-right { text-align: right; }
        .text-center { text-align: center; }
        .text-bold { font-weight: 600; }
        .text-success { color: #10b981; }
        .text-danger { color: #ef4444; }
        .mb-8 { margin-bottom: 8px; }
    </style>
</head>
<body>

    <!-- ENCABEZADO -->
    <div class="header">
        <div class="header-left">
HTML;

    if ($logoAppBase64) {
        $html .= "<img src='{$logoAppBase64}' class='logo' alt='SaberPlus'>";
    } else {
        $html .= "<div style='font-size: 8pt; color: #64748b;'>SaberPlus</div>";
    }

$html .= <<<HTML
        </div>
        
        <div class="header-center">
            <div class="header-title">Reporte de Simulacro</div>
            <div class="header-subtitle">{$colegioSafe}</div>
            <div style="font-size: 9pt; color: #475569;">{$nombreSimulacroSafe}</div>
        </div>
        
        <div class="header-right">
HTML;

    if ($logoColegioBase64) {
        $html .= "<img src='{$logoColegioBase64}' class='logo' alt='{$colegioSafe}'>";
    } else {
        $html .= "<div style='font-size: 8pt; color: #64748b;'>{$colegioSafe}</div>";
    }

$html .= <<<HTML
        </div>
    </div>

    <!-- INFORMACIÓN DEL SIMULACRO -->
    <div class="simulacro-info">
        <div class="simulacro-title">?? {$nombreSimulacroSafe}</div>
        <div class="simulacro-meta">
            <span class="meta-item">?? <strong>Año:</strong> {$anio}</span>
            <span class="meta-item">?? <strong>Estudiantes:</strong> {$totalEstudiantes}</span>
            <span class="meta-item">?? <strong>Promedio Global:</strong> {$promedioGlobal}</span>
            <span class="meta-item">?? <strong>Período:</strong> {$fechaInicio} al {$fechaFin}</span>
        </div>
    </div>

    <!-- ESTADÍSTICAS PRINCIPALES -->
    <div class="stats-grid">
        <!-- RESUMEN GENERAL -->
        <div class="stat-card">
            <div class="card-title">?? Resumen General</div>
            <table>
                <thead>
                    <tr>
                        <th>Indicador</th>
                        <th>Valor</th>
                        <th>Máximo</th>
                        <th>Mínimo</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td>Estudiantes</td>
                        <td>{$totalEstudiantes}</td>
                        <td colspan="2">-</td>
                    </tr>
                    <tr>
                        <td>Puntaje Global</td>
                        <td>{$promedioGlobal}</td>
                        <td class="text-success">{$res['max_global']}</td>
                        <td class="text-danger">{$res['min_global']}</td>
                    </tr>
                </tbody>
            </table>
        </div>

        <!-- PROMEDIOS POR ÁREA -->
        <div class="stat-card">
            <div class="card-title">?? Desempeño por Área</div>
            <table>
                <thead>
                    <tr>
                        <th>Área</th>
                        <th>Promedio</th>
                        <th>% Logro</th>
                        <th>Gráfico</th>
                    </tr>
                </thead>
                <tbody>
HTML;

foreach ($areas as $nombreArea => $data) {
    $clase = strtolower(str_replace(' ', '-', $nombreArea));
    $html .= <<<HTML
                    <tr>
                        <td>{$nombreArea}</td>
                        <td class="text-bold">{$data['promedio']}</td>
                        <td>{$data['porcentaje']}%</td>
                        <td>
                            <div class="progress-container">
                                <div class="progress-fill {$clase}" style="width: {$data['porcentaje']}%"></div>
                                <div class="progress-text">{$data['porcentaje']}%</div>
                            </div>
                        </td>
                    </tr>
HTML;
}

$html .= <<<HTML
                </tbody>
            </table>
        </div>
    </div>

    <!-- ANÁLISIS DE COMPETENCIAS -->
    <div class="stat-card mb-8">
        <div class="card-title">?? Análisis de Competencias</div>
        <div class="areas-container">
            <!-- ÁREAS FUERTES -->
            <div class="area-box area-fuerte">
                <div class="area-label">? Áreas Fuertes</div>
HTML;

foreach ($areasFuertes as $nombreArea => $data) {
    $html .= "<div class='area-item'><strong>{$nombreArea}:</strong> {$data['porcentaje']}% ({$data['correctas']} correctas)</div>";
}

$html .= <<<HTML
            </div>
            
            <!-- ÁREAS A MEJORAR -->
            <div class="area-box area-debil">
                <div class="area-label">?? Áreas a Mejorar</div>
HTML;

foreach ($areasDebiles as $nombreArea => $data) {
    $html .= "<div class='area-item'><strong>{$nombreArea}:</strong> {$data['porcentaje']}% ({$data['correctas']} correctas)</div>";
}

$html .= <<<HTML
            </div>
        </div>
    </div>

    <!-- TOP 10 ESTUDIANTES -->
    <div class="stat-card mb-8">
        <div class="card-title">?? Top 10 Estudiantes</div>
        <table>
            <thead>
                <tr>
                    <th>Estudiante</th>
                    <th>Grado</th>
                    <th>Global</th>
                    <th>Lectura</th>
                    <th>Matemáticas</th>
                    <th>Sociales</th>
                    <th>Naturales</th>
                    <th>Inglés</th>
                </tr>
            </thead>
            <tbody>
                {$rankingRows}
            </tbody>
        </table>
    </div>

    <!-- DISTRIBUCIÓN POR GRADO -->
    <div class="stat-card mb-8">
        <div class="card-title">?? Distribución por Grado</div>
        <table>
            <thead>
                <tr>
                    <th>Grado</th>
                    <th>Estudiantes</th>
                    <th>Promedio</th>
                    <th>Máximo</th>
                    <th>Mínimo</th>
                </tr>
            </thead>
            <tbody>
                {$distRows}
            </tbody>
        </table>
    </div>

    <!-- RECOMENDACIONES -->
    <div class="stat-card" style="background: #f0f9ff; border-color: #0ea5e9;">
        <div class="card-title" style="color: #0369a1;">?? Recomendaciones Pedagógicas</div>
        <div style="font-size: 8pt; color: #475569;">
            <div style="margin-bottom: 4px;"><strong>1. Fortalecer áreas débiles:</strong> Implementar sesiones de refuerzo específicas.</div>
            <div style="margin-bottom: 4px;"><strong>2. Replicar buenas prácticas:</strong> Analizar estrategias de estudiantes destacados.</div>
            <div style="margin-bottom: 4px;"><strong>3. Planificación diferenciada:</strong> Diseñar actividades por nivel de desempeño.</div>
            <div><strong>4. Seguimiento individual:</strong> Monitoreo personalizado para estudiantes con dificultades.</div>
        </div>
    </div>

    <!-- PIE DE PÁGINA -->
    <div class="footer">
        <div style="display: flex; justify-content: space-between; align-items: center;">
            <div>Generado por <strong>SaberPlus</strong> • Sistema de Gestión Educativa</div>
            <div>Página <span class="page-number"></span> • {$fechaGeneracion}</div>
        </div>
    </div>

</body>
</html>
HTML;

    // 7. GENERAR PDF
    $options = new Options();
    $options->set('defaultFont', 'DejaVu Sans');
    $options->set('isHtml5ParserEnabled', true);
    $options->set('isRemoteEnabled', true);
    $options->set('isFontSubsettingEnabled', true);
    $options->set('defaultPaperSize', 'A4');
    $options->set('defaultPaperOrientation', 'landscape');

    $dompdf = new Dompdf($options);
    $dompdf->loadHtml($html, 'UTF-8');
    $dompdf->render();

    // 8. GUARDAR ARCHIVO
    $reportsDir = __DIR__ . '/reports';
    if (!is_dir($reportsDir)) {
        mkdir($reportsDir, 0777, true);
    }

    $fileName = "Reporte_{$simulacroId}_{$anio}_" . date('Ymd_His') . ".pdf";
    $filePath = $reportsDir . "/" . $fileName;

    $output = $dompdf->output();
    if (file_put_contents($filePath, $output)) {
        echo json_encode([
            'status' => 'success',
            'download_url' => "http://172.93.49.94/api/prepsaber/backend/reports/" . $fileName,
            'file_name' => $fileName,
            'metadata' => [
                'simulacro_nombre' => $nombreSimulacro,
                'colegio' => $colegio,
                'total_estudiantes' => $totalEstudiantes,
                'promedio_global' => $promedioGlobal
            ]
        ], JSON_UNESCAPED_UNICODE);
    } else {
        throw new Exception("Error al guardar el archivo PDF.");
    }

} catch (Exception $e) {
    error_log("? Error generando reporte: " . $e->getMessage());
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Error: ' . $e->getMessage()]);
}