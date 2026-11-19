<?php
declare(strict_types=1);

/**
 * SABER+ — Cron de System Health
 *
 * Ejecuta cada 5 minutos desde el sistema de crontab del servidor:
 *   cada 5 min -> php /var/www/html/api/prepsaber/backend/cron_system_health.php >> /var/log/saberplus_cron_health.log 2>&1
 *
 * O manualmente:
 *   php cron_system_health.php
 *
 * Acciones:
 *  1. Ping a cada servicio: BD prepsaber (SELECT 1), BD Moodle (SELECT 1),
 *     Moodle WS (HTTP HEAD 5s), FCM (HTTP HEAD), DeepSeek proxy (HTTP HEAD).
 *  2. INSERT en system_health_checks con service, status, latency_ms, details (JSON).
 *  3. Si un servicio lleva 3 checks consecutivos en error (15 min) -> crear
 *     system_alert severity=critical (si no existe ya una abierta).
 *  4. Detectar picos anormales (errores 24h, pagos pendientes, actividad baja).
 *  5. Loggea resumen a error_log.
 *
 * No requiere sesión admin: es un cron CLI.
 */

require_once __DIR__ . '/includes/conexion.php';
require_once __DIR__ . '/includes/moodle_db.php';
require_once __DIR__ . '/includes/config.php';
require_once __DIR__ . '/includes/system_health.php';

// -- Modo CLI: evitar time limit excesivo --
if (PHP_SAPI === 'cli') {
    @set_time_limit(120);
    @ini_set('display_errors', '1');
    error_reporting(E_ALL);
}

$startTs = microtime(true);
$log = static function (string $msg) {
    $line = '[' . date('Y-m-d H:i:s') . '] [system_health] ' . $msg;
    error_log($line);
    if (PHP_SAPI === 'cli') echo $line . "\n";
};

$log('==== inicio cron_system_health ====');

if (!isset($conexion) || !$conexion instanceof PDO) {
    $log('ERROR: $conexion no disponible (conexion.php falló). Abortando.');
    fwrite(STDERR, "FATAL: no hay conexión a la BD\n");
    exit(1);
}

// 1) Ejecutar todos los pings
$results = saberplus_run_all_health_checks($conexion, false);

// 2) Persistir en system_health_checks
$summary = saberplus_persist_health_checks($conexion, $results);
$log(sprintf(
    'Checks persistidos: %d OK, %d warning, %d error',
    $summary['operational'] ?? 0,
    $summary['warning'] ?? 0,
    $summary['error'] ?? 0
));

// Detalle por servicio
foreach ($results as $r) {
    $det = $r['details'] ?? [];
    $extra = '';
    if (!empty($det['http_code'])) $extra .= " HTTP {$det['http_code']}";
    if (!empty($det['errno']))     $extra .= " errno={$det['errno']}";
    if (!empty($det['message']) && $det['message'] !== 'OK') $extra .= " msg='{$det['message']}'";
    $log(sprintf(
        '  - %-14s %-11s %s%s',
        $r['service'],
        $r['status'],
        isset($r['latency_ms']) ? ($r['latency_ms'] . 'ms') : '—',
        $extra
    ));
}

// 3) Detección de servicios caídos (3 errores consecutivos)
$alertDown = saberplus_alert_consecutive_errors($conexion);
$log(sprintf(
    'Alertas por servicio caído: %d creadas, %d omitidas',
    $alertDown['alerts_created'] ?? 0,
    $alertDown['skipped'] ?? 0
));

// 4) Detección de picos anormales (errores, pagos, actividad)
$peaks = saberplus_detect_abnormal_peaks($conexion);
$log(sprintf(
    'Alertas por picos anormales: %d creadas, %d omitidas',
    $peaks['alerts_created'] ?? 0,
    $peaks['skipped'] ?? 0
));

// 5) Resumen final
$dur = round((microtime(true) - $startTs) * 1000);
$log(sprintf('==== fin cron_system_health (%d ms) ====', $dur));

exit(0);