<?php
declare(strict_types=1);

/**
 * SPRINT 5 — Centro de Monitoreo IA
 *
 * Dashboard profesional para monitorear el uso, costo y salud del tutor IA
 * Saber+ (DeepSeek vía Cloudflare Worker + Gemini directo).
 *
 * Funcionalidades:
 *   - KPIs: solicitudes 24h/7d/30d, tokens mes, costo USD mes (con COP equivalente
 *     si la env var USD_COP_RATE está configurada), latencia p50/p95/avg/max 24h,
 *     error rate 24h, usuarios únicos 30d.
 *   - Estado de servicios: 3 tarjetas con ping real on-demand (DeepSeek Worker,
 *     Gemini directo, Cloudflare Worker HEAD). Botón "Probar servicios" (POST con
 *     CSRF, requiere permiso 'ia.test'); persiste resultados en system_health_checks.
 *   - Gráficos: serie 14d solicitudes IA (admin_svg_serie), donut tokens prompt
 *     vs completion, top 10 usuarios 30d (admin_svg_bars), distribución por hora
 *     del día (24h), tabla historial errores (últimos 20).
 *   - Vista tabla conversaciones recientes (20): usuario, mensajes, tokens,
 *     costo, última actividad.
 *   - Vista tabla costos diarios (30 días de ia_costs).
 *
 * Robustez:
 *   - require_permission('ia.monitor') al inicio.
 *   - require_permission('ia.test') para el botón "Probar servicios".
 *   - safeScalar / safeRows degradan gracefully si las tablas IA no existen
 *     (migración 010 pendiente) → muestra estado vacío.
 *   - Prepared statements SIEMPRE.
 *   - POST actions auditadas con admin_audit_log().
 */

require_once __DIR__ . '/../../bootstrap.php';
require_once __DIR__ . '/../../includes/layout.php';

require_permission('ia.monitor');

// ───────────────────────────────────────────────────────────────────────────
// Helpers locales
// ───────────────────────────────────────────────────────────────────────────

/** Verifica si las tablas IA principales existen. */
function ia_tablas_existen(PDO $db): bool {
    static $existe = null;
    if ($existe !== null) return $existe;
    try {
        $stmt = $db->query("SHOW TABLES LIKE 'ia_mensajes'");
        $existe = ($stmt && $stmt->fetchColumn() !== false);
    } catch (Throwable $e) {
        $existe = false;
    }
    return $existe;
}

/**
 * Calcula un percentil (0-100) a partir de un array de filas con columna 'latency_ms'.
 * Usa interpolación lineal entre los dos valores vecinos.
 */
function ia_percentil(array $filas, int $p): int {
    if (empty($filas)) return 0;
    $vals = array_map('intval', array_column($filas, 'latency_ms'));
    sort($vals);
    $n = count($vals);
    if ($n === 1) return $vals[0];
    if ($p <= 0)   return $vals[0];
    if ($p >= 100) return $vals[$n - 1];
    $pos  = ($p / 100) * ($n - 1);
    $lo   = (int)floor($pos);
    $hi   = (int)ceil($pos);
    if ($lo === $hi) return $vals[$lo];
    $frac = $pos - $lo;
    return (int)round($vals[$lo] + $frac * ($vals[$hi] - $vals[$lo]));
}

/**
 * Hace un ping real a un servicio (HEAD o POST mínimo) y devuelve el resultado.
 *
 * @return array{status:string,latency_ms:int,details:array}
 *     status ∈ {'operational','warning','error'}
 */
function ia_probar_servicio(
    string $url, string $method = 'HEAD',
    ?array $payload = null, ?array $headers = null, int $timeoutSec = 8
): array {
    if (!function_exists('curl_init')) {
        return [
            'status'     => 'error',
            'latency_ms' => 0,
            'details'    => ['error' => 'extensión curl no disponible en PHP'],
        ];
    }

    $ch = curl_init($url);
    if ($ch === false) {
        return [
            'status'     => 'error',
            'latency_ms' => 0,
            'details'    => ['error' => 'curl_init falló'],
        ];
    }

    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, max(2, intval($timeoutSec / 2)));
    curl_setopt($ch, CURLOPT_TIMEOUT, $timeoutSec);
    if ($method === 'HEAD') {
        curl_setopt($ch, CURLOPT_NOBODY, true);
    } elseif ($method === 'POST' && $payload !== null) {
        curl_setopt($ch, CURLOPT_POST, true);
        $bodyJson = json_encode($payload, JSON_UNESCAPED_UNICODE);
        if ($bodyJson === false) {
            curl_close($ch);
            return [
                'status' => 'error', 'latency_ms' => 0,
                'details' => ['error' => 'json_encode falló: ' . json_last_error_msg()],
            ];
        }
        curl_setopt($ch, CURLOPT_POSTFIELDS, $bodyJson);
    }

    $hdr = ['Content-Type: application/json'];
    if ($headers) $hdr = array_merge($hdr, $headers);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $hdr);

    $t0        = microtime(true);
    $response  = curl_exec($ch);
    $latency   = (int)round((microtime(true) - $t0) * 1000);
    $httpcode  = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $errno     = curl_errno($ch);
    $err       = curl_error($ch);
    curl_close($ch);

    $bodyExcerpt = is_string($response) ? mb_substr($response, 0, 400) : '';

    if ($errno !== 0 || $response === false) {
        return [
            'status'     => 'error',
            'latency_ms' => $latency,
            'details'    => [
                'errno' => $errno, 'error' => $err, 'http' => $httpcode,
                'body_excerpt' => $bodyExcerpt,
            ],
        ];
    }

    if ($httpcode >= 500) {
        return [
            'status'     => 'error',
            'latency_ms' => $latency,
            'details'    => ['http' => $httpcode, 'body_excerpt' => $bodyExcerpt],
        ];
    }
    if ($httpcode >= 400 || $httpcode === 0) {
        return [
            'status'     => 'warning',
            'latency_ms' => $latency,
            'details'    => ['http' => $httpcode, 'body_excerpt' => $bodyExcerpt],
        ];
    }

    return [
        'status'     => 'operational',
        'latency_ms' => $latency,
        'details'    => ['http' => $httpcode, 'body_excerpt' => $bodyExcerpt],
    ];
}

