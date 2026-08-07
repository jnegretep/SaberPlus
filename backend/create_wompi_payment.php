<?php
declare(strict_types=1);

/**
 * create_wompi_payment.php
 * Crea checkout de pago Wompi a partir de un plan activo
 */

error_reporting(E_ALL);
ini_set('log_errors', '1');
ini_set('display_errors', '0');

/* =======================
   HEADERS
   ======================= */
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'Método no permitido'
    ]));
}

/* =======================
   DEPENDENCIAS
   ======================= */
require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
$configJwt   = require __DIR__ . '/jwt_config.php';
$wompiConfig = require __DIR__ . '/wompi_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

/* =======================
   JWT
   ======================= */
$headers = function_exists('getallheaders') ? getallheaders() : [];
$auth    = $headers['Authorization']
        ?? $headers['authorization']
        ?? '';

if (!preg_match('/Bearer\s+(\S+)/', $auth, $m)) {
    http_response_code(401);
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'No autorizado'
    ]));
}

try {
    $decoded = JWT::decode(
        $m[1],
        new Key($configJwt['secret'], 'HS256')
    );

    $moodleUserId = (int)($decoded->data->moodle_userid ?? 0);

    if ($moodleUserId <= 0) {
        throw new Exception('ID inválido');
    }

} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'Token inválido'
    ]));
}

/* =======================
   BODY (plan_id)
   ======================= */
$raw  = file_get_contents('php://input');
$data = json_decode($raw, true);

$planId = (int)($data['plan_id'] ?? 0);

if ($planId <= 0) {
    http_response_code(400);
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'plan_id requerido'
    ]));
}

/* =======================
   USUARIO
   ======================= */
$stmt = $conexion->prepare("
    SELECT moodle_id, email, access_level
    FROM usuarios
    WHERE moodle_id = :mid
    LIMIT 1
");
$stmt->execute([':mid' => $moodleUserId]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$user) {
    http_response_code(404);
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'Usuario no encontrado'
    ]));
}

if ($user['access_level'] === 'premium') {
    echo json_encode([
        'status' => 'ok',
        'msg'    => 'Usuario ya es premium'
    ]);
    exit;
}

/* =======================
   PLAN
   ======================= */
$stmt = $conexion->prepare("
    SELECT id, name, price, currency
    FROM plans
    WHERE id = :pid
      AND is_active = 1
    LIMIT 1
");
$stmt->execute([':pid' => $planId]);
$plan = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$plan) {
    http_response_code(404);
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'Plan no disponible'
    ]));
}

/* =======================
   DATOS DE PAGO
   ======================= */
$price         = (int)$plan['price'];
$currency      = $plan['currency'];
$amountInCents = $price * 100;

// Reference limpia (Wompi-safe)
$reference = preg_replace('/\s+/', '_', strtoupper($plan['name']))
    . '_' . $moodleUserId
    . '_' . time();

$reference = preg_replace('/[^A-Z0-9_]/', '', $reference);

/* =======================
   INSERT PAYMENT
   ======================= */
$stmt = $conexion->prepare("
    INSERT INTO payments
    (user_id, reference_code, amount, currency, status, gateway)
    VALUES (:u, :r, :a, :c, 'pending', 'wompi')
");

$stmt->execute([
    ':u' => $moodleUserId,
    ':r' => $reference,
    ':a' => $price,
    ':c' => $currency,
]);

/* =======================
   CHECKOUT WOMPI
   ======================= */

// 1. Calcular el hash de integridad
$signatureData = $reference . $amountInCents . $currency . $wompiConfig['integrity'];
$integrityHash = hash('sha256', $signatureData);

// 2. Construir URL con el parámetro exacto: signature:integrity
$checkoutUrl = 'https://checkout.wompi.co/p/?' . http_build_query([
    'public-key'      => $wompiConfig['public_key'],
    'currency'        => $currency,
    'amount-in-cents' => $amountInCents,
    'reference'       => $reference,
    'signature:integrity' => $integrityHash, // <<< ESTE FUE EL CAMBIO CLAVE
    'redirect-url'    => $wompiConfig['redirect_url'],
]);

/* =======================
   LOGS
   ======================= */
error_log("=== WOMPI DEBUG ===");
error_log("Reference: $reference");
error_log("Amount in cents: $amountInCents");
error_log("Currency: $currency");
error_log("Signature hash: $integrityHash");
error_log("Full URL: $checkoutUrl");

/* =======================
   RESPUESTA
   ======================= */
echo json_encode([
    'status'        => 'ok',
    'checkout_url'  => $checkoutUrl,
    'reference'     => $reference,
    'plan' => [
        'id'        => $plan['id'],
        'name'      => $plan['name'],
        'price'     => $price,
        'currency'  => $currency,
    ]
]);