<?php
// verify_reset_code.php

ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);
ini_set('default_charset', 'UTF-8');

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require __DIR__ . '/includes/conexion.php';

function respond(int $code, array $payload): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=UTF-8');

    // Normalizar todos los strings a UTF-8 válido
    array_walk_recursive($payload, function (&$item) {
        if (is_string($item)) {
            $item = mb_convert_encoding($item, 'UTF-8', 'UTF-8');
        }
    });

    $json = json_encode($payload, JSON_UNESCAPED_UNICODE);
    if ($json === false) {
        $err = json_last_error_msg();
        error_log("[VERIFY_RESET][JSON_ENCODE_FAIL] $err");
        $json = '{"status":"error","msg":"json_encode_failed"}';
    }

    error_log("[VERIFY_RESET][RESPOND_JSON] $json");
    echo $json;
    exit;
}

try {
    $token = $_GET['token'] ?? null;
    if (empty($token)) {
        respond(400, ['status' => 'error', 'msg' => 'Token requerido']);
    }

    // Validar formato 6 dígitos
    if (strlen($token) !== 6 || !ctype_digit($token)) {
        respond(400, ['status' => 'error', 'msg' => 'Código inválido']);
    }

    $stmt = $conexion->prepare("
        SELECT pr.user_id, pr.expires_at, u.email
        FROM password_resets pr
        INNER JOIN usuarios u ON u.id_usuario = pr.user_id
        WHERE pr.token = ?
        LIMIT 1
    ");
    $stmt->execute([$token]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        respond(400, ['status' => 'error', 'msg' => 'Código inválido']);
    }

    if (strtotime($row['expires_at']) < time()) {
        respond(400, ['status' => 'error', 'msg' => 'Código expirado']);
    }

    // Normalizar email a UTF-8
    $email = mb_convert_encoding($row['email'], 'UTF-8', 'UTF-8');

    respond(200, [
        'status' => 'ok',
        'msg'    => 'Código válido',
        'userId' => (int)$row['user_id'],
        'email'  => $email
    ]);

} catch (Throwable $e) {
    error_log("[VERIFY_RESET][EXCEPTION] " . $e->getMessage());
    respond(500, ['status' => 'error', 'msg' => 'Error interno']);
}
