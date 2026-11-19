<?php
declare(strict_types=1);

/**
 * daily_challenges.php - Saber+ Retos Diarios API
 *
 * Devuelve los retos diarios disponibles para el usuario autenticado.
 * Los retos diarios son cuestionarios dentro de los cursos 56-60
 * (categoría "Retos Diarios" id=5 en Moodle).
 *
 * Lógica:
 * - Obtiene los cuestionarios de los cursos 56-60
 * - Verifica cuáles tienen ventana de tiempo activa (timeopen/timeclose)
 * - Verifica cuáles ya completó el usuario hoy
 * - Devuelve: disponibles, completados, y pendientes
 *
 * Response:
 * {
 *   "status": "ok",
 *   "data": {
 *     "date": "2026-08-31",
 *     "available": [ { challenge... } ],
 *     "completed": [ { challenge... } ],
 *     "pending": [ { challenge... } ],
 *     "total_available": 3,
 *     "total_completed": 1,
 *     "all_completed": false
 *   }
 * }
 */

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/includes/config.php';
require __DIR__ . '/includes/moodle.php';
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
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
}

// ── Autenticación JWT ──
$hdrs = function_exists('getallheaders') ? getallheaders() : [];
$authHeader = $hdrs['Authorization'] ?? $hdrs['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';

if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
}

try {
    $decoded = JWT::decode($m[1], new Key($configJwt['secret'], 'HS256'));
    $user_id = (int)($decoded->data->id_usuario ?? 0);
    if ($user_id <= 0) {
        $user_id = (int)($decoded->data->moodle_userid ?? 0);
    }
    if ($user_id <= 0) {
        http_response_code(401);
        exit(json_encode(['status' => 'error', 'msg' => 'Usuario no válido']));
    }
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Token inválido']));
}

// ── IDs de cursos de Retos Diarios ──
$daily_course_ids = [56, 57, 58, 59, 60]; // Matemáticas, Sociales, Inglés, Naturales, Lectura
$today = date('Y-m-d');
$now = time();

try {
    // ── 1. Obtener el moodle_id y moodle_token del usuario ──
    $stmt = $conexion->prepare("
        SELECT moodle_id, moodle_token
        FROM usuarios
        WHERE id_usuario = ?
    ");
    $stmt->execute([$user_id]);
    $userRow = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$userRow || empty($userRow['moodle_id'])) {
        http_response_code(404);
        exit(json_encode(['status' => 'error', 'msg' => 'Usuario no tiene Moodle asociado']));
    }

    $moodleUserId = (int)$userRow['moodle_id'];
    $moodleToken = $userRow['moodle_token'] ?? '';

    // ── 2. Obtener los cuestionarios de cada curso vía Moodle WS ──
    $client = getMoodleClient();
    $allQuizzes = [];

    foreach ($daily_course_ids as $courseId) {
        try {
            // Usar el token del usuario si está disponible, sino el del servicio
            $tokenToUse = !empty($moodleToken) ? $moodleToken : MOODLE_WS_TOKEN;

            $quizzes = $client->request(
                $tokenToUse,
                'mod_quiz_get_quizzes_by_courses',
                ['courseids' => [$courseId]]
            );

            if (isset($quizzes['quizzes'])) {
                foreach ($quizzes['quizzes'] as $quiz) {
                    $allQuizzes[] = $quiz;
                }
            }
        } catch (Exception $e) {
            error_log("[DAILY_CHALLENGES] Error obteniendo quizzes del curso $courseId: " . $e->getMessage());
        }
    }

    // ── 3. Filtrar quizzes disponibles hoy (ventana de tiempo) ──
    $available = [];
    $completed = [];
    $pending = [];

    foreach ($allQuizzes as $quiz) {
        $timeopen = (int)($quiz['timeopen'] ?? 0);
        $timeclose = (int)($quiz['timeclose'] ?? 0);

        // Verificar si el quiz está disponible ahora
        $isOpen = true;
        if ($timeopen > 0 && $now < $timeopen) {
            $isOpen = false; // Aún no abre
        }
        if ($timeclose > 0 && $now > $timeclose) {
            $isOpen = false; // Ya cerró
        }

        if (!$isOpen) continue;

        // Determinar el área/materia basada en el curso
        $courseId = (int)($quiz['course'] ?? 0);
        $area = _getAreaName($courseId);
        $areaColor = _getAreaColor($courseId);
        $areaIcon = _getAreaIcon($courseId);

        $challenge = [
            'id' => (int)$quiz['id'],
            'name' => $quiz['name'] ?? 'Reto Diario',
            'course_id' => $courseId,
            'area' => $area,
            'area_color' => $areaColor,
            'area_icon' => $areaIcon,
            'timeopen' => $timeopen,
            'timeclose' => $timeclose,
            'timelimit' => (int)($quiz['timelimit'] ?? 0),
            'questions' => (int)($quiz['questions'] ?? 0),
        ];

        // ── 4. Verificar si el usuario ya completó este quiz hoy ──
        $isCompleted = _isQuizCompletedToday($conexion, $user_id, $challenge['id'], $today);

        if ($isCompleted) {
            $challenge['completed_at'] = $isCompleted;
            $completed[] = $challenge;
        } else {
            $available[] = $challenge;
            $pending[] = $challenge;
        }
    }

    // ── 5. Respuesta ──
    $totalAvailable = count($available);
    $totalCompleted = count($completed);
    $allCompleted = $totalAvailable === 0 && $totalCompleted > 0;

    echo json_encode([
        'status' => 'ok',
        'data' => [
            'date' => $today,
            'available' => $available,
            'completed' => $completed,
            'pending' => $pending,
            'total_available' => $totalAvailable,
            'total_completed' => $totalCompleted,
            'all_completed' => $allCompleted,
            'total_challenges' => $totalAvailable + $totalCompleted,
        ],
    ], JSON_UNESCAPED_UNICODE);

} catch (Throwable $e) {
    error_log("[DAILY_CHALLENGES] Error: " . $e->getMessage());
    http_response_code(500);
    exit(json_encode([
        'status' => 'error',
        'msg' => 'Error obteniendo retos diarios',
        'debug' => $e->getMessage(),
    ]));
}


