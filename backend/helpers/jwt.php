<?php
/**
 * helpers/jwt.php
 * Implementación mínima de JWT (HS256) sin dependencias externas.
 *
 * Compatible con cualquier PHP 7.4+/8.x con openssl instalado.
 */

declare(strict_types=1);

function base64url_encode(string $data): string
{
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

function base64url_decode(string $data): string
{
    $pad = strlen($data) % 4;
    if ($pad) {
        $data .= str_repeat('=', 4 - $pad);
    }
    return base64_decode(strtr($data, '-_', '+/'));
}

/**
 * Crea un JWT firmado con HS256.
 */
function jwt_create(array $payload): string
{
    $header = ['alg' => 'HS256', 'typ' => 'JWT'];

    $payload = array_merge([
        'iss' => JWT_ISS,
        'aud' => JWT_AUD,
        'iat' => time(),
        'exp' => time() + (JWT_EXP_HOURS * 3600),
    ], $payload);

    $segments = [];
    $segments[] = base64url_encode(json_encode($header, JSON_UNESCAPED_UNICODE));
    $segments[] = base64url_encode(json_encode($payload, JSON_UNESCAPED_UNICODE));
    $signing_input = implode('.', $segments);

    $signature = hash_hmac('sha256', $signing_input, JWT_SECRET, true);
    $segments[] = base64url_encode($signature);

    return implode('.', $segments);
}

/**
 * Verifica un JWT. Devuelve el payload o lanza exception.
 */
function jwt_verify(?string $token): array
{
    if (!$token) {
        throw new RuntimeException('Token no proporcionado.', 401);
    }
    $parts = explode('.', $token);
    if (count($parts) !== 3) {
        throw new RuntimeException('Token mal formado.', 401);
    }
    [$header_b64, $payload_b64, $signature_b64] = $parts;

    // Verificar firma
    $expected = hash_hmac('sha256', "$header_b64.$payload_b64", JWT_SECRET, true);
    $actual = base64url_decode($signature_b64);
    if (!hash_equals($expected, $actual)) {
        throw new RuntimeException('Firma inválida.', 401);
    }

    $payload = json_decode(base64url_decode($payload_b64), true);
    if (!is_array($payload)) {
        throw new RuntimeException('Payload inválido.', 401);
    }

    // Verificar expiración
    if (isset($payload['exp']) && time() >= (int)$payload['exp']) {
        throw new RuntimeException('Token expirado.', 401);
    }
    if (isset($payload['iss']) && $payload['iss'] !== JWT_ISS) {
        throw new RuntimeException('Issuer inválido.', 401);
    }

    return $payload;
}

/**
 * Extrae el Bearer token del header Authorization.
 */
function jwt_from_header(): ?string
{
    $headers = function_exists('getallheaders') ? getallheaders() : [];
    $headers = array_change_key_case($headers, CASE_LOWER);
    if (!empty($headers['authorization'])) {
        if (preg_match('/Bearer\s+(.+)/i', $headers['authorization'], $m)) {
            return trim($m[1]);
        }
    }
    // Fallback para Apache sin getallheaders
    if (isset($_SERVER['HTTP_AUTHORIZATION'])) {
        if (preg_match('/Bearer\s+(.+)/i', $_SERVER['HTTP_AUTHORIZATION'], $m)) {
            return trim($m[1]);
        }
    }
    return null;
}

/**
 * Requiere autenticación. Devuelve payload del usuario o envía 401.
 */
function require_auth(): array
{
    try {
        $payload = jwt_verify(jwt_from_header());
        if (empty($payload['sub'])) {
            send_error('Token sin subject.', 'AUTH_INVALID', 401);
        }
        return $payload;
    } catch (RuntimeException $e) {
        send_error($e->getMessage(), 'AUTH_FAILED', 401);
    }
}

/**
 * Requiere autenticación Y rol específico.
 */
function require_role(string ...$roles): array
{
    $payload = require_auth();
    $userRole = $payload['role'] ?? '';
    if (!in_array($userRole, $roles, true)) {
        send_error('No tiene permisos para esta acción.', 'FORBIDDEN', 403);
    }
    return $payload;
}