/** Ejecuta los pings a los 3 servicios IA y devuelve los resultados. */
function ia_ejecutar_pruebas_servicios(): array {
    $workerUrl = 'https://deepseek-proxy.instel91.workers.dev/';
    $geminiUrl = 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions';
    $geminiKey = (string)env('GEMINI_API_KEY', '');

    $resultados = [];

    // 1. DeepSeek a través del Cloudflare Worker (POST mínimo, max_tokens 5)
    $payloadDs = [
        'model'      => 'deepseek-chat',
        'messages'   => [['role' => 'user', 'content' => 'ping']],
        'max_tokens' => 5,
    ];
    $resultados['deepseek_worker'] = ia_probar_servicio(
        $workerUrl, 'POST', $payloadDs, [], 10
    );
    $resultados['deepseek_worker']['label'] = 'DeepSeek (vía Cloudflare Worker)';

    // 2. Gemini directo (POST con Authorization Bearer)
    if ($geminiKey !== '') {
        $payloadGem = [
            'model'      => env('GEMINI_MODEL', 'gemini-2.0-flash'),
            'messages'   => [['role' => 'user', 'content' => 'ping']],
            'max_tokens' => 5,
        ];
        $resultados['gemini'] = ia_probar_servicio(
            $geminiUrl, 'POST', $payloadGem,
            ['Authorization: Bearer ' . $geminiKey], 10
        );
    } else {
        $resultados['gemini'] = [
            'status'     => 'warning',
            'latency_ms' => 0,
            'details'    => ['error' => 'GEMINI_API_KEY no configurada en .env'],
        ];
    }
    $resultados['gemini']['label'] = 'Gemini directo';

    // 3. Cloudflare Worker — HEAD (solo conectividad, sin costo de API)
    $resultados['cf_worker'] = ia_probar_servicio($workerUrl, 'HEAD', null, [], 6);
    $resultados['cf_worker']['label'] = 'Proxy Cloudflare Worker (HEAD)';

    return $resultados;
}

/** Persiste un resultado de health check en system_health_checks. */
function ia_guardar_health_check(PDO $db, string $service, array $r): void {
    try {
        $stmt = $db->prepare(
            "INSERT INTO system_health_checks
                (service, status, latency_ms, details, checked_at)
             VALUES (:svc, :st, :lat, :det, NOW())"
        );
        $stmt->execute([
            ':svc' => mb_substr($service, 0, 50),
            ':st'  => $r['status'],
            ':lat' => isset($r['latency_ms']) ? (int)$r['latency_ms'] : null,
            ':det' => json_encode($r['details'] ?? [], JSON_UNESCAPED_UNICODE),
        ]);
    } catch (Throwable $e) {
        error_log('[ia_guardar_health_check] ' . $e->getMessage());
    }
}

/**
 * Bar chart vertical (24 horas) en SVG inline.
 * $data = array de 24 enteros (valores por hora 0-23).
 */
function ia_svg_horas(array $data, int $w = 640, int $h = 100, string $color = '#1E4ED8'): string {
    if (empty($data)) return '<svg width="' . $w . '" height="' . $h . '"></svg>';
    $max = max(1, max($data));
    $n   = count($data);
    $pad = 8;
    $barAreaW = $w - $pad * 2;
    $barAreaH = $h - $pad - 14; // deja 14px abajo para etiquetas
    $barW = $barAreaW / $n;
    $bars = '';
    foreach ($data as $i => $v) {
        $bh = ($v / $max) * $barAreaH;
        $x  = $pad + $i * $barW;
        $y  = $pad + $barAreaH - $bh;
        $bars .= sprintf(
            '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="2" fill="%s"/>',
            $x + 1, $y, max(1, $barW - 2), max(1, $bh), $color
        );
        if ($i % 3 === 0) {
            $bars .= sprintf(
                '<text x="%.1f" y="%d" font-family="system-ui" font-size="9" fill="#64748b">%dh</text>',
                $x + 2, $h - 2, $i
            );
        }
    }
    return '<svg width="' . $w . '" height="' . $h . '" viewBox="0 0 ' . $w . ' ' . $h
        . '" xmlns="http://www.w3.org/2000/svg">' . $bars . '</svg>';
}

