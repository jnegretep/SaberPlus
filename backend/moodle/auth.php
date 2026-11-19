<?php
// /var/www/html/api/prepsaber/backend/moodle/auth.php
// ✅ FASE 4: URLs centralizadas en includes/config.php
header('Content-Type: application/json');

require_once __DIR__ . '/../includes/config.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Método no permitido']);
    exit;
}

// 1. Leer credenciales desde JSON body
$body = json_decode(file_get_contents('php://input'), true);
$username = $body['username'] ?? null;
$password = $body['password'] ?? null;

if (! $username || ! $password) {
    http_response_code(400);
    echo json_encode(['error' => 'Faltan username o password']);
    exit;
}

// 2. Configuración centralizada
$SERVICE_NAME = MOODLE_SERVICE_NAME;

// 3. Llamada al endpoint de token de Moodle vía POST (seguridad)
$loginUrl = getMoodleLoginUrl();

$postData = http_build_query([
    'username' => $username,
    'password' => $password,
    'service'  => $SERVICE_NAME,
]);

$ch = curl_init($loginUrl);
curl_setopt_array($ch, [
    CURLOPT_POST           => true,
    CURLOPT_POSTFIELDS     => $postData,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT        => 30,
    CURLOPT_CONNECTTIMEOUT => 30,
    CURLOPT_SSL_VERIFYPEER => true,
    CURLOPT_HTTPHEADER     => [
        'Content-Type: application/x-www-form-urlencoded',
        'Accept: application/json',
    ],
]);

$response = curl_exec($ch);
$curlErr = curl_error($ch);
curl_close($ch);

if ($curlErr) {
    http_response_code(502);
    echo json_encode(['error' => 'Error conectando con Moodle: ' . $curlErr]);
    exit;
}

$data = json_decode($response, true);
if (isset($data['error'])) {
    http_response_code(401);
    echo json_encode(['error' => $data['error']]);
    exit;
}

// 4. Tenemos { token, username, userid, ... }
//    Guardamos o actualizamos el usuario en nuestra base de datos
//    para enlazarlo luego con las llamadas WS. Asumemos MySQL + PDO.

try {
    $pdo = new PDO('mysql:host=localhost;dbname=prepsaber', 'db_user', 'db_pass');
    $stmt = $pdo->prepare("
        INSERT INTO users (moodle_id, username, moodle_token, updated_at)
        VALUES (:moodle_id, :username, :token, NOW())
        ON DUPLICATE KEY UPDATE
          username     = VALUES(username),
          moodle_token = VALUES(moodle_token),
          updated_at   = NOW()
    ");
    $stmt->execute([
        ':moodle_id' => $data['userid'],
        ':username'  => $username,
        ':token'     => $data['token'],
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Error DB: ' . $e->getMessage()]);
    exit;
}

// 5. Generamos un JWT propio para Flutter
echo json_encode([
    'moodle_userid' => $data['userid'],
    'moodle_token'  => $data['token'],
]);
