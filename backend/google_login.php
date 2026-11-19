<?php
declare(strict_types=1);

/**
 * google_login.php - Saber+ Google Sign-In endpoint
 *
 * Recibe el `id_token` de Google (obtenido en el cliente Flutter con
 * google_sign_in), lo valida con Firebase Admin SDK y:
 *
 *  - Si el email YA existe en la BD local → genera JWT propio + refresh token
 *    y responde como login normal (status=ok, is_new_user=false).
 *  - Si el email NO existe → responde con is_new_user=true para que el
 *    frontend lleve al usuario a completar el step2 del registro. NO crea
 *    el usuario todavía (se hace en register.php cuando se completa el
 *    formulario con departamento, ciudad, colegio, grado, etc.).
 *
 * Request body (JSON):
 * {
 *   "id_token": "<google-id-token-jwt>",
 *   "email": "user@gmail.com",          // opcional, se re-valida contra el token
 *   "display_name": "John Doe",          // opcional
 *   "photo_url": "https://..."           // opcional
 * }
 *
 * Response (usuario existente):
 * {
 *   "status": "ok",
 *   "is_new_user": false,
 *   "token": "<saber-jwt>",
 *   "refresh_token": "<rt>",
 *   "expires_at": "2026-08-08T19:46:18+00:00",
 *   "user": { ... }
 * }
 *
 * Response (usuario nuevo):
 * {
 *   "status": "ok",
 *   "is_new_user": true,
 *   "google_email": "user@gmail.com",
 *   "google_name": "John Doe",
 *   "google_picture": "https://..."
 * }
 */

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';

use Kreait\Firebase\Factory;
use Kreait\Firebase\Exception\Auth\FailedToVerifyToken;

// Headers CORS y JSON
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

// 1. Leer y validar input
$input = json_decode(file_get_contents('php://input'), true) ?: [];
$idToken = trim((string)($input['id_token'] ?? ''));

if ($idToken === '') {
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'id_token requerido']));
}

// 2. Cargar credenciales de servicio de Firebase desde el archivo JSON
//    El archivo debe estar en backend/config/firebase-service-account.json
$serviceAccountPath = __DIR__ . '/config/firebase-service-account.json';
if (!file_exists($serviceAccountPath)) {
    error_log("[GOOGLE_LOGIN] No se encontró el archivo de credenciales: $serviceAccountPath");
    http_response_code(500);
    exit(json_encode([
        'status' => 'error',
        'msg' => 'Configuración del servidor incompleta (firebase credentials)'
    ]));
}

try {
    $factory = (new Factory())->withServiceAccount($serviceAccountPath);
    $auth = $factory->createAuth();

    // 3. Verificar el id_token con Firebase Admin SDK
    $verifiedToken = $auth->verifyIdToken($idToken);
    $claims = $verifiedToken->claims();

    $googleEmail = $claims->get('email', '');
    $googleName  = $claims->get('name', '');
    $googlePicture = $claims->get('picture', '');
    $googleUid = $claims->get('sub', '');
    $emailVerified = $claims->get('email_verified', false);

    if ($googleEmail === '') {
        http_response_code(400);
        exit(json_encode(['status' => 'error', 'msg' => 'El token no contiene email']));
    }

    // Opcional: si el cliente envió email, validar que coincida con el del token
    $clientEmail = trim((string)($input['email'] ?? ''));
    if ($clientEmail !== '' && strcasecmp($clientEmail, $googleEmail) !== 0) {
        error_log("[GOOGLE_LOGIN] Email mismatch: token=$googleEmail cliente=$clientEmail");
        http_response_code(400);
        exit(json_encode([
            'status' => 'error',
            'msg' => 'El email del token no coincide con el enviado'
        ]));
    }

    error_log("[GOOGLE_LOGIN] Token verificado. email=$googleEmail, uid=$googleUid, verified=$emailVerified");

} catch (FailedToVerifyToken $e) {
    error_log("[GOOGLE_LOGIN] Token inválido: " . $e->getMessage());
    http_response_code(401);
    exit(json_encode([
        'status' => 'error',
        'msg' => 'Token de Google inválido o expirado'
    ]));
} catch (Throwable $e) {
    error_log("[GOOGLE_LOGIN] Error verificando token: " . $e->getMessage());
    http_response_code(500);
    exit(json_encode([
        'status' => 'error',
        'msg' => 'Error al validar el token de Google'
    ]));
}

