<?php
declare(strict_types=1);

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
    exit(json_encode([
        'status' => 'error',
        'msg' => 'Método no permitido'
    ]));
}

require __DIR__ . '/includes/conexion.php'; // PDO $conexion

// 1?? Obtener plan activo (único)
$stmt = $conexion->prepare("
    SELECT id, code, name, description, price, currency, is_lifetime
    FROM plans
    WHERE is_active = 1
    LIMIT 1
");
$stmt->execute();

$plan = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$plan) {
    echo json_encode([
        'status' => 'error',
        'msg' => 'No hay plan activo'
    ]);
    exit;
}

// 2?? Obtener beneficios del plan
$stmt = $conexion->prepare("
    SELECT text, included
    FROM plan_features
    WHERE plan_id = :pid
    ORDER BY sort_order ASC
");
$stmt->execute([
    ':pid' => $plan['id']
]);

$features = $stmt->fetchAll(PDO::FETCH_ASSOC);

// 3?? Respuesta
echo json_encode([
    'status' => 'ok',
    'plan' => [
        'code'        => $plan['code'],
        'name'        => $plan['name'],
        'description' => $plan['description'],
        'price'       => (int)$plan['price'],
        'currency'    => $plan['currency'],
        'is_lifetime' => (bool)$plan['is_lifetime'],
        'features'    => $features
    ]
]);
