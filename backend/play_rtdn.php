<?php
declare(strict_types=1);

/**
 * play_rtdn.php — Webhook de Real-Time Developer Notifications (RTDN) de
 * Google Play Pub/Sub (Saber+ v1.7.0).
 *
 * Google Play publica los cambios de ciclo de vida de las suscripciones en
 * un topic Pub/Sub; aquí llega el PUSH de ese topic.
 *
 * Seguridad:
 *   - NO es un endpoint público de navegador: sin CORS.
 *   - Se valida la cabecera X-Internal-Token contra env('INTERNAL_TOKEN')
 *     (la misma que usan los crons). Pub/Sub la envía configurada en el
 *     push endpoint. Fail → 403.
 *
 * Body (push de Pub/Sub):
 *   { "message": { "data": "<base64 JSON>", "messageId": "...", ... }, ... }
 *   El JSON decodificado puede traer:
 *     - subscriptionNotification { purchaseToken, subscriptionId, eventType, ... }
 *     - oneTimeProductNotification { purchaseToken, sku/productId, type } (lifetime)
 *     - voidedPurchaseNotification { purchaseToken, orderId, ... }
 *
 * eventType (subscriptionNotification.notificationType):
 *   1 RECOVERED, 2 RENEWED, 3 CANCELED, 4 EXPIRED, 5 ON_HOLD, 6 GRACE,
 *   7 PAUSED, 8 RESTARTED, 11 REVOKED, 12 PRICE_CHANGE_CONFIRMED, ...
 *
 * DECISIÓN v1 (documentada):
 *   - RENEWED / RECOVERED / RESTARTED (+ PURCHASED de inapp) → re-verificar
 *     el token contra Google (MISMA lógica que verify_play_purchase.php vía
 *     includes/google_play_verify.php), actualizar play_purchases, insertar
 *     el pago de la renovación y mantener premium.
 *   - CANCELED / EXPIRED / ON_HOLD / PAUSED / REVOKED → solo actualizar
 *     `state` en play_purchases. NO se degrada access_level en v1:
 *     hay usuarios lifetime (inapp) que nunca expiran, tolerancia de gracia
 *     y riesgo de falsos negativos transitorios. El downgrade real se
 *     hará en v2 con un cron que compare expiry_time contra NOW().
 *   - voidedPurchase (reembolso/anulación) → marcar state='VOIDED' en
 *     play_purchases y log; tampoco se degrada en v1 (misma decisión).
 *
 * Respuesta: SIEMPRE 200 rápido (Pub/Sub reintenta con backoff agresivo
 * cualquier cosa que no sea 200; no queremos tormentas de reintentos).
 */

error_reporting(E_ALL);
ini_set('log_errors', '1');
ini_set('display_errors', '0');

header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
}

require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/includes/google_play_verify.php';

/* ── 1. Token interno (fail 403) ── */
$expectedToken = env('INTERNAL_TOKEN');
$allHeaders = function_exists('getallheaders') ? getallheaders() : [];
$receivedToken = (string)($allHeaders['X-Internal-Token']
    ?? $allHeaders['x-internal-token']
    ?? $_SERVER['HTTP_X_INTERNAL_TOKEN']
    ?? '');

if ($expectedToken === null || $expectedToken === '' || !hash_equals($expectedToken, (string)$receivedToken)) {
    error_log('[PLAY_RTDN] Rechazado: X-Internal-Token inválido o ausente');
    http_response_code(403);
    exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
}

/* ── 2. Decodificar el envelope de Pub/Sub ── */
$raw  = file_get_contents('php://input');
$env  = json_decode((string)$raw, true);

if (!is_array($env) || !isset($env['message']['data'])) {
    // Estructura inesperada: 200 para que Pub/Sub no reintente infinitamente.
    error_log('[PLAY_RTDN] Envelope Pub/Sub inválido: ' . substr((string)$raw, 0, 300));
    exit(json_encode(['status' => 'ok', 'msg' => 'Envelope ignorado']));
}

$notification = json_decode((string)base64_decode((string)$env['message']['data']), true);
$messageId    = (string)($env['message']['messageId'] ?? '');

if (!is_array($notification)) {
    error_log('[PLAY_RTDN] data base64 no es JSON válido');
    exit(json_encode(['status' => 'ok', 'msg' => 'Notificación ignorada']));
}

error_log("[PLAY_RTDN] Notificación recibida (msgId={$messageId}): "
    . substr((string)json_encode($notification, JSON_UNESCAPED_SLASHES), 0, 500));

