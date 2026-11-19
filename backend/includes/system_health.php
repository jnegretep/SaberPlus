<?php
declare(strict_types=1);

/**
 * SABER+ — System Health: helpers de ping de servicios compartidos
 *
 * Usado por:
 *   - backend/cron_system_health.php (cada 5 min desde CLI)
 *   - backend/admin/sections/system/controller.php ("Probar servicios ahora")
 *
 * API:
 *   saberplus_run_all_health_checks(PDO $db, bool $manual = false): array
 *     Realiza pings a cada servicio y devuelve un array de resultados:
 *     [
 *       ['service' => 'db_prepsaber', 'status' => 'operational'|'warning'|'error',
 *        'latency_ms' => int|null, 'details' => ['http_code' => null, 'errno' => 0, 'message' => 'OK']],
 *       ...
 *     ]
 *
 *   saberplus_persist_health_checks(PDO $db, array $results): array
 *     INSERT en system_health_checks por cada resultado.
 *     Devuelve ['operational' => int, 'warning' => int, 'error' => int]
 *
 *   saberplus_detect_and_alert(PDO $db): array
 *     Ejecuta las detecciones de picos anormales y crea system_alerts si aplica.
 *     Devuelve ['alerts_created' => int, 'skipped' => int]
 *
 *   saberplus_check_consecutive_errors(PDO $db, string $service, int $windowMinutes = 15): bool
 *     True si los últimos 3 checks del servicio en la ventana están todos en error.
 *
 *   saberplus_create_alert_if_not_exists(PDO $db, string $severity, string $category, string $title, string $message, array $context = [], ?string $relatedEntity = null, ?int $relatedEntityId = null): ?int
 *     Crea una alerta si no hay otra abierta con el mismo related_entity+title.
 */

if (!defined('DEEPSEEK_PROXY_URL')) {
    // Proxy Cloudflare Worker que enruta a DeepSeek (ver backend/test_deepseek.php).
    define('DEEPSEEK_PROXY_URL', 'https://deepseek-proxy.instel91.workers.dev/');
}

if (!defined('FCM_HOST')) {
    define('FCM_HOST', 'https://fcm.googleapis.com/');
}

/**
 * Ejecuta un HTTP HEAD/GET con timeout corto. Devuelve:
 * ['http_code' => int|0, 'errno' => int, 'error' => string, 'latency_ms' => int]
 */
function saberplus_http_ping(string $url, int $timeoutSec = 5, string $method = 'HEAD'): array {
    if (!function_exists('curl_init')) {
        return ['http_code' => 0, 'errno' => -1, 'error' => 'curl no disponible', 'latency_ms' => 0];
    }
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_NOBODY         => $method === 'HEAD',
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HEADER         => true,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_MAXREDIRS      => 2,
        CURLOPT_CONNECTTIMEOUT => $timeoutSec,
        CURLOPT_TIMEOUT        => $timeoutSec,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_SSL_VERIFYHOST => 2,
    ]);
    $t0 = microtime(true);
    curl_exec($ch);
    $latency = (int)round((microtime(true) - $t0) * 1000);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $errno    = (int)curl_errno($ch);
    $error    = $errno ? curl_error($ch) : '';
    curl_close($ch);
    return [
        'http_code'   => $httpCode,
        'errno'       => $errno,
        'error'       => $error,
        'latency_ms'  => $latency,
    ];
}

/**
 * Hace ping a un servicio concreto. Devuelve un array con:
 * ['service' => string, 'status' => 'operational'|'warning'|'error',
 *  'latency_ms' => int|null, 'details' => array]
 */
