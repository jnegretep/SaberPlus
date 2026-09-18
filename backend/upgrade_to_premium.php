<?php
declare(strict_types=1);

/**
 * upgrade_to_premium.php
 *
 * ⚠️ SEGURIDAD (fix crítico 2026-09):
 * Antes este endpoint activaba premium con SOLO un JWT válido, sin verificar
 * ningún pago — cualquiera podía autoproclamarse premium gratis.
 *
 * Ahora exige una `reference` de pago que exista en la tabla `payments`,
 * pertenezca al usuario del token y esté en estado 'approved' (la aprueba
 * el webhook de Wompi tras verificar firma + monto).
 *
 * La vía normal de activación sigue siendo wompi_webhook.php.
 */

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
}

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
$configJwt = require __DIR__ . '/jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

/* ── 1. Autenticación JWT ── */
$allHeaders = function_exists('getallheaders') ? getallheaders() : [];
$authHeader = $allHeaders['Authorization'] ?? $allHeaders['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';

if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
}

try {
    $decoded = JWT::decode($m[1], new Key($configJwt['secret'], 'HS256'));
    $moodleUserId = (int)($decoded->data->moodle_userid ?? 0);
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Token inválido']));
}

if ($moodleUserId <= 0) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Token sin identificador de usuario']));
}

/* ── 2. Referencia de pago OBLIGATORIA ── */
$data = json_decode(file_get_contents('php://input'), true) ?? [];
$reference = trim((string)($data['reference'] ?? ''));

if ($reference === '') {
    http_response_code(400);
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'Se requiere la referencia del pago. La activación premium solo procede con un pago verificado.'
    ]));
}

/* ── 3. Verificar el pago contra la BD ── */
$stmt = $conexion->prepare("
    SELECT id, user_id, amount, currency, status
    FROM payments
    WHERE reference_code = :ref
    LIMIT 1
");
$stmt->execute([':ref' => $reference]);
$payment = $stmt->fetch(PDO::FETCH_ASSOC);

$pagosValidos = false;

if ($payment) {
    $esDelUsuario = ((int)$payment['user_id'] === $moodleUserId);
    $aprobado     = (strtolower((string)$payment['status']) === 'approved');

    if ($esDelUsuario && $aprobado) {
        $pagosValidos = true;
    }
}

if (!$pagosValidos) {
    error_log("[UPGRADE_PREMIUM] Intento rechazado: moodle_id={$moodleUserId} ref={$reference}");
    http_response_code(403);
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'No se encontró un pago aprobado para esta cuenta. Si ya pagaste, espera la confirmación o contacta a soporte.'
    ]));
}

/* ── 4. Activar premium (idempotente) ── */
$stmt = $conexion->prepare("
    UPDATE usuarios
    SET access_level = 'premium',
        unlocked_at = NOW()
    WHERE moodle_id = :mid
");
$stmt->execute([':mid' => $moodleUserId]);

if ($stmt->rowCount() === 0) {
    // Puede ser que ya fuera premium (UPDATE no cambia filas idénticas en MySQL
    // solo si los valores son exactamente iguales) — verificar estado real.
    $chk = $conexion->prepare("SELECT access_level FROM usuarios WHERE moodle_id = :mid LIMIT 1");
    $chk->execute([':mid' => $moodleUserId]);
    $row = $chk->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        http_response_code(404);
        exit(json_encode(['status' => 'error', 'msg' => 'Usuario no encontrado']));
    }
    if ($row['access_level'] !== 'premium') {
        http_response_code(500);
        exit(json_encode(['status' => 'error', 'msg' => 'No se pudo activar el premium. Intenta de nuevo.']));
    }
}

echo json_encode([
    'status' => 'ok',
    'access_level' => 'premium',
    'msg' => 'Cuenta verificada como PREMIUM'
]);
