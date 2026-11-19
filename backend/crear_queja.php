<?php
declare(strict_types=1);

/**
 * crear_queja.php — Soporte in-app v1.7.0
 *
 * Registra una queja/sugerencia/bug enviada desde la app
 * (pantalla "Ayuda y Soporte"). Requiere JWT.
 *
 * Rate-limit: 1 envío cada 5 minutos por usuario (anti-spam).
 */

header('Access-Control-Allow-Origin: *');
header('Content-Type: application/json; charset=UTF-8');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: POST, OPTIONS');

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

/* ── 1. JWT obligatorio ── */
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

/* ── 2. Validación de entrada ── */
$data = json_decode(file_get_contents('php://input'), true) ?? [];

$tiposValidos = ['queja', 'sugerencia', 'bug', 'otro'];
$tipo   = in_array($data['tipo'] ?? '', $tiposValidos, true) ? (string)$data['tipo'] : 'otro';
$asunto = mb_substr(trim((string)($data['asunto'] ?? '')), 0, 150);
$mensaje = trim((string)($data['mensaje'] ?? ''));

if (mb_strlen($mensaje) < 10) {
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'Cuéntanos un poco más (mínimo 10 caracteres)']));
}
if (mb_strlen($mensaje) > 2000) {
    $mensaje = mb_substr($mensaje, 0, 2000);
}

/* ── 3. Rate limit: 1 envío / 5 min ── */
try {
    $stmt = $conexion->prepare("
        SELECT COUNT(*) FROM quejas_sugerencias
        WHERE user_id = :uid AND creado_en > DATE_SUB(NOW(), INTERVAL 5 MINUTE)
    ");
    $stmt->execute([':uid' => $moodleUserId]);
    if ((int)$stmt->fetchColumn() > 0) {
        http_response_code(429);
        exit(json_encode([
            'status' => 'error',
            'msg' => 'Ya enviaste un mensaje hace poco. Espera unos minutos para enviar otro.'
        ]));
    }
} catch (Exception $e) {
    // Tabla inexistente → se detectará en el INSERT
}

/* ── 4. Insertar ── */
try {
    $stmt = $conexion->prepare("
        INSERT INTO quejas_sugerencias (user_id, tipo, asunto, mensaje)
        VALUES (:uid, :tipo, :asunto, :mensaje)
    ");
    $stmt->execute([
        ':uid'     => $moodleUserId,
        ':tipo'    => $tipo,
        ':asunto'  => $asunto !== '' ? $asunto : null,
        ':mensaje' => $mensaje,
    ]);

    echo json_encode([
        'status' => 'ok',
        'msg'    => '¡Gracias por escribirnos! Tu mensaje llegó al equipo de soporte.',
        'id'     => (int)$conexion->lastInsertId(),
    ], JSON_UNESCAPED_UNICODE);
} catch (Exception $e) {
    error_log('[QUEJAS][CREATE] ' . $e->getMessage());
    http_response_code(500);
    exit(json_encode([
        'status' => 'error',
        'msg' => 'No pudimos guardar tu mensaje. Intenta de nuevo en unos minutos.'
    ]));
}
