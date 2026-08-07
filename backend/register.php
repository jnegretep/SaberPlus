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
require __DIR__ . '/vendor/autoload.php';

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception as PHPMailerException;

// ======== FUNCIONES =========
function generateVerificationCode() {
    return str_pad(random_int(0, 999999), 6, '0', STR_PAD_LEFT);
}

// ======== LÓGICA DE ACCESO (TRIAL / FREE) =========
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
    if (!empty($avatarBase64)) {
        try {
            $decoded = base64_decode($avatarBase64);
            if ($decoded !== false) {
                $avatarsDir = __DIR__ . '/uploads/avatars/';
                if (!is_dir($avatarsDir)) {
                    mkdir($avatarsDir, 0777, true);
                }

                $avatarFilename = 'avatar_' . uniqid() . '.jpg';
                file_put_contents($avatarsDir . $avatarFilename, $decoded);
            }
        } catch (Exception $e) {
            error_log("[REGISTER] Error guardando avatar: " . $e->getMessage());
        }
    }

    // ======== USUARIO EXISTENTE NO VERIFICADO =========
    if ($existingUser && $existingUser['email_verificado'] == 0) {
        $userId = $existingUser['id_usuario'];
        $moodleUsername = $username ?: ('u' . uniqid());

        $updateStmt = $conexion->prepare("
            UPDATE usuarios 
            SET nombre = ?, telefono = ?, departamento = ?, ciudad = ?, 
                colegio = ?, grado = ?, tipo_usuario = ?, moodle_username = ?,
                access_level = ?, is_early_user = ?
            WHERE id_usuario = ?
        ");
        $updateStmt->execute([
            $nombre, $telefono, $departamento, $ciudad, 
            $colegio, $grado, $tipo_usuario, $moodleUsername,
            $accessLevel, $isEarlyUser, $userId
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
            $updateToken = $conexion->prepare("UPDATE email_verifications SET token = ?, expires_at = ? WHERE user_id = ?");
            $updateToken->execute([$token, $expiresAt, $userId]);
        } else {
            $insertToken = $conexion->prepare("INSERT INTO email_verifications (user_id, token, expires_at) VALUES (?, ?, ?)");
            $insertToken->execute([$userId, $token, $expiresAt]);
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
            $mail->addAddress($email, $nombre);

            $mail->isHTML(true);
            $mail->Subject = 'Tu código de verificación - PrepSaber';
            $mail->Body    = "
                <h2>Hola, ".htmlspecialchars($nombre, ENT_QUOTES, 'UTF-8')."</h2>
                <p>Se ha solicitado un nuevo código de verificación.</p>
                <h3 style='font-size: 32px; color: #1E4ED8; letter-spacing: 8px; text-align: center;'>$token</h3>
                <p>Este código expirará en 1 hora.</p>
            ";
            $mail->AltBody = "Hola, $nombre\nTu código es: $token";

            $mailSent = $mail->send();
        } catch (PHPMailerException $e) {
            error_log("[REGISTER] Error PHPMailer: " . $e->getMessage());
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
            colegio, grado, contrasena_hash, tipo_usuario,
            email_verificado, moodle_username, avatar_path,
            access_level, is_early_user
        ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?, 0, ?, ?, ?, ?)
    ");

    $stmt->execute([
        $nombre,
        $email,
        $telefono,
        $departamento,
        $ciudad,
        $colegio,
        $grado,
        $tipo_usuario,
        $moodleUsername,
        $avatarFilename,
        $accessLevel,
        $isEarlyUser
    ]);

    $userId = (int)$conexion->lastInsertId();

    // ======== TOKEN DE VERIFICACIÓN =========
    $token = generateVerificationCode();
    $expiresAt = date('Y-m-d H:i:s', strtotime('+1 hour'));
    $stmt = $conexion->prepare("INSERT INTO email_verifications (user_id, token, expires_at) VALUES (?, ?, ?)");
    $stmt->execute([$userId, $token, $expiresAt]);

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
        $mail->Subject = 'Verifica tu correo - PrepSaber';
        $mail->Body    = "
            <h2>Hola, ".htmlspecialchars($nombre, ENT_QUOTES, 'UTF-8')."</h2>
            <p>Gracias por registrarte en <b>PrepSaber</b>.</p>
            <h3 style='font-size: 32px; color: #1E4ED8; letter-spacing: 8px; text-align: center;'>$token</h3>
            <p>Este código expirará en 1 hora.</p>
        ";
        $mail->AltBody = "Hola, $nombre\nTu código es: $token";

        $mailSent = $mail->send();
    } catch (PHPMailerException $e) {
        error_log("[REGISTER] Error PHPMailer: " . $e->getMessage());
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
