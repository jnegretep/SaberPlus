<?php
// CONFIGURACIÓN EXACTA COMO EL ORIGINAL FUNCIONAL
ob_start();
ini_set('display_errors', 0);
ini_set('default_charset', 'UTF-8');
error_reporting(E_ALL);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/auth_middleware.php';

// Limpieza inicial IDÉNTICA
if (ob_get_length()) ob_clean();

$userData = $GLOBALS['authUser'] ?? null;

if (!$userData || $userData['tipo_usuario'] != 'profesor') {
    http_response_code(401);
    echo json_encode(['status' => 'error', 'message' => 'Acceso no autorizado']);
    exit;
}

$data = json_decode(file_get_contents('php://input'), true);
$colegioProfesor = $userData['colegio'] ?? ($data['colegio'] ?? null);
$grado = $data['grado'] ?? null;
$anio = $data['anio'] ?? null;

if (!$colegioProfesor) {
    echo json_encode(['status' => 'error', 'message' => 'Falta el colegio']);
    exit;
}

// ---------------------------------------------------------
// FUNCIÓN DE LIMPIEZA UTF-8 (LA MISMA, FUNCIONAL)
// ---------------------------------------------------------
function utf8ize($d) {
    if (is_array($d)) {
        foreach ($d as $k => $v) {
            $d[$k] = utf8ize($v);
        }
    } else if (is_string($d)) {
        return mb_convert_encoding($d, 'UTF-8', 'UTF-8');
    }
    return $d;
}