// 4. Buscar usuario por email en BD local
$stmt = $conexion->prepare("
    SELECT id_usuario, tipo_usuario, moodle_username, moodle_id, email_verificado,
           avatar_path, nombre
    FROM usuarios
    WHERE email = :email
    LIMIT 1
");
$stmt->execute([':email' => $googleEmail]);
$userRow = $stmt->fetch(PDO::FETCH_ASSOC);

// 5. Usuario NO existe → responder is_new_user=true
if (!$userRow) {
    error_log("[GOOGLE_LOGIN] Usuario nuevo detectado: $googleEmail");
    echo json_encode([
        'status'        => 'ok',
        'is_new_user'   => true,
        'google_email'  => $googleEmail,
        'google_name'   => $googleName,
        'google_picture'=> $googlePicture,
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

// 6. Usuario EXISTE → generar JWT propio + refresh token
$idUsuario = (int)$userRow['id_usuario'];
$tipoUsuario = $userRow['tipo_usuario'] ?: 'estudiante';
$moodleUserId = (int)($userRow['moodle_id'] ?? 0);

// Si la cuenta no estaba verificada, la marcamos como verificada
// (Google ya validó el email).
if ((int)$userRow['email_verificado'] === 0) {
    try {
        $upd = $conexion->prepare("UPDATE usuarios SET email_verificado = 1 WHERE id_usuario = ?");
        $upd->execute([$idUsuario]);
        error_log("[GOOGLE_LOGIN] Usuario $idUsuario marcado como email_verificado=1 vía Google");
    } catch (Throwable $e) {
        error_log("[GOOGLE_LOGIN] No se pudo actualizar email_verificado: " . $e->getMessage());
    }
}

// Actualizar último login
try {
    $upd = $conexion->prepare("UPDATE usuarios SET ultimo_login = NOW() WHERE id_usuario = ?");
    $upd->execute([$idUsuario]);
} catch (Throwable $e) {
    error_log("[GOOGLE_LOGIN] Error actualizando ultimo_login: " . $e->getMessage());
}

// Si el usuario no tenía avatar y Google provee uno, guardarlo
if (!empty($googlePicture) && empty($userRow['avatar_path'])) {
    try {
        $upd = $conexion->prepare("UPDATE usuarios SET avatar_path = ? WHERE id_usuario = ?");
        $upd->execute([$googlePicture, $idUsuario]);
        error_log("[GOOGLE_LOGIN] Avatar de Google guardado para usuario $idUsuario");
    } catch (Throwable $e) {
        error_log("[GOOGLE_LOGIN] No se pudo guardar avatar de Google: " . $e->getMessage());
    }
}

// Generar JWT propio
$configJwt = require __DIR__ . '/jwt_config.php';
$now = time();
$exp = $now + ($configJwt['expiry_seconds'] ?? 86400);
$jti = bin2hex(random_bytes(16));

$payload = [
    'iss' => $configJwt['issuer'],
    'aud' => $configJwt['audience'],
    'iat' => $now,
    'nbf' => $now,
    'exp' => $exp,
    'jti' => $jti,
    'data' => [
        'id_usuario'   => $idUsuario,
        'email'        => $googleEmail,
        'tipo_usuario' => $tipoUsuario,
        'moodle_userid'=> $moodleUserId,
        'auth_provider'=> 'google',
    ],
];

$appToken = JWT::encode($payload, $configJwt['secret'], 'HS256');
$refreshToken = bin2hex(random_bytes(32));

// Guardar refresh token
try {
    $rt = $conexion->prepare("
        INSERT INTO refresh_tokens (token, id_usuario, expires_at)
        VALUES (:rt, :uid, DATE_ADD(NOW(), INTERVAL 30 DAY))
    ");
    $rt->execute([':rt' => $refreshToken, ':uid' => $idUsuario]);
} catch (Throwable $e) {
    error_log("[GOOGLE_LOGIN] Error guardando refresh token: " . $e->getMessage());
}

// Obtener datos completos del usuario para devolver
try {
    $stmtUser = $conexion->prepare("
        SELECT id_usuario, email, nombre, tipo_usuario, moodle_username, moodle_id,
               avatar_path, telefono, departamento, ciudad, colegio, grado,
               email_verificado, access_level, is_early_user
        FROM usuarios
        WHERE id_usuario = :uid
    ");
    $stmtUser->execute([':uid' => $idUsuario]);
    $userData = $stmtUser->fetch(PDO::FETCH_ASSOC);

    if (!$userData) {
        throw new Exception('Usuario no encontrado tras login');
    }
} catch (Throwable $e) {
    error_log("[GOOGLE_LOGIN] Error obteniendo datos usuario: " . $e->getMessage());
    http_response_code(500);
    exit(json_encode(['status' => 'error', 'msg' => 'Error obteniendo perfil']));
}

error_log("[GOOGLE_LOGIN] Login con Google exitoso. Usuario ID=$idUsuario, tipo=$tipoUsuario");

echo json_encode([
    'status'        => 'ok',
    'is_new_user'   => false,
    'token'         => $appToken,
    'refresh_token' => $refreshToken,
    'expires_at'    => date('c', $exp),
    'user'          => $userData,
], JSON_UNESCAPED_UNICODE);
