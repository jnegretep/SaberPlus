<?php
declare(strict_types=1);

/**
 * smart_notifications.php - Saber+ Notificaciones Inteligentes
 *
 * Este script debe ejecutarse via CRON JOB una vez al dia (ej: 7am).
 * Analiza la actividad de cada usuario y envia notificaciones push
 * personalizadas via FCM.
 *
 * Tipos de notificaciones inteligentes:
 * 1. Inactividad: "Llevas X dias sin practicar"
 * 2. Area debil: "Tu area mas debil es Matematicas, practica mas!"
 * 3. Racha en riesgo: "Tu racha de X dias esta en riesgo, practica hoy!"
 * 4. Nuevo reto diario: "Tienes un nuevo reto diario disponible"
 * 5. Motivacion de ranking: "Subiste X posiciones en el ranking!"
 * 6. Nivel cercano: "Solo te faltan X XP para subir al nivel Y"
 *
 * Uso (cron):
 *   0 7 * * * php /var/www/html/api/prepsaber/backend/smart_notifications.php
 *
 * O via HTTP (con token admin):
 *   curl -X POST https://corpoinstel.edu.co/api/prepsaber/backend/smart_notifications.php
 *
 * Evita spam: maximo 1 notificacion inteligente por usuario por dia.
 */

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/includes/config.php';

use Kreait\Firebase\Factory;
use Kreait\Firebase\Messaging\CloudMessage;
use Kreait\Firebase\Messaging\Notification;

mb_internal_encoding("UTF-8");
$conexion->exec("SET time_zone = '-05:00'"); // Hora Colombia
$conexion->exec("SET NAMES utf8mb4");

error_log("[SMART_NOTIF] Iniciando notificaciones inteligentes...");

// Inicializar Firebase Messaging
try {
    $factory = (new Factory)->withServiceAccount(__DIR__ . '/config/firebase-service-account.json');
    $messaging = $factory->createMessaging();
} catch (Exception $e) {
    error_log("[SMART_NOTIF] Error inicializando Firebase: " . $e->getMessage());
    exit("Error Firebase: " . $e->getMessage());
}

$today = date('Y-m-d');
$sentCount = 0;
$skipCount = 0;

