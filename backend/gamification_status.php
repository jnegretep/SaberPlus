<?php
declare(strict_types=1);

/**
 * gamification_status.php - Saber+ Gamification API
 *
 * Devuelve el estado completo de gamificación del usuario autenticado:
 * - XP total, nivel actual, XP para subir de nivel
 * - Racha actual y racha máxima
 * - Badges desbloqueados y bloqueados (con progreso)
 * - Estadísticas de hoy (simulacros, retos, XP ganada)
 *
 * Response:
 * {
 *   "status": "ok",
 *   "data": {
 *     "xp": { "total": 1250, "level": 4, "next_level_xp": 1600, "current_level_xp": 900, "progress_pct": 70 },
 *     "streak": { "current": 5, "max": 12, "freeze_available": 1, "last_activity": "2026-08-13" },
 *     "badges": { "unlocked": [...], "locked": [...], "total_count": 17, "unlocked_count": 5 },
 *     "today": { "simulacros": 1, "retos": 0, "xp_earned": 150 }
 *   }
 * }
 */

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/auth_middleware.php';

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

if ($_SERVER['REQUEST_METHOD'] !== 'POST' && $_SERVER['REQUEST_METHOD'] !== 'GET') {
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

error_log("[GAMIFICATION_STATUS] Usuario autenticado: ID=" . $user_id);

try {
    // ── 1. Asegurar que el usuario tiene registro en user_gamification ──
    $conexion->prepare(
        "INSERT IGNORE INTO user_gamification (user_id) VALUES (?)"
    )->execute([$user_id]);

    // ── 2. Recalcular racha antes de devolver el estado ──
    _recalculateStreak($conexion, $user_id);

    // ── 3. Obtener estado de gamificación ──
    $stmt = $conexion->prepare("
        SELECT total_xp, current_level, current_streak, max_streak,
               last_activity_date, streak_freeze_count, badges_count
        FROM user_gamification
        WHERE user_id = ?
    ");
    $stmt->execute([$user_id]);
    $gamif = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$gamif) {
        // debería existir por el INSERT IGNORE de arriba, pero por si acaso
        $gamif = [
            'total_xp' => 0, 'current_level' => 1, 'current_streak' => 0,
            'max_streak' => 0, 'last_activity_date' => null,
            'streak_freeze_count' => 0, 'badges_count' => 0
        ];
    }

    $total_xp = (int)$gamif['total_xp'];
    $current_level = (int)$gamif['current_level'];
    $current_streak = (int)$gamif['current_streak'];
    $max_streak = (int)$gamif['max_streak'];

    // Recalcular nivel (por si cambió la fórmula)
    $calculated_level = _levelFromXp($total_xp);
    if ($calculated_level !== $current_level) {
        $conexion->prepare("UPDATE user_gamification SET current_level = ? WHERE user_id = ?")
                 ->execute([$calculated_level, $user_id]);
        $current_level = $calculated_level;
    }

    // XP necesaria para nivel actual y siguiente
    $current_level_xp = _xpForLevel($current_level);
    $next_level_xp = _xpForLevel($current_level + 1);
    $progress_pct = $next_level_xp > $current_level_xp
        ? round(($total_xp - $current_level_xp) / ($next_level_xp - $current_level_xp) * 100, 1)
        : 100;

    // ── 4. Badges desbloqueados ──
    $stmt = $conexion->prepare("
        SELECT b.id, b.code, b.name, b.description, b.icon, b.color,
               b.xp_reward, b.category, b.requirement_type, b.requirement_value,
               ub.unlocked_at
        FROM user_badges ub
        JOIN badges b ON ub.badge_id = b.id
        WHERE ub.user_id = ?
        ORDER BY ub.unlocked_at DESC
    ");
    $stmt->execute([$user_id]);
    $unlocked_badges = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // ── 5. Badges bloqueados (con progreso) ──
    $stmt = $conexion->prepare("
        SELECT id, code, name, description, icon, color, xp_reward, category,
               requirement_type, requirement_value, is_hidden, sort_order
        FROM badges
        WHERE id NOT IN (SELECT badge_id FROM user_badges WHERE user_id = ?)
        ORDER BY sort_order ASC, id ASC
    ");
    $stmt->execute([$user_id]);
    $locked_badges_raw = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Calcular progreso de cada badge bloqueado
    $locked_badges = [];
    foreach ($locked_badges_raw as $b) {
        // Ocultar badges secretos (mostrar solo su existencia, no detalles)
        if ((int)$b['is_hidden'] === 1) {
            $locked_badges[] = [
                'id' => (int)$b['id'],
                'code' => $b['code'],
                'name' => '???',
                'description' => 'Sigue estudiando para descubrir este logro',
                'icon' => 'lock',
                'color' => '#9CA3AF',
                'category' => $b['category'],
                'is_hidden' => true,
                'progress' => 0,
                'progress_target' => 1,
            ];
            continue;
        }

        $progress = _calculateBadgeProgress(
            $conexion, $user_id, $b['requirement_type'], (int)$b['requirement_value']
        );

        $locked_badges[] = [
            'id' => (int)$b['id'],
            'code' => $b['code'],
            'name' => $b['name'],
            'description' => $b['description'],
            'icon' => $b['icon'],
            'color' => $b['color'],
            'xp_reward' => (int)$b['xp_reward'],
            'category' => $b['category'],
            'is_hidden' => false,
            'progress' => $progress['current'],
            'progress_target' => $progress['target'],
            'progress_pct' => $progress['pct'],
        ];
    }

    // ── 6. Actividad de hoy ──
    $today = date('Y-m-d');
    $stmt = $conexion->prepare("
        SELECT simulacros_completed, retos_completed, cursos_accessed,
               questions_answered, xp_earned
        FROM user_daily_activity
        WHERE user_id = ? AND activity_date = ?
    ");
    $stmt->execute([$user_id, $today]);
    $today_data = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$today_data) {
        $today_data = [
            'simulacros_completed' => 0, 'retos_completed' => 0,
            'cursos_accessed' => 0, 'questions_answered' => 0, 'xp_earned' => 0
        ];
    }

    // ── 7. Construir respuesta ──
    echo json_encode([
        'status' => 'ok',
        'data' => [
            'xp' => [
                'total' => $total_xp,
                'level' => $current_level,
                'current_level_xp' => $current_level_xp,
                'next_level_xp' => $next_level_xp,
                'progress_pct' => min(100, max(0, $progress_pct)),
                'xp_to_next_level' => max(0, $next_level_xp - $total_xp),
            ],
            'streak' => [
                'current' => $current_streak,
                'max' => $max_streak,
                'freeze_available' => (int)$gamif['streak_freeze_count'],
                'last_activity' => $gamif['last_activity_date'],
            ],
            'badges' => [
                'unlocked' => array_map(function($b) {
                    return [
                        'id' => (int)$b['id'],
                        'code' => $b['code'],
                        'name' => $b['name'],
                        'description' => $b['description'],
                        'icon' => $b['icon'],
                        'color' => $b['color'],
                        'xp_reward' => (int)$b['xp_reward'],
                        'category' => $b['category'],
                        'unlocked_at' => $b['unlocked_at'],
                    ];
                }, $unlocked_badges),
                'locked' => $locked_badges,
                'total_count' => count($unlocked_badges) + count($locked_badges),
                'unlocked_count' => count($unlocked_badges),
            ],
            'today' => [
                'simulacros' => (int)$today_data['simulacros_completed'],
                'retos' => (int)$today_data['retos_completed'],
                'cursos' => (int)$today_data['cursos_accessed'],
                'questions_answered' => (int)$today_data['questions_answered'],
                'xp_earned' => (int)$today_data['xp_earned'],
            ],
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
    $debugUserId = isset($userId) ? $userId : 'NO_DEFINIDO';

    // Construimos un mensaje muy claro para Apache/PHP
    $logMessage =
        "\n\n"
        . "============================================================\n"
        . "[GAMIFICATION_STATUS] ERROR HTTP 500\n"
        . "============================================================\n"
        . "FECHA/HORA : " . date('Y-m-d H:i:s') . "\n"
        . "MÉTODO     : " . $requestMethod . "\n"
        . "URI        : " . $requestUri . "\n"
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
        'status' => 'error',
        'message' => 'Error interno en gamification_status.php',
        'error' => $errorMessage,
        'file' => basename($errorFile),
        'line' => $errorLine,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

    exit;
}


// =============================================================
// FUNCIONES HELPER
// =============================================================

/**
 * Calcula el nivel basado en XP.
 * Fórmula: nivel = floor(sqrt(xp / 100)) + 1
 */
function _levelFromXp(int $xp): int {
    if ($xp < 0) return 1;
    return (int)floor(sqrt($xp / 100.0)) + 1;
}

/**
 * XP necesaria para alcanzar un nivel.
 * Inversa: xp = (nivel - 1)^2 * 100
 */
function _xpForLevel(int $level): int {
    if ($level < 1) return 0;
    return pow($level - 1, 2) * 100;
}

/**
 * Recalcula la racha del usuario basándose en la última actividad.
 *
 * Reglas:
 * - Si last_activity_date es hoy → racha se mantiene
 * - Si last_activity_date fue ayer → racha se mantiene (hasta que haga actividad hoy)
 * - Si last_activity_date fue antes de ayer y no hay freeze → racha = 0
 * - Si tiene freeze disponible y el gap es de 1 día → consume un freeze, racha se mantiene
 */
function _recalculateStreak(PDO $conexion, int $user_id): void {
    $stmt = $conexion->prepare("
        SELECT current_streak, max_streak, last_activity_date, streak_freeze_count
        FROM user_gamification WHERE user_id = ?
    ");
    $stmt->execute([$user_id]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row || !$row['last_activity_date']) {
        return; // sin actividad previa, no hay nada que recalcular
    }

    $today = new DateTime('today');
    $last = new DateTime($row['last_activity_date']);
    $diff = $today->diff($last);
    $days_diff = (int)$diff->days;

    // Si la última actividad fue hoy, no hacer nada
    if ($days_diff === 0) return;

    // Si fue ayer, no hacer nada todavía (la racha se mantiene pero no incrementa
    // hasta que el usuario haga actividad hoy)
    if ($days_diff === 1) return;

    // Gap de 2+ días: ¿tiene freeze disponible?
    $freeze = (int)$row['streak_freeze_count'];
    if ($freeze > 0 && $days_diff === 2) {
        // Consumir un freeze para cubrir 1 día de gap
        $new_freeze = $freeze - 1;
        $conexion->prepare("
            UPDATE user_gamification
            SET streak_freeze_count = ?, last_activity_date = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
            WHERE user_id = ?
        ")->execute([$new_freeze, $user_id]);
        error_log("[STREAK] Usuario $user_id: freeze consumido (quedan $new_freeze)");
        return;
    }

    // Sin freeze o gap muy grande: resetear racha
    if ((int)$row['current_streak'] > 0) {
        $conexion->prepare("
            UPDATE user_gamification SET current_streak = 0 WHERE user_id = ?
        ")->execute([$user_id]);
        error_log("[STREAK] Usuario $user_id: racha reseteada (gap=$days_diff días)");
    }
}

/**
 * Calcula el progreso del usuario hacia un badge específico.
 */
function _calculateBadgeProgress(PDO $conexion, int $user_id, string $type, int $value): array {
    $current = 0;

    switch ($type) {
        case 'simulacros_count':
            $stmt = $conexion->prepare("SELECT COUNT(*) FROM simulacro_resultados WHERE usuario_id = ?");
            $stmt->execute([$user_id]);
            $current = (int)$stmt->fetchColumn();
            break;

        case 'streak_days':
            $stmt = $conexion->prepare("SELECT MAX(current_streak) FROM user_gamification WHERE user_id = ?");
            $stmt->execute([$user_id]);
            $current = (int)$stmt->fetchColumn();
            break;

        case 'max_score':
            $stmt = $conexion->prepare("SELECT MAX(puntaje_global) FROM simulacro_resultados WHERE usuario_id = ?");
            $stmt->execute([$user_id]);
            $current = (int)$stmt->fetchColumn();
            break;

        case 'xp_total':
            $stmt = $conexion->prepare("SELECT total_xp FROM user_gamification WHERE user_id = ?");
            $stmt->execute([$user_id]);
            $current = (int)$stmt->fetchColumn();
            break;

        case 'rank_position':
            // Top N del ranking global por XP
            $stmt = $conexion->prepare("
                SELECT COUNT(*) + 1
                FROM user_gamification
                WHERE total_xp > (SELECT total_xp FROM user_gamification WHERE user_id = ?)
            ");
            $stmt->execute([$user_id]);
            $current = (int)$stmt->fetchColumn();
            // Para rank, "value" es la posición objetivo (ej: top 10), y current es la posición actual
            // El progreso es "mejor que value-posición usuarios"
            break;

        default:
            // Badge con tipo no reconocido: progreso 0
            break;
    }

    $pct = $value > 0 ? min(100, round($current / $value * 100, 1)) : 0;

    return [
        'current' => $current,
        'target' => $value,
        'pct' => $pct,
    ];
}
