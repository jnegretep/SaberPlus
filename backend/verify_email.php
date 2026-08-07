<?php
// CORS + JSON
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Content-Type: application/json; charset=UTF-8");

// Si es preflight
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// Logs/errores al archivo, nunca al output
error_reporting(E_ALL);
ini_set('display_errors', '0');
ini_set('log_errors', '1');

// Helper para responder SIEMPRE con cuerpo JSON no vac√≠o
function respond(int $code, array $payload): void {
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE);
    // Elimina cualquier buffer previo (plugins, includes, BOM, etc.)
    while (ob_get_level() > 0) {
        ob_end_clean();
    }
    http_response_code($code);
    header('Content-Type: application/json; charset=UTF-8');
    header('Content-Length: ' . strlen($json));
    echo $json;
    flush();
    exit;
}

require __DIR__ . '/includes/conexion.php';

try {
    $token = $_GET['token'] ?? null;
    if (empty($token)) {
        error_log("[verify_email] Token faltante");
        respond(400, ['status' => 'error', 'msg' => 'Token requerido']);
    }

   // ?? VALIDAR QUE SEA C”DIGO DE 6 DÕGITOS NUM…RICOS
    if (strlen($token) !== 6 || !ctype_digit($token)) {
        error_log("[verify_email] Token no es de 6 dÌgitos: $token");
        respond(400, ['status' => 'error', 'msg' => 'CÛdigo inv·lido. Debe ser de 6 dÌgitos numÈricos.']);
    }

    $stmt = $conexion->prepare("
        SELECT ev.user_id, ev.expires_at, u.email_verificado
        FROM email_verifications ev
        INNER JOIN usuarios u ON u.id_usuario = ev.user_id
        WHERE ev.token = ?
        LIMIT 1
    ");
    $stmt->execute([$token]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        error_log("[verify_email] Token inv√°lido: $token");
        respond(400, ['status' => 'error', 'msg' => 'Token inv√°lido']);
    }

    $userId = (int) $row['user_id'];

    if ((int) $row['email_verificado'] === 1) {
        error_log("[verify_email] Email ya verificado para usuario {$userId}");
        respond(200, [
            'status' => 'ok',
            'msg'    => 'Correo ya estaba verificado',
            'userId' => $userId
        ]);
    }

    // Expiraci√≥n
    if (strtotime($row['expires_at']) < time()) {
        error_log("[verify_email] Token expirado para usuario {$userId}");
        respond(400, ['status' => 'error', 'msg' => 'Token expirado']);
    }

    // Marcar verificado
    $stmt = $conexion->prepare("UPDATE usuarios SET email_verificado = 1 WHERE id_usuario = ?");
    $stmt->execute([$userId]);

    // Single-use: eliminar token
    $del = $conexion->prepare("DELETE FROM email_verifications WHERE token = ?");
    $del->execute([$token]);

    error_log("[verify_email] Correo verificado para usuario {$userId}");

    respond(200, [
        'status' => 'ok',
        'msg'    => 'Correo verificado con √©xito',
        'userId' => $userId
    ]);

} catch (Throwable $e) {
    error_log("[verify_email][EXCEPTION] " . $e->getMessage());
    respond(500, ['status' => 'error', 'msg' => 'Error interno']);
}
