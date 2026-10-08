<?php
declare(strict_types=1);

/**
 * verify_play_purchase.php — Verificación server-side de compras de
 * Google Play Billing (Saber+ v1.7.0).
 *
 * Patrón: igual que upgrade_to_premium.php (CORS + JSON + JWT obligatorio),
 * pero la "referencia" aquí es un purchaseToken de Google Play que se
 * verifica EN VIVO contra la Google Play Android Developer API v3.
 *
 * ⚠️ NUNCA confiar en el cliente: el app envía product_id + purchase_token,
 * pero la validez de la compra la decide Google, no el cliente.
 *
 * Flujo:
 *   1. JWT → moodle_id del usuario.
 *   2. Input: product_id y purchase_token (obligatorios), order_id (opcional).
 *   3. Tipo: product_id que termina en 'lifetime' → inapp; si no, subscription.
 *   4. Idempotencia: si el token ya está en play_purchases para este usuario
 *      y en estado con derecho → responder ok sin duplicar nada.
 *   5. Verificar contra Google (includes/google_play_verify.php):
 *        subscription → purchases/subscriptionsv2/tokens/{token}
 *        inapp        → purchases/products/{product_id}/tokens/{token}
 *   6. Registrar en play_purchases + payments y activar premium.
 *
 * Respuesta ok: {status:'ok', access_level:'premium', msg:'...'}
 *
 * Errores:
 *   401 token JWT inválido | 400 input inválido
 *   402 Google no pudo verificar la compra / estado sin derecho
 *   403 el purchaseToken pertenece a otra cuenta
 *   503 pasarela móvil aún no configurada (falta GOOGLE_PLAY_SA_JSON)
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

/* ── 1. Autenticación JWT (bloque copiado de upgrade_to_premium.php) ── */
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
$purchaseType = google_play_purchase_type_for($productId); // 'inapp' | 'subscription'

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

/* ── 5. Idempotencia: ¿compra ya registrada? ── */
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

    // Estados con derecho (compras verificadas antes, activas o vitalicias).
    $estadosValidos = [
        'PURCHASED',
        'SUBSCRIPTION_STATE_ACTIVE',
        'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
        'SUBSCRIPTION_STATE_PROMOTION',
        'SUBSCRIPTION_STATE_PENDING_CANCEL',
    ];
    if (in_array((string)$existing['state'], $estadosValidos, true)) {
        // Auto-sanar el access_level (p. ej. compra verificada pero UPDATE
        // posterior falló): es idempotente y no duplica nada.
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
    // Si el estado registrado NO da derecho, cae abajo a re-verificar con
    // Google (p. ej. estaba ON_HOLD y el usuario ya pagó de nuevo).
}

/* ── 6. Verificación contra Google (NUNCA confiar en el cliente) ── */
$result = google_play_fetch_purchase($productId, $purchaseToken, $purchaseType);

if (!$result['ok']) {
    // OAuth2 roto, red caída o HTTP != 200 (404 token inexistente, 401 SA sin
    // permisos, etc.). Ya se error_log-eó el body (substr 500) en el helper.
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
$expiry = $evaluation['expiry']; // ?DateTime (UTC) — null para inapp
$expirySql = $expiry instanceof DateTime ? $expiry->format('Y-m-d H:i:s') : null;
$rawResponse = substr((string) json_encode($result['body'], JSON_UNESCAPED_SLASHES), 0, 60000);

/* ── 7. Registrar en play_purchases (idempotente por purchase_token) ── */
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

/* ── 8. Registrar en payments (referencia determinística por token) ── */
$referenceCode = 'play_' . substr(sha1($purchaseToken), 0, 24);

// Monto: mapear el product_id de Play al plan de la BD (web/Wompi) para
// reportería. Si no hay match, amount 0 (la compra ya fue validada por Google).
$amount = 0;
try {
    $planLike = str_ends_with($productId, 'monthly') ? '%monthly%'
        : (str_ends_with($productId, 'annual') ? '%annual%' : '%lifetime%');
    $stmt = $conexion->prepare("
        SELECT price FROM plans
        WHERE code LIKE :code AND is_active = 1
        ORDER BY id ASC LIMIT 1
    ");
    $stmt->execute([':code' => $planLike]);
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
    // Duplicado (reference_code ya existe) → idempotencia: no es error fatal.
    error_log('[VERIFY_PLAY] INSERT payments omitido (probable duplicado): ' . $e->getMessage());
}

/* ── 9. Activar premium (idempotente, igual que upgrade_to_premium.php) ── */
$stmt = $conexion->prepare("
    UPDATE usuarios
    SET access_level = 'premium',
        unlocked_at = NOW()
    WHERE moodle_id = :mid
");
$stmt->execute([':mid' => $moodleUserId]);

if ($stmt->rowCount() === 0) {
    // Puede que ya fuera premium (UPDATE idéntico) — verificar estado real.
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
