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
   BODY (plan_id + promo_code opcional v1.7.0)
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

// Código promocional opcional (mayúsculas, sin espacios)
$promoCodeInput = strtoupper(preg_replace('/\s+/', '', (string)($data['promo_code'] ?? '')));

/* =======================
   PROMOCIÓN (v1.7.0)
   - Banner con descuento → se aplica AUTOMÁTICAMENTE al plan (si aplica).
   - Código (promo_code)  → el usuario lo escribe; si es válido tiene prioridad.
   Nunca se apilan dos promos: gana la de mayor descuento (código empatado gana).
   ======================= */
$promoAplicada = null;   // fila de promociones
$promoOrigen  = null;   // 'codigo' | 'banner'

try {
    $stmt = $conexion->prepare("
        SELECT id, titulo, tipo, descuento_tipo, descuento_valor, usos, max_usos
        FROM promociones
        WHERE activo = 1
          AND NOW() BETWEEN fecha_inicio AND fecha_fin
          AND (max_usos IS NULL OR usos < max_usos)
          AND (plan_id IS NULL OR plan_id = :pid)
          AND (
                (tipo = 'banner' AND descuento_valor > 0)
                OR (tipo = 'codigo' AND codigo = :code)
              )
        ORDER BY descuento_valor DESC
    ");
    $stmt->execute([':pid' => $planId, ':code' => $promoCodeInput !== '' ? $promoCodeInput : '__none__']);
    $candidatas = $stmt->fetchAll(PDO::FETCH_ASSOC);
} catch (Exception $e) {
    // Tabla promociones aún no migrada → seguimos sin descuento
    error_log('[WOMPI][PROMO] tabla no disponible: ' . $e->getMessage());
    $candidatas = [];
}

if (!empty($candidatas)) {
    foreach ($candidatas as $c) {
        // El código ingresado (si vino) tiene prioridad; si no, banner automático.
        if ($c['tipo'] === 'codigo' && $promoCodeInput !== '') {
            $promoAplicada = $c;
            $promoOrigen   = 'codigo';
            break; // código válido encontrado
        }
        if ($c['tipo'] === 'banner') {
            $promoAplicada = $c;
            $promoOrigen   = 'banner';
            break; // ya venían ordenadas por mayor descuento
        }
    }
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
   CONSUMO ATÓMICO DEL CUPO PROMOCIONAL (v1.7.0)
   Se hace DESPUÉS de validar usuario y plan (nunca se quema un cupo
   si el pago no va a crearse). Protegido contra carrera: el UPDATE
   solo incrementa si sigue habiendo cupo y vigencia.
   ======================= */
if ($promoAplicada !== null) {
    $stmt = $conexion->prepare("
        UPDATE promociones
        SET usos = usos + 1
        WHERE id = :id AND activo = 1
          AND NOW() BETWEEN fecha_inicio AND fecha_fin
          AND (max_usos IS NULL OR usos < max_usos)
    ");
    $stmt->execute([':id' => (int)$promoAplicada['id']]);
    if ($stmt->rowCount() === 0) {
        // Otro usuario consumió el último cupo justo ahora → sin promo
        $promoAplicada = null;
        $promoOrigen   = null;
    }
}

/* =======================
   DATOS DE PAGO (con descuento si hay promo v1.7.0)
   ======================= */
$precioBase = (int)$plan['price'];
$currency   = $plan['currency'];
$price      = $precioBase;

$descuentoInfo = null;
if ($promoAplicada !== null) {
    $valor = (float)$promoAplicada['descuento_valor'];
    if ($promoAplicada['descuento_tipo'] === 'porcentaje') {
        $valor = max(0, min(100, $valor));
        $price = (int)round($precioBase * (1 - $valor / 100));
    } else { // monto fijo COP
        $price = (int)round($precioBase - $valor);
    }
    // Wompi exige mínimo ~$1.000 COP + no regalamos premium gratis
    if ($price < 1000) {
        $price = 1000;
    }
    $descuentoInfo = [
        'id'              => (int)$promoAplicada['id'],
        'titulo'          => (string)$promoAplicada['titulo'],
        'origen'          => $promoOrigen,
        'tipo'            => (string)$promoAplicada['descuento_tipo'],
        'valor'           => (float)$promoAplicada['descuento_valor'],
        'precio_base'     => $precioBase,
        'precio_final'    => $price,
    ];
}

$amountInCents = $price * 100;

// Reference limpia (Wompi-safe)
$reference = preg_replace('/\s+/', '_', strtoupper($plan['name']))
    . '_' . $moodleUserId
    . '_' . time();

$reference = preg_replace('/[^A-Z0-9_]/', '', $reference);

/* =======================
   INSERT PAYMENT
   (amount = precio FINAL con descuento → el webhook de Wompi valida
    contra este valor y cuadra sin cambios; promo_id deja auditoría)
   ======================= */
$stmt = $conexion->prepare("
    INSERT INTO payments
    (user_id, reference_code, amount, currency, status, gateway, promo_id)
    VALUES (:u, :r, :a, :c, 'pending', 'wompi', :promo)
");

try {
    $stmt->execute([
        ':u'     => $moodleUserId,
        ':r'     => $reference,
        ':a'     => $price,
        ':c'     => $currency,
        ':promo' => $promoAplicada !== null ? (int)$promoAplicada['id'] : null,
    ]);
} catch (Exception $e) {
    // Columna promo_id aún no migrada → reintento sin promo_id
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
}

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
if ($promoAplicada !== null) {
    error_log("Promo aplicada (#{$promoAplicada['id']} {$promoAplicada['titulo']} via $promoOrigen): "
        . "$precioBase -> $price COP");
}
error_log("Full URL: $checkoutUrl");

/* =======================
   RESPUESTA
   ======================= */
$respuesta = [
    'status'        => 'ok',
    'checkout_url'  => $checkoutUrl,
    'reference'     => $reference,
    'plan' => [
        'id'        => $plan['id'],
        'name'      => $plan['name'],
        'price'     => $price,
        'currency'  => $currency,
    ],
];
if ($descuentoInfo !== null) {
    $respuesta['descuento'] = $descuentoInfo;
}
if ($promoCodeInput !== '' && $promoOrigen !== 'codigo') {
    $respuesta['promo_code_invalido'] = true;
    $respuesta['promo_code_msg'] = 'El código no es válido o ya venció. '
        . ($descuentoInfo !== null ? 'Aplicamos la promo vigente.' : 'Continúa sin descuento.');
}
echo json_encode($respuesta, JSON_UNESCAPED_UNICODE);