try {
    // Obtener todos los usuarios activos con FCM token
    $stmt = $conexion->prepare("
        SELECT u.id_usuario, u.nombre, u.email, u.fcm_token,
               u.moodle_id, u.tipo_usuario,
               ug.total_xp, ug.current_level, ug.current_streak,
               ug.last_activity_date
        FROM usuarios u
        LEFT JOIN user_gamification ug ON u.id_usuario = ug.user_id
        WHERE u.fcm_token IS NOT NULL
          AND u.fcm_token != ''
          AND u.email_verificado = 1
        ORDER BY u.id_usuario ASC
    ");
    $stmt->execute();
    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);

    error_log("[SMART_NOTIF] Usuarios a analizar: " . count($users));

    foreach ($users as $user) {
        $userId = (int)$user['id_usuario'];
        $fcmToken = $user['fcm_token'];
        $nombre = $user['nombre'] ?: 'estudiante';
        $primerNombre = explode(' ', $nombre)[0];
        $streak = (int)($user['current_streak'] ?? 0);
        $level = (int)($user['current_level'] ?? 1);
        $totalXp = (int)($user['total_xp'] ?? 0);
        $lastActivity = $user['last_activity_date'];

        // Verificar si ya recibio una notificacion inteligente hoy
        $stmtCheck = $conexion->prepare("
            SELECT id FROM notifications
            WHERE user_id = ? AND type = 'smart'
              AND DATE(created_at) = CURDATE()
            LIMIT 1
        ");
        $stmtCheck->execute([$userId]);
        if ($stmtCheck->fetch()) {
            $skipCount++;
            continue; // Ya recibio una hoy
        }

        // Calcular dias de inactividad
        $diasInactivo = 0;
        if ($lastActivity) {
            $last = new DateTime($lastActivity);
            $now = new DateTime($today);
            $diff = $now->diff($last);
            $diasInactivo = (int)$diff->days;
        }

        // Determinar que notificacion enviar (prioridad)
        $notification = null;

        // Prioridad 1: Racha en riesgo (streak >= 3 y inactivo 1 dia)
        if ($streak >= 3 && $diasInactivo >= 1) {
            $notification = [
                'title' => 'Tu racha esta en riesgo!',
                'body' => "$primerNombre, llevas $streak dias de racha. No la pierdas! Practica hoy.",
                'type' => 'streak_risk',
                'data' => ['streak' => $streak, 'action' => 'go_dashboard'],
            ];
        }
        // Prioridad 2: Inactividad prolongada (3+ dias)
        elseif ($diasInactivo >= 3) {
            // Buscar area mas debil
            $areaDebil = _getWeakestArea($conexion, (int)$user['moodle_id']);
            $areaText = $areaDebil ? " Tu area mas debil es $areaDebil." : '';

            $notification = [
                'title' => "Te extrañamos, $primerNombre!",
                'body' => "Llevas $diasInactivo dias sin practicar.$areaText Vuelve a entrenar para el ICFES!",
                'type' => 'inactivity',
                'data' => ['days_inactive' => $diasInactivo, 'action' => 'go_dashboard'],
            ];
        }
        // Prioridad 3: Nuevo reto diario disponible (si no ha hecho reto hoy)
        elseif ($diasInactivo == 0 || $diasInactivo <= 1) {
            // Verificar si ya completo el reto diario de hoy
            $retoCompletado = _checkDailyChallengeCompleted($conexion, (int)$user['moodle_id'], $today);

            if (!$retoCompletado) {
                $notification = [
                    'title' => 'Nuevo reto diario disponible!',
                    'body' => "$primerNombre, tienes retos diarios esperando. Completalos y gana 50 XP por cada uno!",
                    'type' => 'daily_challenge',
                    'data' => ['action' => 'go_daily_challenges'],
                ];
            }
        }

        // Prioridad 4: Nivel cercano (si falta poco para subir de nivel)
        if ($notification === null && $totalXp > 0) {
            $xpParaSubir = _xpForLevel($level + 1) - $totalXp;
            if ($xpParaSubir > 0 && $xpParaSubir <= 50) {
                $notification = [
                    'title' => 'Casi subes de nivel!',
                    'body' => "Solo te faltan $xpParaSubir XP para subir al nivel " . ($level + 1) . ". Practica un poco mas!",
                    'type' => 'level_near',
                    'data' => ['xp_needed' => $xpParaSubir, 'next_level' => $level + 1, 'action' => 'go_dashboard'],
                ];
            }
        }

        // Prioridad 5: Motivacion general (1 vez por semana para usuarios activos)
        if ($notification === null && $diasInactivo == 0) {
            // Solo los lunes
            if (date('N') == 1) {
                $notification = [
                    'title' => 'Comienza la semana con todo!',
                    'body' => "$primerNombre, nuevo reto diario te espera. mantén tu racha de $streak dias!",
                    'type' => 'weekly_motivation',
                    'data' => ['action' => 'go_daily_challenges'],
                ];
            }
        }

        // Enviar notificacion si hay una
        if ($notification !== null) {
            $sent = _sendSmartNotification(
                $messaging,
                $conexion,
                $userId,
                $fcmToken,
                $notification['title'],
                $notification['body'],
                $notification['type'],
                $notification['data']
            );

            if ($sent) {
                $sentCount++;
            }
        }

        // Pequena pausa para no saturar FCM
        usleep(100000); // 100ms
    }

    error_log("[SMART_NOTIF] Completado. Enviadas: $sentCount, Omitidas: $skipCount");

    // Solo imprimir si se ejecuta via HTTP (no cron)
    if (php_sapi_name() !== 'cli') {
        header('Content-Type: application/json');
        echo json_encode([
            'status' => 'ok',
            'sent' => $sentCount,
            'skipped' => $skipCount,
            'total_users' => count($users),
        ]);
    }

} catch (Throwable $e) {
    error_log("[SMART_NOTIF] Error: " . $e->getMessage());
    if (php_sapi_name() !== 'cli') {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'msg' => $e->getMessage()]);
    }
}


