<?php
declare(strict_types=1);

/**
 * includes/google_play_verify.php — Helper compartido de verificación
 * server-side contra la Google Play Android Developer API v3.
 *
 * Lo usan:
 *   - verify_play_purchase.php  (compra desde el app Android, con JWT)
 *   - play_rtdn.php             (webhook Pub/Sub para renovaciones)
 *
 * ⚠️ NUNCA confiar en el cliente: la compra SIEMPRE se consulta a Google
 * antes de activar premium. El purchaseToken que envía el app solo sirve
 * para IDENTIFICAR la compra; su validez la decide Google.
 *
 * Requiere en backend/.env (ver docs/PLAY_BILLING_SETUP.md):
 *   GOOGLE_PLAY_PACKAGE_NAME  → default 'com.saberplus.app'
 *   GOOGLE_PLAY_SA_JSON       → JSON COMPLETO de la service account
 *                               (una sola línea, con comillas escapadas)
 *
 * Flujo OAuth2 service account (sin SDK de Google, solo openssl + cURL):
 *   1. Construir un JWT (header RS256 + claims iss/scope/aud/exp/iat).
 *   2. Firmarlo con la private_key de la service account (openssl_sign SHA256).
 *   3. POST a https://oauth2.googleapis.com/token con
 *      grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer → access_token.
 *   4. El access_token se cachea en /tmp/saberplus_gplay_token.json por
 *      50 minutos (escritura atómica) — los tokens de Google viven 3600 s.
 */

require_once __DIR__ . '/../env.php';

const GOOGLE_PLAY_OAUTH_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const GOOGLE_PLAY_SCOPE           = 'https://www.googleapis.com/auth/androidpublisher';
const GOOGLE_PLAY_API_BASE        = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications';
const GOOGLE_PLAY_TOKEN_CACHE     = '/tmp/saberplus_gplay_token.json';
const GOOGLE_PLAY_TOKEN_TTL       = 3000; // 50 minutos (< 3600 s de vida real)

/* ─────────────────────────────────────────────
   Configuración
   ───────────────────────────────────────────── */

function google_play_package_name(): string
{
    return env('GOOGLE_PLAY_PACKAGE_NAME', 'com.saberplus.app');
}

/**
 * Decodifica GOOGLE_PLAY_SA_JSON. Retorna null si no está configurada
 * o el JSON no tiene client_email / private_key.
 */
function google_play_sa_json(): ?array
{
    $raw = env('GOOGLE_PLAY_SA_JSON');
    if ($raw === null || trim($raw) === '') {
        return null;
    }
    $sa = json_decode($raw, true);
    if (!is_array($sa) || empty($sa['client_email']) || empty($sa['private_key'])) {
        return null;
    }
    return $sa;
}

/* ─────────────────────────────────────────────
   OAuth2 service account
   ───────────────────────────────────────────── */