/** Convierte un status en emoji 🟢🟡🔴. */
function ia_status_emoji(string $status): string {
    return match ($status) {
        'operational' => '🟢',
        'warning'     => '🟡',
        default       => '🔴',
    };
}

// ───────────────────────────────────────────────────────────────────────────
// POST actions (botón "Probar servicios")
// ───────────────────────────────────────────────────────────────────────────

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = (string)($_POST['action'] ?? '');

    if ($action === 'probar_servicios') {
        require_permission('ia.test');
        // CSRF ya verificado por bootstrap.php para form POST no-JSON.

        $resultados = ia_ejecutar_pruebas_servicios();
        $okCount    = count(array_filter(
            $resultados, fn($r) => ($r['status'] ?? '') === 'operational'
        ));
        $totalCount = count($resultados);

        // Persistir cada resultado en system_health_checks
        foreach ($resultados as $svc => $r) {
            ia_guardar_health_check($conexion, $svc, $r);
        }

        // Auditar la acción
        admin_audit_log(
            $conexion,
            'ia.test_servicios',
            'ia_services',
            null,
            json_encode([
                'ok_count'   => $okCount,
                'total'      => $totalCount,
                'resultados' => array_map(fn($r) => [
                    'status'     => $r['status'],
                    'latency_ms' => $r['latency_ms'] ?? 0,
                ], $resultados),
            ], JSON_UNESCAPED_UNICODE),
            'ai'
        );

        if ($okCount === $totalCount) {
            admin_flash('success', "Servicios IA verificados: {$okCount}/{$totalCount} operativos.");
        } elseif ($okCount > 0) {
            admin_flash('warning', "Servicios IA: {$okCount}/{$totalCount} operativos. Revisa el detalle abajo.");
        } else {
            admin_flash('error', 'Ningún servicio IA responde. Verifica la configuración.');
        }

        header('Location: ' . admin_section_url('ai'));
        exit;
    }
}

// ───────────────────────────────────────────────────────────────────────────
// Verificación temprana: ¿existen las tablas IA?
// ───────────────────────────────────────────────────────────────────────────

$tablasIAExisten = ia_tablas_existen($conexion);

// ───────────────────────────────────────────────────────────────────────────
// KPIs principales (degradan a 0 si las tablas no existen)
// ───────────────────────────────────────────────────────────────────────────

$ia24h = $tablasIAExisten
    ? (int)safeScalar($conexion,
        "SELECT COUNT(*) FROM ia_mensajes WHERE created_at > NOW() - INTERVAL 1 DAY")
    : 0;
$ia7d = $tablasIAExisten
    ? (int)safeScalar($conexion,
        "SELECT COUNT(*) FROM ia_mensajes WHERE created_at > NOW() - INTERVAL 7 DAY")
    : 0;
$ia30d = $tablasIAExisten
    ? (int)safeScalar($conexion,
        "SELECT COUNT(*) FROM ia_mensajes WHERE created_at > NOW() - INTERVAL 30 DAY")
    : 0;

