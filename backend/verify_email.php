<?php
// CORS + JSON
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

error_reporting(E_ALL);
ini_set('display_errors', '0');
ini_set('log_errors', '1');

// ✅ FIX (FASE 2.5) — "respuesta vacía" en verify_email.
//
// Antes: json_encode($payload) podía devolver false si el archivo tenía
// caracteres acentuados con encoding inválido (el original tenía mojibake:
// 'invÃĄlido', 'ÃĐxito'). En ese caso:
//   strlen(false) = 0  →  header('Content-Length: 0')
//   echo false = ''    →  body vacío
//   cliente Flutter ve "respuesta vacía"
//
// Ahora:
//  1. json_encode con JSON_UNESCAPED_UNICODE (UTF-8 completo).
//  2. Si falla → fallback con JSON_INVALID_UTF8_SUBSTITUTE.
//  3. Si aún falla → JSON ASCII mínimo (nunca '' al cliente).
//  4. NO setear Content-Length (evita mismatch con gzip/proxy de Cloudflare).
//  5. fastcgi_finish_request() cuando esté disponible (entrega el body al
//     servidor inmediatamente antes de exit, sin depender de flush()).
//  6. Todos los mensajes en ASCII puro (sin acentos) para blindar el archivo
//     contra futuros problemas de encoding del editor.
function respond(int $code, array $payload): void {
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE);
    if ($json === false) {
        error_log("[verify_email] json_encode fallo UTF-8: " . json_last_error_msg());
        $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
    }
    if ($json === false) {
        error_log("[verify_email] json_encode fallo incluso con substitute: " . json_last_error_msg());
        $json = '{"status":"error","msg":"Encoding error"}';
    }

    while (ob_get_level() > 0) {
        ob_end_clean();
    }
    http_response_code($code);
    header('Content-Type: application/json; charset=UTF-8');
    // ⚠️ NO header('Content-Length: ...') — lo calcula Apache/nginx.
    echo $json;

    if (function_exists('fastcgi_finish_request')) {
        fastcgi_finish_request();
    } else {
        flush();
    }
    exit;
}

require __DIR__ . '/includes/conexion.php';

try {
    $token = $_GET['token'] ?? null;
    if (empty($token)) {
        error_log("[verify_email] Token faltante");
        respond(400, ['status' => 'error', 'msg' => 'Token requerido']);
    }

    if (strlen($token) !== 6 || !ctype_digit($token)) {
        error_log("[verify_email] Token no es de 6 digitos: $token");
        respond(400, ['status' => 'error', 'msg' => 'Codigo invalido. Debe ser de 6 digitos numericos.']);
    }

    $stmt = $conexion->prepare("
        SELECT ev.user_id, ev.expires_at, u.email_verificado,
               (u.contrasena_hash IS NOT NULL AND u.contrasena_hash <> '') AS has_password
        FROM email_verifications ev
        INNER JOIN usuarios u ON u.id_usuario = ev.user_id
        WHERE ev.token = ?
        LIMIT 1
    ");
    $stmt->execute([$token]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        error_log("[verify_email] Token invalido: $token");
        respond(400, ['status' => 'error', 'msg' => 'Token invalido']);
    }

    $userId = (int) $row['user_id'];
    $hasPassword = (bool) $row['has_password'];

    if ((int) $row['email_verificado'] === 1) {
        error_log("[verify_email] Email ya verificado para usuario {$userId} (has_password=" . ($hasPassword ? '1' : '0') . ")");
        respond(200, [
            'status' => 'ok',
            'msg'    => 'Correo ya estaba verificado',
            'userId' => $userId,
            'hasPassword' => $hasPassword,
        ]);
    }

    if (strtotime($row['expires_at']) < time()) {
        error_log("[verify_email] Token expirado para usuario {$userId}");
        respond(400, ['status' => 'error', 'msg' => 'Token expirado']);
    }

    $stmt = $conexion->prepare("UPDATE usuarios SET email_verificado = 1 WHERE id_usuario = ?");
    $stmt->execute([$userId]);

    $del = $conexion->prepare("DELETE FROM email_verifications WHERE token = ?");
    $del->execute([$token]);

    error_log("[verify_email] Correo verificado para usuario {$userId} (has_password=" . ($hasPassword ? '1' : '0') . ")");

    respond(200, [
        'status' => 'ok',
        'msg'    => 'Correo verificado exitosamente',
        'userId' => $userId,
        'hasPassword' => $hasPassword,
    ]);

} catch (Throwable $e) {
    error_log("[verify_email][EXCEPTION] " . $e->getMessage());
    respond(500, ['status' => 'error', 'msg' => 'Error interno']);
}