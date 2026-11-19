<?php
declare(strict_types=1);

/**
 * mis_quejas.php — Historial de soporte del usuario (v1.7.0)
 *
 * Devuelve las quejas/sugerencias enviadas por el usuario autenticado
 * con su estado y la respuesta del equipo cuando exista.
 */

header('Access-Control-Allow-Origin: *');
header('Content-Type: application/json; charset=UTF-8');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';

$configJwt = require __DIR__ . '/jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

/* ── JWT obligatorio ── */
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

try {
    $stmt = $conexion->prepare("
        SELECT id, tipo, asunto, mensaje, estado, respuesta_admin, creado_en, actualizado_en
        FROM quejas_sugerencias
        WHERE user_id = :uid
        ORDER BY creado_en DESC
        LIMIT 50
    ");
    $stmt->execute([':uid' => $moodleUserId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Estructura de estado → texto amable para la app
    $etiquetas = [
        'nuevo'       => 'Recibido',
        'en_proceso'  => 'En revisión',
        'resuelto'    => 'Resuelto',
        'descartado'  => 'Cerrado',
    ];

    $salida = [];
    foreach ($rows as $r) {
        $salida[] = [
            'id'              => (int)$r['id'],
            'tipo'            => (string)$r['tipo'],
            'asunto'          => $r['asunto'] !== null ? (string)$r['asunto'] : '',
            'mensaje'         => (string)$r['mensaje'],
            'estado'          => (string)$r['estado'],
            'estado_texto'    => $etiquetas[$r['estado']] ?? $r['estado'],
            'respuesta_admin' => $r['respuesta_admin'] !== null ? (string)$r['respuesta_admin'] : null,
            'creado_en'       => (string)$r['creado_en'],
            'actualizado_en'  => (string)$r['actualizado_en'],
        ];
    }

    echo json_encode([
        'status' => 'ok',
        'quejas' => $salida,
    ], JSON_UNESCAPED_UNICODE);
} catch (Exception $e) {
    error_log('[QUEJAS][LIST] ' . $e->getMessage());
    // Tabla inexistente → lista vacía, la app nunca se rompe
    echo json_encode(['status' => 'ok', 'quejas' => []]);
}
