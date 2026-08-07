<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require __DIR__ . '/auth_middleware.php';

$userData = $GLOBALS['authUser'] ?? null;

if (!$userData || $userData['tipo_usuario'] != 'profesor') {
    http_response_code(401);
    echo json_encode(['status' => 'error', 'message' => 'Acceso no autorizado']);
    exit;
}

$data = json_decode(file_get_contents('php://input'), true);
$simulacroId = isset($data['simulacro_id']) ? (int)$data['simulacro_id'] : null;

// Prioridad al colegio del body; si no viene, usa el del token
$colegioProfesor = $data['colegio'] ?? ($userData['colegio'] ?? null);
$grado = isset($data['grado']) ? $data['grado'] : null;
$anio  = isset($data['anio'])  ? $data['anio']  : date('Y');

if (!$simulacroId) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'ID de simulacro requerido']);
    exit;
}

try {
    // 1. Información general del simulacro
    $generalQuery = "
        SELECT 
            sr.simulacro_id,
            COUNT(DISTINCT sr.usuario_id) AS total_estudiantes,
            COUNT(sr.id)                  AS total_resultados,
            AVG(sr.puntaje_global)        AS promedio_global,
            MIN(sr.fecha_realizacion)     AS fecha_inicio,
            MAX(sr.fecha_realizacion)     AS fecha_fin
        FROM simulacro_resultados sr
        JOIN usuarios u ON sr.usuario_id = u.moodle_id
        WHERE sr.simulacro_id = :simulacro_id
          AND sr.colegio      = :colegio
          AND u.tipo_usuario  = 'estudiante'
    ";
    $generalParams = [':simulacro_id' => $simulacroId, ':colegio' => $colegioProfesor];
    if ($grado && $grado !== 'Todos') { $generalQuery .= " AND u.grado = :grado"; $generalParams[':grado'] = $grado; }
    if ($anio) { $generalQuery .= " AND YEAR(sr.fecha_realizacion) = :anio"; $generalParams[':anio'] = $anio; }

    $generalStmt = $conexion->prepare($generalQuery);
    $generalStmt->execute($generalParams);
    $generalInfo = $generalStmt->fetch(PDO::FETCH_ASSOC);

    if (!$generalInfo || (int)$generalInfo['total_estudiantes'] === 0) {
        echo json_encode([
            'status' => 'ok',
            'detail' => [
                'simulacro_id' => $simulacroId,
                'mensaje'      => 'No hay resultados para este simulacro con los filtros aplicados'
            ]
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }

    // 2. Promedios por área
    $areasQuery = "
        SELECT 
            AVG(sr.lectura_puntaje)     AS lectura,
            AVG(sr.matematicas_puntaje) AS matematicas,
            AVG(sr.sociales_puntaje)    AS sociales,
            AVG(sr.naturales_puntaje)   AS naturales,
            AVG(sr.ingles_puntaje)      AS ingles
        FROM simulacro_resultados sr
        JOIN usuarios u ON sr.usuario_id = u.moodle_id
        WHERE sr.simulacro_id = :simulacro_id
          AND sr.colegio      = :colegio
          AND u.tipo_usuario  = 'estudiante'
    ";
    $areasParams = [':simulacro_id' => $simulacroId, ':colegio' => $colegioProfesor];
    if ($grado && $grado !== 'Todos') { $areasQuery .= " AND u.grado = :grado"; $areasParams[':grado'] = $grado; }
    if ($anio) { $areasQuery .= " AND YEAR(sr.fecha_realizacion) = :anio"; $areasParams[':anio'] = $anio; }

    $areasStmt = $conexion->prepare($areasQuery);
    $areasStmt->execute($areasParams);
    $areasInfo = $areasStmt->fetch(PDO::FETCH_ASSOC);

    // 3. Ranking
    $rankingQuery = "
        SELECT 
            u.id_usuario,
            u.nombre,
            u.grado,
            sr.puntaje_global,
            sr.lectura_puntaje,
            sr.matematicas_puntaje,
            sr.sociales_puntaje,
            sr.naturales_puntaje,
            sr.ingles_puntaje,
            sr.tiempo_empleado,
            sr.fecha_realizacion
        FROM simulacro_resultados sr
        JOIN usuarios u ON sr.usuario_id = u.moodle_id
        WHERE sr.simulacro_id = :simulacro_id
          AND sr.colegio      = :colegio
          AND u.tipo_usuario  = 'estudiante'
    ";
    $rankingParams = [':simulacro_id' => $simulacroId, ':colegio' => $colegioProfesor];
    if ($grado && $grado !== 'Todos') { $rankingQuery .= " AND u.grado = :grado"; $rankingParams[':grado'] = $grado; }
    if ($anio) { $rankingQuery .= " AND YEAR(sr.fecha_realizacion) = :anio"; $rankingParams[':anio'] = $anio; }
    $rankingQuery .= " ORDER BY sr.puntaje_global DESC";

    $rankingStmt = $conexion->prepare($rankingQuery);
    $rankingStmt->execute($rankingParams);
    $rankingInfo = $rankingStmt->fetchAll(PDO::FETCH_ASSOC);

    // 4. Distribución por grado
    $distributionByGrade = [];
    if (!$grado || $grado === 'Todos') {
        $distributionQuery = "
            SELECT 
                u.grado,
                COUNT(*)               AS total_estudiantes,
                AVG(sr.puntaje_global) AS promedio_grado,
                MAX(sr.puntaje_global) AS max_grado,
                MIN(sr.puntaje_global) AS min_grado
            FROM simulacro_resultados sr
            JOIN usuarios u ON sr.usuario_id = u.moodle_id
            WHERE sr.simulacro_id = :simulacro_id
              AND sr.colegio      = :colegio
              AND u.tipo_usuario  = 'estudiante'
        ";
        $distParams = [':simulacro_id' => $simulacroId, ':colegio' => $colegioProfesor];
        if ($anio) { $distributionQuery .= " AND YEAR(sr.fecha_realizacion) = :anio"; $distParams[':anio'] = $anio; }
        $distributionQuery .= " GROUP BY u.grado ORDER BY u.grado";

        $distributionStmt = $conexion->prepare($distributionQuery);
        $distributionStmt->execute($distParams);
        $distributionByGrade = $distributionStmt->fetchAll(PDO::FETCH_ASSOC);
    }

    // 5. Áreas débiles en PHP
    $weakAreasInfo = [];
    if ($areasInfo) {
        $threshold = 70;
        $areasMap = [
            'Lectura'     => $areasInfo['lectura'],
            'Matemáticas' => $areasInfo['matematicas'],
            'Sociales'    => $areasInfo['sociales'],
            'Naturales'   => $areasInfo['naturales'],
            'Inglés'      => $areasInfo['ingles']
        ];
        foreach ($areasMap as $nombreArea => $promedio) {
            if ($promedio !== null && $promedio < $threshold) {
                $weakAreasInfo[] = [
                    'area'     => $nombreArea,
                    'promedio' => round((float)$promedio, 2)
                ];
            }
        }
    }

    // Respuesta final
    $response = [
        'status' => 'ok',
        'detail' => [
            'simulacro_id' => $simulacroId,
            'general_info' => [
                'total_estudiantes' => (int)$generalInfo['total_estudiantes'],
                'total_resultados'  => (int)$generalInfo['total_resultados'],
                'promedio_global'   => round((float)$generalInfo['promedio_global'], 2),
                'fecha_inicio'      => $generalInfo['fecha_inicio'],
                'fecha_fin'         => $generalInfo['fecha_fin']
            ],
            'promedios_por_area' => [
                'lectura'     => round((float)($areasInfo['lectura'] ?? 0), 2),
                'matematicas' => round((float)($areasInfo['matematicas'] ?? 0), 2),
                'sociales'    => round((float)($areasInfo['sociales'] ?? 0), 2),
                    'naturales'   => round((float)($areasInfo['naturales'] ?? 0), 2),
                'ingles'      => round((float)($areasInfo['ingles'] ?? 0), 2)
            ],
            'ranking_estudiantes'    => $rankingInfo,
            'distribucion_por_grado' => $distributionByGrade,
            'areas_debiles'          => $weakAreasInfo,
            'filters_applied'        => [
                'colegio' => $colegioProfesor,
                'grado'   => $grado,
                'anio'    => $anio
            ]
        ]
    ];

    echo json_encode($response, JSON_UNESCAPED_UNICODE);

} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode([
        'status'  => 'error',
        'message' => 'Error BD: ' . $e->getMessage()
    ]);
}
?>
