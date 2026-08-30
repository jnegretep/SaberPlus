<?php
declare(strict_types=1);

// login.php - Optimizado y con mejor manejo de logs
// ✅ FASE 4: URLs centralizadas en includes/config.php
require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/includes/config.php';
require __DIR__ . '/includes/moodle.php';
$configJwt = require __DIR__ . '/jwt_config.php';

use Firebase\JWT\JWT;

// Headers para CORS y JSON
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

// 1. Validar input
$input = json_decode(file_get_contents('php://input'), true);
$email = trim((string)($input['email'] ?? ''));
$password = (string)($input['password'] ?? $input['contrasena'] ?? '');

if ($email === '' || $password === '') {
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'Email y contraseña requeridos']));
}

error_log("[LOGIN] Intento de login para: $email");

// 2. Buscar usuario local
$stmt = $conexion->prepare("
    SELECT id_usuario, tipo_usuario, moodle_username, email_verificado
    FROM usuarios 
    WHERE email = :email 
    LIMIT 1
");
$stmt->execute([':email' => $email]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);

$idUsuario = null;
$tipoUsuario = null;
$moodleUsername = null;
$fullName = '';

if ($user) {
    $idUsuario = (int)$user['id_usuario'];
    $tipoUsuario = $user['tipo_usuario'];
    $moodleUsername = trim((string)$user['moodle_username']);
    
    // Verificar si el usuario está verificado
    if ($user['email_verificado'] == 0) {
        error_log("[LOGIN] Usuario no verificado: $email");
        http_response_code(403);
        exit(json_encode([
            'status' => 'unverified',
            'msg' => 'Usuario no verificado. Por favor verifica tu email primero.',
            'user_id' => $idUsuario,
            'email' => $email
        ]));
    }
    error_log("[LOGIN] Usuario encontrado localmente. ID: $idUsuario, Tipo: $tipoUsuario");
} else {
    // 3. Buscar en Moodle si no existe localmente
    error_log("[LOGIN] Usuario no encontrado localmente, buscando en Moodle: $email");
    try {
        $client = getMoodleClient();
        $remoteUsers = $client->request(
            MOODLE_WS_TOKEN,
            'core_user_get_users_by_field',
            ['field' => 'email', 'values[0]' => $email]
        );
        
        if (empty($remoteUsers)) {
            error_log("[LOGIN] Usuario no existe en Moodle: $email");
            http_response_code(401);
            exit(json_encode(['status' => 'error', 'msg' => 'Credenciales inválidas']));
        }
        
        $remote = $remoteUsers[0];
        $moodleUsername = $remote['username'];
        $fullName = trim(($remote['firstname'] ?? '') . ' ' . ($remote['lastname'] ?? ''));
        $tipoUsuario = 'estudiante';
        error_log("[LOGIN] Usuario encontrado en Moodle. Username: $moodleUsername");
        
    } catch (Exception $e) {
        error_log("[LOGIN] Error consultando Moodle: " . $e->getMessage());
        http_response_code(502);
        exit(json_encode(['status' => 'error', 'msg' => 'Error conectando con la plataforma']));
    }
}

// ✅ FASE 4: Autenticación en Moodle vía POST (no GET) con URL centralizada
// Importante: las credenciales se envían en el body, no en la URL,
// por seguridad (no quedan en logs de Apache/proxies).
$loginUrl = getMoodleLoginUrl();

error_log("[LOGIN] Autenticando en Moodle: $loginUrl (usuario: $moodleUsername)");

$postData = http_build_query([
    'username' => $moodleUsername,
    'password' => $password,
    'service'  => MOODLE_SERVICE_NAME,
]);

$ch = curl_init($loginUrl);
curl_setopt_array($ch, [
    CURLOPT_POST           => true,
    CURLOPT_POSTFIELDS     => $postData,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT        => 30,
    CURLOPT_CONNECTTIMEOUT => 30,
    CURLOPT_SSL_VERIFYPEER => true,   // ✅ Verificar SSL (HTTPS obligatorio)
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_HTTPHEADER     => [
        'Content-Type: application/x-www-form-urlencoded',
        'Accept: application/json',
    ],
]);

$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$curlErr = curl_errno($ch) ? curl_error($ch) : null;
curl_close($ch);

if ($curlErr) {
    error_log("[LOGIN] Error cURL: $curlErr");
    http_response_code(502);
    exit(json_encode(['status' => 'error', 'msg' => 'Error de conexión con Moodle']));
}

$data = json_decode($response, true) ?? [];

// 5. Validar respuesta de Moodle
if ($httpCode !== 200 || isset($data['error'])) {
    error_log("[LOGIN] Error en Moodle. HTTP: $httpCode, Error: " . ($data['error'] ?? 'Desconocido'));
    http_response_code(401);
    exit(json_encode([
        'status' => 'error',
        'msg' => $data['error'] ?? 'Credenciales inválidas'
    ]));
}

if (empty($data['token'])) {
    error_log("[LOGIN] Token no recibido de Moodle. Respuesta: $response");
    http_response_code(500);
    exit(json_encode(['status' => 'error', 'msg' => 'Error en la plataforma']));
}

$moodleToken = $data['token'];
error_log("[LOGIN] Token de Moodle obtenido correctamente");

// 6. Obtener userid de Moodle
try {
    $client = getMoodleClient();
    $siteInfo = $client->request($moodleToken, 'core_webservice_get_site_info', []);
    $moodleUserId = (int)($siteInfo['userid'] ?? 0);
    
    if ($moodleUserId <= 0) {
        throw new Exception('userid inválido');
    }
    error_log("[LOGIN] Moodle User ID obtenido: $moodleUserId");
    
} catch (Exception $e) {
    error_log("[LOGIN] Error obteniendo site_info: " . $e->getMessage());
    http_response_code(502);
    exit(json_encode(['status' => 'error', 'msg' => 'Error obteniendo información del usuario']));
}

// 7. Obtener nombre completo si es necesario
if ($fullName === '') {
    try {
        $users = $client->request(
            $moodleToken,
            'core_user_get_users_by_field',
            ['field' => 'id', 'values[0]' => $moodleUserId]
        );
        $mu = $users[0] ?? [];
        $fullName = trim(($mu['firstname'] ?? '') . ' ' . ($mu['lastname'] ?? ''));
    } catch (Exception $e) {
        error_log("[LOGIN] No se pudo obtener nombre completo: " . $e->getMessage());
    }
}

// 8. Sincronizar/Actualizar usuario en BD local
try {
    if ($idUsuario) {
        $upd = $conexion->prepare("
            UPDATE usuarios
            SET moodle_username = :muser,
                moodle_id = :mid,
                moodle_token = :mtok,
                ultimo_login = NOW()
            WHERE id_usuario = :uid
        ");
        $upd->execute([
            ':muser' => $moodleUsername,
            ':mid' => $moodleUserId,
            ':mtok' => $moodleToken,
            ':uid' => $idUsuario
        ]);
        error_log("[LOGIN] Usuario actualizado. ID: $idUsuario");
    } else {
        $pwHash = password_hash($password, PASSWORD_DEFAULT);
        $ins = $conexion->prepare("
            INSERT INTO usuarios
                (email, contrasena_hash, nombre, tipo_usuario,
                 moodle_username, moodle_id, moodle_token, ultimo_login)
            VALUES
                (:email, :phash, :nombre, :tuser,
                 :muser, :mid, :mtok, NOW())
        ");
        $ins->execute([
            ':email' => $email,
            ':phash' => $pwHash,
            ':nombre' => $fullName,
            ':tuser' => $tipoUsuario,
            ':muser' => $moodleUsername,
            ':mid' => $moodleUserId,
            ':mtok' => $moodleToken
        ]);
        $idUsuario = (int)$conexion->lastInsertId();
        error_log("[LOGIN] Nuevo usuario creado. ID: $idUsuario");
    }
} catch (Exception $e) {
    error_log("[LOGIN] Error BD al sincronizar usuario: " . $e->getMessage());
    http_response_code(500);
    exit(json_encode(['status' => 'error', 'msg' => 'Error en base de datos']));
}

// 9. Generar JWT
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
        'id_usuario' => $idUsuario,
        'email' => $email,
        'tipo_usuario' => $tipoUsuario,
        'moodle_userid' => $moodleUserId,
        'moodle_token' => $moodleToken
    ]
];

$appToken = JWT::encode($payload, $configJwt['secret'], 'HS256');
$refreshToken = bin2hex(random_bytes(32));

// 10. Guardar refresh token
try {
    $rt = $conexion->prepare("
        INSERT INTO refresh_tokens (token, id_usuario, expires_at)
        VALUES (:rt, :uid, DATE_ADD(NOW(), INTERVAL 30 DAY))
    ");
    $rt->execute([':rt' => $refreshToken, ':uid' => $idUsuario]);
} catch (Exception $e) {
    error_log("[LOGIN] Error guardando refresh token: " . $e->getMessage());
}

// 11. Obtener datos completos del usuario
try {
    $stmtUser = $conexion->prepare("
        SELECT id_usuario, email, nombre, tipo_usuario, moodle_username, moodle_id,
               avatar_path, telefono, departamento, ciudad, colegio, grado,
               email_verificado, access_level, is_early_user, registration_date
        FROM usuarios
        WHERE id_usuario = :uid
    ");
    $stmtUser->execute([':uid' => $idUsuario]);
    $userData = $stmtUser->fetch(PDO::FETCH_ASSOC);
    
    if (!$userData) {
        throw new Exception('Usuario no encontrado después de login');
    }
    
} catch (Exception $e) {
    error_log("[LOGIN] Error obteniendo datos usuario: " . $e->getMessage());
    http_response_code(500);
    exit(json_encode(['status' => 'error', 'msg' => 'Error obteniendo perfil']));
}

// 12. Respuesta exitosa
error_log("[LOGIN] Login exitoso para usuario ID: $idUsuario, Tipo: $tipoUsuario");
echo json_encode([
    'status' => 'ok',
    'token' => $appToken,
    'refresh_token' => $refreshToken,
    'expires_at' => date('c', $exp),
    'moodle_userid' => $moodleUserId,
    'moodle_token' => $moodleToken,
    'user' => $userData
], JSON_UNESCAPED_UNICODE);
?>