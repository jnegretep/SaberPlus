<?php
declare(strict_types=1);

/**
 * gamification_ranking.php - Saber+ Gamification Ranking API
 *
 * Devuelve el ranking de usuarios por XP con diferentes períodos:
 * - all_time: ranking histórico por XP total
 * - weekly: XP ganada en los últimos 7 días
 * - monthly: XP ganada en los últimos 30 días
 *
 * Request:
 *   GET /gamification_ranking.php?period=weekly&limit=50
 *   POST con body: { "period": "weekly", "limit": 50 }
 *
 * Response:
 * {
 *   "status": "ok",
 *   "data": {
 *     "period": "weekly",
 *     "user_position": 5,
 *     "total_users": 1234,
 *     "ranking": [
 *       { "position": 1, "user_id": 40, "name": "Juan Pérez", "avatar_path": "...", "xp": 1250, "level": 4 },
 *       ...
 *     ]
 *   }
 * }
 */

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/auth_middleware.php';

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

// ── Usuario autenticado por auth_middleware.php ──
$user_id = (int)($authUser['id_usuario'] ?? 0);

if ($user_id <= 0) {
    $user_id = (int)($authUser['moodle_userid'] ?? 0);
}

if ($user_id <= 0) {
    http_response_code(401);
    exit(json_encode([
        'status' => 'error',
        'msg' => 'Usuario no válido'
    ]));
}

error_log("[GAMIFICATION_RANKING] Usuario autenticado: ID=" . $user_id);

// ── Leer parámetros ──
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $period = $_GET['period'] ?? 'all_time';
    $limit = (int)($_GET['limit'] ?? 50);
} else {
    $input = json_decode(file_get_contents('php://input'), true) ?: [];
    $period = $input['period'] ?? 'all_time';
    $limit = (int)($input['limit'] ?? 50);
}

$valid_periods = ['all_time', 'weekly', 'monthly'];
if (!in_array($period, $valid_periods)) {
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'period no válido (usar: all_time, weekly, monthly)']));
}

// ── IMPORTANTE: sanitizar $limit como int ──
// Lo forzamos a int y lo limitamos al rango [1, 200] para poder inlinerlo
// en el SQL sin riesgo de SQL injection (PDO emulado convierte el placeholder
// LIMIT ? a string '50' y MySQL lo rechaza — conocido bug/limitación).
$limit = max(1, min(200, (int)$limit));

