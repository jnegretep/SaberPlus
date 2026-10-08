<?php
/**
 * admin/check_ia.php — Diagnóstico del Tutor IA (DeepSeek) para Saber+
 *
 * PARA QUÉ SIRVE: si el tutor IA falla en la app, esta página dice EXACTAMENTE
 * por qué (¿sin saldo?, ¿API key mala?, ¿timeout?) sin necesidad de ser dev.
 *
 * ACCESO (cualquiera de las dos):
 *   1. Sesión de administrador iniciada en admin/index.php
 *   2. Cabecera X-Internal-Token con el valor de INTERNAL_TOKEN (backend/.env)
 *
 * ⚠️ NUNCA muestra la API key — solo su longitud.
 */
session_start();

require_once __DIR__ . '/../env.php';

/** Escapa texto para HTML (anti-XSS). */
function sp_h($txt): string {
    return htmlspecialchars((string)$txt, ENT_QUOTES, 'UTF-8');
}

// ── Guard de acceso: sesión de admin O token interno ──
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
 * Hace la MISMA llamada que hace el tutor IA real (mismo endpoint y modelo),
 * pero mínima (max_tokens 20, mensaje "Di OK") para gastar casi nada de saldo.
 * Devuelve SIEMPRE un array con: ok, diagnostico, mensaje, http, latencia,
 * body_excerpt y key_len. Nunca la key.
 */
