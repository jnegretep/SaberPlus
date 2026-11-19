<?php
declare(strict_types=1);

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST' && $_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    exit(json_encode([
        'status' => 'error',
        'msg' => 'Método no permitido'
    ]));
}

require __DIR__ . '/includes/conexion.php';

// 1?? Obtener TODOS los planes activos
$stmt = $conexion->prepare("
    SELECT id, code, name, description, price, currency, is_lifetime
    FROM plans
    WHERE is_active = 1
    ORDER BY price ASC
");
$stmt->execute();

$plans = $stmt->fetchAll(PDO::FETCH_ASSOC);

if (empty($plans)) {
    echo json_encode([
        'status' => 'error',
        'msg' => 'No hay planes disponibles'
    ]);
    exit;
}

// 2?? Para cada plan, obtener sus características
foreach ($plans as &$plan) {
    $stmtFeatures = $conexion->prepare("
        SELECT text, included
        FROM plan_features
        WHERE plan_id = :pid
        ORDER BY sort_order ASC
    ");
    $stmtFeatures->execute([':pid' => $plan['id']]);
    $plan['features'] = $stmtFeatures->fetchAll(PDO::FETCH_ASSOC);
    
    // Convertir tipos de datos
    $plan['price'] = (int)$plan['price'];
    $plan['is_lifetime'] = (bool)$plan['is_lifetime'];
}

// 3?? Respuesta
echo json_encode([
    'status' => 'ok',
    'plans' => $plans
]);