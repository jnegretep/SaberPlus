<?php
declare(strict_types=1);

/**
 * gamification_award_xp.php - Saber+ Gamification API
 *
 * Otorga XP al usuario por completar una acción (simulacro, reto, curso, etc.)
 * y verifica si se desbloquearon nuevos badges.
 *
 * Request body (JSON):
 * {
 *   "reason": "simulacro" | "reto" | "curso" | "daily_login" | "streak_bonus",
 *   "xp_amount": 150,                    // opcional, si no se envía se calcula automáticamente
 *   "reference_id": 2,                   // opcional, ID del simulacro/reto/curso
 *   "description": "Completaste Simulacro 1"  // opcional
 * }
 *
 * Response:
 * {
 *   "status": "ok",
 *   "data": {
 *     "xp_awarded": 150,
 *     "total_xp": 1250,
 *     "level": 4,
 *     "leveled_up": false,
 *     "new_level": null,
 *     "new_badges": [ { ...badge }, ... ],
 *     "streak_updated": true,
 *     "current_streak": 5
 *   }
 * }
 */

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/auth_middleware.php';

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
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

error_log("[GAMIFICATION_AWARD_XP] Usuario autenticado: ID=" . $user_id);

// ── Leer input ──
$input = json_decode(file_get_contents('php://input'), true) ?: [];
$reason = trim((string)($input['reason'] ?? ''));
$xp_amount = (int)($input['xp_amount'] ?? 0);
$reference_id = isset($input['reference_id']) ? (int)$input['reference_id'] : null;
$description = trim((string)($input['description'] ?? ''));

if ($reason === '') {
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'reason requerido']));
}

// Razones válidas
$valid_reasons = ['simulacro', 'reto', 'curso', 'daily_login', 'streak_bonus', 'badge_unlock', 'manual'];
if (!in_array($reason, $valid_reasons)) {
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'reason no válido']));
}

error_log("[GAMIFICATION_AWARD_XP] Petición: user_id={$user_id}, reason={$reason}, xp_amount={$xp_amount}, reference_id=" . ($reference_id ?? 'null'));