// =============================================================
// FUNCIONES HELPER
// =============================================================

/**
 * Verifica si un usuario completó un quiz hoy.
 * Busca en simulacro_resultados o en una tabla de intentos.
 */
function _isQuizCompletedToday(PDO $conexion, int $userId, int $quizId, string $today): ?string {
    // Primero buscar en la tabla de intentos de Moodle (si existe)
    try {
        $stmt = $conexion->prepare("
            SELECT DATE_FORMAT(timefinish, '%Y-%m-%d %H:%i:%s') as completed_at
            FROM quiz_attempts
            WHERE userid = (SELECT moodle_id FROM usuarios WHERE id_usuario = ?)
              AND quiz = ?
              AND state = 'finished'
              AND DATE(timefinish) = ?
            ORDER BY timefinish DESC
            LIMIT 1
        ");
        $stmt->execute([$userId, $quizId, $today]);
        $result = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($result) {
            return $result['completed_at'];
        }
    } catch (Exception $e) {
        // La tabla quiz_attempts podría no existir o no tener datos
        // Fallback: buscar en simulacro_resultados
    }

    // Fallback: buscar en user_daily_activity si hay registro de actividad
    try {
        $stmt = $conexion->prepare("
            SELECT 1
            FROM user_daily_activity
            WHERE user_id = ? AND activity_date = ? AND retos_completed > 0
            LIMIT 1
        ");
        $stmt->execute([$userId, $today]);
        if ($stmt->fetch()) {
            return $today . ' 00:00:00'; // Aproximación
        }
    } catch (Exception $e) {
        // Ignorar
    }

    return null;
}

/**
 * Retorna el nombre del área basado en el course_id.
 */
function _getAreaName(int $courseId): string {
    $map = [
        56 => 'Matemáticas',
        57 => 'Sociales y Ciudadanas',
        58 => 'Inglés',
        59 => 'Ciencias Naturales',
        60 => 'Lectura Crítica',
    ];
    return $map[$courseId] ?? 'Reto Diario';
}

/**
 * Retorna el color del área en hex.
 */
function _getAreaColor(int $courseId): string {
    $map = [
        56 => '#2563EB', // Azul - Matemáticas
        57 => '#8B5CF6', // Púrpura - Sociales
        58 => '#0EA5E9', // Sky - Inglés
        59 => '#F97316', // Naranja - Naturales
        60 => '#22C55E', // Verde - Lectura
    ];
    return $map[$courseId] ?? '#1E4ED8';
}

/**
 * Retorna el nombre del icono Material para el área.
 */
function _getAreaIcon(int $courseId): string {
    $map = [
        56 => 'calculate_rounded',
        57 => 'public_rounded',
        58 => 'translate_rounded',
        59 => 'science_rounded',
        60 => 'menu_book_rounded',
    ];
    return $map[$courseId] ?? 'extension_rounded';
}
