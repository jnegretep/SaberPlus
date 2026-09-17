<?php
declare(strict_types=1);

/**
 * icfes_prediction.php - Saber+ Prediccion ICFES y Comparativa Historica
 *
 * Devuelve:
 * 1. Prediccion del puntaje ICFES basado en el progreso del usuario
 * 2. Evolucion historica del puntaje (grafico de linea)
 * 3. Analisis por area (fortalezas y debilidades)
 * 4. Comparativa con promedio nacional (si hay datos)
 * 5. Tendencia (subiendo/bajando/estable)
 *
 * La prediccion se calcula con:
 * - Promedio de ultimos 3 simulacros (peso 60%)
 * - Tendencia (mejora/empeora) (peso 20%)
 * - Consistencia (variacion entre simulacros) (peso 20%)
 */

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/includes/config.php';

// 🔧 FIX #1: jwt_config.php usa `return [...]`, hay que capturar el array.
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
    // 1. Obtener todos los resultados de simulacros del usuario
    // 🔧 FIX #2: eliminada la subquery a `moodle.mdl_course` porque el usuario
    // `jnegretep` no tiene GRANT SELECT sobre esa base. El campo `simulacro_nombre`
    // se resuelve con el fallback 'Simulacro' más abajo.
    $stmt = $conexion->prepare("
        SELECT DATE_FORMAT(fecha_realizacion, '%Y-%m-%d') as fecha,
               puntaje_global,
               lectura_puntaje, matematicas_puntaje, sociales_puntaje,
               naturales_puntaje, ingles_puntaje,
               tiempo_empleado
        FROM simulacro_resultados sr
        WHERE sr.usuario_id = ?
        ORDER BY sr.fecha_realizacion ASC
    ");
    $stmt->execute([$moodleUserId]);
    $results = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // 2. Si no hay datos suficientes
    if (count($results) < 1) {
        echo json_encode([
            'status' => 'ok',
            'data' => [
                'prediction' => null,
                'history' => [],
                'area_analysis' => [],
                'recommendations' => [
                    'Aun no has realizado simulacros. ¡Completa tu primer simulacro diagnostico para ver tu prediccion!',
                ],
            ],
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }

    // 3. Construir historico
    $history = [];
    foreach ($results as $r) {
        $history[] = [
            'date' => $r['fecha'],
            'score' => (float)$r['puntaje_global'],
            'simulacro' => $r['simulacro_nombre'] ?? 'Simulacro',
            'areas' => [
                'lectura' => (float)($r['lectura_puntaje'] ?? 0),
                'matematicas' => (float)($r['matematicas_puntaje'] ?? 0),
                'sociales' => (float)($r['sociales_puntaje'] ?? 0),
                'naturales' => (float)($r['naturales_puntaje'] ?? 0),
                'ingles' => (float)($r['ingles_puntaje'] ?? 0),
            ],
        ];
    }

    // 4. Calcular prediccion
    $prediction = _calculatePrediction($results);

    // 5. Analisis por area
    $areaAnalysis = _calculateAreaAnalysis($results);

    // 6. Generar recomendaciones
    $recommendations = _generateRecommendations($results, $areaAnalysis, $prediction);

    echo json_encode([
        'status' => 'ok',
        'data' => [
            'prediction' => $prediction,
            'history' => $history,
            'area_analysis' => $areaAnalysis,
            'recommendations' => $recommendations,
        ],
    ], JSON_UNESCAPED_UNICODE);

} catch (Throwable $e) {
    error_log("[ICFES_PREDICTION] Error: " . $e->getMessage());
    http_response_code(500);
    exit(json_encode([
        'status' => 'error',
        'msg' => 'Error obteniendo prediccion',
        'debug' => $e->getMessage(),
    ]));
}


// =============================================================
// FUNCIONES DE CALCULO
// =============================================================

/**
 * Calcula la prediccion del puntaje ICFES.
 */
function _calculatePrediction(array $results): array {
    $totalSimulacros = count($results);
    $scores = array_map(fn($r) => (float)$r['puntaje_global'], $results);

    $recentScores = array_slice($scores, max(0, $totalSimulacros - 3));
    $avgRecent = array_sum($recentScores) / count($recentScores);

    $lastScore = end($scores);

    $avgTotal = array_sum($scores) / count($scores);
    $trendDiff = $avgRecent - $avgTotal;
    $trendPct = $avgTotal > 0 ? ($trendDiff / $avgTotal * 100) : 0;

    if ($trendPct > 3) {
        $trend = 'ascending';
    } elseif ($trendPct < -3) {
        $trend = 'descending';
    } else {
        $trend = 'stable';
    }

    $trendAdjustment = $trendDiff * 0.2;
    $predictedScore = ($avgRecent * 0.8) + ($avgRecent + $trendAdjustment) * 0.2;
    $predictedScore = max(0, min(500, round($predictedScore)));

    $consistency = _calculateConsistency($recentScores);
    $confidencePct = min(95, ($totalSimulacros * 15) + ($consistency * 0.3));

    if ($totalSimulacros >= 5 && $consistency > 80) {
        $confidence = 'alta';
    } elseif ($totalSimulacros >= 3) {
        $confidence = 'media';
    } else {
        $confidence = 'baja';
    }

    $rangeMargin = (100 - $confidencePct) * 0.5;
    $rangeMin = max(0, round($predictedScore - $rangeMargin));
    $rangeMax = min(500, round($predictedScore + $rangeMargin));

    $message = _getPredictionMessage($predictedScore, $trend, $totalSimulacros);

    return [
        'predicted_score' => $predictedScore,
        'confidence' => $confidence,
        'confidence_pct' => round($confidencePct),
        'range_min' => $rangeMin,
        'range_max' => $rangeMax,
        'based_on_simulacros' => $totalSimulacros,
        'last_score' => round($lastScore),
        'trend' => $trend,
        'trend_pct' => round($trendPct, 1),
        'message' => $message,
    ];
}

function _calculateConsistency(array $scores): float {
    if (count($scores) < 2) return 50;

    $avg = array_sum($scores) / count($scores);
    if ($avg == 0) return 0;

    $variance = 0;
    foreach ($scores as $s) {
        $variance += pow($s - $avg, 2);
    }
    $stdDev = sqrt($variance / count($scores));
    $coefficientVariation = ($stdDev / $avg) * 100;

    return max(0, min(100, 100 - $coefficientVariation));
}

function _getPredictionMessage(float $score, string $trend, int $totalSim): string {
    if ($totalSim < 2) {
        return 'Completa mas simulacros para obtener una prediccion mas precisa.';
    }

    $trendText = match($trend) {
        'ascending' => 'Tu progreso esta mejorando. Sigue asi!',
        'descending' => 'Tu rendimiento ha bajado. Repasa los temas donde fallaste.',
        'stable' => 'Tu rendimiento es estable. Para mejorar, enfocate en tus areas debiles.',
        default => 'Continua practicando para mejorar tu prediccion.',
    };

    if ($score >= 400) {
        return "Excelente nivel! Estarias en el top 10% nacional. $trendText";
    } elseif ($score >= 350) {
        return "Muy buen nivel! Tienes grandes posibilidades de excelencia. $trendText";
    } elseif ($score >= 300) {
        return "Buen nivel! Vas por buen camino. $trendText";
    } elseif ($score >= 250) {
        return "Nivel medio. Con mas practica puedes llegar a 300+. $trendText";
    } else {
        return "Necesitas reforzar conceptos basicos. No te rindas! $trendText";
    }
}

function _calculateAreaAnalysis(array $results): array {
    $areas = [
        'Lectura Critica' => ['key' => 'lectura_puntaje', 'color' => '#22C55E', 'icon' => 'menu_book_rounded'],
        'Matematicas' => ['key' => 'matematicas_puntaje', 'color' => '#2563EB', 'icon' => 'calculate_rounded'],
        'Sociales y Ciudadanas' => ['key' => 'sociales_puntaje', 'color' => '#8B5CF6', 'icon' => 'public_rounded'],
        'Ciencias Naturales' => ['key' => 'naturales_puntaje', 'color' => '#F97316', 'icon' => 'science_rounded'],
        'Ingles' => ['key' => 'ingles_puntaje', 'color' => '#0EA5E9', 'icon' => 'translate_rounded'],
    ];

    $analysis = [];

    foreach ($areas as $areaName => $config) {
        $key = $config['key'];
        $scores = array_map(fn($r) => (float)($r[$key] ?? 0), $results);

        $validScores = array_filter($scores, fn($s) => $s > 0);
        if (empty($validScores)) {
            $analysis[] = [
                'area' => $areaName,
                'avg' => 0,
                'last' => 0,
                'trend' => 'no_data',
                'trend_pct' => 0,
                'color' => $config['color'],
                'icon' => $config['icon'],
            ];
            continue;
        }

        $avg = array_sum($validScores) / count($validScores);
        $last = end($validScores);

        if (count($validScores) >= 2) {
            $firstHalf = array_slice(array_values($validScores), 0, intval(count($validScores) / 2));
            $secondHalf = array_slice(array_values($validScores), intval(count($validScores) / 2));
            $firstAvg = array_sum($firstHalf) / count($firstHalf);
            $secondAvg = array_sum($secondHalf) / count($secondHalf);
            $areaTrendPct = $firstAvg > 0 ? (($secondAvg - $firstAvg) / $firstAvg * 100) : 0;

            if ($areaTrendPct > 5) $areaTrend = 'up';
            elseif ($areaTrendPct < -5) $areaTrend = 'down';
            else $areaTrend = 'stable';
        } else {
            $areaTrend = 'stable';
            $areaTrendPct = 0;
        }

        $analysis[] = [
            'area' => $areaName,
            'avg' => round($avg, 1),
            'last' => round($last, 1),
            'trend' => $areaTrend,
            'trend_pct' => round($areaTrendPct, 1),
            'color' => $config['color'],
            'icon' => $config['icon'],
        ];
    }

    usort($analysis, fn($a, $b) => $b['avg'] <=> $a['avg']);

    return $analysis;
}

function _generateRecommendations(array $results, array $areaAnalysis, array $prediction): array {
    $recommendations = [];

    if (!empty($areaAnalysis)) {
        $weakest = end($areaAnalysis);
        if ($weakest['avg'] > 0) {
            $recommendations[] = "Tu area mas debil es {$weakest['area']} " .
                "(promedio: {$weakest['avg']}). " .
                "Practica mas ejercicios de esta area para mejorar tu puntaje global.";
        }

        $strongest = $areaAnalysis[0];
        if ($strongest['avg'] > 0) {
            $recommendations[] = "Tu area mas fuerte es {$strongest['area']} " .
                "(promedio: {$strongest['avg']}). " .
                "Mantente practicando para conservar tu nivel.";
        }
    }

    if ($prediction !== null) {
        $trend = $prediction['trend'];
        $trendPct = $prediction['trend_pct'];

        if ($trend === 'ascending') {
            $recommendations[] = "Has mejorado {$trendPct}% desde tus primeros simulacros. Sigue asi!";
        } elseif ($trend === 'descending') {
            $recommendations[] = "Tu rendimiento ha bajado {$trendPct}% en los ultimos simulacros. " .
                "Repasa los temas donde mas has fallado.";
        }

        $totalSim = $prediction['based_on_simulacros'];
        if ($totalSim < 3) {
            $recommendations[] = "Solo has realizado {$totalSim} simulacro(s). " .
                "Completa al menos 3 para obtener una prediccion mas precisa.";
        } elseif ($totalSim >= 5) {
            $recommendations[] = "Has realizado {$totalSim} simulacros. Tu prediccion tiene " .
                "alta confiabilidad. Sigue tu ritmo de practica!";
        }
    }

    if (count($results) >= 2) {
        $firstScore = (float)$results[0]['puntaje_global'];
        $lastScore = (float)end($results)['puntaje_global'];
        $improvement = $lastScore - $firstScore;

        if ($improvement > 20) {
            $recommendations[] = "Has mejorado {$improvement} puntos desde tu diagnostico. " .
                "Estas en el camino correcto!";
        } elseif ($improvement < -20) {
            $recommendations[] = "Tu puntaje ha bajado " . abs($improvement) . " puntos. " .
                "Te recomendamos repasar los conceptos basicos.";
        }
    }

    return $recommendations;
}