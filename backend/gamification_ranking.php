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
require __DIR__ . '/jwt_config.php';

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
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Token inválido']));
}

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

$limit = max(1, min(200, $limit));  // entre 1 y 200

try {
    // ── Construir query según período ──
    if ($period === 'all_time') {
        // Ranking por XP total
        $sql = "
            SELECT ug.user_id, u.nombre, u.avatar_path, u.colegio, u.ciudad,
                   ug.total_xp as xp, ug.current_level as level
            FROM user_gamification ug
            JOIN usuarios u ON ug.user_id = u.id_usuario
            WHERE ug.total_xp > 0
            ORDER BY ug.total_xp DESC
            LIMIT ?
        ";
        $stmt = $conexion->prepare($sql);
        $stmt->execute([$limit]);
        $ranking = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Contar total de usuarios con XP > 0
        $total_users = (int)$conexion->query("SELECT COUNT(*) FROM user_gamification WHERE total_xp > 0")->fetchColumn();

    } else {
        // Ranking por XP ganada en el período (weekly/monthly)
        $days = $period === 'weekly' ? 7 : 30;
        $sql = "
            SELECT xt.user_id as user_id,
                   u.nombre, u.avatar_path, u.colegio, u.ciudad,
                   SUM(xt.xp_amount) as xp,
                   FLOOR(SQRT(ug.total_xp / 100.0)) + 1 as level
            FROM xp_transactions xt
            JOIN usuarios u ON xt.user_id = u.id_usuario
            JOIN user_gamification ug ON xt.user_id = ug.user_id
            WHERE xt.created_at >= DATE_SUB(NOW(), INTERVAL $days DAY)
              AND xt.xp_amount > 0
            GROUP BY xt.user_id, u.nombre, u.avatar_path, u.colegio, u.ciudad, ug.total_xp
            ORDER BY xp DESC
            LIMIT ?
        ";
        $stmt = $conexion->prepare($sql);
        $stmt->execute([$limit]);
        $ranking = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Contar usuarios activos en el período
        $stmt = $conexion->prepare("
            SELECT COUNT(DISTINCT user_id)
            FROM xp_transactions
            WHERE created_at >= DATE_SUB(NOW(), INTERVAL $days DAY) AND xp_amount > 0
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
                    WHERE created_at >= DATE_SUB(NOW(), INTERVAL $days DAY) AND xp_amount > 0
                    GROUP BY user_id
                ) as t
                WHERE t.total > (
                    SELECT COALESCE(SUM(xp_amount), 0)
                    FROM xp_transactions
                    WHERE user_id = ? AND created_at >= DATE_SUB(NOW(), INTERVAL $days DAY) AND xp_amount > 0
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
    error_log("[RANKING] Error: " . $e->getMessage());
    http_response_code(500);
    exit(json_encode([
        'status' => 'error',
        'msg' => 'Error obteniendo ranking',
        'debug' => $e->getMessage(),
    ]));
}