// =============================================================
// FUNCIONES HELPER
// =============================================================

/**
 * Envia una notificacion push via FCM y la guarda en la BD.
 */
function _sendSmartNotification(
    $messaging,
    $conexion,
    int $userId,
    string $fcmToken,
    string $title,
    string $body,
    string $type,
    array $data
): bool {
    try {
        // Construir mensaje FCM
        $message = CloudMessage::withTarget('token', $fcmToken)
            ->withNotification(Notification::create($title, $body))
            ->withData([
                'type' => 'smart',
                'smart_type' => $type,
                'title' => $title,
                'body' => $body,
                'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                ...$data,
            ]);

        $messaging->send($message);

        // Guardar en la BD
        $stmt = $conexion->prepare("
            INSERT INTO notifications (user_id, type, title, body, data, created_at)
            VALUES (?, 'smart', ?, ?, ?, NOW())
        ");
        $stmt->execute([
            $userId,
            $title,
            $body,
            json_encode($data, JSON_UNESCAPED_UNICODE),
        ]);

        error_log("[SMART_NOTIF] Enviada a usuario $userId: $title");
        return true;
    } catch (Exception $e) {
        error_log("[SMART_NOTIF] Error enviando a usuario $userId: " . $e->getMessage());
        return false;
    }
}

/**
 * Obtiene el area mas debil del usuario basado en simulacros.
 */
function _getWeakestArea(PDO $conexion, int $moodleId): ?string {
    try {
        $stmt = $conexion->prepare("
            SELECT
                AVG(lectura_puntaje) as lectura,
                AVG(matematicas_puntaje) as matematicas,
                AVG(sociales_puntaje) as sociales,
                AVG(naturales_puntaje) as naturales,
                AVG(ingles_puntaje) as ingles
            FROM simulacro_resultados
            WHERE usuario_id = ?
        ");
        $stmt->execute([$moodleId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$row) return null;

        $areas = [
            'Lectura Critica' => (float)($row['lectura'] ?? 0),
            'Matematicas' => (float)($row['matematicas'] ?? 0),
            'Sociales' => (float)($row['sociales'] ?? 0),
            'Naturales' => (float)($row['naturales'] ?? 0),
            'Ingles' => (float)($row['ingles'] ?? 0),
        ];

        // Filtrar areas con datos (> 0)
        $validAreas = array_filter($areas, fn($v) => $v > 0);
        if (empty($validAreas)) return null;

        // Retornar el area con menor promedio
        asort($validAreas);
        return array_key_first($validAreas);
    } catch (Exception $e) {
        return null;
    }
}

/**
 * Verifica si el usuario ya completo un reto diario hoy.
 */
function _checkDailyChallengeCompleted(PDO $conexion, int $moodleId, string $today): bool {
    try {
        $stmt = $conexion->prepare("
            SELECT COUNT(*) as count
            FROM quiz_attempts
            WHERE userid = ?
              AND state = 'finished'
              AND DATE(timefinish) = ?
        ");
        $stmt->execute([$moodleId, $today]);
        $result = $stmt->fetch(PDO::FETCH_ASSOC);
        return (int)($result['count'] ?? 0) > 0;
    } catch (Exception $e) {
        return false;
    }
}

/**
 * XP necesaria para alcanzar un nivel.
 */
function _xpForLevel(int $level): int {
    if ($level < 1) return 0;
    return ($level - 1) * ($level - 1) * 100;
}
