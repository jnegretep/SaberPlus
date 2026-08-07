<?php
// teacher_list_simulacros.php - Versión definitiva
ini_set('display_errors', 0);
error_reporting(E_ALL);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/auth_middleware.php';

$userData = $GLOBALS['authUser'] ?? null;

if (!$userData || $userData['tipo_usuario'] !== 'profesor') {
    http_response_code(401);
    echo json_encode(['status' => 'error', 'message' => 'No autorizado']);
    exit;
}

$data = json_decode(file_get_contents('php://input'), true);
$colegio = $userData['colegio'] ?? ($data['colegio'] ?? null);
$grado = $data['grado'] ?? null;
$anio = $data['anio'] ?? date('Y');

if (!$colegio) {
    echo json_encode(['status' => 'error', 'message' => 'Falta el colegio']);
    exit;
}

try {
    // 1. OBTENER TOKEN MOODLE DEL PROFESOR
    $profesorMoodleId = $userData['moodle_id'] ?? null;
    $moodleToken = null;
    
    if ($profesorMoodleId) {
        $stmtToken = $conexion->prepare("SELECT moodle_token FROM usuarios WHERE moodle_id = :mid");
        $stmtToken->execute([':mid' => $profesorMoodleId]);
        $tokenRow = $stmtToken->fetch(PDO::FETCH_ASSOC);
        $moodleToken = $tokenRow['moodle_token'] ?? null;
    }
    
    // 2. OBTENER SIMULACROS CON PARTICIPACIÓN
    $query = "
        SELECT 
            sr.simulacro_id as id,
            sr.course_id,
            COUNT(DISTINCT sr.usuario_id) as total_estudiantes,
            COUNT(DISTINCT sr.id) as total_intentos,
            AVG(sr.puntaje_global) as promedio_global,
            MIN(sr.fecha_realizacion) as fecha_inicio,
            MAX(sr.fecha_realizacion) as fecha_fin
        FROM simulacro_resultados sr
        INNER JOIN usuarios u ON sr.usuario_id = u.moodle_id
        WHERE u.colegio = :colegio
        AND u.tipo_usuario = 'estudiante'
        AND sr.colegio = :colegio2
    ";
    
    $params = [':colegio' => $colegio, ':colegio2' => $colegio];
    
    if ($grado && $grado != 'Todos' && $grado != '') {
        $query .= " AND u.grado = :grado";
        $params[':grado'] = $grado;
    }
    
    if ($anio && $anio != 'Todos' && $anio != '' && is_numeric($anio)) {
        $query .= " AND YEAR(sr.fecha_realizacion) = :anio";
        $params[':anio'] = (int)$anio;
    }
    
    $query .= " GROUP BY sr.simulacro_id, sr.course_id
                ORDER BY MAX(sr.fecha_realizacion) DESC";
    
    $stmt = $conexion->prepare($query);
    $stmt->execute($params);
    $simulacrosRaw = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    // 3. OBTENER NOMBRES DESDE MOODLE (por lotes por course_id)
    $formattedSimulacros = [];
    
    if ($moodleToken && !empty($simulacrosRaw)) {
        // Agrupar por course_id para hacer una sola llamada por curso
        $courseGroups = [];
        foreach ($simulacrosRaw as $sim) {
            $courseId = (int)$sim['course_id'];
            if (!isset($courseGroups[$courseId])) {
                $courseGroups[$courseId] = [];
            }
            $courseGroups[$courseId][] = $sim;
        }
        
        // Para cada curso, obtener sus quizzes
        foreach ($courseGroups as $courseId => $simulacrosDelCurso) {
            try {
                require_once __DIR__ . '/includes/moodle.php';
                $client = getMoodleClient();
                
                $result = $client->request(
                    $moodleToken,
                    'mod_quiz_get_quizzes_by_courses',
                    ['courseids[0]' => $courseId]
                );
                
                $quizzes = $result['quizzes'] ?? [];
                
                // Crear mapa rápido de quizzes por ID
                $quizMap = [];
                foreach ($quizzes as $quiz) {
                    $quizMap[$quiz['id']] = $quiz;
                }
                
                // Procesar cada simulacro de este curso
                foreach ($simulacrosDelCurso as $sim) {
                    $simulacroId = (int)$sim['id'];
                    $quizData = $quizMap[$simulacroId] ?? null;
                    
                    $formattedSimulacros[] = [
                        'id' => $simulacroId,
                        'course_id' => $courseId,
                        'nombre' => $quizData['name'] ?? "Simulacro #{$simulacroId}",
                        'descripcion' => $quizData['intro'] ?? '',
                        'fecha' => date('Y-m-d', strtotime($sim['fecha_inicio'])),
                        'total_estudiantes' => (int)$sim['total_estudiantes'],
                        'total_intentos' => (int)$sim['total_intentos'],
                        'promedio_global' => round((float)$sim['promedio_global'], 1),
                        'fecha_inicio' => $sim['fecha_inicio'],
                        'fecha_fin' => $sim['fecha_fin'],
                        'completado' => true
                    ];
                }
                
            } catch (Exception $e) {
                error_log("? Error obteniendo quizzes curso {$courseId}: " . $e->getMessage());
                // Fallback: usar datos básicos
                foreach ($simulacrosDelCurso as $sim) {
                    $formattedSimulacros[] = [
                        'id' => (int)$sim['id'],
                        'course_id' => $courseId,
                        'nombre' => "Simulacro #" . $sim['id'],
                        'descripcion' => '',
                        'fecha' => date('Y-m-d', strtotime($sim['fecha_inicio'])),
                        'total_estudiantes' => (int)$sim['total_estudiantes'],
                        'total_intentos' => (int)$sim['total_intentos'],
                        'promedio_global' => round((float)$sim['promedio_global'], 1),
                        'fecha_inicio' => $sim['fecha_inicio'],
                        'fecha_fin' => $sim['fecha_fin'],
                        'completado' => true
                    ];
                }
            }
        }
    } elseif (!empty($simulacrosRaw)) {
        // Fallback sin Moodle
        foreach ($simulacrosRaw as $sim) {
            $formattedSimulacros[] = [
                'id' => (int)$sim['id'],
                'course_id' => (int)$sim['course_id'],
                'nombre' => "Simulacro #" . $sim['id'],
                'descripcion' => '',
                'fecha' => date('Y-m-d', strtotime($sim['fecha_inicio'])),
                'total_estudiantes' => (int)$sim['total_estudiantes'],
                'total_intentos' => (int)$sim['total_intentos'],
                'promedio_global' => round((float)$sim['promedio_global'], 1),
                'fecha_inicio' => $sim['fecha_inicio'],
                'fecha_fin' => $sim['fecha_fin'],
                'completado' => true
            ];
        }
    }
    
    echo json_encode([
        'status' => 'ok',
        'simulacros' => $formattedSimulacros,
        'metadata' => [
            'colegio' => $colegio,
            'grado' => $grado ?? 'Todos',
            'anio' => $anio,
            'total' => count($formattedSimulacros)
        ]
    ], JSON_UNESCAPED_UNICODE);
    
} catch (Exception $e) {
    error_log("? Error en teacher_list_simulacros: " . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'Error al listar simulacros: ' . $e->getMessage()
    ], JSON_UNESCAPED_UNICODE);
}
?>