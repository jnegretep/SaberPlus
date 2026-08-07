<?php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['status' => 'error', 'msg' => 'Método no permitido']);
    exit;
}

require __DIR__ . '/includes/conexion.php';

function generateToken($len = 16) {
    return bin2hex(random_bytes($len));
}

$input = json_decode(file_get_contents('php://input'), true);
$email = trim($input['email'] ?? '');

if (!$email) {
    http_response_code(400);
    echo json_encode(['status'=>'error','msg'=>'Email requerido']);
    exit;
}

try {
    // Verificar que el usuario existe y tiene email verificado
    $stmt = $conexion->prepare("SELECT id_usuario, nombre FROM usuarios WHERE email = ? AND email_verificado = 1");
    $stmt->execute([$email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        // No revelar si el email no existe o no está verificado para evitar info leak
        echo json_encode(['status'=>'ok', 'msg'=>'Si el correo está registrado, recibirás un email para restablecer la contraseña']);
        exit;
    }

    // Generar token y guardar con expiración (por ejemplo 1 hora)
    $token = generateToken(24);
    $expiresAt = date('Y-m-d H:i:s', strtotime('+1 hour'));

    // Insertar o actualizar token de recuperación
    $stmt = $conexion->prepare("DELETE FROM password_resets WHERE user_id = ?");
    $stmt->execute([$user['id_usuario']]);

    $stmt = $conexion->prepare("INSERT INTO password_resets (user_id, token, expires_at) VALUES (?, ?, ?)");
    $stmt->execute([$user['id_usuario'], $token, $expiresAt]);

    // Enviar email con link de recuperación
    $resetLink = "http://localhost/api/prepsaber/backend/reset_password.php?token=$token";

    $subject = "Restablece tu contraseña - PrepSaber";
    $message = "Hola {$user['nombre']},\n\n"
        . "Haz clic en el siguiente enlace para restablecer tu contraseña:\n"
        . "$resetLink\n\n"
        . "Este enlace expirará en 1 hora.\n\n"
        . "Si no solicitaste este cambio, ignora este mensaje.";

    $headers = "From: no-reply@localhost\r\n";

    @mail($email, $subject, $message, $headers);

    echo json_encode(['status'=>'ok', 'msg'=>'Si el correo está registrado, recibirás un email para restablecer la contraseña']);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['status'=>'error','msg'=>'Error interno','error'=>$e->getMessage()]);
}