/* ── 3. subscriptionNotification ── */
if (isset($notification['subscriptionNotification'])
    && is_array($notification['subscriptionNotification'])
) {
    $sub   = $notification['subscriptionNotification'];
    $token = (string)($sub['purchaseToken'] ?? '');
    $type  = (int)($sub['eventType'] ?? $sub['notificationType'] ?? 0);

    if ($token === '') {
        exit(json_encode(['status' => 'ok', 'msg' => 'Sin purchaseToken']));
    }

    // Tipos que implican derecho/renovación → re-verificar con Google.
    $reverifyTypes = [
        1, // RECOVERED
        2, // RENEWED
        8, // RESTARTED (reactivación tras pausa)
    ];
    // Tipos que solo actualizan estado (v1: sin downgrade).
    $stateOnlyMap = [
        3  => 'SUBSCRIPTION_STATE_PENDING_CANCEL', // CANCELED (renovación cancelada)
        4  => 'SUBSCRIPTION_STATE_EXPIRED',        // EXPIRED
        5  => 'SUBSCRIPTION_STATE_ON_HOLD',        // ON_HOLD
        6  => 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',// GRACE
        7  => 'SUBSCRIPTION_STATE_PAUSED',         // PAUSED
        11 => 'REVOKED',                           // REVOKED
    ];

    if (in_array($type, $reverifyTypes, true)) {
        play_rtdn_reverify($conexion, $token, 'subscription', $type);
        exit(json_encode(['status' => 'ok', 'msg' => 'Re-verificado']));
    }

    if (isset($stateOnlyMap[$type])) {
        play_rtdn_update_state($conexion, $token, $stateOnlyMap[$type]);
        exit(json_encode(['status' => 'ok', 'msg' => 'Estado actualizado']));
    }

    // Otros tipos (cambios de precio, deferred, test...) → ack silencioso.
    exit(json_encode(['status' => 'ok', 'msg' => 'EventType ' . $type . ' sin acción v1']));
}