/** Codifica en base64url (JWT). */
function google_play_b64url(string $data): string
{
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

/**
 * Obtiene (y cachea) un access_token de service account.
 * Lanza RuntimeException con mensaje técnico si falla.
 */
function google_play_access_token(): string
{
    /* 1. Cache todavía válida (margen de 60 s). */
    if (is_readable(GOOGLE_PLAY_TOKEN_CACHE)) {
        $cache = json_decode((string) file_get_contents(GOOGLE_PLAY_TOKEN_CACHE), true);
        if (is_array($cache)
            && !empty($cache['access_token'])
            && (int) ($cache['expires_at'] ?? 0) > time() + 60
        ) {
            return (string) $cache['access_token'];
        }
    }

    $sa = google_play_sa_json();
    if ($sa === null) {
        throw new RuntimeException('GOOGLE_PLAY_SA_JSON no configurado o inválido');
    }

    /* 2. JWT de service account (RS256). */
    $now = time();
    $header  = ['alg' => 'RS256', 'typ' => 'JWT'];
    $claims  = [
        'iss'   => (string) $sa['client_email'],
        'scope' => GOOGLE_PLAY_SCOPE,
        'aud'   => GOOGLE_PLAY_OAUTH_TOKEN_URL,
        'exp'   => $now + 3600,
        'iat'   => $now,
    ];
    $unsigned = google_play_b64url((string) json_encode($header, JSON_UNESCAPED_SLASHES))
        . '.'
        . google_play_b64url((string) json_encode($claims, JSON_UNESCAPED_SLASHES));

    // La private_key del JSON viene con "\n" escapados → volver a saltos de
    // línea reales antes de pasársela a openssl.
    $privateKey = str_replace('\\n', "\n", (string) $sa['private_key']);
    $pkey = openssl_pkey_get_private($privateKey);
    if ($pkey === false) {
        throw new RuntimeException('private_key inválida en GOOGLE_PLAY_SA_JSON');
    }

    $signature = '';
    if (!openssl_sign($unsigned, $signature, $pkey, OPENSSL_ALGO_SHA256)) {
        throw new RuntimeException('No se pudo firmar el JWT de service account');
    }
    $jwt = $unsigned . '.' . google_play_b64url($signature);

    /* 3. Exchange del JWT por access_token. */
    $ch = curl_init(GOOGLE_PLAY_OAUTH_TOKEN_URL);
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT        => 30,
        CURLOPT_POSTFIELDS     => http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion'  => $jwt,
        ]),
    ]);
    $body = curl_exec($ch);
    $http = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err  = curl_error($ch);
    curl_close($ch);

    if ($body === false || $http !== 200) {
        error_log('[GOOGLE_PLAY] OAuth2 falló: HTTP ' . $http . ' curl=' . $err
            . ' body=' . substr((string) $body, 0, 300));
        throw new RuntimeException('OAuth2 de Google falló (HTTP ' . $http . ')');
    }

    $data = json_decode((string) $body, true);
    if (!is_array($data) || empty($data['access_token'])) {
        throw new RuntimeException('Respuesta OAuth2 sin access_token');
    }

    /* 4. Cachear el token (escritura atómica: tmp + rename). */
    $cache = [
        'access_token' => (string) $data['access_token'],
        'expires_at'   => time() + GOOGLE_PLAY_TOKEN_TTL,
    ];
    $tmpFile = GOOGLE_PLAY_TOKEN_CACHE . '.' . getmypid() . '.tmp';
    if (@file_put_contents($tmpFile, json_encode($cache), LOCK_EX) !== false) {
        if (!@rename($tmpFile, GOOGLE_PLAY_TOKEN_CACHE)) {
            @unlink($tmpFile);
        }
    }

    return (string) $data['access_token'];
}

/* ─────────────────────────────────────────────
   Consulta de compras a la Developer API v3
   ───────────────────────────────────────────── */

/**
 * Consulta la compra en Google Play.
 *
 * $purchaseType: 'subscription' (purchases/subscriptionsv2/tokens) o
 *                'inapp' (purchases/products/{productId}/tokens).
 *
 * Retorna: ['ok' => bool, 'http' => int, 'body' => ?array, 'error' => ?string]
 *   - ok=true  → HTTP 200 y body decodificado (o null si Google no devolvió JSON).
 *   - ok=false → error de OAuth2, de red o HTTP != 200 (ya se error_log-eó
 *                el body truncado a 500 chars).
 */
function google_play_fetch_purchase(string $productId, string $purchaseToken, string $purchaseType): array
{
    $pkg   = urlencode(google_play_package_name());
    $token = urlencode($purchaseToken);

    if ($purchaseType === 'inapp') {
        $url = GOOGLE_PLAY_API_BASE . "/{$pkg}/purchases/products/"
            . urlencode($productId) . "/tokens/{$token}";
    } else {
        $url = GOOGLE_PLAY_API_BASE . "/{$pkg}/purchases/subscriptionsv2/tokens/{$token}";
    }

    try {
        $accessToken = google_play_access_token();
    } catch (RuntimeException $e) {
        return ['ok' => false, 'http' => 0, 'body' => null, 'error' => $e->getMessage()];
    }

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT        => 30,
        CURLOPT_HTTPHEADER     => [
            'Authorization: Bearer ' . $accessToken,
            'Accept: application/json',
        ],
    ]);
    $body = curl_exec($ch);
    $http = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err  = curl_error($ch);
    curl_close($ch);

    if ($body === false) {
        error_log('[GOOGLE_PLAY] cURL falló: ' . $err);
        return ['ok' => false, 'http' => 0, 'body' => null, 'error' => 'cURL: ' . $err];
    }

    $decoded = json_decode((string) $body, true);

    if ($http !== 200) {
        error_log('[GOOGLE_PLAY] HTTP ' . $http . ' al verificar compra (' . $purchaseType . '): '
            . substr((string) $body, 0, 500));
        return ['ok' => false, 'http' => $http, 'body' => is_array($decoded) ? $decoded : null, 'error' => 'HTTP ' . $http];
    }

    return ['ok' => true, 'http' => 200, 'body' => is_array($decoded) ? $decoded : null, 'error' => null];
}

/* ─────────────────────────────────────────────
   Evaluación del payload de Google
   ───────────────────────────────────────────── */

