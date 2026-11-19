<?php
declare(strict_types=1);

/**
 * cron_ia_costs.php — Agregación diaria de costos IA para SABER+ Command Center.
 *
 * Diseñado para ejecutarse una vez al día (00:05 UTC) vía crontab:
 *
 *   5 0 * * *  php /var/www/html/api/prepsaber/backend/cron_ia_costs.php \
 *                  >> /var/log/saberplus/cron_ia_costs.log 2>&1
 *
 * También se puede invocar manualmente desde CLI:
 *
 *   php backend/cron_ia_costs.php
 *
 * Qué hace:
 *   1. Lee la tabla `ia_mensajes` del DÍA ANTERIOR agrupada por `provider`.
 *   2. Calcula: total_requests, total_tokens_prompt, total_tokens_completion,
 *      total_cost_usd, avg_latency_ms, error_count.
 *   3. UPSERT en `ia_costs` con snapshot_date = ayer (UNIQUE date+provider).
 *   4. Loggea el resultado por stdout/stderr y error_log.
 *
 * Seguridad / robustez:
 *   - Idempotente: si se ejecuta dos veces, ON DUPLICATE KEY UPDATE sobrescribe.
 *   - Si la tabla `ia_mensajes` no existe (migración 010 pendiente), sale
 *     silenciosamente con un warning (no rompe nada).
 *   - Lockfile con flock() para evitar concurrencia.
 *   - Solo prepared statements (aunque la fecha se calcula internamente,
 *     no viene de input externo).
 *   - Limpieza de locks obsoletos (>30 min).
 */

require_once __DIR__ . '/includes/conexion.php';
require_once __DIR__ . '/env.php';

// ── Lockfile (anti-concurrencia) con limpieza de obsoletos ──
$lockFile = sys_get_temp_dir() . '/cron_ia_costs.lock';
if (file_exists($lockFile)) {
    $age = time() - filemtime($lockFile);
    if ($age > 1800) { // > 30 min
        @unlink($lockFile);
    }
}
$fp = fopen($lockFile, 'c');
if (!$fp || !flock($fp, LOCK_EX | LOCK_NB)) {
    fwrite(STDERR, '[cron_ia_costs] otra instancia en ejecución, saliendo' . "\n");
    exit(0);
}

/**
 * Helper de logging dual: error_log (para PHP) + stdout/stderr (para CLI).
 */
function ia_cron_log(string $msg, bool $stderr = false): void {
    $line = sprintf('[%s] %s', date('Y-m-d H:i:s'), $msg);
    error_log('[cron_ia_costs] ' . $msg);
    if ($stderr) {
        fwrite(STDERR, $line . "\n");
    } else {
        fwrite(STDOUT, $line . "\n");
    }
}

ia_cron_log('Iniciando agregación diaria de costos IA (pid=' . getmypid() . ')');

// ── 1. Verificar que la tabla ia_mensajes existe ──
try {
    $checkStmt = $conexion->query("SHOW TABLES LIKE 'ia_mensajes'");
    $tablaMensajesExiste = ($checkStmt && $checkStmt->fetchColumn() !== false);

    $checkStmt2 = $conexion->query("SHOW TABLES LIKE 'ia_costs'");
    $tablaCostsExiste = ($checkStmt2 && $checkStmt2->fetchColumn() !== false);
} catch (Throwable $e) {
    ia_cron_log('Error verificando tablas IA: ' . $e->getMessage(), true);
    flock($fp, LOCK_UN);
    fclose($fp);
    exit(1);
}

if (!$tablaMensajesExiste || !$tablaCostsExiste) {
    ia_cron_log(
        'Tablas IA no existen (migración 010 pendiente) — '
        . 'ia_mensajes=' . ($tablaMensajesExiste ? 'OK' : 'FALTA')
        . ', ia_costs=' . ($tablaCostsExiste ? 'OK' : 'FALTA')
        . '. Saliendo.',
        true
    );
    flock($fp, LOCK_UN);
    fclose($fp);
    exit(0);
}

// ── 2. Fecha de ayer (UTC — la BD guarda en +00:00) ──
try {
    $stmtFecha = $conexion->query('SELECT DATE(NOW() - INTERVAL 1 DAY) AS ayer');
    $ayer = (string)$stmtFecha->fetchColumn();
} catch (Throwable $e) {
    // fallback a PHP
    $ayer = date('Y-m-d', strtotime('-1 day'));
}
if (!$ayer) {
    $ayer = date('Y-m-d', strtotime('-1 day'));
}
ia_cron_log('Snapshot date (ayer): ' . $ayer);

