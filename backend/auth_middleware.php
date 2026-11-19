<?php
// auth_middleware.php

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;
use Firebase\JWT\ExpiredException;
use Firebase\JWT\SignatureInvalidException;
use Firebase\JWT\BeforeValidException;

$config = require __DIR__ . '/jwt_config.php';

/**
 * Obtener encabezado Authorization
 */
function getAuthorizationHeader() {
    if (isset($_SERVER['Authorization'])) return trim($_SERVER["Authorization"]);
    if (isset($_SERVER['HTTP_AUTHORIZATION'])) return trim($_SERVER["HTTP_AUTHORIZATION"]);

    if (function_exists('apache_request_headers')) {
        $requestHeaders = apache_request_headers();
        $requestHeaders = array_change_key_case($requestHeaders, CASE_LOWER);
        if (isset($requestHeaders['authorization'])) {
            return trim($requestHeaders['authorization']);
        }
    }
    return null;
}

/**
 * Obtener token Bearer
 */
function getBearerToken() {
    $header = getAuthorizationHeader();
    if (!empty($header) && preg_match('/Bearer\s(\S+)/', $header, $matches)) {
        return $matches[1];
    }
    return null;
}

$token = getBearerToken();

if (!$token) {
    http_response_code(401);
    echo json_encode(['status' => 'error', 'msg' => 'Token no proporcionado']);
    exit;
}

/**
 * DECODIFICAR JWT CON MANEJO COMPLETO DE ERRORES
 */
try {
    $decoded = JWT::decode($token, new Key($config['secret'], 'HS256'));

} catch (ExpiredException $e) {
    http_response_code(401);
    echo json_encode(['status' => 'error', 'msg' => 'Token expirado']);
    exit;

} catch (SignatureInvalidException $e) {
    http_response_code(401);
    echo json_encode(['status' => 'error', 'msg' => 'Firma inválida']);
    exit;

} catch (BeforeValidException $e) {
    http_response_code(401);
    echo json_encode(['status' => 'error', 'msg' => 'Token aún no válido']);
    exit;

} catch (\UnexpectedValueException $e) {
    http_response_code(401);
    echo json_encode(['status' => 'error', 'msg' => 'Token malformado']);
    exit;

} catch (Exception $e) {
    http_response_code(401);
    echo json_encode(['status' => 'error', 'msg' => 'Token inválido']);
    exit;
}

/**
 * VALIDAR SI EL TOKEN FUE REVOCADO
 */
$stmt = $conexion->prepare("SELECT 1 FROM revoked_tokens WHERE jti = ? LIMIT 1");
$stmt->execute([$decoded->jti]);

if ($stmt->fetch()) {
    http_response_code(401);
    echo json_encode(['status' => 'error', 'msg' => 'Token revocado']);
    exit;
}

/**
 * EXPORTAR DATOS DEL USUARIO
 */
$GLOBALS['authUser'] = (array)$decoded->data;
$GLOBALS['currentJti'] = $decoded->jti;

error_log("[auth_middleware] Token válido, id_usuario=" . ($GLOBALS['authUser']['id_usuario'] ?? 'null'));

/**
 * Validar rol del usuario actual
 */
function requireRole($allowedRoles, $currentUser) {
    if (is_string($allowedRoles)) $allowedRoles = [$allowedRoles];
    if (!in_array($currentUser['tipo_usuario'], $allowedRoles)) {
        http_response_code(403);
        echo json_encode(['status' => 'error', 'msg' => 'Acceso denegado. Rol insuficiente']);
        exit;
    }
}
