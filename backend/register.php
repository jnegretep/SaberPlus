<?php
// register.php

// ======== CORS Y FORMATO =========
ini_set('display_errors', 0);
ini_set('display_startup_errors', 0);
error_reporting(E_ALL);
ob_start();

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

// ======== DEPENDENCIAS =========
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/includes/config.php';
require __DIR__ . '/includes/avatar_helper.php';
require __DIR__ . '/vendor/autoload.php';
require_once __DIR__ . '/env.php';

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception as PHPMailerException;

// ======== FUNCIONES =========
function generateVerificationCode() {
    return str_pad(random_int(0, 999999), 6, '0', STR_PAD_LEFT);
}

// ======== RATE-LIMIT PT3 =========
function register_rate_limit_excedido(): bool {
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'desconocida';
    $archivo = sys_get_temp_dir() . '/saberplus_rl_register_' . md5($ip) . '.json';
    $fp = @fopen($archivo, 'c+');
    if ($fp === false) {
        return false;
    }
    $ahora = time();
    $ventana = 600;
    $maximos = 3;
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

if (register_rate_limit_excedido()) {
    http_response_code(429);
    ob_clean();
    echo json_encode(['error' => 'rate_limit', 'msg' => 'Demasiados intentos. Espera unos minutos.'], JSON_UNESCAPED_UNICODE);
    exit;
}

$fechaLimite = '2026-03-01';
if (date('Y-m-d') < $fechaLimite) {
    $accessLevel = 'trial';
    $isEarlyUser = 1;
} else {
    $accessLevel = 'free';
    $isEarlyUser = 0;
}

try {
    // ======== LECTURA Y VALIDACIÓN DEL JSON =========
    $input = file_get_contents('php://input');
    $data = json_decode($input, true);

    if (json_last_error() !== JSON_ERROR_NONE) {
        http_response_code(400);
        echo json_encode(['status'=>'error','msg'=>'JSON inválido']);
        exit;
    }

    if (empty($data['nombre']) || empty($data['email'])) {
        http_response_code(400);
        echo json_encode(['status'=>'error','msg'=>'Nombre y email son obligatorios']);
        exit;
    }

    $nombre        = trim($data['nombre']);
    $email         = strtolower(trim($data['email']));
    $telefono      = isset($data['telefono']) ? trim((string)$data['telefono']) : null;
    $departamento  = isset($data['departamento']) ? trim((string)$data['departamento']) : null;
    $ciudad        = isset($data['ciudad']) ? trim((string)$data['ciudad']) : null;
    $colegio       = isset($data['colegio']) ? trim((string)$data['colegio']) : null;
    $grado         = isset($data['grado']) ? trim((string)$data['grado']) : null;
    $tipo_usuario  = isset($data['tipo_usuario']) ? trim((string)$data['tipo_usuario']) : 'estudiante';
    $username      = isset($data['username']) ? trim((string)$data['username']) : null;
    $avatarBase64  = isset($data['avatar']) ? trim((string)$data['avatar']) : null;

    $fechaNacimiento = isset($data['fecha_nacimiento']) && $data['fecha_nacimiento'] !== ''
        ? trim((string)$data['fecha_nacimiento'])
        : null;
    if ($fechaNacimiento !== null) {
        if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $fechaNacimiento)) {
            http_response_code(400);
            echo json_encode(['status' => 'error', 'msg' => 'Fecha de nacimiento inválida (formato YYYY-MM-DD)']);
            exit;
        }
        $tsFecha = strtotime($fechaNacimiento);
        $edad = $tsFecha ? (int)((time() - $tsFecha) / (365.25 * 86400)) : -1;
        if ($tsFecha === false || $tsFecha > time() || $edad < 5 || $edad > 100) {
            http_response_code(400);
            echo json_encode(['status' => 'error', 'msg' => 'Fecha de nacimiento fuera de rango (5-100 años)']);
            exit;
        }
    }

    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        http_response_code(400);
        echo json_encode(['status'=>'error','msg'=>'Email inválido']);
        exit;
    }

    // ======== VALIDACIÓN DE EMAIL ÚNICO =========
    $stmt = $conexion->prepare("SELECT id_usuario, email_verificado FROM usuarios WHERE email = ? LIMIT 1");
    $stmt->execute([$email]);
    $existingUser = $stmt->fetch(PDO::FETCH_ASSOC);

    // ======== PROCESAR AVATAR =========
    $avatarFilename = null;
    if (!$existingUser || (int)$existingUser['email_verificado'] === 0) {
        $avatarFilename = saberplus_guardar_avatar_base64($avatarBase64, 'REGISTER');
    }

    // ======== CREDENCIALES SMTP CENTRALIZADAS + LOGS DE DIAGNÓSTICO =========
    $smtpUser     = env('SMTP_USER', 'Saberplus2026@gmail.com');
    $smtpPass     = env('SMTP_PASS', ''); 
    $smtpFrom     = env('SMTP_FROM', 'Saberplus2026@gmail.com');
    $smtpFromName = env('SMTP_FROM_NAME', 'Equipo de soporte Saber+');
    $smtpHost     = env('SMTP_HOST', 'smtp.gmail.com');
    $smtpPort     = (int) env('SMTP_PORT', '587');

    // LOG DE DIAGNÓSTICO: Verifica si leyó las variables del .env correctamente
    error_log("[REGISTER DIAGNOSTIC] SMTP User cargado: '{$smtpUser}' | Password configurada: " . (!empty($smtpPass) ? "SÍ (Longitud: " . strlen($smtpPass) . ")" : "VACÍA"));

    // ======== USUARIO EXISTENTE NO VERIFICADO =========
    if ($existingUser && $existingUser['email_verificado'] == 0) {
        $userId = $existingUser['id_usuario'];
        $moodleUsername = $username ?: ('u' . uniqid());

        $updateStmt = $conexion->prepare("
            UPDATE usuarios 
            SET nombre = ?, telefono = ?, departamento = ?, ciudad = ?, 
                colegio = ?, grado = ?, tipo_usuario = ?, moodle_username = ?,
                access_level = ?, is_early_user = ?,
                fecha_nacimiento = COALESCE(?, fecha_nacimiento)
            WHERE id_usuario = ?
        ");
        $updateStmt->execute([
            $nombre, $telefono, $departamento, $ciudad, 
            $colegio, $grado, $tipo_usuario, $moodleUsername,
            $accessLevel, $isEarlyUser,
            $fechaNacimiento,
            $userId
        ]);

        if ($avatarFilename) {
            $updateAvatar = $conexion->prepare("UPDATE usuarios SET avatar_path = ? WHERE id_usuario = ?");
            $updateAvatar->execute([$avatarFilename, $userId]);
        }

        $token = generateVerificationCode();
        $expiresAt = date('Y-m-d H:i:s', strtotime('+1 hour'));

        $checkVerif = $conexion->prepare("SELECT id FROM email_verifications WHERE user_id = ?");
        $checkVerif->execute([$userId]);

        if ($checkVerif->fetch()) {
            $updateToken = $conexion->prepare("UPDATE email_verifications SET token = ?, expires_at = ?, used = 0 WHERE user_id = ?");
            $updateToken->execute([$token, $expiresAt, $userId]);
        } else {
            $insertToken = $conexion->prepare("INSERT INTO email_verifications (user_id, token, expires_at) VALUES (?, ?, ?)");
            $insertToken->execute([$userId, $token, $expiresAt]);
        }

        $mail = new PHPMailer(true);
        $mailSent = false;

        try {
            $mail->isSMTP();
            $mail->Host       = $smtpHost;
            $mail->SMTPAuth   = true;
            $mail->Username   = $smtpUser;
            $mail->Password   = $smtpPass;
            $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
            $mail->Port       = $smtpPort;
            $mail->CharSet    = 'UTF-8';

            $mail->setFrom($smtpFrom, $smtpFromName);
            $mail->addAddress($email, $nombre);

            $mail->isHTML(true);
            $mail->Subject = 'Tu codigo de verificacion - Saber+';
            $mail->Body    = "
                <div style='font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;'>
                    <h2 style='color: #1E4ED8;'>Hola, ".htmlspecialchars($nombre, ENT_QUOTES, 'UTF-8')."</h2>
                    <p>Has solicitado un nuevo codigo de verificacion para tu cuenta en <b>Saber+</b>.</p>
                    <p>Tu codigo de verificacion es:</p>
                    <h3 style='font-size: 32px; color: #1E4ED8; letter-spacing: 8px; text-align: center;'>$token</h3>
                    <p>Este codigo expirara en 1 hora.</p>
                </div>
            ";
            $mail->AltBody = "Hola, $nombre\nTu codigo de verificacion es: $token";

            $mailSent = $mail->send();
        } catch (PHPMailerException $e) {
            // LOG DETALLADO DE FALLO DE EMAIL
            error_log("[REGISTER] Error PHPMailer (Usuario no verificado): " . $e->getMessage() . " | Info SMTP: " . $mail->ErrorInfo);
        }

        ob_clean();
        echo json_encode([
            'status'    => 'unverified',
            'msg'       => 'Usuario existente no verificado. Se ha enviado un nuevo código.',
            'mail_sent' => $mailSent,
            'user_id'   => $userId,
            'username'  => $moodleUsername,
            'avatar'    => $avatarFilename,
            'access_level' => $accessLevel
        ]);
        exit;
    }

    // ======== USUARIO YA EXISTE Y ESTÁ VERIFICADO =========
    if ($existingUser && $existingUser['email_verificado'] == 1) {
        http_response_code(409);
        echo json_encode(['status'=>'error','msg'=>'El correo ya está registrado y verificado. Inicia sesión.']);
        exit;
    }

    // ======== CREACIÓN DE NUEVO USUARIO =========
    $moodleUsername = $username ?: ('u' . uniqid());

    $stmt = $conexion->prepare("
        INSERT INTO usuarios (
            nombre, email, telefono, departamento, ciudad,
            colegio, grado, fecha_nacimiento, contrasena_hash, tipo_usuario,
            email_verificado, moodle_username, avatar_path,
            access_level, is_early_user
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, 0, ?, ?, ?, ?)
    ");

    $stmt->execute([
        $nombre,
        $email,
        $telefono,
        $departamento,
        $ciudad,
        $colegio,
        $grado,
        $fechaNacimiento,
        $tipo_usuario,
        $moodleUsername,
        $avatarFilename,
        $accessLevel,
        $isEarlyUser
    ]);

    $userId = (int)$conexion->lastInsertId();

    // ======== TOKEN DE VERIFICACION =========
    $token = generateVerificationCode();
    $expiresAt = date('Y-m-d H:i:s', strtotime('+1 hour'));
    $stmt = $conexion->prepare("INSERT INTO email_verifications (user_id, token, expires_at) VALUES (?, ?, ?)");
    $stmt->execute([$userId, $token, $expiresAt]);

    $mail = new PHPMailer(true);
    $mailSent = false;

    try {
        $mail->isSMTP();
        $mail->Host       = $smtpHost;
        $mail->SMTPAuth   = true;
        $mail->Username   = $smtpUser;
        $mail->Password   = $smtpPass;
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = $smtpPort;
        $mail->CharSet    = 'UTF-8';

        $mail->setFrom($smtpFrom, $smtpFromName);
        $mail->addAddress($email, $nombre);

        $mail->isHTML(true);
        $mail->Subject = 'Tu codigo de verificacion - Saber+';
        $mail->Body    = "
            <div style='font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;'>
                <h2 style='color: #1E4ED8;'>Hola, ".htmlspecialchars($nombre, ENT_QUOTES, 'UTF-8')."</h2>
                <p>Gracias por registrarte en <b>Saber+</b>. Para completar tu registro, ingresa el siguiente codigo en la app:</p>
                <h3 style='font-size: 32px; color: #1E4ED8; letter-spacing: 8px; text-align: center;'>$token</h3>
                <p>Este codigo expirara en 1 hora. Si no creaste esta cuenta, ignora este correo.</p>
            </div>
        ";
        $mail->AltBody = "Hola, $nombre\n\nTu codigo de verificacion es: $token";

        $mailSent = $mail->send();
    } catch (PHPMailerException $e) {
        // LOG DETALLADO DE FALLO DE EMAIL NUEVO USUARIO
        error_log("[REGISTER] Error PHPMailer (Nuevo usuario): " . $e->getMessage() . " | Info SMTP: " . $mail->ErrorInfo);
    }

    ob_clean();
    echo json_encode([
        'status'    => 'ok',
        'msg'       => $mailSent
            ? 'Registro creado. Revisa tu correo para verificar la cuenta.'
            : 'Registro creado, pero no se pudo enviar el correo.',
        'mail_sent' => $mailSent,
        'user_id'   => $userId,
        'username'  => $moodleUsername,
        'avatar'    => $avatarFilename,
        'access_level' => $accessLevel
    ]);
    exit;

} catch (Throwable $e) {
    error_log("[REGISTER] Error general: " . $e->getMessage());
    http_response_code(500);
    ob_clean();
    echo json_encode(['status'=>'error','msg'=>'Error interno']);
    exit;
}