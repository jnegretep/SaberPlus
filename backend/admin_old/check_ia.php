<?php
/**
 * admin/check_ia.php — Diagnóstico del Tutor IA (multi-proveedor) para Saber+
 *
 * PARA QUÉ SIRVE: si el tutor IA falla en la app, esta página dice EXACTAMENTE
 * por qué (¿sin key?, ¿sin saldo?, ¿bloqueo de red del hosting?) sin ser dev.
 *
 * v3 (2026-10): prueba TODOS los proveedores configurables (Gemini y DeepSeek),
 * muestra una matriz de conectividad y sugiere el arreglo concreto.
 *
 * ACCESO (cualquiera de las dos):
 *   1. Sesión de administrador iniciada en admin/index.php
 *   2. Cabecera X-Internal-Token con el valor de INTERNAL_TOKEN (backend/.env)
 *
 * ⚠️ NUNCA muestra las API keys — solo su longitud.
 */
session_start();

require_once __DIR__ . '/../env.php';

/** Escapa texto para HTML (anti-XSS). */
function sp_h($txt): string {
    return htmlspecialchars((string)$txt, ENT_QUOTES, 'UTF-8');
}

// ── Guard de acceso ──
$esAdminSesion = isset($_SESSION['admin_logged_in']) && $_SESSION['admin_logged_in'] === true;
$internalToken = env('INTERNAL_TOKEN', '');
$headerToken   = $_SERVER['HTTP_X_INTERNAL_TOKEN'] ?? '';
$esTokenInterno = ($internalToken !== '' && $internalToken !== null)
    && hash_equals($internalToken, (string)$headerToken);

if (!$esAdminSesion && !$esTokenInterno) {
    http_response_code(403);
    header('Content-Type: text/html; charset=UTF-8');
    exit('<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8">'
        . '<title>Saber+ Admin — Acceso denegado</title></head>'
        . '<body style="font-family:sans-serif;text-align:center;padding-top:80px;background:#f4f6fa;">'
        . '<h1 style="color:#EF4444;">⛔ Acceso denegado</h1>'
        . '<p>Inicia sesión en el <a href="index.php">panel de administración</a> '
        . 'o envía la cabecera X-Internal-Token correcta.</p></body></html>');
}

/**
 * Prueba UN proveedor con una llamada mínima («Di OK», max_tokens 20).
 * Devuelve: ok, diagnostico, mensaje, http, latencia, body_excerpt, key_len.
 */
