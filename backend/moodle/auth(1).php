<?php
// /var/www/html/api/prepsaber/backend/moodle/auth.php
header('Content-Type: application/json');

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

// 2. Configuración mínima: URL de Moodle y nombre del servicio
$MOODLE_URL     = 'http://172.93.49.94/preicfes';
$SERVICE_NAME   = 'PrepSaber service';  // Igual al “shortname” de tu servicio WS en Moodle

// 3. Llamada al endpoint de token de Moodle
$loginUrl = $MOODLE_URL . '/login/token.php'
          . '?username=' . urlencode($username)
          . '&password=' . urlencode($password)
          . '&service='  . urlencode($SERVICE_NAME);

$ch = curl_init($loginUrl);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
$response = curl_exec($ch);
curl_close($ch);

$data = json_decode($response, true);
if (isset($data['error'])) {
    http_response_code(401);
    echo json_encode(['error' => $data['error']]);
    exit;
}

// 4. Tenemos { token, username, userid, ... }
//    Guardamos o actualizamos el usuario en nuestra base de datos
//    para enlazarlo luego con las llamadas WS. Asumimos MySQL + PDO.

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

// 5. Generamos un JWT propio para Flutter (o sesión PHP, según tu sistema)
//    Aquí devolvemos el token de Moodle + moodle_userid.
//    En producción deberías emitir un JWT firmado con tu clave.

echo json_encode([
    'moodle_userid' => $data['userid'],
    'moodle_token'  => $data['token'],
]);