function sp_probar_deepseek(): array {
    $api_key = env('DEEPSEEK_API_KEY');

    if ($api_key === null || $api_key === '') {
        return [
            'ok'            => false,
            'diagnostico'   => 'SIN API KEY',
            'mensaje'       => 'La variable DEEPSEEK_API_KEY NO está configurada en backend/.env. El tutor IA no puede funcionar sin ella.',
            'http'          => 0,
            'latencia'      => 0,
            'body_excerpt'  => '',
            'key_len'       => 0,
        ];
    }

    $key_len = strlen($api_key);
    $payload = json_encode([
        'model'      => 'deepseek-chat',
        'messages'   => [['role' => 'user', 'content' => 'Di OK']],
        'max_tokens' => 20,
    ]);

    try {
        $ch = curl_init('https://api.deepseek.com/chat/completions');
        if ($ch === false) {
            throw new Exception('No se pudo inicializar curl');
        }
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $payload);
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10);
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

        // ── Interpretar resultado para un no-dev ──
        if ($errno === 28) {
            return ['ok' => false, 'diagnostico' => 'TIMEOUT', 'mensaje' => 'La conexión con DeepSeek tardó demasiado (más de 30 segundos). Suele ser un problema de red del servidor. Intenta de nuevo en unos minutos.', 'http' => 0, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
        }
        if ($response === false || $errno !== 0) {
            return ['ok' => false, 'diagnostico' => 'ERROR DE RED', 'mensaje' => 'No se pudo conectar con api.deepseek.com (curl errno ' . $errno . '). Revisa la salida a internet del servidor o el firewall.', 'http' => 0, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
        }

        if ($httpcode === 200) {
            $json = json_decode($body, true);
            $texto = is_array($json) ? trim((string)($json['choices'][0]['message']['content'] ?? '')) : '';
            if ($texto !== '') {
                return ['ok' => true, 'diagnostico' => 'TODO BIEN', 'mensaje' => 'La IA respondió correctamente: «' . $texto . '». El tutor IA está funcionando.', 'http' => 200, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
            }
            return ['ok' => false, 'diagnostico' => 'RESPUESTA VACÍA', 'mensaje' => 'DeepSeek respondió HTTP 200 pero sin contenido. Vuelve a probar; si persiste, contacta soporte.', 'http' => 200, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
        }

        // Mapear errores típicos de DeepSeek
        $err_txt = strtolower($body . ' http' . $httpcode);
        if ($httpcode === 402 || str_contains($err_txt, 'insufficient') || str_contains($err_txt, 'balance')) {
            return ['ok' => false, 'diagnostico' => 'SIN SALDO', 'mensaje' => 'SIN SALDO: la cuenta de DeepSeek no tiene saldo. Recarga en platform.deepseek.com → Billing → Top up.', 'http' => $httpcode, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
        }
        if ($httpcode === 401 || str_contains($err_txt, 'authentication') || str_contains($err_txt, 'invalid_api_key')) {
            return ['ok' => false, 'diagnostico' => 'API KEY INVÁLIDA', 'mensaje' => 'La API key no es válida. Copia de nuevo la key desde platform.deepseek.com → API Keys y actualiza DEEPSEEK_API_KEY en backend/.env.', 'http' => $httpcode, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
        }
        if ($httpcode === 429 || str_contains($err_txt, 'rate_limit')) {
            return ['ok' => false, 'diagnostico' => 'LÍMITE DE PETICIONES', 'mensaje' => 'Se superó el límite de peticiones por minuto de DeepSeek. Espera un momento y vuelve a probar.', 'http' => $httpcode, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
        }

        return ['ok' => false, 'diagnostico' => 'ERROR DESCONOCIDO', 'mensaje' => 'DeepSeek devolvió HTTP ' . $httpcode . '. Revisa el detalle técnico de abajo; si no lo entiendes, envíaselo a tu desarrollador.', 'http' => $httpcode, 'latencia' => $latencia, 'body_excerpt' => $excerpt, 'key_len' => $key_len];
    } catch (Exception $e) {
        error_log('[CHECK_IA] ' . $e->getMessage());
        return ['ok' => false, 'diagnostico' => 'ERROR INTERNO', 'mensaje' => 'Error inesperado al ejecutar la prueba: ' . $e->getMessage(), 'http' => 0, 'latencia' => 0, 'body_excerpt' => '', 'key_len' => $key_len ?? 0];
    }
}

// ── Estado del entorno (siempre visible) ──
$envKey   = env('DEEPSEEK_API_KEY');
$keyLen   = ($envKey !== null && $envKey !== '') ? strlen($envKey) : 0;
$curlOk   = function_exists('curl_init');
$phpOk    = version_compare(PHP_VERSION, '8.0.0', '>=');
$tsAhora  = date('d/m/Y H:i:s');

// ── Ejecutar prueba si pidieron POST ──
$resultado = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $resultado = sp_probar_deepseek();
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
    .wrap { max-width: 760px; margin: 0 auto; }
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
    .alert.bad   { background: #FEE2E2; color: #7F1D1D; border: 1px solid #EF4444; font-size: 18px; }
    pre { background: #0f172a; color: #a5f3fc; border-radius: 10px; padding: 14px; font-size: 12px; overflow-x: auto; margin-top: 12px; white-space: pre-wrap; word-break: break-all; }
    .tag { display: inline-block; background: #EFF6FF; color: #1E4ED8; border-radius: 8px; padding: 4px 10px; font-size: 12px; font-weight: 700; margin-left: 8px; }
    a.back { color: #1E4ED8; text-decoration: none; font-size: 14px; font-weight: 600; }
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
        <div class="row"><span class="k">DEEPSEEK_API_KEY (backend/.env)</span><span class="<?= $keyLen > 0 ? 'ok' : 'bad' ?>"><?= $keyLen > 0 ? 'Configurada ✓ (longitud ' . $keyLen . ')' : 'NO CONFIGURADA ✗' ?></span></div>
    </div>

    <!-- ── Prueba en vivo ── -->
    <div class="card">
        <h2>Prueba en vivo <span class="tag">gasta ~0.0001 USD</span></h2>
        <p style="font-size:14px;color:#64748b;margin-bottom:16px;">
            Envía un mensaje mínimo («Di OK») a DeepSeek usando la MISMA configuración del tutor IA.
        </p>

        <?php if ($resultado !== null): ?>
            <div class="alert <?= $resultado['ok'] ? 'ok' : 'bad' ?>">
                <?= $resultado['ok'] ? '✅ ' . sp_h($resultado['diagnostico']) : '⛔ ' . sp_h($resultado['diagnostico']) ?><br>
                <span style="font-weight:500;font-size:14px;"><?= sp_h($resultado['mensaje']) ?></span>
            </div>

            <div style="margin-top:16px;">
                <div class="row"><span class="k">Código HTTP de DeepSeek</span><span><?= (int)$resultado['http'] ?: '—' ?></span></div>
                <div class="row"><span class="k">Latencia</span><span><?= (int)$resultado['latencia'] ?> ms</span></div>
                <div class="row"><span class="k">Longitud de la API key</span><span><?= (int)$resultado['key_len'] ?> caracteres</span></div>
                <div class="row"><span class="k">Hora de la prueba</span><span><?= sp_h(date('d/m/Y H:i:s')) ?></span></div>
            </div>

            <?php if ($resultado['body_excerpt'] !== ''): ?>
                <p style="font-size:12px;color:#64748b;margin-top:14px;">Detalle técnico (respuesta cruda de DeepSeek, truncada — para tu desarrollador):</p>
                <pre><?= sp_h($resultado['body_excerpt']) ?></pre>
            <?php endif; ?>
        <?php endif; ?>

        <form method="post" style="margin-top:20px;">
            <button type="submit" class="btn">🧪 Probar IA</button>
        </form>
    </div>

    <p style="font-size:12px;color:#94a3b8;text-align:center;">
        Esta página nunca muestra la API key, solo su longitud.<br>
        Si el resultado es «SIN SALDO», recarga el balance en
        <strong>platform.deepseek.com → Billing → Top up</strong>.
    </p>
</div>
</body>
</html>