try {
    // ── Construir query según período ──
    if ($period === 'all_time') {
        // Ranking por XP total
        // OJO: $limit ya está sanitizado como int → seguro inlinerlo en el SQL
        $sql = "
            SELECT ug.user_id, u.nombre, u.avatar_path, u.colegio, u.ciudad,
                   ug.total_xp as xp, ug.current_level as level
            FROM user_gamification ug
            JOIN usuarios u ON ug.user_id = u.id_usuario
            WHERE ug.total_xp > 0
            ORDER BY ug.total_xp DESC
            LIMIT {$limit}
        ";
        $stmt = $conexion->prepare($sql);
        $stmt->execute();
        $ranking = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Contar total de usuarios con XP > 0
        $total_users = (int)$conexion->query("SELECT COUNT(*) FROM user_gamification WHERE total_xp > 0")->fetchColumn();

    } else {
        // Ranking por XP ganada en el período (weekly/monthly)
        // $days es un literal int → seguro
        $days = $period === 'weekly' ? 7 : 30;
        $sql = "
            SELECT xt.user_id as user_id,
                   u.nombre, u.avatar_path, u.colegio, u.ciudad,
                   SUM(xt.xp_amount) as xp,
                   FLOOR(SQRT(ug.total_xp / 100.0)) + 1 as level
            FROM xp_transactions xt
            JOIN usuarios u ON xt.user_id = u.id_usuario
            JOIN user_gamification ug ON xt.user_id = ug.user_id
            WHERE xt.created_at >= DATE_SUB(NOW(), INTERVAL {$days} DAY)
              AND xt.xp_amount > 0
            GROUP BY xt.user_id, u.nombre, u.avatar_path, u.colegio, u.ciudad, ug.total_xp
            ORDER BY xp DESC
            LIMIT {$limit}
        ";
        $stmt = $conexion->prepare($sql);
        $stmt->execute();
        $ranking = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Contar usuarios activos en el período
        $stmt = $conexion->prepare("
            SELECT COUNT(DISTINCT user_id)
            FROM xp_transactions
            WHERE created_at >= DATE_SUB(NOW(), INTERVAL {$days} DAY) AND xp_amount > 0
        ");
        $stmt->execute();
        $total_users = (int)$stmt->fetchColumn();
    }

    // ── Procesar ranking: agregar posición y buscar al usuario actual ──
    $user_position = null;
    $processed = [];
    foreach ($ranking as $i => $row) {
        $position = $i + 1;
        $uid = (int)$row['user_id'];

        if ($uid === $user_id) {
            $user_position = $position;
        }

        $processed[] = [
            'position' => $position,
            'user_id' => $uid,
            'name' => $row['nombre'] ?? 'Usuario',
            'avatar_path' => $row['avatar_path'] ?? null,
            'colegio' => $row['colegio'] ?? null,
            'ciudad' => $row['ciudad'] ?? null,
            'xp' => (int)$row['xp'],
            'level' => (int)$row['level'],
            'is_current_user' => $uid === $user_id,
        ];
    }

    // Si el usuario actual no está en el top, buscar su posición real
    if ($user_position === null) {
        if ($period === 'all_time') {
            $stmt = $conexion->prepare("
                SELECT COUNT(*) + 1 as position
                FROM user_gamification
                WHERE total_xp > (SELECT total_xp FROM user_gamification WHERE user_id = ?)
            ");
            $stmt->execute([$user_id]);
            $user_position = (int)$stmt->fetchColumn();
        } else {
            $days = $period === 'weekly' ? 7 : 30;
            $stmt = $conexion->prepare("
                SELECT COUNT(*) + 1 as position
                FROM (
                    SELECT user_id, SUM(xp_amount) as total
                    FROM xp_transactions
                    WHERE created_at >= DATE_SUB(NOW(), INTERVAL {$days} DAY) AND xp_amount > 0
                    GROUP BY user_id
                ) as t
                WHERE t.total > (
                    SELECT COALESCE(SUM(xp_amount), 0)
                    FROM xp_transactions
                    WHERE user_id = ? AND created_at >= DATE_SUB(NOW(), INTERVAL {$days} DAY) AND xp_amount > 0
                )
            ");
            $stmt->execute([$user_id]);
            $user_position = (int)$stmt->fetchColumn();
        }
    }

    echo json_encode([
        'status' => 'ok',
        'data' => [
            'period' => $period,
            'user_position' => $user_position,
            'total_users' => $total_users,
            'ranking' => $processed,
        ],
    ], JSON_UNESCAPED_UNICODE);

} catch (Throwable $e) {

    // ============================================================
    // LOG DETALLADO DEL ERROR 500
    // ============================================================

    $errorMessage = $e->getMessage();
    $errorFile    = $e->getFile();
    $errorLine    = $e->getLine();
    $errorClass   = get_class($e);

    // Información adicional de la petición
    $requestMethod = $_SERVER['REQUEST_METHOD'] ?? 'UNKNOWN';
    $requestUri    = $_SERVER['REQUEST_URI'] ?? 'UNKNOWN';

    // Usuario autenticado, si llegó a identificarse antes del error
    $debugUserId = isset($user_id) ? $user_id : 'NO_DEFINIDO';

    // Construimos un mensaje muy claro para Apache/PHP
    $logMessage =
        "\n\n"
        . "============================================================\n"
        . "[GAMIFICATION_RANKING] ERROR HTTP 500\n"
        . "============================================================\n"
        . "FECHA/HORA : " . date('Y-m-d H:i:s') . "\n"
        . "MÉTODO     : " . $requestMethod . "\n"
        . "URI        : " . $requestUri . "\n"
        . "PERIODO    : " . (isset($period) ? $period : 'NO_DEFINIDO') . "\n"
        . "LIMIT      : " . (isset($limit) ? $limit : 'NO_DEFINIDO') . "\n"
        . "USER ID    : " . $debugUserId . "\n"
        . "TIPO ERROR : " . $errorClass . "\n"
        . "MENSAJE    : " . $errorMessage . "\n"
        . "ARCHIVO    : " . $errorFile . "\n"
        . "LÍNEA      : " . $errorLine . "\n"
        . "============================================================\n";

    // Si existe una excepción anterior, también la mostramos
    if ($e->getPrevious() !== null) {
        $previous = $e->getPrevious();

        $logMessage .=
            "ERROR ANTERIOR:\n"
            . "TIPO       : " . get_class($previous) . "\n"
            . "MENSAJE    : " . $previous->getMessage() . "\n"
            . "ARCHIVO    : " . $previous->getFile() . "\n"
            . "LÍNEA      : " . $previous->getLine() . "\n"
            . "============================================================\n";
    }

    // Stack trace completo
    $logMessage .=
        "STACK TRACE:\n"
        . $e->getTraceAsString() . "\n"
        . "============================================================\n\n";

    // Enviar todo al log de PHP/Apache
    error_log($logMessage);

    // Respuesta HTTP 500
    http_response_code(500);

    header('Content-Type: application/json; charset=utf-8');

    echo json_encode([
        'status'  => 'error',
        'message' => 'Error interno en gamification_ranking.php',
        'error'   => $errorMessage,
        'file'    => basename($errorFile),
        'line'    => $errorLine,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

    exit;
}
