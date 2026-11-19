<?php
declare(strict_types=1);

/**
 * error_analysis.php - Saber+ Analisis de Errores
 *
 * Analiza los errores del usuario en simulacros y los clasifica por:
 * 1. Por area (cual area falla mas)
 * 2. Por tipo de error (conceptual, calculo, comprension, tiempo)
 * 3. Por patron (preguntas que siempre falla)
 * 4. Evolucion del error (esta mejorando o empeorando)
 */

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/includes/config.php';

// 🔧 FIX #1: jwt_config.php usa `return [...]`, hay que capturar el array.
// Antes: require __DIR__ . '/jwt_config.php';
$configJwt = require __DIR__ . '/jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if (!in_array($_SERVER['REQUEST_METHOD'], ['POST', 'GET'])) {
    http_response_code(405);
    exit(json_encode(['status' => 'error', 'msg' => 'Metodo no permitido']));
}

// Autenticacion JWT
$hdrs = function_exists('getallheaders') ? getallheaders() : [];
$authHeader = $hdrs['Authorization'] ?? $hdrs['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';

if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
}

try {
    $decoded = JWT::decode($m[1], new Key($configJwt['secret'], 'HS256'));
    $moodleUserId = (int)($decoded->data->moodle_userid ?? 0);
    $userId = (int)($decoded->data->id_usuario ?? 0);
    if ($moodleUserId <= 0 && $userId > 0) {
        $stmt = $conexion->prepare("SELECT moodle_id FROM usuarios WHERE id_usuario = ?");
        $stmt->execute([$userId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        $moodleUserId = (int)($row['moodle_id'] ?? 0);
    }
    if ($moodleUserId <= 0) {
        http_response_code(401);
        exit(json_encode(['status' => 'error', 'msg' => 'Usuario no valido']));
    }
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Token invalido']));
}

try {
    // 1. Obtener todos los resultados de simulacros
    // 🔧 FIX #2: eliminada la subquery a `mdl_course`. Esa tabla vive en la
    // base de datos de Moodle, y el usuario `jnegretep` no tiene permisos
    // sobre ella. El campo `simulacro_nombre` cae al fallback más abajo.
    $stmt = $conexion->prepare("
        SELECT DATE_FORMAT(fecha_realizacion, '%Y-%m-%d') as fecha,
               puntaje_global,
               lectura_correctas, matematicas_correctas, sociales_correctas,
               naturales_correctas, ingles_correctas,
               lectura_puntaje, matematicas_puntaje, sociales_puntaje,
               naturales_puntaje, ingles_puntaje,
               tiempo_empleado
        FROM simulacro_resultados sr
        WHERE sr.usuario_id = ?
        ORDER BY sr.fecha_realizacion ASC
    ");
    $stmt->execute([$moodleUserId]);
    $results = $stmt->fetchAll(PDO::FETCH_ASSOC);

    if (count($results) < 1) {
        echo json_encode([
            'status' => 'ok',
            'data' => [
                'summary' => null,
                'by_area' => [],
                'error_types' => [],
                'evolution' => [],
                'recommendations' => ['Aun no has realizado simulacros. Completa tu primer simulacro para ver tu analisis de errores.'],
            ],
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }

    // 2. Calcular resumen general
    $summary = _calculateSummary($results);

    // 3. Analisis por area
    $byArea = _calculateByArea($results);

    // 4. Clasificar tipos de error (estimacion basada en patrones)
    $errorTypes = _classifyErrorTypes($results, $byArea);

    // 5. Evolucion de errores
    $evolution = _calculateEvolution($results);

    // 6. Generar recomendaciones
    $recommendations = _generateErrorRecommendations($summary, $byArea, $errorTypes, $evolution);

    echo json_encode([
        'status' => 'ok',
        'data' => [
            'summary' => $summary,
            'by_area' => $byArea,
            'error_types' => $errorTypes,
            'evolution' => $evolution,
            'recommendations' => $recommendations,
        ],
    ], JSON_UNESCAPED_UNICODE);

} catch (Throwable $e) {
    error_log("[ERROR_ANALYSIS] Error: " . $e->getMessage());
    http_response_code(500);
    exit(json_encode([
        'status' => 'error',
        'msg' => 'Error obteniendo analisis',
        'debug' => $e->getMessage(),
    ]));
}


// =============================================================
// FUNCIONES
// =============================================================

/**
 * Calcula el resumen general de errores.
 */
function _calculateSummary(array $results): array {
    $totalCorrect = 0;
    $totalQuestions = 0;
    $totalTime = 0;
    $simCount = count($results);

    foreach ($results as $r) {
        $correct = (int)$r['lectura_correctas'] + (int)$r['matematicas_correctas'] +
                   (int)$r['sociales_correctas'] + (int)$r['naturales_correctas'] +
                   (int)$r['ingles_correctas'];

        $estimatedTotal = 125;
        $totalCorrect += $correct;
        $totalQuestions += $estimatedTotal;
        $totalTime += (int)$r['tiempo_empleado'];
    }

    $totalIncorrect = $totalQuestions - $totalCorrect;
    $accuracy = $totalQuestions > 0 ? round(($totalCorrect / $totalQuestions) * 100, 1) : 0;
    $avgTimePerSim = $simCount > 0 ? round($totalTime / $simCount) : 0;

    $areas = [];
    foreach ($results as $r) {
        $areas['Lectura Critica'][] = (int)$r['lectura_correctas'];
        $areas['Matematicas'][] = (int)$r['matematicas_correctas'];
        $areas['Sociales y Ciudadanas'][] = (int)$r['sociales_correctas'];
        $areas['Ciencias Naturales'][] = (int)$r['naturales_correctas'];
        $areas['Ingles'][] = (int)$r['ingles_correctas'];
    }

    $avgByArea = [];
    foreach ($areas as $name => $scores) {
        $validScores = array_filter($scores, fn($s) => $s >= 0);
        if (!empty($validScores)) {
            $avgByArea[$name] = array_sum($validScores) / count($validScores);
        }
    }

    asort($avgByArea);
    $weakestArea = !empty($avgByArea) ? array_key_first($avgByArea) : 'N/A';
    $strongestArea = !empty($avgByArea) ? array_key_last($avgByArea) : 'N/A';

    return [
        'total_questions' => $totalQuestions,
        'correct' => $totalCorrect,
        'incorrect' => max(0, $totalIncorrect),
        'unanswered' => max(0, $totalQuestions - $totalCorrect - $totalIncorrect),
        'accuracy_pct' => $accuracy,
        'total_simulacros' => $simCount,
        'avg_time_per_simulacro' => $avgTimePerSim,
        'weakest_area' => $weakestArea,
        'strongest_area' => $strongestArea,
    ];
}

/**
 * Analiza errores por area.
 */
function _calculateByArea(array $results): array {
    $areasConfig = [
        'Lectura Critica' => ['key' => 'lectura', 'color' => '#22C55E', 'icon' => 'menu_book_rounded', 'total_questions' => 25],
        'Matematicas' => ['key' => 'matematicas', 'color' => '#2563EB', 'icon' => 'calculate_rounded', 'total_questions' => 25],
        'Sociales y Ciudadanas' => ['key' => 'sociales', 'color' => '#8B5CF6', 'icon' => 'public_rounded', 'total_questions' => 25],
        'Ciencias Naturales' => ['key' => 'naturales', 'color' => '#F97316', 'icon' => 'science_rounded', 'total_questions' => 25],
        'Ingles' => ['key' => 'ingles', 'color' => '#0EA5E9', 'icon' => 'translate_rounded', 'total_questions' => 25],
    ];

    $analysis = [];

    foreach ($areasConfig as $areaName => $config) {
        $key = $config['key'];
        $totalCorrect = 0;
        $totalQuestions = 0;

        foreach ($results as $r) {
            $correct = (int)($r["{$key}_correctas"] ?? 0);
            $totalCorrect += $correct;
            $totalQuestions += $config['total_questions'];
        }

        $totalIncorrect = max(0, $totalQuestions - $totalCorrect);
        $accuracy = $totalQuestions > 0 ? round(($totalCorrect / $totalQuestions) * 100, 1) : 0;

        $analysis[] = [
            'area' => $areaName,
            'total' => $totalQuestions,
            'correct' => $totalCorrect,
            'incorrect' => $totalIncorrect,
            'accuracy' => $accuracy,
            'color' => $config['color'],
            'icon' => $config['icon'],
        ];
    }

    usort($analysis, fn($a, $b) => $a['accuracy'] <=> $b['accuracy']);

    return $analysis;
}

/**
 * Clasifica los errores por tipo usando heuristicas.
 */
function _classifyErrorTypes(array $results, array $byArea): array {
    $totalErrors = 0;
    foreach ($byArea as $a) {
        $totalErrors += $a['incorrect'];
    }

    if ($totalErrors == 0) {
        return [
            [
                'type' => 'none',
                'label' => 'Sin errores',
                'count' => 0,
                'pct' => 0,
                'description' => 'No has tenido errores en tus simulacros. Excelente!',
            ],
        ];
    }

    $errorTypes = [];

    // 1. Error conceptual
    $conceptualErrors = 0;
    foreach ($byArea as $area) {
        if ($area['accuracy'] < 60) {
            $conceptualErrors += $area['incorrect'];
        }
    }
    if ($conceptualErrors > 0) {
        $errorTypes[] = [
            'type' => 'conceptual',
            'label' => 'Error conceptual',
            'count' => $conceptualErrors,
            'pct' => round(($conceptualErrors / $totalErrors) * 100, 1),
            'description' => 'No dominas los conceptos basicos de algunas areas. Repasa la teoria antes de seguir practicando.',
            'icon' => 'school_rounded',
            'color' => '#EF4444',
        ];
    }

    // 2. Error de calculo
    $mathArea = null;
    foreach ($byArea as $area) {
        if (strpos($area['area'], 'Matematicas') !== false) {
            $mathArea = $area;
            break;
        }
    }
    if ($mathArea && $mathArea['incorrect'] > 0) {
        $errorTypes[] = [
            'type' => 'calculation',
            'label' => 'Error de calculo',
            'count' => $mathArea['incorrect'],
            'pct' => round(($mathArea['incorrect'] / $totalErrors) * 100, 1),
            'description' => 'Cometes errores en operaciones matematicas. Practica mas ejercicios de algebra, aritmetica y geometria.',
            'icon' => 'calculate_rounded',
            'color' => '#F59E0B',
        ];
    }

    // 3. Error de comprension
    $comprehensionErrors = 0;
    foreach ($byArea as $area) {
        if (strpos($area['area'], 'Lectura') !== false || strpos($area['area'], 'Ingles') !== false) {
            $comprehensionErrors += $area['incorrect'];
        }
    }
    if ($comprehensionErrors > 0) {
        $errorTypes[] = [
            'type' => 'comprehension',
            'label' => 'Error de comprension',
            'count' => $comprehensionErrors,
            'pct' => round(($comprehensionErrors / $totalErrors) * 100, 1),
            'description' => 'Tienes dificultad interpretando textos. Lee mas y practica comprension lectora.',
            'icon' => 'menu_book_rounded',
            'color' => '#3B82F6',
        ];
    }

    // 4. Error por tiempo
    $avgTime = 0;
    foreach ($results as $r) {
        $avgTime += (int)$r['tiempo_empleado'];
    }
    $avgTime = count($results) > 0 ? $avgTime / count($results) : 0;

    $timeErrors = 0;
    if ($avgTime > 0 && $avgTime < 1800) {
        $timeErrors = (int)($totalErrors * 0.1);
        if ($timeErrors > 0) {
            $errorTypes[] = [
                'type' => 'time_pressure',
                'label' => 'Error por tiempo',
                'count' => $timeErrors,
                'pct' => round(($timeErrors / $totalErrors) * 100, 1),
                'description' => 'Estas respondiendo muy rapido. Toma mas tiempo para analizar cada pregunta.',
                'icon' => 'timer_rounded',
                'color' => '#8B5CF6',
            ];
        }
    }

    usort($errorTypes, fn($a, $b) => $b['count'] <=> $a['count']);

    return $errorTypes;
}

/**
 * Calcula la evolucion de la precision a lo largo del tiempo.
 */
function _calculateEvolution(array $results): array {
    $evolution = [];

    foreach ($results as $r) {
        $correct = (int)$r['lectura_correctas'] + (int)$r['matematicas_correctas'] +
                   (int)$r['sociales_correctas'] + (int)$r['naturales_correctas'] +
                   (int)$r['ingles_correctas'];

        $estimatedTotal = 125;
        $accuracy = $estimatedTotal > 0 ? round(($correct / $estimatedTotal) * 100, 1) : 0;
        $errors = $estimatedTotal - $correct;

        $evolution[] = [
            'date' => $r['fecha'],
            'accuracy' => $accuracy,
            'errors' => max(0, $errors),
            'simulacro' => $r['simulacro_nombre'] ?? 'Simulacro',
        ];
    }

    return $evolution;
}

/**
 * Genera recomendaciones basadas en el analisis de errores.
 */
function _generateErrorRecommendations(array $summary, array $byArea, array $errorTypes, array $evolution): array {
    $recommendations = [];

    if (!empty($errorTypes) && $errorTypes[0]['type'] !== 'none') {
        $topError = $errorTypes[0];
        $recommendations[] = "Tu tipo de error mas comun es '{$topError['label']}' " .
            "({$topError['pct']}% de tus errores). {$topError['description']}";
    }

    if (!empty($byArea)) {
        $weakest = $byArea[0];
        if ($weakest['accuracy'] < 50) {
            $recommendations[] = "Tu area mas debil es {$weakest['area']} " .
                "con solo {$weakest['accuracy']}% de precision. " .
                "Te recomendamos repasar los conceptos basicos antes de hacer mas simulacros.";
        } elseif ($weakest['accuracy'] < 70) {
            $recommendations[] = "Tu area mas debil es {$weakest['area']} " .
                "({$weakest['accuracy']}% precision). Practica mas ejercicios de esta area.";
        }
    }

    if (count($evolution) >= 2) {
        $first = $evolution[0]['accuracy'];
        $last = end($evolution)['accuracy'];
        $diff = $last - $first;

        if ($diff > 10) {
            $recommendations[] = "Has mejorado tu precision del {$first}% al {$last}% " .
                "(+{$diff} puntos). Sigue asi!";
        } elseif ($diff < -10) {
            $recommendations[] = "Tu precision ha bajado del {$first}% al {$last}% " .
                "({$diff} puntos). Repasa los temas donde mas has fallado.";
        }
    }

    if ($summary['avg_time_per_simulacro'] > 0 && $summary['avg_time_per_simulacro'] < 1800) {
        $minutos = round($summary['avg_time_per_simulacro'] / 60);
        $recommendations[] = "En promedio dedicas {$minutos} minutos por simulacro. " .
            "Considera tomar mas tiempo para analizar cada pregunta.";
    }

    $accuracy = $summary['accuracy_pct'];
    if ($accuracy >= 80) {
        $recommendations[] = "Excelente precision del {$accuracy}%! Estas listo para el ICFES real.";
    } elseif ($accuracy >= 60) {
        $recommendations[] = "Buena precision del {$accuracy}%. Con un poco mas de practica puedes llegar al 80%.";
    } elseif ($accuracy >= 40) {
        $recommendations[] = "Tu precision es del {$accuracy}%. Necesitas reforzar varios conceptos. No te rindas!";
    } else {
        $recommendations[] = "Tu precision es del {$accuracy}%. Te recomendamos repasar los conceptos basicos de cada area.";
    }

    return $recommendations;
}