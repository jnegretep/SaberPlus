<?php
// resend_verification.php
header('Content-Type: application/json');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");

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
require __DIR__ . '/vendor/autoload.php';

use PHPMailer\PHPMailer\PHPMailer;

$data = json_decode(file_get_contents('php://input'), true);
$email = $data['email'] ?? '';

if (empty($email)) {
    echo json_encode(['status' => 'error', 'msg' => 'Email es requerido']);
    exit;
}

try {
    // Verificar si el usuario existe
    $stmt = $conexion->prepare("SELECT id_usuario, nombre, email_verificado FROM usuarios WHERE email = ?");
    $stmt->execute([$email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$user) {
        echo json_encode(['status' => 'error', 'msg' => 'Usuario no encontrado']);
        exit;
    }
    
    // Si ya está verificado
    if ($user['email_verificado'] == 1) {
        echo json_encode(['status' => 'error', 'msg' => 'El email ya está verificado']);
        exit;
    }
    
    // Generar nuevo código de 6 dígitos
    $token = str_pad(random_int(0, 999999), 6, '0', STR_PAD_LEFT);
    $expiresAt = date('Y-m-d H:i:s', strtotime('+1 hour'));
    
    // Actualizar o insertar código de verificación
    $checkVerif = $conexion->prepare("SELECT id FROM email_verifications WHERE user_id = ?");
    $checkVerif->execute([$user['id_usuario']]);
    
    if ($checkVerif->fetch()) {
        $updateStmt = $conexion->prepare("UPDATE email_verifications SET token = ?, expires_at = ? WHERE user_id = ?");
        $updateStmt->execute([$token, $expiresAt, $user['id_usuario']]);
    } else {
        $insertStmt = $conexion->prepare("INSERT INTO email_verifications (user_id, token, expires_at) VALUES (?, ?, ?)");
        $insertStmt->execute([$user['id_usuario'], $token, $expiresAt]);
    }
    
    // Enviar correo
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
        $mail->addAddress($email, $user['nombre']);

        $mail->isHTML(true);
        $mail->Subject = 'Nuevo código de verificación - PrepSaber';
        $mail->Body    = "
            <h2>Hola, ".htmlspecialchars($user['nombre'], ENT_QUOTES, 'UTF-8')."</h2>
            <p>Se ha solicitado un nuevo código de verificación para tu cuenta en <b>PrepSaber</b>.</p>
            <p>Tu nuevo código de verificación es:</p>
            <h3 style='font-size: 32px; color: #1E4ED8; letter-spacing: 8px; text-align: center;'>$token</h3>
            <p>Por favor, ingresa este código de 6 dígitos en la aplicación.</p>
            <p>Este código expirará en 1 hora.</p>
            <p><small>Si no solicitaste un nuevo código, puedes ignorar este mensaje.</small></p>
        ";
        $mail->AltBody = "Hola, {$user['nombre']}\nTu nuevo código de verificación es: $token\nExpira en 1 hora.";

        $mailSent = $mail->send();
        error_log("[RESEND] Correo reenviado a $email: " . ($mailSent ? 'Éxito' : 'Falló'));
    } catch (Exception $e) {
        error_log("[RESEND] Error PHPMailer: " . $e->getMessage());
    }
    
    echo json_encode([
        'status' => 'ok',
        'msg' => $mailSent ? 'Código reenviado exitosamente' : 'Error al enviar el correo',
        'mail_sent' => $mailSent
    ]);
    
} catch (PDOException $e) {
    error_log("Error al reenviar código: " . $e->getMessage());
    echo json_encode(['status' => 'error', 'msg' => 'Error en el servidor']);
}
?>