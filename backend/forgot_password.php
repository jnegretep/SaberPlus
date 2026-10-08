<?php
// forgot_password.php

// ======== CORS Y FORMATO =========
ini_set('display_errors', 0);
ini_set('display_startup_errors', 0);
error_reporting(E_ALL);
ini_set('default_charset', 'UTF-8');

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    $json = '{"status":"error","msg":"Método no permitido"}';
    header('Content-Length: ' . strlen($json));
    echo $json;
    exit;
}

// ======== DEPENDENCIAS =========
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/vendor/autoload.php';

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception as PHPMailerException;

// ======== FUNCIONES =========
function generateResetCode(): string {
    return str_pad((string)random_int(0, 999999), 6, '0', STR_PAD_LEFT);
}

function respond(int $code, array $payload): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=UTF-8');

    // Normalizar todos los strings a UTF-8 válido
    array_walk_recursive($payload, function (&$item) {
        if (is_string($item)) {
            $item = mb_convert_encoding($item, 'UTF-8', 'UTF-8');
        }
    });

    $json = json_encode($payload, JSON_UNESCAPED_UNICODE);
    if ($json === false) {
        $err = json_last_error_msg();
        error_log("[FORGOT_PASSWORD][JSON_ENCODE_FAIL] $err");
        $json = '{"status":"error","msg":"json_encode_failed"}';
    }

    error_log("[FORGOT_PASSWORD][RESPOND_JSON] $json");
    header('Content-Length: ' . strlen($json));
    echo $json;
    flush();
    exit;
}

try {
    // ======== LECTURA Y VALIDACIÓN DEL JSON =========
    $input = file_get_contents('php://input');
    $data = json_decode($input, true);

    if (json_last_error() !== JSON_ERROR_NONE) {
        respond(400, ['status'=>'error','msg'=>'JSON inválido']);
    }

    $email = strtolower(trim($data['email'] ?? ''));
    if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
        respond(400, ['status'=>'error','msg'=>'Email inválido']);
    }

    // ======== BUSCAR USUARIO =========
    $stmt = $conexion->prepare("SELECT id_usuario, nombre FROM usuarios WHERE email = ? LIMIT 1");
    $stmt->execute([$email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    // Por seguridad, no revelamos si existe o no
    if (!$user) {
        error_log("[FORGOT_PASSWORD] Email no encontrado: $email");
        respond(200, ['status'=>'ok','msg'=>'Si el correo existe, se enviará un código de recuperación']);
    }

    $userId = (int)$user['id_usuario'];
    $nombre = (string)$user['nombre'];

    // Normalizar valores a UTF-8 seguro
    $nombre = mb_convert_encoding($nombre, 'UTF-8', 'UTF-8');
    $email  = mb_convert_encoding($email, 'UTF-8', 'UTF-8');

    // ======== GENERAR TOKEN =========
    $token = generateResetCode();
    $expiresAt = date('Y-m-d H:i:s', strtotime('+15 minutes'));

    // Invalidar tokens previos
    $del = $conexion->prepare("DELETE FROM password_resets WHERE user_id = ?");
    $del->execute([$userId]);

    // Guardar nuevo token
    $ins = $conexion->prepare("INSERT INTO password_resets (user_id, token, expires_at) VALUES (?, ?, ?)");
    $ins->execute([$userId, $token, $expiresAt]);

    // ======== ENVÍO DE CORREO =========
    $mail = new PHPMailer(true);
    $mailSent = false;

    try {
        $mail->isSMTP();
        $mail->Host       = 'smtp.gmail.com';
        $mail->SMTPAuth   = true;
        $mail->Username   = 'jnegretep24@gmail.com';
        $mail->Password   = 'aqendcuwweqphwhg';
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = 587;
        $mail->CharSet    = 'UTF-8';

        $mail->setFrom('jnegretep24@gmail.com', 'PrepSaber');
        $mail->addAddress($email, $nombre);

        $mail->isHTML(true);
        $mail->Subject = 'Recupera tu contraseña - PrepSaber';
        $mail->Body    = "
            <h2>Hola, ".htmlspecialchars($nombre, ENT_QUOTES, 'UTF-8')."</h2>
            <p>Has solicitado recuperar tu contraseña.</p>
            <h3 style='font-size: 32px; color: #1E4ED8; letter-spacing: 8px; text-align: center;'>$token</h3>
            <p>Este código expirará en 15 minutos.</p>
        ";
        $mail->AltBody = "Hola, $nombre\nTu código de recuperación es: $token";

        $mailSent = $mail->send();
    } catch (PHPMailerException $e) {
        error_log("[FORGOT_PASSWORD] Error PHPMailer: " . $e->getMessage());
    }

    error_log("[FORGOT_PASSWORD] Código enviado a user_id=$userId");

    // ======== RESPUESTA =========
    respond(200, [
        'status'    => 'ok',
        'msg'       => 'Si el correo existe, se enviará un código de recuperación',
        'mail_sent' => $mailSent ? true : false,
    ]);

} catch (Throwable $e) {
    error_log("[FORGOT_PASSWORD][EXCEPTION] " . $e->getMessage());
    respond(500, ['status'=>'error','msg'=>'Error interno']);
}