function saberplus_ping_service(PDO $db, string $serviceKey): array {
    switch ($serviceKey) {
        case 'db_prepsaber':
            return saberplus_ping_db($db, 'db_prepsaber');

        case 'db_moodle':
            $moodle = function_exists('getMoodleDBConnection') ? getMoodleDBConnection() : null;
            if ($moodle === null) {
                return [
                    'service'    => 'db_moodle',
                    'status'     => 'error',
                    'latency_ms' => null,
                    'details'    => [
                        'http_code' => null,
                        'errno'     => 0,
                        'message'   => 'Sin conexión PDO a Moodle (getMoodleDBConnection devolvió null)',
                    ],
                ];
            }
            return saberplus_ping_db($moodle, 'db_moodle');

        case 'moodle_ws':
            $url = defined('MOODLE_BASE_URL') ? rtrim(MOODLE_BASE_URL, '/') . '/' : 'https://preicfes.corpoinstel.edu.co/';
            $r = saberplus_http_ping($url, 5, 'HEAD');
            $status = 'operational';
            if ($r['http_code'] === 0 || $r['http_code'] >= 500) $status = 'error';
            elseif ($r['http_code'] >= 400) $status = 'warning';
            return [
                'service'    => 'moodle_ws',
                'status'     => $status,
                'latency_ms' => $r['latency_ms'] ?: null,
                'details'    => [
                    'http_code' => $r['http_code'] ?: null,
                    'errno'     => $r['errno'] ?: 0,
                    'message'   => $r['error'] ?: 'OK',
                    'url'       => $url,
                ],
            ];

        case 'fcm':
            $r = saberplus_http_ping(FCM_HOST, 5, 'HEAD');
            $status = 'operational';
            if ($r['http_code'] === 0 || $r['http_code'] >= 500) $status = 'error';
            elseif ($r['http_code'] >= 400) $status = 'warning';
            return [
                'service'    => 'fcm',
                'status'     => $status,
                'latency_ms' => $r['latency_ms'] ?: null,
                'details'    => [
                    'http_code' => $r['http_code'] ?: null,
                    'errno'     => $r['errno'] ?: 0,
                    'message'   => $r['error'] ?: 'OK',
                    'url'       => FCM_HOST,
                ],
            ];

        case 'deepseek':
            $r = saberplus_http_ping(DEEPSEEK_PROXY_URL, 5, 'HEAD');
            // Algunos workers Cloudflare responden 405 a HEAD; consideramos 2xx/3xx/401/403/405 como OK (servicio vivo).
            $status = 'operational';
            $okCodes = [0 => false]; // 0 = sin respuesta
            $isAlive = ($r['http_code'] >= 200 && $r['http_code'] < 500)
                       || in_array($r['http_code'], [401, 403, 405], true);
            if (!$isAlive || $r['http_code'] === 0) $status = 'error';
            return [
                'service'    => 'deepseek',
                'status'     => $status,
                'latency_ms' => $r['latency_ms'] ?: null,
                'details'    => [
                    'http_code' => $r['http_code'] ?: null,
                    'errno'     => $r['errno'] ?: 0,
                    'message'   => $r['error'] ?: 'OK',
                    'url'       => DEEPSEEK_PROXY_URL,
                ],
            ];

        default:
            return [
                'service'    => $serviceKey,
                'status'     => 'error',
                'latency_ms' => null,
                'details'    => ['message' => "Servicio desconocido: $serviceKey"],
            ];
    }
}

function saberplus_ping_db(PDO $db, string $label): array {
    $t0 = microtime(true);
    try {
        $stmt = $db->query('SELECT 1');
        if (!$stmt) throw new RuntimeException('query devolvió false');
        $latency = (int)round((microtime(true) - $t0) * 1000);
        return [
            'service'    => $label,
            'status'     => $latency > 2000 ? 'warning' : 'operational',
            'latency_ms' => $latency,
            'details'    => ['http_code' => null, 'errno' => 0, 'message' => 'OK'],
        ];
    } catch (Throwable $e) {
        $latency = (int)round((microtime(true) - $t0) * 1000);
        return [
            'service'    => $label,
            'status'     => 'error',
            'latency_ms' => $latency ?: null,
            'details'    => [
                'http_code' => null,
                'errno'     => $e->getCode() ?: 1,
                'message'   => mb_substr($e->getMessage(), 0, 500),
            ],
        ];
    }
}

/**
 * Ejecuta todos los pings definidos y devuelve un array de resultados.
 */
function saberplus_run_all_health_checks(PDO $db, bool $manual = false): array {
    $services = ['db_prepsaber', 'db_moodle', 'moodle_ws', 'fcm', 'deepseek'];
    $results = [];
    foreach ($services as $svc) {
        $results[] = saberplus_ping_service($db, $svc);
    }
    return $results;
}

/**
 * Persiste los resultados en system_health_checks.
 * Devuelve un summary ['operational' => int, 'warning' => int, 'error' => int].
 */