$tokensPromptMes = $tablasIAExisten
    ? (int)safeScalar($conexion,
        "SELECT COALESCE(SUM(prompt_tokens), 0)
         FROM ia_mensajes
         WHERE created_at > DATE_FORMAT(NOW(), '%Y-%m-01')")
    : 0;
$tokensCompletionMes = $tablasIAExisten
    ? (int)safeScalar($conexion,
        "SELECT COALESCE(SUM(completion_tokens), 0)
         FROM ia_mensajes
         WHERE created_at > DATE_FORMAT(NOW(), '%Y-%m-01')")
    : 0;
$tokensMes = $tokensPromptMes + $tokensCompletionMes;

$costoMes = $tablasIAExisten
    ? (float)safeScalar($conexion,
        "SELECT COALESCE(SUM(cost_usd), 0)
         FROM ia_mensajes
         WHERE created_at > DATE_FORMAT(NOW(), '%Y-%m-01')")
    : 0.0;

// Errores 24h y tasa
$errores24h = $tablasIAExisten
    ? (int)safeScalar($conexion,
        "SELECT COUNT(*) FROM ia_mensajes
         WHERE error_code IS NOT NULL AND created_at > NOW() - INTERVAL 1 DAY")
    : 0;
$errorRate = $ia24h > 0 ? ($errores24h / $ia24h) * 100 : 0.0;

// Usuarios únicos 30d
$usuariosUnicos30d = $tablasIAExisten
    ? (int)safeScalar($conexion,
        "SELECT COUNT(DISTINCT user_id) FROM ia_mensajes
         WHERE created_at > NOW() - INTERVAL 30 DAY")
    : 0;

// Latencia 24h: avg, max, p50, p95
$latAvg24h = $tablasIAExisten
    ? (int)safeScalar($conexion,
        "SELECT COALESCE(AVG(latency_ms), 0) FROM ia_mensajes
         WHERE created_at > NOW() - INTERVAL 1 DAY AND latency_ms > 0")
    : 0;
$latMax24h = $tablasIAExisten
    ? (int)safeScalar($conexion,
        "SELECT COALESCE(MAX(latency_ms), 0) FROM ia_mensajes
         WHERE created_at > NOW() - INTERVAL 1 DAY")
    : 0;
$latencias24h = $tablasIAExisten
    ? safeRows($conexion,
        "SELECT latency_ms FROM ia_mensajes
         WHERE created_at > NOW() - INTERVAL 1 DAY AND latency_ms > 0
         ORDER BY latency_ms ASC LIMIT 5000")
    : [];
$latP50 = ia_percentil($latencias24h, 50);
$latP95 = ia_percentil($latencias24h, 95);

// ───────────────────────────────────────────────────────────────────────────
// COP equivalente (opcional, configurable)
// ───────────────────────────────────────────────────────────────────────────
$usdCopRate  = (float)env('USD_COP_RATE', '0');
$costoMesCop = $usdCopRate > 0 ? $costoMes * $usdCopRate : 0.0;

// ───────────────────────────────────────────────────────────────────────────
// Datos para gráficos
// ───────────────────────────────────────────────────────────────────────────

// Serie 14d de solicitudes IA
$serieSolicitudes14d = $tablasIAExisten
    ? adminSerieNDias($conexion, 14, 'COUNT(*)', 'ia_mensajes')
    : array_map(
        fn($i) => ['fecha' => date('Y-m-d', strtotime("-$i day")), 'valor' => 0],
        range(13, 0)
      );

// Donut tokens prompt vs completion (mes actual)
$donutTokens = [];
if ($tokensMes > 0) {
    $donutTokens = [
        ['label' => 'Prompt',     'value' => $tokensPromptMes,     'color' => '#3B82F6'],
        ['label' => 'Completion', 'value' => $tokensCompletionMes, 'color' => '#10B981'],
    ];
}

// Top 10 usuarios por solicitudes en 30d
$topUsuarios = $tablasIAExisten
    ? safeRows($conexion,
        "SELECT COALESCE(u.email, CONCAT('user_', m.user_id)) AS email,
                COUNT(*) AS value
         FROM ia_mensajes m
         LEFT JOIN usuarios u ON u.moodle_id = m.user_id
         WHERE m.created_at > NOW() - INTERVAL 30 DAY
         GROUP BY m.user_id
         ORDER BY value DESC
         LIMIT 10")
    : [];

// Distribución por hora del día (últimas 24h)
$distribucionHoras = $tablasIAExisten
    ? safeRows($conexion,
        "SELECT HOUR(created_at) AS h, COUNT(*) AS c
         FROM ia_mensajes
         WHERE created_at > NOW() - INTERVAL 24 HOUR
         GROUP BY h
         ORDER BY h")
    : [];
$horasData = array_fill(0, 24, 0);
foreach ($distribucionHoras as $r) {
    $h = (int)$r['h'];
    if ($h >= 0 && $h < 24) $horasData[$h] = (int)$r['c'];
}

// Historial de errores (últimos 20)
$erroresHistorial = $tablasIAExisten
    ? safeRows($conexion,
        "SELECT m.error_code, m.error_message, m.provider, m.model,
                m.latency_ms, m.created_at,
                COALESCE(u.email, CONCAT('user_', m.user_id)) AS email
         FROM ia_mensajes m
         LEFT JOIN usuarios u ON u.moodle_id = m.user_id
         WHERE m.error_code IS NOT NULL
         ORDER BY m.id DESC
         LIMIT 20")
    : [];

// ───────────────────────────────────────────────────────────────────────────
// Tablas
// ───────────────────────────────────────────────────────────────────────────

// Conversaciones recientes (20)
$conversaciones = $tablasIAExisten
    ? safeRows($conexion,
        "SELECT c.id, c.user_id, c.message_count, c.total_tokens,
                c.estimated_cost_usd, c.started_at, c.last_activity_at,
                COALESCE(u.email, CONCAT('user_', c.user_id)) AS email
         FROM ia_conversaciones c
         LEFT JOIN usuarios u ON u.moodle_id = c.user_id
         ORDER BY c.last_activity_at DESC
         LIMIT 20")
    : [];

// Costos diarios (últimos 30 días)
$costosDiarios = safeRows($conexion,
    "SELECT snapshot_date, provider, total_requests, total_tokens_prompt,
            total_tokens_completion, total_cost_usd, avg_latency_ms, error_count
     FROM ia_costs
     WHERE snapshot_date >= (CURDATE() - INTERVAL 30 DAY)
     ORDER BY snapshot_date DESC, provider");

// Última health check por servicio (de system_health_checks)
$lastChecks = [];
try {
    $rowsHC = safeRows($conexion,
        "SELECT h.service, h.status, h.latency_ms, h.details, h.checked_at
         FROM system_health_checks h
         INNER JOIN (
            SELECT service, MAX(id) AS max_id
            FROM system_health_checks
            GROUP BY service
         ) m ON m.max_id = h.id");
    foreach ($rowsHC as $r) {
        $lastChecks[$r['service']] = $r;
    }
} catch (Throwable $e) {}

// Si no hay health checks previos, inicializamos con estado 'unknown'
$servicios = [
    'deepseek_worker' => [
        'label' => 'DeepSeek (Cloudflare Worker)',
        'desc'  => 'Tutor IA principal — POST a deepseek-proxy.instel91.workers.dev',
    ],
    'gemini' => [
        'label' => 'Gemini directo',
        'desc'  => 'Failover — POST a generativelanguage.googleapis.com',
    ],
    'cf_worker' => [
        'label' => 'Proxy Cloudflare Worker',
        'desc'  => 'Conectividad base — HEAD al Worker',
    ],
];
foreach ($servicios as $key => &$info) {
    if (isset($lastChecks[$key])) {
        $info['status']     = $lastChecks[$key]['status'];
        $info['latency_ms'] = (int)$lastChecks[$key]['latency_ms'];
        $info['checked_at'] = $lastChecks[$key]['checked_at'];
    } else {
        $info['status']     = 'unknown';
        $info['latency_ms'] = null;
        $info['checked_at'] = null;
    }
}
unset($info);

// ───────────────────────────────────────────────────────────────────────────
// Render
// ───────────────────────────────────────────────────────────────────────────

render_header('Centro de Monitoreo IA', ['section' => 'ai']);
?>

<div class="section-header">
    <div>
        <div class="section-header__title">Centro de Monitoreo IA</div>
        <div class="section-header__subtitle">
            Uso, costo y salud del tutor IA Saber+ (DeepSeek + Gemini)
        </div>
    </div>
    <div class="quick-stats">
        <div class="quick-stat">
            <div class="quick-stat__value"><?= admin_fmt_int($ia24h) ?></div>
            <div class="quick-stat__label">Solicitudes 24h</div>
        </div>
        <div class="quick-stat">
            <div class="quick-stat__value"><?= admin_fmt_int($usuariosUnicos30d) ?></div>
            <div class="quick-stat__label">Usuarios IA (30d)</div>
        </div>
        <div class="quick-stat">
            <div class="quick-stat__value"><?= admin_fmt_pct($errorRate) ?></div>
            <div class="quick-stat__label">Error rate 24h</div>
        </div>
    </div>
</div>

<?php if (!$tablasIAExisten): ?>
<section class="card">
    <div class="card__header">
        <div class="card__title">⚠️ Tablas IA no detectadas</div>
    </div>
    <div style="padding: 16px; color: #64748b;">
        Las tablas <code>ia_mensajes</code>, <code>ia_conversaciones</code> y
        <code>ia_costs</code> aún no existen en la base de datos.
        Ejecuta la migración <code>migrations/010_admin_command_center.sql</code>
        para activar el monitoreo completo.
        <div style="margin-top: 12px;">
            <code style="background: #f1f5f9; padding: 8px 12px; border-radius: 6px; font-size: 13px;">
                mysql -u root prepsaber &lt; backend/migrations/010_admin_command_center.sql
            </code>
        </div>
    </div>
</section>
<?php endif; ?>

<!-- ── Estado de servicios ── -->
<section class="card">
    <div class="card__header">
        <div class="card__title">🤖 Estado de servicios IA</div>
        <?php if (admin_has_permission('ia.test')): ?>
        <form method="post" style="display: inline;">
            <?= admin_csrf_field() ?>
            <input type="hidden" name="action" value="probar_servicios">
            <button type="submit" class="btn btn--sm btn--primary">
                🧪 Probar servicios
            </button>
        </form>
        <?php endif; ?>
    </div>
    <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 16px; padding: 16px;">
        <?php foreach ($servicios as $svcKey => $svc): ?>
        <div style="border: 1px solid #e2e8f0; border-radius: 12px; padding: 16px; background: #fafbfc;">
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px;">
                <strong><?= sp_h($svc['label']) ?></strong>
                <span style="font-size: 18px;" title="<?= sp_h($svc['status'] ?? 'unknown') ?>">
                    <?= ia_status_emoji($svc['status'] ?? 'unknown') ?>
                </span>
            </div>
            <div style="font-size: 12.5px; color: #64748b; margin-bottom: 8px;">
                <?= sp_h($svc['desc']) ?>
            </div>
            <div style="font-size: 12px; color: #475569; display: flex; flex-direction: column; gap: 4px;">
                <?php if ($svc['latency_ms'] !== null): ?>
                <div>Latencia: <strong><?= (int)$svc['latency_ms'] ?> ms</strong></div>
                <?php endif; ?>
                <?php if (!empty($svc['checked_at'])): ?>
                <div>Último check: <?= admin_fmt_tiempo_relativo($svc['checked_at']) ?></div>
                <?php else: ?>
                <div style="color: #94a3b8;">Sin verificación previa — pulsa "Probar servicios".</div>
                <?php endif; ?>
            </div>
        </div>
        <?php endforeach; ?>
    </div>
</section>

<!-- ── KPIs principales ── -->
<section class="kpi-row">
    <div class="kpi-card">
        <div class="kpi-card__header">
            <div class="kpi-card__title">Solicitudes 24h</div>
            <div class="kpi-card__icon">📈</div>
        </div>
        <div class="kpi-card__value"><?= admin_fmt_int($ia24h) ?></div>
        <div class="kpi-card__subtitle">
            7d: <?= admin_fmt_int($ia7d) ?> · 30d: <?= admin_fmt_int($ia30d) ?>
        </div>
    </div>

    <div class="kpi-card kpi-card--success">
        <div class="kpi-card__header">
            <div class="kpi-card__title">Tokens consumidos (mes)</div>
            <div class="kpi-card__icon">🔢</div>
        </div>
        <div class="kpi-card__value"><?= admin_fmt_int($tokensMes) ?></div>
        <div class="kpi-card__subtitle">
            <?= admin_fmt_int($tokensPromptMes) ?> prompt ·
            <?= admin_fmt_int($tokensCompletionMes) ?> completion
        </div>
    </div>

    <div class="kpi-card kpi-card--purple">
        <div class="kpi-card__header">
            <div class="kpi-card__title">Costo IA (mes)</div>
            <div class="kpi-card__icon">💸</div>
        </div>
        <div class="kpi-card__value" style="font-size: var(--fs-2xl);"><?= admin_fmt_usd($costoMes) ?></div>
        <div class="kpi-card__subtitle">
            <?php if ($usdCopRate > 0): ?>
            ≈ <?= admin_fmt_cop($costoMesCop) ?> (tasa: <?= admin_fmt_int($usdCopRate) ?> COP/USD)
            <?php else: ?>
            Configura <code>USD_COP_RATE</code> en .env para ver COP
            <?php endif; ?>
        </div>
    </div>

    <div class="kpi-card kpi-card--info">
        <div class="kpi-card__header">
            <div class="kpi-card__title">Latencia 24h</div>
            <div class="kpi-card__icon">⏱️</div>
        </div>
        <div class="kpi-card__value" style="font-size: var(--fs-xl);">
            <?= admin_fmt_int($latP50) ?><span style="font-size: 14px; color: #64748b;">ms p50</span>
        </div>
        <div class="kpi-card__subtitle">
            p95: <?= admin_fmt_int($latP95) ?>ms · avg: <?= admin_fmt_int($latAvg24h) ?>ms · max: <?= admin_fmt_int($latMax24h) ?>ms
        </div>
    </div>
</section>

<section class="kpi-row">
    <div class="kpi-card <?= $errorRate < 5 ? 'kpi-card--success' : ($errorRate < 20 ? 'kpi-card--warning' : 'kpi-card--danger') ?>">
        <div class="kpi-card__header">
            <div class="kpi-card__title">Tasa de error 24h</div>
            <div class="kpi-card__icon">⚠️</div>
        </div>
        <div class="kpi-card__value"><?= admin_fmt_pct($errorRate) ?></div>
        <div class="kpi-card__subtitle">
            <?= admin_fmt_int($errores24h) ?> errores de <?= admin_fmt_int($ia24h) ?> solicitudes
        </div>
    </div>

    <div class="kpi-card kpi-card--info">
        <div class="kpi-card__header">
            <div class="kpi-card__title">Usuarios únicos IA (30d)</div>
            <div class="kpi-card__icon">👥</div>
        </div>
        <div class="kpi-card__value"><?= admin_fmt_int($usuariosUnicos30d) ?></div>
        <div class="kpi-card__subtitle">
            <?php if ($ia30d > 0 && $usuariosUnicos30d > 0): ?>
            <?= admin_fmt_int((int)round($ia30d / max(1, $usuariosUnicos30d))) ?> msgs/usuario promedio
            <?php else: ?>
            —
            <?php endif; ?>
        </div>
    </div>

    <div class="kpi-card">
        <div class="kpi-card__header">
            <div class="kpi-card__title">Solicitudes 7d</div>
            <div class="kpi-card__icon">📅</div>
        </div>
        <div class="kpi-card__value"><?= admin_fmt_int($ia7d) ?></div>
        <div class="kpi-card__subtitle">Promedio: <?= admin_fmt_int((int)round($ia7d / 7)) ?>/día</div>
    </div>

    <div class="kpi-card kpi-card--success">
        <div class="kpi-card__header">
            <div class="kpi-card__title">Solicitudes 30d</div>
            <div class="kpi-card__icon">🗓️</div>
        </div>
        <div class="kpi-card__value"><?= admin_fmt_int($ia30d) ?></div>
        <div class="kpi-card__subtitle">Promedio: <?= admin_fmt_int((int)round($ia30d / 30)) ?>/día</div>
    </div>
</section>

<!-- ── Gráficos ── -->
<section class="dashboard-row">
    <div class="chart-container">
        <div class="chart-container__header">
            <div>
                <div class="chart-container__title">Solicitudes IA (14 días)</div>
                <div class="chart-container__subtitle">Total de mensajes intercambiados con el tutor</div>
            </div>
        </div>
        <div class="chart-container__body">
            <?= admin_svg_serie($serieSolicitudes14d, 600, 120, '#1E4ED8') ?>
        </div>
    </div>

    <div class="chart-container">
        <div class="chart-container__header">
            <div>
                <div class="chart-container__title">Distribución tokens (mes)</div>
                <div class="chart-container__subtitle">Prompt vs Completion</div>
            </div>
        </div>
        <div class="chart-container__body" style="display: flex; justify-content: center; align-items: center; gap: 24px;">
            <?php if (!empty($donutTokens)): ?>
                <?= admin_svg_donut($donutTokens, 130, 20) ?>
                <div style="display: flex; flex-direction: column; gap: 8px; font-size: 13px;">
                    <?php foreach ($donutTokens as $d): ?>
                    <div style="display: flex; align-items: center; gap: 8px;">
                        <span style="width: 10px; height: 10px; border-radius: 2px; background: <?= sp_h($d['color']) ?>;"></span>
                        <strong><?= sp_h($d['label']) ?></strong>:
                        <span style="color: #475569;"><?= admin_fmt_int($d['value']) ?></span>
                    </div>
                    <?php endforeach; ?>
                </div>
            <?php else: ?>
                <div class="empty-state">
                    <div class="empty-state__icon">📊</div>
                    <div class="empty-state__message">Sin tokens consumidos este mes</div>
                </div>
            <?php endif; ?>
        </div>
    </div>
</section>

<section class="dashboard-row">
    <div class="chart-container">
        <div class="chart-container__header">
            <div>
                <div class="chart-container__title">Top 10 usuarios IA (30d)</div>
                <div class="chart-container__subtitle">Por número de solicitudes</div>
            </div>
        </div>
        <div class="chart-container__body">
            <?php if (!empty($topUsuarios)): ?>
                <?= admin_svg_bars($topUsuarios, 580, 22, 6, '#1E4ED8') ?>
            <?php else: ?>
                <div class="empty-state">
                    <div class="empty-state__icon">👥</div>
                    <div class="empty-state__message">Sin actividad IA en los últimos 30 días</div>
                </div>
            <?php endif; ?>
        </div>
    </div>

    <div class="chart-container">
        <div class="chart-container__header">
            <div>
                <div class="chart-container__title">Distribución por hora (24h)</div>
                <div class="chart-container__subtitle">Solicitudes IA por hora del día</div>
            </div>
        </div>
        <div class="chart-container__body">
            <?= ia_svg_horas($horasData, 600, 120, '#1E4ED8') ?>
        </div>
    </div>
</section>

<!-- ── Historial de errores ── -->
<section class="card">
    <div class="card__header">
        <div class="card__title">🚨 Historial de errores (últimos 20)</div>
        <?php if (!empty($erroresHistorial)): ?>
        <span class="badge badge--danger"><?= admin_fmt_int(count($erroresHistorial)) ?></span>
        <?php endif; ?>
    </div>
    <?php if (empty($erroresHistorial)): ?>
    <div class="empty-state" style="padding: 24px;">
        <div class="empty-state__icon">✅</div>
        <div class="empty-state__title">Sin errores recientes</div>
        <div class="empty-state__message">No se han registrado errores de IA en las últimas solicitudes.</div>
    </div>
    <?php else: ?>
    <div style="max-height: 420px; overflow-y: auto;">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Cuándo</th>
                    <th>Usuario</th>
                    <th>Código</th>
                    <th>Mensaje</th>
                    <th>Provider</th>
                    <th>Latencia</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($erroresHistorial as $err): ?>
                <tr>
                    <td style="white-space: nowrap; font-size: 12px;">
                        <?= admin_fmt_tiempo_relativo($err['created_at']) ?>
                    </td>
                    <td style="font-size: 12px;"><?= sp_h($err['email']) ?></td>
                    <td>
                        <span class="badge badge--danger"><?= sp_h($err['error_code']) ?></span>
                    </td>
                    <td style="font-size: 12px; max-width: 380px; word-break: break-word;">
                        <?= sp_h(mb_substr((string)$err['error_message'], 0, 200)) ?>
                    </td>
                    <td style="font-size: 12px;"><?= sp_h($err['provider'] ?? '—') ?></td>
                    <td style="font-size: 12px;"><?= (int)$err['latency_ms'] ?> ms</td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>
    <?php endif; ?>
</section>

<!-- ── Conversaciones recientes ── -->
<section class="card">
    <div class="card__header">
        <div class="card__title">💬 Conversaciones recientes (20)</div>
    </div>
    <?php if (empty($conversaciones)): ?>
    <div class="empty-state" style="padding: 24px;">
        <div class="empty-state__icon">💬</div>
        <div class="empty-state__message">Sin conversaciones registradas todavía.</div>
    </div>
    <?php else: ?>
    <div style="max-height: 480px; overflow-y: auto;">
        <table class="data-table">
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Usuario</th>
                    <th>Mensajes</th>
                    <th>Tokens</th>
                    <th>Costo USD</th>
                    <th>Iniciada</th>
                    <th>Última actividad</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($conversaciones as $c): ?>
                <tr>
                    <td><code>#<?= (int)$c['id'] ?></code></td>
                    <td style="font-size: 12px;"><?= sp_h($c['email']) ?></td>
                    <td><?= admin_fmt_int($c['message_count']) ?></td>
                    <td><?= admin_fmt_int($c['total_tokens']) ?></td>
                    <td><?= admin_fmt_usd($c['estimated_cost_usd']) ?></td>
                    <td style="font-size: 12px; white-space: nowrap;"><?= admin_fmt_fecha($c['started_at']) ?></td>
                    <td style="font-size: 12px; white-space: nowrap;"><?= admin_fmt_tiempo_relativo($c['last_activity_at']) ?></td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>
    <?php endif; ?>
</section>

<!-- ── Costos diarios (ia_costs) ── -->
<section class="card">
    <div class="card__header">
        <div class="card__title">💰 Costos diarios IA (últimos 30 días)</div>
        <?php if (!empty($costosDiarios)): ?>
        <span class="badge badge--info"><?= admin_fmt_int(count($costosDiarios)) ?> registros</span>
        <?php endif; ?>
    </div>
    <?php if (empty($costosDiarios)): ?>
    <div class="empty-state" style="padding: 24px;">
        <div class="empty-state__icon">📭</div>
        <div class="empty-state__title">Sin costos agregados todavía</div>
        <div class="empty-state__message">
            El cron <code>cron_ia_costs.php</code> se ejecuta diariamente a las 00:05 UTC.
            Migración 010 o cron pendiente.
        </div>
    </div>
    <?php else: ?>
    <div style="max-height: 480px; overflow-y: auto;">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Fecha</th>
                    <th>Provider</th>
                    <th>Requests</th>
                    <th>Tokens Prompt</th>
                    <th>Tokens Completion</th>
                    <th>Costo USD</th>
                    <th>Latencia avg</th>
                    <th>Errores</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($costosDiarios as $c): ?>
                <tr>
                    <td style="white-space: nowrap;">
                        <?= sp_h($c['snapshot_date']) ?>
                    </td>
                    <td>
                        <span class="badge badge--gray"><?= sp_h($c['provider']) ?></span>
                    </td>
                    <td><?= admin_fmt_int($c['total_requests']) ?></td>
                    <td><?= admin_fmt_int($c['total_tokens_prompt']) ?></td>
                    <td><?= admin_fmt_int($c['total_tokens_completion']) ?></td>
                    <td><strong><?= admin_fmt_usd($c['total_cost_usd']) ?></strong></td>
                    <td><?= admin_fmt_int($c['avg_latency_ms']) ?> ms</td>
                    <td>
                        <?php if ((int)$c['error_count'] > 0): ?>
                        <span class="badge badge--danger"><?= admin_fmt_int($c['error_count']) ?></span>
                        <?php else: ?>
                        <span style="color: #94a3b8;">0</span>
                        <?php endif; ?>
                    </td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    </div>
    <?php endif; ?>
</section>

<!-- ── Nota técnica ── -->
<section class="card" style="background: #f8fafc;">
    <div style="padding: 16px; font-size: 12px; color: #64748b;">
        <strong>Detalle técnico:</strong>
        El tutor IA Saber+ usa <code>DeepSeek</code> vía Cloudflare Worker
        (<code>deepseek-proxy.instel91.workers.dev</code>) como proveedor principal.
        Pricing DeepSeek vigente: <strong>input $0.27 / 1M tokens</strong>,
        <strong>output $1.10 / 1M tokens</strong>.
        Cada intercambio (prompt + respuesta) se persiste en <code>ia_mensajes</code>
        y se actualiza la conversación activa en <code>ia_conversaciones</code>.
        El cron <code>cron_ia_costs.php</code> consolida los costos diarios en
        <code>ia_costs</code> a las 00:05 UTC.
    </div>
</section>

<?php
render_footer();
