<?php
declare(strict_types=1);

/**
 * get_app_config.php - Saber+ Configuración de la aplicación
 *
 * Devuelve la configuración administrable de la app:
 * - Enlaces externos (Google Play, Facebook, etc.)
 * - Configuración de rating
 * - Configuración de planes
 * - Configuración de referidos
 *
 * No requiere autenticación (configuración pública).
 */

require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/includes/config.php';

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: GET, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

try {
    $stmt = $conexion->query("SELECT clave, valor, grupo FROM app_config");
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $config = [];
    foreach ($rows as $row) {
        $config[$row['clave']] = $row['valor'];
    }

    echo json_encode([
        'status' => 'ok',
        'config' => $config,
    ], JSON_UNESCAPED_UNICODE);

} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'msg' => 'Error obteniendo configuración']);
}