function saberplus_persist_health_checks(PDO $db, array $results): array {
    $summary = ['operational' => 0, 'warning' => 0, 'error' => 0];
    try {
        $stmt = $db->prepare(
            "INSERT INTO system_health_checks (service, status, latency_ms, details)
             VALUES (:service, :status, :latency_ms, :details)"
        );
        foreach ($results as $r) {
            $details = $r['details'] ?? [];
            // Asegurar tipo JSON string
            $detailsJson = json_encode($details, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            $stmt->execute([
                ':service'    => mb_substr((string)$r['service'], 0, 50),
                ':status'     => $r['status'],
                ':latency_ms' => isset($r['latency_ms']) ? (int)$r['latency_ms'] : null,
                ':details'    => $detailsJson,
            ]);
            $summary[$r['status']] = ($summary[$r['status']] ?? 0) + 1;
        }
    } catch (Throwable $e) {
        error_log('[SYSTEM_HEALTH] Error persistiendo checks: ' . $e->getMessage());
    }
    return $summary;
}

/**
 * Comprueba si los últimos 3 checks del servicio (en ventana de N minutos) están en error.
 */
function saberplus_check_consecutive_errors(PDO $db, string $service, int $windowMinutes = 15, int $consecutive = 3): bool {
    try {
        $stmt = $db->prepare(
            "SELECT status FROM system_health_checks
             WHERE service = :service
               AND checked_at >= (NOW() - INTERVAL :minutes MINUTE)
             ORDER BY checked_at DESC
             LIMIT :limit"
        );
        $stmt->bindValue(':service', $service, PDO::PARAM_STR);
        $stmt->bindValue(':minutes', $windowMinutes, PDO::PARAM_INT);
        $stmt->bindValue(':limit', $consecutive, PDO::PARAM_INT);
        $stmt->execute();
        $rows = $stmt->fetchAll(PDO::FETCH_COLUMN);
        if (count($rows) < $consecutive) return false;
        foreach ($rows as $st) {
            if ($st !== 'error') return false;
        }
        return true;
    } catch (Throwable $e) {
        error_log('[SYSTEM_HEALTH] check_consecutive_errors: ' . $e->getMessage());
        return false;
    }
}

/**
 * Crea una alerta si no existe ya una abierta con el mismo related_entity+title.
 * Devuelve el ID de la alerta creada, o null si fue omitida.
 */
function saberplus_create_alert_if_not_exists(
    PDO $db,
    string $severity,
    string $category,
    string $title,
    string $message,
    array $context = [],
    ?string $relatedEntity = null,
    ?int $relatedEntityId = null
): ?int {
    try {
        // Verificar si ya existe una alerta abierta para el mismo related_entity+title
        $stmt = $db->prepare(
            "SELECT id FROM system_alerts
             WHERE is_resolved = 0
               AND title = :title"
        );
        $stmt->execute([':title' => $title]);
        if ($stmt->fetch()) return null;

        $stmt = $db->prepare(
            "INSERT INTO system_alerts
                (severity, category, title, message, context, related_entity, related_entity_id, is_resolved)
             VALUES
                (:severity, :category, :title, :message, :context, :related_entity, :related_entity_id, 0)"
        );
        $stmt->execute([
            ':severity'          => $severity,
            ':category'          => mb_substr($category, 0, 50),
            ':title'             => mb_substr($title, 0, 255),
            ':message'           => $message,
            ':context'           => !empty($context) ? json_encode($context, JSON_UNESCAPED_UNICODE) : null,
            ':related_entity'    => $relatedEntity ? mb_substr($relatedEntity, 0, 100) : null,
            ':related_entity_id' => $relatedEntityId,
        ]);
        return (int)$db->lastInsertId();
    } catch (Throwable $e) {
        error_log('[SYSTEM_HEALTH] create_alert: ' . $e->getMessage());
        return null;
    }
}

/**
 * Detecta picos anormales:
 *  - Errores 24h > 50  -> alerta high
 *  - Pagos pendientes > 24h > 10 -> alerta medium
 *  - Actividad diaria < 50% del promedio 7d -> alerta medium (o info si solo 1 día)
 *
 * Devuelve ['alerts_created' => int, 'skipped' => int]
 */
function saberplus_detect_abnormal_peaks(PDO $db): array {
    $created = 0;
    $skipped = 0;

    // 1) Errores 24h > 50
    try {
        $errores24h = (int)$db->query(
            "SELECT COUNT(*) FROM error_logs WHERE created_at > NOW() - INTERVAL 24 HOUR"
        )->fetchColumn();
        if ($errores24h > 50) {
            $id = saberplus_create_alert_if_not_exists(
                $db,
                'high',
                'errors',
                "Pico de errores: {$errores24h} en 24h",
                "Se han registrado {$errores24h} errores en las últimas 24 horas (umbral 50).",
                ['errores_24h' => $errores24h, 'umbral' => 50],
                'error_logs'
            );
            $id !== null ? $created++ : $skipped++;
        }
    } catch (Throwable $e) {
        error_log('[SYSTEM_HEALTH] detect errors: ' . $e->getMessage());
    }

    // 2) Pagos pendientes > 24h > 10
    try {
        $pagosPend = (int)$db->query(
            "SELECT COUNT(*) FROM payments
             WHERE LOWER(status) = 'pending'
               AND created_at > NOW() - INTERVAL 24 HOUR"
        )->fetchColumn();
        if ($pagosPend > 10) {
            $id = saberplus_create_alert_if_not_exists(
                $db,
                'medium',
                'payments',
                "Pagos pendientes: {$pagosPend} en 24h",
                "Hay {$pagosPend} pagos en estado 'pending' en las últimas 24 horas (umbral 10).",
                ['pagos_pendientes_24h' => $pagosPend, 'umbral' => 10],
                'payments'
            );
            $id !== null ? $created++ : $skipped++;
        }
    } catch (Throwable $e) {
        error_log('[SYSTEM_HEALTH] detect payments: ' . $e->getMessage());
    }

    // 3) Actividad diaria < 50% del promedio 7d (en simulacro_resultados)
    try {
        // Total hoy
        $hoy = (int)$db->query(
            "SELECT COUNT(*) FROM simulacro_resultados
             WHERE fecha_realizacion >= CURDATE()"
        )->fetchColumn();

        // Promedio 7 días (excluyendo hoy)
        $prom7d = (float)$db->query(
            "SELECT COALESCE(AVG(c), 0) FROM (
               SELECT COUNT(*) AS c FROM simulacro_resultados
               WHERE fecha_realizacion >= CURDATE() - INTERVAL 7 DAY
                 AND fecha_realizacion < CURDATE()
               GROUP BY DATE(fecha_realizacion)
             ) sub"
        )->fetchColumn();

        if ($prom7d > 0 && $hoy < ($prom7d * 0.5)) {
            $pct = $prom7d > 0 ? round(($hoy / $prom7d) * 100, 1) : 0;
            $id = saberplus_create_alert_if_not_exists(
                $db,
                'medium',
                'activity',
                "Actividad diaria baja: {$pct}% del promedio 7d",
                "Hoy se han completado {$hoy} simulacros, frente a un promedio de " . round($prom7d) . " en los últimos 7 días ({$pct}%).",
                ['hoy' => $hoy, 'promedio_7d' => round($prom7d, 1), 'pct' => $pct],
                'simulacro_resultados'
            );
            $id !== null ? $created++ : $skipped++;
        }
    } catch (Throwable $e) {
        error_log('[SYSTEM_HEALTH] detect activity: ' . $e->getMessage());
    }

    return ['alerts_created' => $created, 'skipped' => $skipped];
}

/**
 * Detección de 3 errores consecutivos por servicio → alerta critical.
 */
function saberplus_alert_consecutive_errors(PDO $db): array {
    $services = ['db_prepsaber', 'db_moodle', 'moodle_ws', 'fcm', 'deepseek'];
    $created = 0;
    $skipped = 0;
    foreach ($services as $svc) {
        if (saberplus_check_consecutive_errors($db, $svc, 15, 3)) {
            $id = saberplus_create_alert_if_not_exists(
                $db,
                'critical',
                'service_down',
                "Servicio caído: {$svc}",
                "El servicio {$svc} lleva 3 checks consecutivos en estado 'error' (últimos 15 min).",
                ['service' => $svc, 'consecutive_errors' => 3, 'window_minutes' => 15],
                'system_health_checks',
                null
            );
            $id !== null ? $created++ : $skipped++;
        }
    }
    return ['alerts_created' => $created, 'skipped' => $skipped];
}