try {
    // ── 1. Asegurar que existe registro en user_gamification ──
    $conexion->prepare("INSERT IGNORE INTO user_gamification (user_id) VALUES (?)")->execute([$user_id]);

    // ── 2. Calcular XP automático si no se envió explícitamente ──
    if ($xp_amount <= 0) {
        $xp_amount = _calculateAutoXp($reason, $reference_id);
    }
    if ($xp_amount <= 0) {
        // Nada que otorgar
        $current_xp = _getUserXp($conexion, $user_id);
        echo json_encode([
            'status' => 'ok',
            'data' => [
                'xp_awarded' => 0,
                'total_xp' => $current_xp,
                'level' => _levelFromXp($current_xp),
                'leveled_up' => false,
                'new_badges' => [],
                'streak_updated' => false,
            ],
        ]);
        exit;
    }

    // ── 3. Obtener nivel actual antes de otorgar XP ──
    $old_xp = _getUserXp($conexion, $user_id);
    $old_level = _levelFromXp($old_xp);

    // ── 4. Registrar transacción de XP ──
    $stmt = $conexion->prepare("
        INSERT INTO xp_transactions (user_id, xp_amount, reason, reference_id, description)
        VALUES (?, ?, ?, ?, ?)
    ");
    $stmt->execute([$user_id, $xp_amount, $reason, $reference_id, $description ?: null]);

    // ── 5. Actualizar XP total y nivel ──
    $new_xp = $old_xp + $xp_amount;
    $new_level = _levelFromXp($new_xp);
    $leveled_up = $new_level > $old_level;

    $conexion->prepare("
        UPDATE user_gamification SET total_xp = ?, current_level = ? WHERE user_id = ?
    ")->execute([$new_xp, $new_level, $user_id]);

    // ── 6. Actualizar racha diaria ──
    $streak_updated = _updateStreak($conexion, $user_id);

    // ── 7. Actualizar actividad diaria ──
    _updateDailyActivity($conexion, $user_id, $reason, $xp_amount);

    // ── 8. Verificar nuevos badges desbloqueados ──
    $new_badges = _checkAndUnlockBadges($conexion, $user_id, $new_xp, $reason, $reference_id);

    // ── 9. Si se desbloquearon badges, sumar XP bonus ──
    $bonus_xp = 0;
    foreach ($new_badges as $badge) {
        $bonus_xp += $badge['xp_reward'];
    }
    if ($bonus_xp > 0) {
        $conexion->prepare("
            INSERT INTO xp_transactions (user_id, xp_amount, reason, description)
            VALUES (?, ?, 'badge_unlock', ?)
        ")->execute([$user_id, $bonus_xp, "Bonus por desbloquear badges"]);

        $new_xp += $bonus_xp;
        $new_level = _levelFromXp($new_xp);
        $leveled_up = $new_level > $old_level;

        $conexion->prepare("
            UPDATE user_gamification SET total_xp = ?, current_level = ? WHERE user_id = ?
        ")->execute([$new_xp, $new_level, $user_id]);
    }

    // ── 10. Responder ──
    echo json_encode([
        'status' => 'ok',
        'data' => [
            'xp_awarded' => $xp_amount + $bonus_xp,
            'xp_base' => $xp_amount,
            'xp_bonus' => $bonus_xp,
            'total_xp' => $new_xp,
            'level' => $new_level,
            'leveled_up' => $leveled_up,
            'new_level' => $leveled_up ? $new_level : null,
            'old_level' => $old_level,
            'new_badges' => $new_badges,
            'streak_updated' => $streak_updated,
            'current_streak' => _getCurrentStreak($conexion, $user_id),
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
        . "[GAMIFICATION_AWARD_XP] ERROR HTTP 500\n"
        . "============================================================\n"
        . "FECHA/HORA : " . date('Y-m-d H:i:s') . "\n"
        . "MÉTODO     : " . $requestMethod . "\n"
        . "URI        : " . $requestUri . "\n"
        . "USER ID    : " . $debugUserId . "\n"
        . "REASON     : " . (isset($reason) ? $reason : 'NO_DEFINIDO') . "\n"
        . "XP_AMOUNT  : " . (isset($xp_amount) ? $xp_amount : 'NO_DEFINIDO') . "\n"
        . "REFERENCE  : " . (isset($reference_id) ? ($reference_id ?? 'null') : 'NO_DEFINIDO') . "\n"
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
        'message' => 'Error interno en gamification_award_xp.php',
        'error'   => $errorMessage,
        'file'    => basename($errorFile),
        'line'    => $errorLine,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

    exit;
}


// =============================================================
// FUNCIONES HELPER
// =============================================================

function _levelFromXp(int $xp): int {
    if ($xp < 0) return 1;
    return (int)floor(sqrt($xp / 100.0)) + 1;
}

function _getUserXp(PDO $conexion, int $user_id): int {
    $stmt = $conexion->prepare("SELECT total_xp FROM user_gamification WHERE user_id = ?");
    $stmt->execute([$user_id]);
    $xp = $stmt->fetchColumn();
    return $xp !== false ? (int)$xp : 0;
}

function _getCurrentStreak(PDO $conexion, int $user_id): int {
    $stmt = $conexion->prepare("SELECT current_streak FROM user_gamification WHERE user_id = ?");
    $stmt->execute([$user_id]);
    $s = $stmt->fetchColumn();
    return $s !== false ? (int)$s : 0;
}

/**
 * Calcula XP automático según el motivo.
 */
function _calculateAutoXp(string $reason, ?int $reference_id): int {
    switch ($reason) {
        case 'simulacro':
            // XP base por simulacro + bonus por puntaje
            // (el frontend puede enviar xp_amount calculado con el puntaje)
            return 100;

        case 'reto':
            return 50;  // XP base por completar un reto

        case 'curso':
            return 20;  // XP por acceder/completar contenido de curso

        case 'daily_login':
            return 10;  // XP por abrir la app diariamente

        case 'streak_bonus':
            // Bonus por mantener racha (se llama con xp_amount explícito)
            return 0;

        default:
            return 0;
    }
}

/**
 * Actualiza la racha diaria del usuario.
 * Reglas:
 * - Si last_activity_date es hoy → no hacer nada (ya contó)
 * - Si fue ayer → incrementar racha +1
 * - Si fue antes → resetear racha a 1
 * - Actualizar max_streak si current_streak supera el récord
 */
function _updateStreak(PDO $conexion, int $user_id): bool {
    $today = date('Y-m-d');

    $stmt = $conexion->prepare("
        SELECT current_streak, max_streak, last_activity_date
        FROM user_gamification WHERE user_id = ?
    ");
    $stmt->execute([$user_id]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) return false;

    // Si ya actualizó hoy, no hacer nada
    if ($row['last_activity_date'] === $today) {
        return false;
    }

    $current_streak = (int)$row['current_streak'];
    $new_streak = 1;  // por defecto, reiniciar a 1

    if ($row['last_activity_date']) {
        $last = new DateTime($row['last_activity_date']);
        $today_dt = new DateTime($today);
        $diff = $today_dt->diff($last);
        $days_diff = (int)$diff->days;

        if ($days_diff === 1) {
            // Actividad consecutiva: incrementar racha
            $new_streak = $current_streak + 1;
        }
        // Si days_diff === 0 ya se manejó arriba
        // Si days_diff > 1, se resetea a 1
    }

    $new_max = max((int)$row['max_streak'], $new_streak);

    $conexion->prepare("
        UPDATE user_gamification
        SET current_streak = ?, max_streak = ?, last_activity_date = ?
        WHERE user_id = ?
    ")->execute([$new_streak, $new_max, $today, $user_id]);

    error_log("[STREAK] Usuario $user_id: racha actualizada a $new_streak (max=$new_max)");
    return true;
}

/**
 * Actualiza el registro de actividad diaria.
 */
function _updateDailyActivity(PDO $conexion, int $user_id, string $reason, int $xp): void {
    $today = date('Y-m-d');

    // Determinar qué columna incrementar
    // (switch clásico para compatibilidad con PHP 7 — match() es PHP 8.0+)
    $column = null;
    switch ($reason) {
        case 'simulacro':
            $column = 'simulacros_completed';
            break;
        case 'reto':
            $column = 'retos_completed';
            break;
        case 'curso':
            $column = 'cursos_accessed';
            break;
    }

    // Insert or update del registro diario
    if ($column) {
        $sql = "
            INSERT INTO user_daily_activity (user_id, activity_date, {$column}, xp_earned)
            VALUES (?, ?, 1, ?)
            ON DUPLICATE KEY UPDATE {$column} = {$column} + 1, xp_earned = xp_earned + VALUES(xp_earned)
        ";
    } else {
        $sql = "
            INSERT INTO user_daily_activity (user_id, activity_date, xp_earned)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE xp_earned = xp_earned + VALUES(xp_earned)
        ";
    }
    $conexion->prepare($sql)->execute([$user_id, $today, $xp]);
}

/**
 * Verifica todos los badges que el usuario podría haber desbloqueado
 * y los marca como desbloqueados si cumplen los requisitos.
 *
 * Retorna los badges recién desbloqueados (para que el frontend los celebre).
 */
function _checkAndUnlockBadges(PDO $conexion, int $user_id, int $total_xp, string $reason, ?int $reference_id): array {
    // Obtener todos los badges que el usuario NO tiene
    $stmt = $conexion->prepare("
        SELECT b.id, b.code, b.name, b.description, b.icon, b.color,
               b.xp_reward, b.category, b.requirement_type, b.requirement_value
        FROM badges b
        WHERE b.id NOT IN (SELECT badge_id FROM user_badges WHERE user_id = ?)
    ");
    $stmt->execute([$user_id]);
    $candidates = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $unlocked = [];

    foreach ($candidates as $badge) {
        $met = false;

        switch ($badge['requirement_type']) {
            case 'simulacros_count':
                if ($reason === 'simulacro') {
                    $stmt = $conexion->prepare("SELECT COUNT(*) FROM simulacro_resultados WHERE usuario_id = ?");
                    $stmt->execute([$user_id]);
                    $count = (int)$stmt->fetchColumn();
                    $met = $count >= (int)$badge['requirement_value'];
                }
                break;

            case 'streak_days':
                $stmt = $conexion->prepare("SELECT current_streak FROM user_gamification WHERE user_id = ?");
                $stmt->execute([$user_id]);
                $streak = (int)$stmt->fetchColumn();
                $met = $streak >= (int)$badge['requirement_value'];
                break;

            case 'max_score':
                if ($reason === 'simulacro') {
                    $stmt = $conexion->prepare("SELECT MAX(puntaje_global) FROM simulacro_resultados WHERE usuario_id = ?");
                    $stmt->execute([$user_id]);
                    $max_score = (int)$stmt->fetchColumn();
                    $met = $max_score >= (int)$badge['requirement_value'];
                }
                break;

            case 'xp_total':
                $met = $total_xp >= (int)$badge['requirement_value'];
                break;

            case 'rank_position':
                // Verificar posición en el ranking global
                $stmt = $conexion->prepare("
                    SELECT COUNT(*) + 1 as position
                    FROM user_gamification
                    WHERE total_xp > (SELECT total_xp FROM user_gamification WHERE user_id = ?)
                ");
                $stmt->execute([$user_id]);
                $position = (int)$stmt->fetchColumn();
                // Para "top 10": requirement_value = 10, position debe ser <= 10
                $met = $position > 0 && $position <= (int)$badge['requirement_value'];
                break;

            // Otros tipos se verifican en endpoints específicos (no aquí)
        }

        if ($met) {
            // Desbloquear badge
            $conexion->prepare("
                INSERT IGNORE INTO user_badges (user_id, badge_id) VALUES (?, ?)
            ")->execute([$user_id, $badge['id']]);

            // Actualizar contador en user_gamification
            $conexion->prepare("
                UPDATE user_gamification SET badges_count = badges_count + 1 WHERE user_id = ?
            ")->execute([$user_id]);

            $unlocked[] = [
                'id' => (int)$badge['id'],
                'code' => $badge['code'],
                'name' => $badge['name'],
                'description' => $badge['description'],
                'icon' => $badge['icon'],
                'color' => $badge['color'],
                'xp_reward' => (int)$badge['xp_reward'],
                'category' => $badge['category'],
            ];

            error_log("[BADGE] Usuario $user_id desbloqueó: {$badge['code']}");
        }
    }

    return $unlocked;
}