/** Parsea un timestamp RFC3339 de Google (Z o +00:00) a DateTime UTC. */
function google_play_parse_rfc3339(?string $value): ?DateTime
{
    if ($value === null || $value === '') {
        return null;
    }
    $normalized = str_replace('Z', '+00:00', $value);
    $dt = DateTime::createFromFormat('Y-m-d\TH:i:s.uP', $normalized)
        ?: DateTime::createFromFormat('Y-m-d\TH:i:sP', $normalized);
    return $dt instanceof DateTime ? $dt : null;
}

/**
 * Evalúa el payload de Google y decide si la compra da derecho a premium.
 *
 * Retorna: ['valid' => bool, 'state' => string, 'expiry' => ?DateTime, 'reason' => ?string]
 *
 * - inapp (p. ej. saberplus_premium_lifetime):
 *     purchases.products → purchaseState 0 = PURCHASED.
 *     (1 = CANCELED, 2 = PENDING → sin derecho hasta confirmarse).
 *
 * - subscription (monthly/annual, subscriptionsv2):
 *     subscriptionState con derecho (activas):
 *       SUBSCRIPTION_STATE_ACTIVE               (proto 1)
 *       SUBSCRIPTION_STATE_IN_GRACE_PERIOD      (proto 2)
 *       SUBSCRIPTION_STATE_PROMOTION            (proto 3)
 *       SUBSCRIPTION_STATE_PENDING_CANCEL       (proto 4 — canceló la renovación
 *                                                pero sigue pagando hasta expiry)
 *     Sin derecho: CANCELED / EXPIRED / ON_HOLD / PAUSED / etc.
 *     La API REST devuelve el enum como STRING; por robustez también se
 *     aceptan los valores numéricos del proto (1..4).
 *     Expiry: lineItems[0].expiryTime (o expiryTime del payload).
 */
function google_play_evaluate_purchase(?array $payload, string $purchaseType): array
{
    if (!is_array($payload)) {
        return ['valid' => false, 'state' => 'INVALID_RESPONSE', 'expiry' => null,
                'reason' => 'Respuesta inválida de Google Play'];
    }

    if ($purchaseType === 'inapp') {
        $purchaseState = (int) ($payload['purchaseState'] ?? -1);
        $valid = ($purchaseState === 0); // PURCHASED
        return [
            'valid'  => $valid,
            'state'  => $valid ? 'PURCHASED' : ('purchaseState=' . $purchaseState),
            'expiry' => null,
            'reason' => $valid ? null : 'El producto único no está en estado PURCHASED',
        ];
    }

    /* ── subscription (subscriptionsv2) ── */
    $raw = $payload['subscriptionState'] ?? '';

    // Normalizar: numérico (proto) → nombre canónico; string → tal cual.
    $numericMap = [
        1 => 'SUBSCRIPTION_STATE_ACTIVE',
        2 => 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
        3 => 'SUBSCRIPTION_STATE_PROMOTION',
        4 => 'SUBSCRIPTION_STATE_PENDING_CANCEL',
    ];
    $state = is_int($raw)
        ? ($numericMap[$raw] ?? ('SUBSCRIPTION_STATE_' . $raw))
        : (string) $raw;

    $entitledStates = [
        'SUBSCRIPTION_STATE_ACTIVE',
        'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
        'SUBSCRIPTION_STATE_PROMOTION',
        'SUBSCRIPTION_STATE_PENDING_CANCEL',
    ];
    $valid = in_array($state, $entitledStates, true);

    // Expiración: preferir lineItems[0].expiryTime; fallback al del payload.
    $expiryRaw = null;
    if (!empty($payload['lineItems']) && is_array($payload['lineItems'][0])) {
        $expiryRaw = $payload['lineItems'][0]['expiryTime'] ?? null;
    }
    if ($expiryRaw === null) {
        $expiryRaw = $payload['expiryTime'] ?? null;
    }
    $expiry = google_play_parse_rfc3339($expiryRaw === null ? null : (string) $expiryRaw);

    return [
        'valid'  => $valid,
        'state'  => $state !== '' ? $state : 'SUBSCRIPTION_STATE_UNKNOWN',
        'expiry' => $expiry,
        'reason' => $valid ? null : 'La suscripción no está activa (estado: ' . $state . ')',
    ];
}

/**
 * Normaliza el tipo de compra a partir del product_id de Play.
 * Los productos que terminan en 'lifetime' son inapp; el resto, suscripción.
 */
function google_play_purchase_type_for(string $productId): string
{
    return str_ends_with($productId, 'lifetime') ? 'inapp' : 'subscription';
}