function sp_probar_proveedor(array $prov, string $key_env, string $url, string $model): array {
    $api_key = env($key_env);

    if ($api_key === null || $api_key === '') {
        return [
            'ok' => false,
            'diagnostico' => 'SIN API KEY',
            'mensaje' => "La variable {$key_env} NO está configurada en backend/.env. "
                . ($key_env === 'GEMINI_API_KEY'
                    ? 'Es GRATUITA: créala en aistudio.google.com/apikey y cópiala en backend/.env.'
                    : 'Cópiala desde platform.deepseek.com → API Keys.'),
            'http' => 0, 'latencia' => 0, 'body_excerpt' => '', 'key_len' => 0,
        ];
    }

    $key_len = strlen($api_key);
    $payload = json_encode([
        'model'      => $model,
        'messages'   => [['role' => 'user', 'content' => 'Di OK']],
        'max_tokens' => 20,
    ]);

    try {
        $ch = curl_init($url);
        if ($ch === false) {
            throw new Exception('No se pudo inicializar curl');
        }
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $payload);
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 8);
        curl_setopt($ch, CURLOPT_TIMEOUT, 30);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $api_key,
        ]);

        $t0 = microtime(true);
        $response  = curl_exec($ch);
        $latencia  = (int)round((microtime(true) - $t0) * 1000);
        $httpcode  = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $errno     = curl_errno($ch);
        curl_close($ch);

        $body = is_string($response) ? $response : '';
        $excerpt = mb_substr($body, 0, 500);

        if ($errno === 28) {
            return ['ok' => false, 'diagnostico' => 'TIMEOUT', 'mensaje' => 'La conexión tardó demasiado (30s+). Problema de red del servidor.', 'http' => 0, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
        }
        if ($response === false || $errno !== 0) {
            $esBloqueo = in_array($errno, [7, 35, 60], true);
            return ['ok' => false, 'diagnostico' => 'BLOQUEO DE RED', 'mensaje' => $esBloqueo
                ? 'El servidor NO PUEDE CONECTARSE con este proveedor (curl errno ' . $errno . '). Es un bloqueo de salida del hosting (firewall). Solución: usa Gemini (IPs de Google, alcanzables) o pide al hosting abrir la salida.'
                : 'No se pudo conectar (curl errno ' . $errno . '). Revisa la salida a internet del servidor.', 'http' => 0, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
        }

        if ($httpcode === 200) {
            $json = json_decode($body, true);
            $texto = is_array($json) ? trim((string)($json['choices'][0]['message']['content'] ?? '')) : '';
            if ($texto !== '') {
                return ['ok' => true, 'diagnostico' => 'TODO BIEN', 'mensaje' => 'La IA respondió: «' . $texto . '». Este proveedor SIRVE para el tutor IA.', 'http' => 200, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
            }
            return ['ok' => false, 'diagnostico' => 'RESPUESTA VACÍA', 'mensaje' => 'HTTP 200 pero sin contenido. Vuelve a probar; si persiste, contacta soporte.', 'http' => 200, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
        }

        $err_txt = strtolower($body . ' http' . $httpcode);
        if ($httpcode === 402 || str_contains($err_txt, 'insufficient') || str_contains($err_txt, 'balance')) {
            return ['ok' => false, 'diagnostico' => 'SIN SALDO', 'mensaje' => 'SIN SALDO: recarga en la plataforma del proveedor (Billing → Top up).', 'http' => $httpcode, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
        }
        if ($httpcode === 401 || str_contains($err_txt, 'authentication') || str_contains($err_txt, 'invalid_api_key') || str_contains($err_txt, 'api key not valid')) {
            return ['ok' => false, 'diagnostico' => 'API KEY INVÁLIDA', 'mensaje' => "La API key no es válida. Copia de nuevo la key y actualiza {$key_env} en backend/.env.", 'http' => $httpcode, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
        }
        if ($httpcode === 429 || str_contains($err_txt, 'rate_limit') || str_contains($err_txt, 'resource_exhausted')) {
            return ['ok' => false, 'diagnostico' => 'LÍMITE DE PETICIONES', 'mensaje' => 'Se superó el límite de peticiones por minuto. Espera un momento y vuelve a probar.', 'http' => $httpcode, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
        }

        return ['ok' => false, 'diagnostico' => 'ERROR DESCONOCIDO', 'mensaje' => 'HTTP ' . $httpcode . '. Revisa el detalle técnico de abajo.', 'http' => $httpcode, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
    } catch (Exception $e) {
        error_log('[CHECK_IA] ' . $e->getMessage());
        return ['ok' => false, 'diagnostico' => 'ERROR INTERNO', 'mensaje' => 'Error inesperado: ' . $e->getMessage(), 'http' => 0, 'latencia' => 0, 'body_excerpt' => '', 'key_len' => $key_len ?? 0];
    }
}

// ── Estado del entorno ──
$phpOk   = version_compare(PHP_VERSION, '8.0.0', '>=');
$curlOk  = function_exists('curl_init');
$tsAhora = date('d/m/Y H:i:s');

$ordenCfg = (string)(env('IA_PROVEEDORES') ?? 'gemini,deepseek');
$orden    = array_filter(array_map('trim', explode(',', $ordenCfg)));

$proveedores = [
    'gemini' => [
        'label'  => 'Google Gemini',
        'key_env'=> 'GEMINI_API_KEY',
        'url'    => 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
        'model'  => env('GEMINI_MODEL', 'gemini-2.0-flash'),
        'nota'   => 'IPs de Google — alcanzables desde este servidor. API key gratuita en aistudio.google.com/apikey',
    ],
    'deepseek' => [
        'label'  => 'DeepSeek',
        'key_env'=> 'DEEPSEEK_API_KEY',
        'url'    => 'https://api.deepseek.com/chat/completions',
        'model'  => env('DEEPSEEK_MODEL', 'deepseek-chat'),
        'nota'   => '⚠️ Conocido: el hosting bloquea la salida a api.deepseek.com (IP AWS). Funcionará cuando el hosting la abra o al mudar de servidor.',
    ],
];

// ── Ejecutar pruebas si pidieron POST ──
$resultados = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $resultados = [];
    foreach ($proveedores as $id => $p) {
        $resultados[$id] = sp_probar_proveedor($p, $p['key_env'], $p['url'], $p['model']);
    }
}

$algunaKey = false;
foreach ($proveedores as $p) {
    $k = env($p['key_env']);
    if ($k !== null && $k !== '') { $algunaKey = true; }
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Saber+ Admin — Diagnóstico Tutor IA</title>
<style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f4f6fa; color: #1a1a2e; padding: 32px 16px; }
    .wrap { max-width: 800px; margin: 0 auto; }
    h1 { font-size: 24px; font-weight: 800; color: #1E4ED8; margin-bottom: 4px; }
    .sub { font-size: 14px; color: #64748b; margin-bottom: 24px; }
    .card { background: white; border-radius: 16px; padding: 24px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); margin-bottom: 20px; }
    .card h2 { font-size: 16px; font-weight: 700; margin-bottom: 16px; color: #1a1a2e; }
    .row { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #f1f5f9; font-size: 14px; }
    .row:last-child { border-bottom: none; }
    .row .k { color: #64748b; font-weight: 600; }
    .ok   { color: #16A34A; font-weight: 700; }
    .bad  { color: #EF4444; font-weight: 700; }
    .btn { display: inline-block; background: #1E4ED8; color: white; border: none; border-radius: 12px; font-size: 16px; font-weight: 700; padding: 14px 32px; cursor: pointer; transition: 0.2s; }
    .btn:hover { background: #1E3A8A; }
    .alert { border-radius: 14px; padding: 18px 20px; font-size: 15px; font-weight: 600; margin-top: 8px; }
    .alert.ok    { background: #DCFCE7; color: #14532D; border: 1px solid #16A34A; }
    .alert.bad   { background: #FEE2E2; color: #7F1D1D; border: 1px solid #EF4444; }
    .alert.info  { background: #EFF6FF; color: #1E3A8A; border: 1px solid #3B82F6; font-weight: 500; }
    pre { background: #0f172a; color: #a5f3fc; border-radius: 10px; padding: 14px; font-size: 12px; overflow-x: auto; margin-top: 12px; white-space: pre-wrap; word-break: break-all; }
    a.back { color: #1E4ED8; text-decoration: none; font-size: 14px; font-weight: 600; }
    .prov { border: 1px solid #e2e8f0; border-radius: 14px; padding: 18px; margin-top: 14px; }
    .prov h3 { font-size: 15px; margin-bottom: 8px; }
    .nota { font-size: 12.5px; color: #64748b; margin-top: 6px; }
    code { background: #f1f5f9; border-radius: 5px; padding: 2px 6px; font-size: 12.5px; }
</style>
</head>
<body>
<div class="wrap">
    <h1>🤖 Diagnóstico del Tutor IA</h1>
    <p class="sub">Saber+ Admin &nbsp;·&nbsp; <a class="back" href="index.php">← Volver al panel</a></p>

    <!-- ── Estado del entorno ── -->
    <div class="card">
        <h2>Estado del servidor</h2>
        <div class="row"><span class="k">Fecha y hora del servidor</span><span><?= sp_h($tsAhora) ?></span></div>
        <div class="row"><span class="k">Versión de PHP</span><span class="<?= $phpOk ? 'ok' : 'bad' ?>"><?= sp_h(PHP_VERSION) ?> <?= $phpOk ? '✓' : '(se requiere 8+)' ?></span></div>
        <div class="row"><span class="k">Extensión curl</span><span class="<?= $curlOk ? 'ok' : 'bad' ?>"><?= $curlOk ? 'Instalada ✓' : 'FALTA ✗' ?></span></div>
        <div class="row"><span class="k">Orden de proveedores (IA_PROVEEDORES)</span><span><?= sp_h($ordenCfg ?: 'gemini,deepseek (por defecto)') ?></span></div>
        <?php foreach ($proveedores as $p): ?>
            <?php $k = env($p['key_env']); $kl = ($k !== null && $k !== '') ? strlen($k) : 0; ?>
            <div class="row">
                <span class="k"><?= sp_h($p['key_env']) ?> (backend/.env)</span>
                <span class="<?= $kl > 0 ? 'ok' : 'bad' ?>"><?= $kl > 0 ? 'Configurada ✓ (longitud ' . $kl . ')' : 'NO CONFIGURADA ✗' ?></span>
            </div>
        <?php endforeach; ?>
        <?php if (!$algunaKey): ?>
            <div class="alert bad" style="margin-top:14px;">
                ⛔ No hay NINGUNA API key configurada — el tutor IA no puede funcionar.<br>
                <span style="font-weight:500;font-size:14px;">La más rápida de activar es <strong>Gemini</strong>:
                entra a <strong>aistudio.google.com/apikey</strong> (con tu cuenta Google), crea una key gratuita
                y agrégala a <code>backend/.env</code> como <code>GEMINI_API_KEY=AIza...</code></span>
            </div>
        <?php endif; ?>
    </div>

    <!-- ── Cómo funciona el failover ── -->
    <div class="card">
        <h2>Cómo funciona ahora el tutor IA</h2>
        <div class="alert info">
            El tutor intenta los proveedores <strong>en orden</strong> (<?= sp_h(implode(' → ', $orden ?: ['gemini', 'deepseek'])) ?>).
            Si uno falla por red, saldo o key, pasa automáticamente al siguiente. La app no se entera del fallo.
        </div>
    </div>

    <!-- ── Pruebas en vivo ── -->
    <div class="card">
        <h2>Prueba en vivo de los proveedores <span class="tag" style="display:inline-block;background:#EFF6FF;color:#1E4ED8;border-radius:8px;padding:4px 10px;font-size:12px;font-weight:700;">costo mínimo</span></h2>
        <p style="font-size:14px;color:#64748b;margin-bottom:6px;">
            Envía un mensaje mínimo («Di OK») a cada proveedor con la MISMA configuración del tutor IA.
        </p>

        <?php if ($resultados !== null): ?>
            <?php foreach ($resultados as $id => $r): $p = $proveedores[$id]; ?>
                <div class="prov">
                    <h3><?= sp_h($p['label']) ?> — modelo <code><?= sp_h($p['model']) ?></code></h3>
                    <div class="alert <?= $r['ok'] ? 'ok' : 'bad' ?>" style="margin-top:4px;">
                        <?= $r['ok'] ? '✅ ' . sp_h($r['diagnostico']) : '⛔ ' . sp_h($r['diagnostico']) ?><br>
                        <span style="font-weight:500;font-size:14px;"><?= sp_h($r['mensaje']) ?></span>
                    </div>
                    <div class="row"><span class="k">Código HTTP</span><span><?= (int)$r['http'] ?: '—' ?></span></div>
                    <div class="row"><span class="k">Latencia</span><span><?= (int)$r['latencia'] ?> ms</span></div>
                    <div class="row"><span class="k">Longitud de la API key</span><span><?= (int)$r['key_len'] ?> caracteres</span></div>
                    <p class="nota"><?= sp_h($p['nota']) ?></p>
                    <?php if ($r['body_excerpt'] !== ''): ?>
                        <pre><?= sp_h($r['body_excerpt']) ?></pre>
                    <?php endif; ?>
                </div>
            <?php endforeach; ?>
            <div style="margin-top:16px;" class="alert <?= (isset($resultados['gemini']) && $resultados['gemini']['ok']) || (isset($resultados['deepseek']) && $resultados['deepseek']['ok']) ? 'ok' : 'bad' ?>">
                <?= (isset($resultados['gemini']) && $resultados['gemini']['ok']) || (isset($resultados['deepseek']) && $resultados['deepseek']['ok'])
                    ? '✅ Al menos un proveedor responde → el tutor IA FUNCIONA con esa configuración.'
                    : '⛔ Ningún proveedor respondió → revisa los diagnósticos de arriba.' ?>
            </div>
        <?php endif; ?>

        <form method="post" style="margin-top:20px;">
            <button type="submit" class="btn">🧪 Probar todos los proveedores</button>
        </form>
    </div>

    <p style="font-size:12px;color:#94a3b8;text-align:center;">
        Esta página nunca muestra las API keys, solo su longitud.<br>
        Gemini: keys gratuitas en <strong>aistudio.google.com/apikey</strong> ·
        DeepSeek: recarga en <strong>platform.deepseek.com → Billing</strong>.
    </p>
</div>
</body>
</html>
