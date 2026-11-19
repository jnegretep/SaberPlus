<?php
declare(strict_types=1);

/**
 * verify_play_purchase.php — Verificación server-side de compras de
 * Google Play Billing (Saber+ v2.3).
 *
 * FIX v2.3: 
 *  - Se usa la columna 'is_active' (no 'activo') para mapear el plan.
 *  - Se usa la columna 'play_product_id' para buscar el precio exacto,
 *    evitando hacer un LIKE frágil.
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
require __DIR__ . '/includes/google_play_verify.php';
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

/* ── 2. Input JSON ── */
$data = json_decode(file_get_contents('php://input'), true) ?? [];

$productId     = preg_replace('/[^A-Za-z0-9._\-]/', '', (string)($data['product_id'] ?? ''));
$purchaseToken = trim((string)($data['purchase_token'] ?? ''));
$orderId       = substr(trim((string)($data['order_id'] ?? '')), 0, 190);

if ($productId === '' || $purchaseToken === '') {
    http_response_code(400);
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'Se requieren product_id y purchase_token de Google Play.',
    ]));
}
if (strlen($purchaseToken) > 512) {
    $purchaseToken = substr($purchaseToken, 0, 512);
}

/* ── 3. Tipo de compra ── */
$purchaseType = google_play_purchase_type_for($productId);

/* ── 4. ¿Pasarela configurada? ── */
if (google_play_sa_json() === null) {
    error_log('[VERIFY_PLAY] GOOGLE_PLAY_SA_JSON ausente — pasarela móvil no configurada');
    http_response_code(503);
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'Pasarela de pagos móvil aún no configurada (GOOGLE_PLAY_SA_JSON). '
                  . 'Sigue docs/PLAY_BILLING_SETUP.md',
    ]));
}

/* ── 5. Idempotencia ── */
$stmt = $conexion->prepare("
    SELECT id, user_id, state, expiry_time
    FROM play_purchases
    WHERE purchase_token = :token
    LIMIT 1
");
$stmt->execute([':token' => $purchaseToken]);
$existing = $stmt->fetch(PDO::FETCH_ASSOC);

if ($existing) {
    if ((int)$existing['user_id'] !== $moodleUserId) {
        error_log("[VERIFY_PLAY] Token de otra cuenta: user={$moodleUserId} owner={$existing['user_id']}");
        http_response_code(403);
        exit(json_encode([
            'status' => 'error',
            'msg'    => 'Esta compra está asociada a otra cuenta. Usa la cuenta con la que compraste.',
        ]));
    }

    $estadosValidos = [
        'PURCHASED',
        'SUBSCRIPTION_STATE_ACTIVE',
        'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
        'SUBSCRIPTION_STATE_PROMOTION',
        'SUBSCRIPTION_STATE_PENDING_CANCEL',
    ];
    if (in_array((string)$existing['state'], $estadosValidos, true)) {
        $stmt = $conexion->prepare("
            UPDATE usuarios SET access_level = 'premium', unlocked_at = NOW()
            WHERE moodle_id = :mid
        ");
        $stmt->execute([':mid' => $moodleUserId]);

        exit(json_encode([
            'status'       => 'ok',
            'access_level' => 'premium',
            'msg'          => 'Cuenta verificada como PREMIUM',
        ]));
    }
}

/* ── 6. Verificación contra Google ── */
$result = google_play_fetch_purchase($productId, $purchaseToken, $purchaseType);

if (!$result['ok']) {
    http_response_code(402);
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'La compra no pudo verificarse con Google. Intenta de nuevo en unos minutos.',
    ]));
}

$evaluation = google_play_evaluate_purchase($result['body'], $purchaseType);

if (!$evaluation['valid']) {
    error_log('[VERIFY_PLAY] Compra sin derecho: product=' . $productId
        . ' state=' . $evaluation['state'] . ' reason=' . ($evaluation['reason'] ?? '?'));
    http_response_code(402);
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'La compra no está activa en Google Play ('
                  . $evaluation['state'] . '). Si ya pagaste, espera la confirmación o contacta a soporte.',
    ]));
}

$state  = $evaluation['state'];
$expiry = $evaluation['expiry'];
$expirySql = $expiry instanceof DateTime ? $expiry->format('Y-m-d H:i:s') : null;
$rawResponse = substr((string) json_encode($result['body'], JSON_UNESCAPED_SLASHES), 0, 60000);

/* ── 7. Registrar en play_purchases ── */
$stmt = $conexion->prepare("
    INSERT INTO play_purchases
        (user_id, product_id, purchase_token, order_id, purchase_type, state, expiry_time, raw_response)
    VALUES
        (:uid, :pid, :token, :oid, :ptype, :state, :expiry, :raw)
    ON DUPLICATE KEY UPDATE
        state        = VALUES(state),
        expiry_time  = VALUES(expiry_time),
        raw_response = VALUES(raw_response),
        order_id     = IFNULL(VALUES(order_id), order_id)
");
$stmt->execute([
    ':uid'    => $moodleUserId,
    ':pid'    => $productId,
    ':token'  => $purchaseToken,
    ':oid'    => $orderId !== '' ? $orderId : null,
    ':ptype'  => $purchaseType,
    ':state'  => $state,
    ':expiry' => $expirySql,
    ':raw'    => $rawResponse,
]);

/* ── 8. Registrar en payments ── */
$referenceCode = 'play_' . substr(sha1($purchaseToken), 0, 24);

$amount = 0;
try {
    // ✅ FIX: Buscar por play_product_id (exacto) o por code (fallback)
    $stmt = $conexion->prepare("
        SELECT price FROM plans
        WHERE is_active = 1 
          AND (play_product_id = :pid OR code LIKE :code)
        ORDER BY id ASC LIMIT 1
    ");
    
    $planLike = str_ends_with($productId, 'monthly') ? '%monthly%'
        : (str_ends_with($productId, 'annual') ? '%annual%' : '%lifetime%');
        
    $stmt->execute([':pid' => $productId, ':code' => $planLike]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($row) {
        $amount = (int)$row['price'];
    }
} catch (Exception $e) {
    error_log('[VERIFY_PLAY] No se pudo mapear precio del plan: ' . $e->getMessage());
}

try {
    $stmt = $conexion->prepare("
        INSERT INTO payments
            (user_id, reference_code, amount, currency, status, gateway)
        VALUES
            (:uid, :ref, :amount, 'COP', 'approved', 'play_billing')
    ");
    $stmt->execute([
        ':uid'    => $moodleUserId,
        ':ref'    => $referenceCode,
        ':amount' => $amount,
    ]);
} catch (Exception $e) {
    error_log('[VERIFY_PLAY] INSERT payments omitido (probable duplicado): ' . $e->getMessage());
}

/* ── 9. Activar premium ── */
$stmt = $conexion->prepare("
    UPDATE usuarios
    SET access_level = 'premium',
        unlocked_at = NOW()
    WHERE moodle_id = :mid
");
$stmt->execute([':mid' => $moodleUserId]);

if ($stmt->rowCount() === 0) {
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
    'status'       => 'ok',
    'access_level' => 'premium',
    'msg'          => 'Cuenta verificada como PREMIUM',
]);