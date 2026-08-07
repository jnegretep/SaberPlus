<?php
ini_set('display_errors', 1);
error_reporting(E_ALL);

// ?? AÑADE UTF-8
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/auth_middleware.php';

// ?? AÑADE UTF-8 a la conexión
if (isset($conexion)) {
    $conexion->exec("SET NAMES 'utf8mb4'");
    $conexion->exec("SET CHARACTER SET utf8mb4");
}

$userData = $GLOBALS['authUser'] ?? null;

if (!$userData || $userData['tipo_usuario'] !== 'profesor') {
    http_response_code(403);
    echo json_encode(['status' => 'error', 'msg' => 'Acceso denegado. Rol insuficiente']);
    exit;
}

$data = json_decode(file_get_contents('php://input'), true);

$colegioProfesor = $userData['colegio'] ?? null;
$grado = $data['grado'] ?? null;
$anio = $data['anio'] ?? null;

if (!$colegioProfesor) {
    $colegioProfesor = $data['colegio'] ?? null;
}

if (!$colegioProfesor) {
    echo json_encode(['status' => 'error', 'msg' => 'No se especificó el colegio']);
    exit;
}

try {
    // ?? CORRECCIÓN PRINCIPAL: Usar u.moodle_id en lugar de u.id_usuario
    $query = "SELECT 
                u.id_usuario,
                u.moodle_id,  
                u.nombre,
                u.email,
                u.grado,
                u.avatar_path,
                COUNT(sr.id) as total_simulacros,
                COALESCE(MAX(sr.puntaje_global), 0) as mejor_puntaje,
                MAX(sr.fecha_realizacion) as ultimo_simulacro
              FROM usuarios u
              LEFT JOIN simulacro_resultados sr ON u.moodle_id = sr.usuario_id";  
    
    // Condición del año en el JOIN
    if ($anio && $anio != 'Todos') {
        $query .= " AND YEAR(sr.fecha_realizacion) = :anio";
    }
    
    $query .= " WHERE u.colegio = :colegio AND u.tipo_usuario = 'estudiante'";
    
    $params = [':colegio' => $colegioProfesor];
    if ($anio && $anio != 'Todos') {
        $params[':anio'] = $anio;
    }
    
    if ($grado && $grado != 'Todos') {
        $query .= " AND u.grado = :grado";
        $params[':grado'] = $grado;
    }
    
    $query .= " GROUP BY u.id_usuario ORDER BY u.nombre ASC";
    
    $stmt = $conexion->prepare($query);
    $stmt->execute($params);
    $students = $stmt->fetchAll(PDO::FETCH_ASSOC);

    if (empty($students)) {
        echo json_encode([
            'status' => 'ok',
            'students' => [],
            'message' => 'No hay estudiantes registrados con estos filtros'
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }
    
    // Para cada estudiante, calcular promedios por área y tendencia
    foreach ($students as &$student) {
        $moodleId = $student['moodle_id'];
        
        // ?? CORRECCIÓN: Usar moodle_id en las subconsultas
        // 1. Promedios por área
        $areasQuery = "SELECT 
                COALESCE(AVG(lectura_puntaje), 0) as lectura_promedio,
                COALESCE(AVG(matematicas_puntaje), 0) as matematicas_promedio,
                COALESCE(AVG(sociales_puntaje), 0) as sociales_promedio,
                COALESCE(AVG(naturales_puntaje), 0) as naturales_promedio,
                COALESCE(AVG(ingles_puntaje), 0) as ingles_promedio
            FROM simulacro_resultados 
            WHERE usuario_id = :moodle_id";  
        
        $aParams = [':moodle_id' => $moodleId];
        if ($anio && $anio != 'Todos') {
            $areasQuery .= " AND YEAR(fecha_realizacion) = :anio";
            $aParams[':anio'] = $anio;
        }
        
        $areasStmt = $conexion->prepare($areasQuery);
        $areasStmt->execute($aParams);
        $areas = $areasStmt->fetch(PDO::FETCH_ASSOC);
        
        // 2. Calcular tendencia (comparar últimos 2 simulacros)
        $tendenciaQuery = "SELECT puntaje_global 
            FROM simulacro_resultados 
            WHERE usuario_id = :moodle_id";  
        
        $tParams = [':moodle_id' => $moodleId];
        if ($anio && $anio != 'Todos') {
            $tendenciaQuery .= " AND YEAR(fecha_realizacion) = :anio";
            $tParams[':anio'] = $anio;
        }
        
        $tendenciaQuery .= " ORDER BY fecha_realizacion DESC LIMIT 2";
        
        $tendenciaStmt = $conexion->prepare($tendenciaQuery);
        $tendenciaStmt->execute($tParams);
        $ultimosPuntajes = $tendenciaStmt->fetchAll(PDO::FETCH_COLUMN);
        
        $tendencia = "+0%";
        if (count($ultimosPuntajes) == 2) {
            $puntajeAnterior = (float)$ultimosPuntajes[1];
            $puntajeActual = (float)$ultimosPuntajes[0];
            
            if ($puntajeAnterior > 0) {
                $porcentajeCambio = (($puntajeActual - $puntajeAnterior) / $puntajeAnterior) * 100;
                $tendencia = ($porcentajeCambio >= 0 ? "+" : "") . round($porcentajeCambio, 1) . "%";
            }
        }
        
        // 3. Transformar al formato que espera Flutter
        $student = [
            'id' => (int)$student['id_usuario'],
            'nombre' => $student['nombre'],
            'grado' => $student['grado'],
            'avatar' => $student['avatar_path'],
            'puntaje_global' => round((float)$student['mejor_puntaje']),
            'ultimo_simulacro' => $student['ultimo_simulacro'] ? 
                date('Y-m-d', strtotime($student['ultimo_simulacro'])) : '',
            'simulacros_realizados' => (int)$student['total_simulacros'],
            'tendencia' => $tendencia,
            'areas' => [
                'lectura' => round((float)$areas['lectura_promedio']),
                'matematicas' => round((float)$areas['matematicas_promedio']),
                'sociales' => round((float)$areas['sociales_promedio']),
                'naturales' => round((float)$areas['naturales_promedio']),
                'ingles' => round((float)$areas['ingles_promedio']),
            ]
        ];
    }
    
    echo json_encode([
        'status' => 'ok',
        'students' => $students
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error', 
        'msg' => 'Error en el servidor: ' . $e->getMessage()
    ], JSON_UNESCAPED_UNICODE);
}