try {
    error_log("?? Teacher Stats: colegio=$colegioProfesor, grado=" . ($grado ?? 'null') . ", anio=" . ($anio ?? 'null'));
    
    // Forzar UTF-8 en la conexión si existe (IGUAL AL ORIGINAL)
    if (isset($conexion)) {
        $conexion->exec("SET NAMES 'utf8mb4'");
        $conexion->exec("SET CHARACTER SET utf8mb4");
    }

    // ================== 1. ESTUDIANTES (CONSULTA IDÉNTICA AL ORIGINAL) ==================
    $estudiantesQuery = "SELECT COUNT(DISTINCT id_usuario) as total_estudiantes FROM usuarios WHERE colegio = :colegio AND tipo_usuario = 'estudiante'";
    $estParams = [':colegio' => $colegioProfesor];
    
    if ($grado && $grado != 'Todos') {
        $estudiantesQuery .= " AND grado = :grado";
        $estParams[':grado'] = $grado;
    }
    
    $estStmt = $conexion->prepare($estudiantesQuery);
    $estStmt->execute($estParams);
    $estResult = $estStmt->fetch(PDO::FETCH_ASSOC);
    $totalEstudiantes = (int)($estResult['total_estudiantes'] ?? 0);

    // ================== 2. SIMULACROS (CONSULTA IDÉNTICA) ==================
    $simulacrosQuery = "
        SELECT 
            COUNT(sr.id) as total_simulacros,
            COALESCE(AVG(sr.puntaje_global), 0) as promedio_global,
            COALESCE(AVG(sr.lectura_puntaje), 0) as lectura,
            COALESCE(AVG(sr.matematicas_puntaje), 0) as matematicas,
            COALESCE(AVG(sr.sociales_puntaje), 0) as sociales,
            COALESCE(AVG(sr.naturales_puntaje), 0) as naturales,
            COALESCE(AVG(sr.ingles_puntaje), 0) as ingles
        FROM simulacro_resultados sr
        INNER JOIN usuarios u ON sr.usuario_id = u.moodle_id
        WHERE u.colegio = :colegio AND u.tipo_usuario = 'estudiante'
    ";
    
    $simParams = [':colegio' => $colegioProfesor];
    if ($grado && $grado != 'Todos') {
        $simulacrosQuery .= " AND u.grado = :grado";
        $simParams[':grado'] = $grado;
    }
    if ($anio && $anio != 'null' && $anio != 'Todos') {
        $simulacrosQuery .= " AND YEAR(sr.fecha_realizacion) = :anio";
        $simParams[':anio'] = $anio;
    }
    
    $simStmt = $conexion->prepare($simulacrosQuery);
    $simStmt->execute($simParams);
    $simulacrosStats = $simStmt->fetch(PDO::FETCH_ASSOC);
    $totalSimulacros = (int)($simulacrosStats['total_simulacros'] ?? 0);

    // ================== 3. FALLBACK SIN AÑO (EXACTAMENTE IGUAL) ==================
    if ($totalSimulacros == 0 && $anio && $anio != 'null' && $anio != 'Todos') {
        $qBackup = "SELECT COUNT(sr.id) as t, COALESCE(AVG(sr.puntaje_global), 0) as p FROM simulacro_resultados sr INNER JOIN usuarios u ON sr.usuario_id = u.moodle_id WHERE u.colegio = :c AND u.tipo_usuario = 'estudiante'";
        $pBackup = [':c' => $colegioProfesor];
        if ($grado && $grado != 'Todos') { 
            $qBackup .= " AND u.grado = :g"; 
            $pBackup[':g'] = $grado; 
        }
        
        $sBackup = $conexion->prepare($qBackup);
        $sBackup->execute($pBackup);
        $rBackup = $sBackup->fetch(PDO::FETCH_ASSOC);
        
        if (($rBackup['t'] ?? 0) > 0) {
            error_log("?? Datos históricos encontrados sin filtro de año");
        }
    }

    $promedioGlobal = round((float)($simulacrosStats['promedio_global'] ?? 0), 1);

    // ================== 4. DISTRIBUCIÓN (IGUAL PERO CON VALIDACIÓN MÁS SEGURA) ==================
    $distributionStats = [];
    if ($totalSimulacros > 0) {
        $distQ = "SELECT CASE WHEN sr.puntaje_global <= 200 THEN '0-200' WHEN sr.puntaje_global <= 300 THEN '201-300' WHEN sr.puntaje_global <= 400 THEN '301-400' WHEN sr.puntaje_global <= 500 THEN '401-500' ELSE '501-600' END as rango, COUNT(*) as cantidad FROM simulacro_resultados sr INNER JOIN usuarios u ON sr.usuario_id = u.moodle_id WHERE u.colegio = :c AND u.tipo_usuario = 'estudiante'";
        $distP = [':c' => $colegioProfesor];
        if ($grado && $grado != 'Todos') { 
            $distQ .= " AND u.grado = :g"; 
            $distP[':g'] = $grado; 
        }
        if ($anio && $anio != 'null' && $anio != 'Todos') { 
            $distQ .= " AND YEAR(sr.fecha_realizacion) = :a"; 
            $distP[':a'] = $anio; 
        }
        $distQ .= " GROUP BY rango ORDER BY rango";
        
        $stmtD = $conexion->prepare($distQ);
        $stmtD->execute($distP);
        $rawD = $stmtD->fetchAll(PDO::FETCH_ASSOC);
        
        $colors = ['0-200'=>'#EF4444','201-300'=>'#F59E0B','301-400'=>'#10B981','401-500'=>'#1E4ED8','501-600'=>'#8B5CF6'];
        foreach ($rawD as $row) {
            $distributionStats[] = [
                'rango' => $row['rango'],
                'cantidad' => (int)$row['cantidad'],
                'color' => $colors[$row['rango']] ?? '#64748B'
            ];
        }
    }

    // ================== 5. MEJORES ESTUDIANTES (IGUAL PERO CON SANITIZACIÓN) ==================
    $topStudents = [];
    if ($totalSimulacros > 0) {
        $topQ = "SELECT u.nombre, MAX(sr.puntaje_global) as mejor FROM usuarios u INNER JOIN simulacro_resultados sr ON u.moodle_id = sr.usuario_id WHERE u.colegio = :c AND u.tipo_usuario = 'estudiante'";
        $topP = [':c' => $colegioProfesor];
        if ($grado && $grado != 'Todos') { 
            $topQ .= " AND u.grado = :g"; 
            $topP[':g'] = $grado; 
        }
        if ($anio && $anio != 'null' && $anio != 'Todos') { 
            $topQ .= " AND YEAR(sr.fecha_realizacion) = :a"; 
            $topP[':a'] = $anio; 
        }
        $topQ .= " GROUP BY u.id_usuario ORDER BY mejor DESC LIMIT 3";
        
        $stmtT = $conexion->prepare($topQ);
        $stmtT->execute($topP);
        $rawT = $stmtT->fetchAll(PDO::FETCH_ASSOC);
        foreach ($rawT as $st) {
            $topStudents[] = [
                'nombre' => $st['nombre'],
                'puntaje' => (int)round((float)$st['mejor']),
                'avatar' => null
            ];
        }
    }

    // ================== 6. ÁREAS (EXACTAMENTE IGUAL) ==================
    $areas = [
        'lectura' => round((float)($simulacrosStats['lectura'] ?? 0), 1),
        'matematicas' => round((float)($simulacrosStats['matematicas'] ?? 0), 1),
        'sociales' => round((float)($simulacrosStats['sociales'] ?? 0), 1),
        'naturales' => round((float)($simulacrosStats['naturales'] ?? 0), 1),
        'ingles' => round((float)($simulacrosStats['ingles'] ?? 0), 1)
    ];
    
    $weakAreas = [];
    $labels = ['lectura'=>'Lectura','matematicas'=>'Matemáticas','sociales'=>'Sociales','naturales'=>'Naturales','ingles'=>'Inglés'];
    foreach ($areas as $key => $val) {
        if ($val > 0 && $val < 70) $weakAreas[] = $labels[$key];
    }

    // ================== 7. RESPUESTA FINAL (ESTRUCTURA IDÉNTICA) ==================
    $response = [
        'status' => 'ok',
        'stats' => [
            'total_estudiantes' => $totalEstudiantes,
            'total_simulacros' => $totalSimulacros,
            'promedio_global' => $promedioGlobal,
            'promedios_por_area' => $areas,
            'distribucion_puntajes' => $distributionStats,
            'evolucion_mensual' => [],
            'mejores_estudiantes' => $topStudents,
            'areas_mejorar' => array_slice($weakAreas, 0, 3),
            'tendencias' => ['global'=>'+0%','lectura'=>'+0%','matematicas'=>'+0%','sociales'=>'+0%','naturales'=>'+0%','ingles'=>'+0%']
        ]
    ];

    error_log("?? Sending Response: estudiantes=$totalEstudiantes, simulacros=$totalSimulacros, promedio=$promedioGlobal");

    // ================== 8. ENVÍO SEGURO (IGUAL PERO CON PEQUEÑA MEJORA) ==================
    
    // Aplicar utf8ize a toda la respuesta para prevenir problemas
    $response = utf8ize($response);
    
    // Intentar codificar JSON
    $jsonOutput = json_encode($response, JSON_UNESCAPED_UNICODE);

    // Si falla, intentar una vez más con limpieza básica
    if ($jsonOutput === false) {
        error_log("?? JSON Encode Error: " . json_last_error_msg() . ", intentando limpieza...");
        
        // Función de limpieza simple para strings
        $cleanData = function($data) use (&$cleanData) {
            if (is_array($data)) {
                return array_map($cleanData, $data);
            } elseif (is_string($data)) {
                // Eliminar caracteres no válidos y normalizar
                $data = preg_replace('/[^\x{0009}\x{000A}\x{000D}\x{0020}-\x{D7FF}\x{E000}-\x{FFFD}]+/u', ' ', $data);
                $data = trim($data);
                return $data;
            }
            return $data;
        };
        
        $response = $cleanData($response);
        $jsonOutput = json_encode($response, JSON_UNESCAPED_UNICODE);
        
        // Si aún falla, enviar respuesta mínima
        if ($jsonOutput === false) {
            if (ob_get_length()) ob_clean();
            $minimalResponse = [
                'status' => 'ok',
                'stats' => [
                    'total_estudiantes' => $totalEstudiantes,
                    'total_simulacros' => $totalSimulacros,
                    'promedio_global' => $promedioGlobal,
                    'promedios_por_area' => array_map('floatval', $areas),
                    'distribucion_puntajes' => [],
                    'evolucion_mensual' => [],
                    'mejores_estudiantes' => array_map(function($s) {
                        return ['nombre' => 'Estudiante', 'puntaje' => $s['puntaje'], 'avatar' => null];
                    }, $topStudents),
                    'areas_mejorar' => [],
                    'tendencias' => ['global'=>'+0%','lectura'=>'+0%','matematicas'=>'+0%','sociales'=>'+0%','naturales'=>'+0%','ingles'=>'+0%']
                ]
            ];
            echo json_encode($minimalResponse, JSON_UNESCAPED_UNICODE);
            exit;
        }
    }

    // ENVIO FINAL (IGUAL AL ORIGINAL)
    if (ob_get_length()) ob_clean();
    echo $jsonOutput;
    flush();

} catch (PDOException $e) {
    if (ob_get_length()) ob_clean();
    error_log("? Database Error: " . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'Error en la base de datos'
    ]);
    exit;
} catch (Exception $e) {
    if (ob_get_length()) ob_clean();
    error_log("? General Error: " . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'Error interno del servidor'
    ]);
    exit;
}
?>