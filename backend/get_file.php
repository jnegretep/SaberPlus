<?php
declare(strict_types=1);

// =======================================
// Proxy de archivos Moodle — PrepSaber
// =======================================

// Permitir CORS
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// Validar parámetro URL
$url = $_GET['url'] ?? '';
if (! $url) {
    http_response_code(400);
    header("Content-Type: application/json; charset=UTF-8");
    echo json_encode(['status' => 'error', 'msg' => 'Falta parámetro url']);
    exit;
}

// Token con permisos de lectura
$token = '37663518c05c753401b5fa535ceb7316';

// ======================================================
// 1. Decodificar y sanear URL
// ======================================================
$url = urldecode($url);

// Corregir coma en IP (172,93.49.94 -> 172.93.49.94)
$url = preg_replace('/(\d+),(\d+\.\d+\.\d+)/', '$1.$2', $url);

// Recortar basura en primer '<' o '%3C'
$cutPos = false;
$posTag = strpos($url, '<');
$posEnc = stripos($url, '%3C');
if ($posTag !== false) $cutPos = $posTag;
if ($posEnc !== false) $cutPos = ($cutPos === false) ? $posEnc : min($cutPos, $posEnc);
if ($cutPos !== false) {
    $url = substr($url, 0, $cutPos);
}

// Re-encodear el path para manejar espacios y caracteres especiales
$parts = parse_url($url);
$scheme   = $parts['scheme'] ?? 'http';
$host     = $parts['host'] ?? '';
$port     = isset($parts['port']) ? ':' . $parts['port'] : '';
$path     = isset($parts['path']) ? implode('/', array_map('rawurlencode', explode('/', $parts['path']))) : '';
$query    = $parts['query'] ?? '';

$url = "$scheme://$host$port$path";
if ($query) {
    $url .= "?$query";
}

// Validar que sea un recurso Moodle
if (strpos($url, 'pluginfile.php') === false) {
    http_response_code(400);
    header("Content-Type: application/json; charset=UTF-8");
    echo json_encode(['status' => 'error', 'msg' => 'URL no válida', 'url' => $url]);
    exit;
}

// Asegurar que use /webservice/pluginfile.php/
if (!preg_match('#/webservice/pluginfile\.php/#', $url)) {
    $url = preg_replace('#/pluginfile\.php/#', '/webservice/pluginfile.php/', $url);
}

// Añadir token si no está
if (!preg_match('/([?&])token=/', $url)) {
    $url .= (strpos($url, '?') === false ? '?' : '&') . 'token=' . urlencode($token);
}

// ======================================================
// 2. Descargar archivo desde Moodle
// ======================================================
$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_SSL_VERIFYPEER => false,
    CURLOPT_SSL_VERIFYHOST => false,
    CURLOPT_HEADER => true,
    CURLOPT_USERAGENT => 'Mozilla/5.0 (compatible; PrepSaberProxy/1.0)',
    CURLOPT_TIMEOUT => 30,
]);

$response = curl_exec($ch);
$errno = curl_errno($ch);
$error = curl_error($ch);
$httpcode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$header_size = curl_getinfo($ch, CURLINFO_HEADER_SIZE);
$contentType = curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
curl_close($ch);

$body = $response !== false ? substr($response, (int)$header_size) : '';

// ======================================================
// 3. Manejo de errores
// ======================================================
if ($httpcode !== 200 || !$body) {
    http_response_code(502);
    header("Content-Type: application/json; charset=UTF-8");
    echo json_encode([
        'status' => 'error',
        'msg' => 'No se pudo obtener el archivo',
        'httpcode' => $httpcode,
        'url' => $url,
        'type' => $contentType,
        'errno' => $errno,
        'error' => $error,
    ]);
    exit;
}

// ======================================================
// 4. Determinar tipo MIME si Moodle no lo envía bien
// ======================================================
if (!$contentType || stripos($contentType, 'text/html') !== false) {
    $ext = strtolower(pathinfo(parse_url($url, PHP_URL_PATH), PATHINFO_EXTENSION));
    $map = [
        'jpg' => 'image/jpeg',
        'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'svg' => 'image/svg+xml',
        'webp' => 'image/webp',
        'mp4' => 'video/mp4',
        'mov' => 'video/quicktime',
        'm4v' => 'video/x-m4v',
        'webm' => 'video/webm',
        'pdf' => 'application/pdf',
        'mp3' => 'audio/mpeg',
        'wav' => 'audio/wav',
    ];
    $contentType = $map[$ext] ?? 'application/octet-stream';
}

// ======================================================
// 5. Enviar archivo binario
// ======================================================
header("Content-Type: $contentType");
header("Cache-Control: public, max-age=86400");
echo $body;
