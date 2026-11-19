<?php
declare(strict_types=1);

/**
 * refresh.php — Renueva el JWT usando el refresh token (30 días).
 *
 * v2 (2026-10) — FIX CRÍTICO "error de conexión al volver tras inactividad":
 *   El JWT regenerado NO incluía `moodle_userid` ni `moodle_token`, así que
 *   tras un refresh automático TODOS los endpoints de Moodle respondían
 *   "Usuario no encontrado" / 401 → la app mostraba error de conexión y
 *   obligaba a iniciar sesión de nuevo.
 *
 *   Ahora el payload del JWT es IDÉNTICO al de login.php:
 *   {id_usuario, email, tipo_usuario, moodle_userid, moodle_token}
 *
 *   Además: se invalida el refresh token usado (rotación real) y se eliminan
 *   los tokens viejos del usuario (funciona con o sin UNIQUE KEY en la tabla).
 */

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';

use Firebase\JWT\JWT;

$config = require __DIR__ . '/jwt_config.php';
header('Content-Type: application/json; charset=UTF-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
}

// Aceptar JSON y form-urlencoded (el cliente envía form-urlencoded)
$rawBody = file_get_contents('php://input');
$jsonBody = json_decode($rawBody, true);
$refresh_token = is_array($jsonBody) && isset($jsonBody['refresh_token'])
    ? $jsonBody['refresh_token']
    : ($_POST['refresh_token'] ?? '');

$refresh_token = is_string($refresh_token) ? trim($refresh_token) : '';

if (!$refresh_token || !preg_match('/^[a-f0-9]{64}$/', $refresh_token)) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'msg' => 'Refresh token inválido']);
    exit;
}

try {
    // Buscar y validar refresh token
    $stmt = $conexion->prepare(
        "SELECT id_usuario FROM refresh_tokens
         WHERE token = ? AND expires_at > NOW()"
    );
    $stmt->execute([$refresh_token]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        http_response_code(401);
        echo json_encode(['status' => 'error', 'msg' => 'Refresh token inválido o expirado']);
        exit;
    }

    $id_usuario = (int)$row['id_usuario'];

    // ✅ FIX: obtener TODOS los campos que espera el payload del JWT
    // (idéntico a login.php — incluidos moodle_userid y moodle_token).
    $stmt = $conexion->prepare(
        "SELECT id_usuario, email, tipo_usuario, moodle_id, moodle_token, activo
         FROM usuarios WHERE id_usuario = ?"
    );
    $stmt->execute([$id_usuario]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        http_response_code(401);
        echo json_encode(['status' => 'error', 'msg' => 'Usuario no existe']);
        exit;
    }
    if (isset($user['activo']) && (int)$user['activo'] !== 1) {
        http_response_code(403);
        echo json_encode(['status' => 'error', 'msg' => 'Cuenta desactivada']);
        exit;
    }

    // ── Rotación REAL del refresh token ──
    // 1. Borrar el token usado y cualquier token viejo del usuario
    //    (funciona con o sin UNIQUE KEY, y no deja tokens huérfanos válidos).
    $stmt = $conexion->prepare("DELETE FROM refresh_tokens WHERE id_usuario = ?");
    $stmt->execute([$id_usuario]);

    // 2. Insertar el nuevo (30 días)
    $new_refresh_token = bin2hex(random_bytes(32));
    $stmt = $conexion->prepare("
        INSERT INTO refresh_tokens (id_usuario, token, expires_at)
        VALUES (:uid, :token, DATE_ADD(NOW(), INTERVAL 30 DAY))
    ");
    $stmt->execute([':uid' => $id_usuario, ':token' => $new_refresh_token]);

    error_log("[refresh] Token rotado para user_id={$id_usuario}");

    // ── Nuevo JWT con el MISMO payload que login.php ──
    $now = time();
    $exp = $now + (int)($config['expiry_seconds'] ?? 86400);
    $jti = bin2hex(random_bytes(16));

    $payload = [
        'iss' => $config['issuer'],
        'aud' => $config['audience'],
        'iat' => $now,
        'nbf' => $now,
        'exp' => $exp,
        'jti' => $jti,
        'data' => [
            'id_usuario'    => (int)$user['id_usuario'],
            'email'         => $user['email'],
            'tipo_usuario'  => $user['tipo_usuario'],
            'moodle_userid' => (int)$user['moodle_id'],
            'moodle_token'  => $user['moodle_token'],
        ],
    ];

    $jwt = JWT::encode($payload, $config['secret'], $config['algo'] ?? 'HS256');

    echo json_encode([
        'status'        => 'ok',
        'token'         => $jwt,
        'refresh_token' => $new_refresh_token,
        'expires_at'    => date('c', $exp),
    ], JSON_UNESCAPED_UNICODE);

} catch (Throwable $e) {
    error_log('[refresh] Error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['status' => 'error', 'msg' => 'Error interno']);
    exit;
}