// ── 3. Agregar ia_mensajes por provider ──
$sqlAgrega = "SELECT
                COALESCE(NULLIF(provider, ''), 'unknown') AS provider,
                COUNT(*)                                  AS total_requests,
                COALESCE(SUM(prompt_tokens), 0)           AS total_tokens_prompt,
                COALESCE(SUM(completion_tokens), 0)       AS total_tokens_completion,
                COALESCE(SUM(cost_usd), 0)                AS total_cost_usd,
                COALESCE(AVG(latency_ms), 0)              AS avg_latency_ms,
                SUM(CASE WHEN error_code IS NOT NULL THEN 1 ELSE 0 END) AS error_count
              FROM ia_mensajes
              WHERE DATE(created_at) = :ayer
              GROUP BY provider
              ORDER BY total_requests DESC";

try {
    $stmtAgrega = $conexion->prepare($sqlAgrega);
    $stmtAgrega->execute([':ayer' => $ayer]);
    $filas = $stmtAgrega->fetchAll(PDO::FETCH_ASSOC);
} catch (Throwable $e) {
    ia_cron_log('Error consultando ia_mensajes: ' . $e->getMessage(), true);
    flock($fp, LOCK_UN);
    fclose($fp);
    exit(1);
}

if (empty($filas)) {
    ia_cron_log('No hay mensajes IA para la fecha ' . $ayer . '. Nada que agregar.');
    flock($fp, LOCK_UN);
    fclose($fp);
    exit(0);
}

// ── 4. UPSERT en ia_costs ──
// UNIQUE KEY uq_date_provider (snapshot_date, provider) garantiza idempotencia.
$sqlUpsert = "INSERT INTO ia_costs
    (snapshot_date, provider, total_requests, total_tokens_prompt,
     total_tokens_completion, total_cost_usd, avg_latency_ms, error_count)
    VALUES
    (:fecha, :provider, :reqs, :tp, :tc, :cost, :lat, :err)
    ON DUPLICATE KEY UPDATE
        total_requests         = VALUES(total_requests),
        total_tokens_prompt    = VALUES(total_tokens_prompt),
        total_tokens_completion= VALUES(total_tokens_completion),
        total_cost_usd         = VALUES(total_cost_usd),
        avg_latency_ms         = VALUES(avg_latency_ms),
        error_count            = VALUES(error_count)";

$insertados = 0;
$fallidos   = 0;
$totalReqs  = 0;
$totalCost  = 0.0;
$totalErr   = 0;

foreach ($filas as $fila) {
    $provider   = (string)$fila['provider'];
    $reqs       = (int)$fila['total_requests'];
    $tp         = (int)$fila['total_tokens_prompt'];
    $tc         = (int)$fila['total_tokens_completion'];
    $cost       = round((float)$fila['total_cost_usd'], 6);
    $avgLat     = (int)round((float)$fila['avg_latency_ms']);
    $errs       = (int)$fila['error_count'];

    try {
        $stmtIns = $conexion->prepare($sqlUpsert);
        $stmtIns->execute([
            ':fecha'   => $ayer,
            ':provider'=> mb_substr($provider, 0, 50),
            ':reqs'    => $reqs,
            ':tp'      => $tp,
            ':tc'      => $tc,
            ':cost'    => $cost,
            ':lat'     => $avgLat,
            ':err'     => $errs,
        ]);
        $insertados++;
        $totalReqs += $reqs;
        $totalCost += $cost;
        $totalErr  += $errs;

        ia_cron_log(sprintf(
            '  provider=%-12s reqs=%-6d prompt=%-8d compl=%-8d cost=$%-10.6f avg_lat=%-5dms err=%d',
            $provider, $reqs, $tp, $tc, $cost, $avgLat, $errs
        ));
    } catch (Throwable $e) {
        $fallidos++;
        ia_cron_log('Error UPSERT provider=' . $provider . ': ' . $e->getMessage(), true);
    }
}

ia_cron_log(sprintf(
    'OK: %d providers actualizados, %d fallidos | TOTAL reqs=%d cost=$%.4f errores=%d',
    $insertados, $fallidos, $totalReqs, $totalCost, $totalErr
));

flock($fp, LOCK_UN);
fclose($fp);
exit($fallidos > 0 ? 2 : 0);