/* ── 4. oneTimeProductNotification (producto único: lifetime) ── */
if (isset($notification['oneTimeProductNotification'])
    && is_array($notification['oneTimeProductNotification'])
) {
    $one   = $notification['oneTimeProductNotification'];
    $token = (string)($one['purchaseToken'] ?? '');
    // type 1 = PURCHASED, 2 = CANCELED (one-time).
    $type  = (int)($one['type'] ?? 0);

    if ($token === '') {
        exit(json_encode(['status' => 'ok', 'msg' => 'Sin purchaseToken']));
    }

    if ($type === 1) {
        // Solo re-verificar si ya conocemos la compra (el app la verifica en
        // su momento con el product_id; aquí puede no venir el producto).
        $stmt = $conexion->prepare("
            SELECT product_id FROM play_purchases WHERE purchase_token = :token LIMIT 1
        ");
        $stmt->execute([':token' => $token]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            play_rtdn_reverify($conexion, $token, 'inapp', $type, (string)$row['product_id']);
        } else {
            error_log('[PLAY_RTDN] oneTimeProduct PURCHASED sin registro previo (token desconocido)');
        }
        exit(json_encode(['status' => 'ok', 'msg' => 'One-time procesado']));
    }

    play_rtdn_update_state($conexion, $token, 'ONE_TIME_CANCELED');
    exit(json_encode(['status' => 'ok', 'msg' => 'One-time actualizado']));
}

/* ── 5. voidedPurchaseNotification (reembolso / anulación) ── */
if (isset($notification['voidedPurchaseNotification'])
    && is_array($notification['voidedPurchaseNotification'])
) {
    $void  = $notification['voidedPurchaseNotification'];
    $token = (string)($void['purchaseToken'] ?? '');

    if ($token !== '') {
        // v1: solo dejar constancia; NO se degrada access_level desde el
        // webhook (decisión documentada arriba; v2 con cron evaluará).
        play_rtdn_update_state($conexion, $token, 'VOIDED');
    }
    exit(json_encode(['status' => 'ok', 'msg' => 'Voided registrado']));
}

/* ── 6. Cualquier otra cosa → ack rápido ── */
exit(json_encode(['status' => 'ok', 'msg' => 'Notificación no manejada v1']));

/* ═══════════════════════════════════════════
   Helpers
   ═══════════════════════════════════════════ */

/**
 * Re-verifica un purchaseToken contra Google (misma lógica que
 * verify_play_purchase.php) y aplica los efectos: play_purchases +
 * payments (renovación) + premium.
 *
 * $productId solo es obligatorio para 'inapp' (el endpoint de Google lo
 * necesita); para 'subscription' basta el token.
 */
function play_rtdn_reverify(PDO $conexion, string $token, string $purchaseType, int $eventType, ?string $productId = null): void
{
    // Buscar el user_id por play_purchases (para renovaciones de suscripción
    // el usuario no está logueado en este contexto).
    $stmt = $conexion->prepare("
        SELECT user_id, product_id FROM play_purchases WHERE purchase_token = :token LIMIT 1
    ");
    $stmt->execute([':token' => $token]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        error_log("[PLAY_RTDN] Token desconocido, no se puede re-verificar (eventType={$eventType})");
        return;
    }

    $userId     = (int)$row['user_id'];
    $effectiveProductId = $productId ?? (string)$row['product_id'];

    // Si la pasarela aún no está configurada (p. ej. pruebas del webhook),
    // no romper: registrar y salir.
    if (google_play_sa_json() === null) {
        error_log('[PLAY_RTDN] GOOGLE_PLAY_SA_JSON ausente; re-verificación omitida');
        return;
    }

    $result = google_play_fetch_purchase($effectiveProductId, $token, $purchaseType);
    if (!$result['ok']) {
        error_log('[PLAY_RTDN] Google rechazó la consulta: HTTP ' . $result['http']);
        return; // 200 igualmente (Pub/Sub no debe martillar).
    }

    $evaluation = google_play_evaluate_purchase($result['body'], $purchaseType);
    $state  = $evaluation['state'];
    $expirySql = $evaluation['expiry'] instanceof DateTime
        ? $evaluation['expiry']->format('Y-m-d H:i:s')
        : null;
    $rawResponse = substr((string) json_encode($result['body'], JSON_UNESCAPED_SLASHES), 0, 60000);

    // Actualizar el registro de la compra (el token ya existe → UPDATE).
    $stmt = $conexion->prepare("
        UPDATE play_purchases
        SET state = :state,
            expiry_time = COALESCE(:expiry, expiry_time),
            raw_response = :raw
        WHERE purchase_token = :token
    ");
    $stmt->execute([
        ':state'  => $state,
        ':expiry' => $expirySql,
        ':raw'    => $rawResponse,
        ':token'  => $token,
    ]);

    if (!$evaluation['valid']) {
        // Sin derecho tras re-verificar: NO degradar en v1 (documentado).
        error_log("[PLAY_RTDN] Re-verificación sin derecho: user={$userId} state={$state}");
        return;
    }

    // Pago de la renovación: referencia determinística por token+expiry para
    // no colisionar con el pago original (que usa solo el token) ni duplicar
    // la misma renovación si Pub/Sub reenvía el evento.
    $referenceCode = 'play_' . substr(sha1($token . '|' . (string)$expirySql), 0, 24);

    $amount = 0;
    try {
        $planLike = str_ends_with($effectiveProductId, 'monthly') ? '%monthly%'
            : (str_ends_with($effectiveProductId, 'annual') ? '%annual%' : '%lifetime%');
        $stmt = $conexion->prepare("
            SELECT price FROM plans WHERE code LIKE :code AND is_active = 1 ORDER BY id ASC LIMIT 1
        ");
        $stmt->execute([':code' => $planLike]);
        $plan = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($plan) {
            $amount = (int)$plan['price'];
        }
    } catch (Exception $e) {
        error_log('[PLAY_RTDN] Precio del plan no mapeable: ' . $e->getMessage());
    }

    try {
        $stmt = $conexion->prepare("
            INSERT INTO payments
                (user_id, reference_code, amount, currency, status, gateway)
            VALUES
                (:uid, :ref, :amount, 'COP', 'approved', 'play_billing')
        ");
        $stmt->execute([
            ':uid'    => $userId,
            ':ref'    => $referenceCode,
            ':amount' => $amount,
        ]);
    } catch (Exception $e) {
        error_log('[PLAY_RTDN] INSERT payments omitido (probable duplicado): ' . $e->getMessage());
    }

    // Mantener premium (idempotente).
    $stmt = $conexion->prepare("
        UPDATE usuarios SET access_level = 'premium', unlocked_at = NOW()
        WHERE moodle_id = :mid
    ");
    $stmt->execute([':mid' => $userId]);

    error_log("[PLAY_RTDN] Re-verificación OK: user={$userId} state={$state}");
}

/**
 * Actualiza solo el estado de la compra en play_purchases.
 * v1: NUNCA degrada access_level (decisión documentada en la cabecera).
 */
function play_rtdn_update_state(PDO $conexion, string $token, string $state): void
{
    try {
        $stmt = $conexion->prepare("
            UPDATE play_purchases SET state = :state WHERE purchase_token = :token
        ");
        $stmt->execute([':state' => $state, ':token' => $token]);

        if ($stmt->rowCount() === 0) {
            error_log("[PLAY_RTDN] Token desconocido al actualizar estado ({$state})");
        } else {
            error_log("[PLAY_RTDN] Estado actualizado a {$state} (sin downgrade en v1)");
        }
    } catch (Exception $e) {
        error_log('[PLAY_RTDN] Error actualizando estado: ' . $e->getMessage());
    }
}
