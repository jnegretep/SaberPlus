<?php
/**
 * config/cors.php
 * Manejo de CORS para la API REST.
 */

declare(strict_types=1);

header('Access-Control-Allow-Origin: *'); // En producción: restringir al dominio del front
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Access-Control-Max-Age: 86400');
header('Content-Type: application/json; charset=utf-8');

// Preflight CORS
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}
