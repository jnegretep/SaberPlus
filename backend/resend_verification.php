<?php
// resend_verification.php
// ✅ W2D: reenvío del ENLACE MÁGICO de verificación (24h), alineado con el
// flujo real de register.php. Ya NO genera códigos de 6 dígitos.
//
// Entrada (POST JSON): {user_id} o, como fallback, {email}.
// Respuestas:
//   - {status:'ok', mail_sent:bool, msg}          → reenvío procesado
//   - {status:'ok', already_verified:true, msg}   → ya estaba verificado
//   - 404 {status:'error', msg:'Usuario no encontrado'}
//   - 429 {status:'error', msg:'...'}             → rate limit 3/10 min (user+IP)
//   - Errores SMTP NO rompen la UX: HTTP 200 con mail_sent:false + error_log.

ini_set('display_errors', 0);
ini_set('display_startup_errors', 0);
error_reporting(E_ALL);
ob_start();

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    ob_clean();
    echo json_encode(['status' => 'error', 'msg' => 'Método no permitido']);
    exit;
}

// ======== DEPENDENCIAS =========
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/includes/config.php'; // BACKEND_BASE_URL (enlace mágico)
require __DIR__ . '/vendor/autoload.php';
// ✅ PT3: cargador de backend/.env (ya lo trae conexion.php; explícito por claridad)
require_once __DIR__ . '/env.php';

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception as PHPMailerException;

