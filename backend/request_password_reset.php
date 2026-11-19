<?php
// request_password_reset.php — FIX (Fase 2.5):
//  1. Código de 6 dígitos numéricos (compatible con set_password.php).
//  2. PHPMailer en lugar de @mail() (antes: no enviaba nada en producción).
//  3. Sin enlaces a localhost (el usuario recibe el código directamente).
//  4. Rate-limit por IP: 3 intentos / 10 min.
//  5. Respuesta neutra y logs honestos.

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
require __DIR__ . '/vendor/autoload.php';
require_once __DIR__ . '/env.php';

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception as PHPMailerException;

function reset_rate_limit_excedido(): bool {
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'desconocida';
    $archivo = sys_get_temp_dir() . '/saberplus_rl_reset_' . md5($ip) . '.json';
    $fp = @fopen($archivo, 'c+');
    if ($fp === false) return false;
    $ahora = time();
    $timestamps = [];
    $permitido = true;
    try {
        if (flock($fp, LOCK_EX)) {
            $raw = stream_get_contents($fp);
            if (is_string($raw) && $raw !== '') {
                $dec = json_decode($raw, true);
                if (is_array($dec)) {
                    foreach ($dec as $t) {
                        if (is_numeric($t) && ($ahora - (int)$t) < 600) {
                            $timestamps[] = (int)$t;
                        }
                    }
                }
            }
            $permitido = count($timestamps) < 3;
            if ($permitido) $timestamps[] = $ahora;
            ftruncate($fp, 0);
            rewind($fp);
            fwrite($fp, json_encode($timestamps));
            fflush($fp);
            flock($fp, LOCK_UN);
        }
    } finally {
        fclose($fp);
    }
    return !$permitido;
}

if (reset_rate_limit_excedido()) {
    http_response_code(429);
    echo json_encode(['status' => 'error', 'msg' => 'Demasiados intentos. Espera unos minutos.'], JSON_UNESCAPED_UNICODE);
    exit;
}

$input = json_decode(file_get_contents('php://input'), true) ?: [];
$email = strtolower(trim($input['email'] ?? ''));

$respuesta_neutra = [
    'status' => 'ok',
    'msg'    => 'Si el correo está registrado y verificado, recibirás un código de recuperación en tu email.',
];

if (!$email || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'msg' => 'Correo electrónico inválido']);
    exit;
}

try {
    $stmt = $conexion->prepare("
        SELECT id_usuario, nombre
        FROM usuarios
        WHERE email = ? AND email_verificado = 1
        LIMIT 1
    ");
    $stmt->execute([$email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        // No revelar si el email no existe para evitar info leak
        echo json_encode($respuesta_neutra, JSON_UNESCAPED_UNICODE);
        exit;
    }

    // Generar código de 6 dígitos (mismo formato que email_verifications).
    $code = str_pad((string)random_int(0, 999999), 6, '0', STR_PAD_LEFT);
    $expiresAt = date('Y-m-d H:i:s', strtotime('+1 hour'));

    // Guardar en password_resets (borrar anteriores del mismo usuario).
    $conexion->prepare("DELETE FROM password_resets WHERE user_id = ?")
             ->execute([$user['id_usuario']]);
    $conexion->prepare("
        INSERT INTO password_resets (user_id, token, expires_at)
        VALUES (?, ?, ?)
    ")->execute([$user['id_usuario'], $code, $expiresAt]);

    error_log("[FORGOT_PASSWORD] Código generado para user_id={$user['id_usuario']}");

    // Enviar por PHPMailer con las MISMAS credenciales que register.php.
    $mail = new PHPMailer(true);
    $mailSent = false;
    try {
        $mail->isSMTP();
        $mail->Host       = env('SMTP_HOST', 'smtp.gmail.com');
        $mail->SMTPAuth   = true;
        $mail->Username   = env('SMTP_USER', 'Saberplus2026@gmail.com');
        
        // ⚠️ IMPORTANTE: Asegúrate de que la contraseña en .env sea correcta.
        $mail->Password   = env('SMTP_PASS', 'rwretxvadnprnrzl'); 
        
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = (int) env('SMTP_PORT', '587');
        $mail->CharSet    = 'UTF-8';

        $mail->setFrom(
            env('SMTP_FROM', 'Saberplus2026@gmail.com'),
            env('SMTP_FROM_NAME', 'Equipo de soporte Saber+')
        );
        $mail->addAddress($email, $user['nombre']);

        $safeNombre = htmlspecialchars($user['nombre'], ENT_QUOTES, 'UTF-8');
        $mail->isHTML(true);
        $mail->Subject = 'Recupera tu contraseña - Saber+';
        $mail->Body = "
            <div style='font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;'>
                <h2 style='color: #1E4ED8;'>Hola, {$safeNombre}</h2>
                <p>Recibimos una solicitud para restablecer la contraseña de tu cuenta en <b>Saber+</b>.</p>
                <p>Tu código de recuperación es:</p>
                <h3 style='font-size: 32px; color: #1E4ED8; letter-spacing: 8px; text-align: center;'>{$code}</h3>
                <p>Ingresa este código en la app para establecer una nueva contraseña.</p>
                <p>El código expira en 1 hora.</p>
                <p style='color: #666; font-size: 12px;'>Si no solicitaste este cambio, ignora este correo.</p>
            </div>
        ";
        $mail->AltBody = "Hola, {$user['nombre']}\n\nTu código de recuperación es: {$code}\n\nExpira en 1 hora.";
        
        $mailSent = $mail->send();
    } catch (PHPMailerException $e) {
        error_log("[FORGOT_PASSWORD] ❌ Error PHPMailer: " . $e->getMessage());
    }

    if ($mailSent) {
        error_log("[FORGOT_PASSWORD] ✅ Correo enviado a $email (user_id={$user['id_usuario']})");
    } else {
        error_log("[FORGOT_PASSWORD] ❌ FALLÓ el envío a $email");
    }

    // Siempre respondemos neutro por seguridad.
    echo json_encode($respuesta_neutra, JSON_UNESCAPED_UNICODE);

} catch (Throwable $e) {
    error_log("[FORGOT_PASSWORD] Error general: " . $e->getMessage());
    http_response_code(500);
    echo json_encode(['status' => 'error', 'msg' => 'Error interno']);
}