// ======== RATE-LIMIT (3 reenvíos / 10 min por user_id + IP) =========
// ✅ Mismo patrón /tmp + flock que register.php. Previene abuso del SMTP
// desde una misma cuenta o IP.
function resend_rate_limit_excedido(int $userId): bool {
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'desconocida';
    $archivo = sys_get_temp_dir() . '/saberplus_rl_resend_' . md5($userId . '|' . $ip) . '.json';
    $fp = @fopen($archivo, 'c+');
    if ($fp === false) {
        return false; // si /tmp falla, no bloquear el reenvío
    }
    $ahora = time();
    $ventana = 600;   // 10 minutos
    $maximos = 3;     // 3 reenvíos por ventana
    $timestamps = [];
    $permitido = true;
    try {
        if (flock($fp, LOCK_EX)) {
            $raw = stream_get_contents($fp);
            if (is_string($raw) && $raw !== '') {
                $dec = json_decode($raw, true);
                if (is_array($dec)) {
                    foreach ($dec as $t) {
                        if (is_numeric($t) && ($ahora - (int)$t) < $ventana) {
                            $timestamps[] = (int)$t;
                        }
                    }
                }
            }
            $permitido = count($timestamps) < $maximos;
            if ($permitido) {
                $timestamps[] = $ahora;
            }
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

try {
    // ======== LECTURA Y VALIDACIÓN DEL JSON =========
    $input = file_get_contents('php://input');
    $data = json_decode($input, true);

    if (json_last_error() !== JSON_ERROR_NONE) {
        http_response_code(400);
        ob_clean();
        echo json_encode(['status' => 'error', 'msg' => 'JSON inválido']);
        exit;
    }

    $userId = isset($data['user_id']) ? (int)$data['user_id'] : 0;
    $email  = isset($data['email']) ? strtolower(trim((string)$data['email'])) : '';

    if ($userId <= 0 && $email === '') {
        http_response_code(400);
        ob_clean();
        echo json_encode(['status' => 'error', 'msg' => 'user_id o email es requerido']);
        exit;
    }

    // ======== BÚSQUEDA DEL USUARIO (por id; fallback por email) =========
    if ($userId > 0) {
        $stmt = $conexion->prepare(
            "SELECT id_usuario, nombre, email, email_verificado
             FROM usuarios WHERE id_usuario = ? LIMIT 1"
        );
        $stmt->execute([$userId]);
    } else {
        $stmt = $conexion->prepare(
            "SELECT id_usuario, nombre, email, email_verificado
             FROM usuarios WHERE email = ? LIMIT 1"
        );
        $stmt->execute([$email]);
    }
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        http_response_code(404);
        ob_clean();
        echo json_encode(['status' => 'error', 'msg' => 'Usuario no encontrado']);
        exit;
    }

    $userId = (int)$user['id_usuario'];
    $nombre = $user['nombre'];
    $email  = strtolower(trim((string)$user['email']));

    // ======== YA VERIFICADO (no reenvía) =========
    if ((int)$user['email_verificado'] === 1) {
        ob_clean();
        echo json_encode([
            'status'            => 'ok',
            'already_verified'  => true,
            'msg'               => 'Tu correo ya está verificado. Presiona "Ya verifiqué mi correo".',
        ]);
        exit;
    }

    // ======== RATE-LIMIT =========
    if (resend_rate_limit_excedido($userId)) {
        http_response_code(429);
        ob_clean();
        echo json_encode([
            'status' => 'error',
            'msg'    => 'Has alcanzado el límite de reenvíos. Espera unos minutos e intenta de nuevo.',
        ]);
        exit;
    }

    // ======== TOKEN NUEVO (enlace mágico, 24h — igual que register.php) =========
    $token = bin2hex(random_bytes(16));
    $expiresAt = date('Y-m-d H:i:s', strtotime('+24 hours'));

    // Invalida los tokens anteriores de ese usuario (UPDATE; si no hay fila, INSERT)
    $checkVerif = $conexion->prepare("SELECT id FROM email_verifications WHERE user_id = ?");
    $checkVerif->execute([$userId]);

    if ($checkVerif->fetch()) {
        $updateToken = $conexion->prepare("UPDATE email_verifications SET token = ?, expires_at = ? WHERE user_id = ?");
        $updateToken->execute([$token, $expiresAt, $userId]);
    } else {
        $insertToken = $conexion->prepare("INSERT INTO email_verifications (user_id, token, expires_at) VALUES (?, ?, ?)");
        $insertToken->execute([$userId, $token, $expiresAt]);
    }

    // ======== ENVÍO DEL CORREO (mismo HTML que register.php) =========
    $verifyUrl = rtrim(BACKEND_BASE_URL, '/') . '/verify_email_link.php?token=' . $token;

    $mail = new PHPMailer(true);
    $mailSent = false;

    // ✅ PT3: credenciales SMTP fuera del código → backend/.env
    // (SMTP_USER / SMTP_PASS / SMTP_FROM / SMTP_FROM_NAME).
    // Fallback transitorio del password a la app-password anterior
    // (expuesta en git) SOLO para no romper el envío antes de configurar
    // el .env del servidor: ROTARLA en Gmail y definir SMTP_PASS.
    $smtpUser     = env('SMTP_USER', 'Saberplus2026@gmail.com');
    $smtpPass     = env('SMTP_PASS', 'rwretxvadnprnrzl');
    $smtpFrom     = env('SMTP_FROM', 'Saberplus2026@gmail.com');
    $smtpFromName = env('SMTP_FROM_NAME', 'Equipo de soporte Saber+');
    if (env('SMTP_PASS') === null || env('SMTP_PASS') === '') {
        error_log('[RESEND][SMTP] ADVERTENCIA: SMTP_PASS no definida en backend/.env; usando app-password de fallback expuesta en git. Defínela y ROTALA en Gmail.');
    }

    try {
        $mail->isSMTP();
        $mail->Host       = env('SMTP_HOST', 'smtp.gmail.com');
        $mail->SMTPAuth   = true;
        $mail->Username   = $smtpUser;
        $mail->Password   = $smtpPass;
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = (int) env('SMTP_PORT', '587');
        $mail->CharSet    = 'UTF-8';

        $mail->setFrom($smtpFrom, $smtpFromName);
        $mail->addAddress($email, $nombre);

        $mail->isHTML(true);
        $mail->Subject = 'Confirma tu correo - Saber+';
        $mail->Body    = "
            <div style='font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;'>
                <h2 style='color: #1E4ED8;'>Hola, ".htmlspecialchars($nombre, ENT_QUOTES, 'UTF-8')."</h2>
                <p>Has solicitado un nuevo enlace de verificacion para tu cuenta en <b>Saber+</b>.</p>
                <p>Haz clic en el siguiente boton para confirmar tu correo electronico:</p>
                <div style='text-align: center; margin: 32px 0;'>
                    <a href='{$verifyUrl}' style='background: #1E4ED8; color: white; padding: 16px 40px; border-radius: 12px; text-decoration: none; font-size: 18px; font-weight: bold; display: inline-block;'>
                        Confirmar mi correo
                    </a>
                </div>
                <p style='color: #666; font-size: 14px;'>O copia y pega este enlace en tu navegador:</p>
                <p style='word-break: break-all; color: #1E4ED8; font-size: 13px;'>{$verifyUrl}</p>
                <hr style='border: none; border-top: 1px solid #eee; margin: 24px 0;'>
                <p style='color: #999; font-size: 12px;'>Este enlace expirara en 24 horas. Si no solicitaste esta verificacion, ignora este correo.</p>
            </div>
        ";
        $mail->AltBody = "Hola, $nombre\n\nConfirma tu correo en Saber+ visitando:\n$verifyUrl";

        $mailSent = $mail->send();
    } catch (PHPMailerException $e) {
        error_log("[RESEND] Error PHPMailer: " . $e->getMessage());
    }

    // ======== RESPUESTA ========
    // Errores SMTP NO rompen la UX: HTTP 200 con mail_sent:false.
    ob_clean();
    echo json_encode([
        'status'    => 'ok',
        'mail_sent' => $mailSent,
        'msg'       => $mailSent
            ? 'Correo reenviado. Revisa tu bandeja de entrada y spam.'
            : 'No se pudo enviar el correo. Intenta de nuevo en unos minutos.',
    ]);
    exit;

} catch (Throwable $e) {
    error_log("[RESEND] Error general: " . $e->getMessage());
    http_response_code(500);
    ob_clean();
    echo json_encode(['status' => 'error', 'msg' => 'Error interno']);
    exit;
}
