<?php
declare(strict_types=1);

/**
 * verify_email_link.php - Saber+ Verificacion de email por enlace magico
 *
 * Este endpoint se accede via GET con un token en la URL:
 *   https://corpoinstel.edu.co/api/prepsaber/backend/verify_email_link.php?token=XXXX
 *
 * Si el token es valido:
 * - Marca el email como verificado
 * - Redirige a la app (deep link) o muestra pagina de exito
 * - Elimina el token usado
 *
 * Si el token es invalido o expirado:
 * - Muestra pagina de error
 */

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// Obtener el token de la URL
$token = trim($_GET['token'] ?? '');

if (empty($token)) {
    _renderPage('error', 'Enlace invalido', 'No se recibio el token de verificacion.');
    exit;
}

try {
    // Buscar el token en la base de datos
    $stmt = $conexion->prepare("
        SELECT ev.id, ev.user_id, ev.expires_at, u.email, u.nombre, u.email_verificado
        FROM email_verifications ev
        JOIN usuarios u ON ev.user_id = u.id_usuario
        WHERE ev.token = ?
        LIMIT 1
    ");
    $stmt->execute([$token]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        _renderPage('error', 'Token invalido', 'El enlace de verificacion no es valido o ya fue utilizado.');
        exit;
    }

    // Verificar si ya esta verificado
    if ($row['email_verificado'] == 1) {
        _renderPage('info', 'Ya verificado', 'Tu correo ya fue verificado anteriormente. Ya puedes iniciar sesion en Saber+.');
        exit;
    }

    // Verificar si el token expiro
    if (strtotime($row['expires_at']) < time()) {
        _renderPage('error', 'Enlace expirado', 'Este enlace de verificacion ha expirado. Por favor, solicita un nuevo enlace desde la app.');
        exit;
    }

    // Todo OK: marcar email como verificado
    $update = $conexion->prepare("UPDATE usuarios SET email_verificado = 1 WHERE id_usuario = ?");
    $update->execute([$row['user_id']]);

    // Eliminar el token usado
    $delete = $conexion->prepare("DELETE FROM email_verifications WHERE id = ?");
    $delete->execute([$row['id']]);

    error_log("[VERIFY_LINK] Email verificado para usuario ID: {$row['user_id']} ({$row['email']})");

    // Mostrar pagina de exito
    _renderPage('success', 'Correo verificado', "Hola {$row['nombre']}, tu correo electronico ha sido verificado exitosamente. Ya puedes iniciar sesion en Saber+.");

} catch (Exception $e) {
    error_log("[VERIFY_LINK] Error: " . $e->getMessage());
    _renderPage('error', 'Error', 'Ocurrio un error al verificar tu correo. Intenta de nuevo mas tarde.');
}


// =============================================================
// FUNCION DE RENDERIZADO DE PAGINA HTML
// =============================================================

function _renderPage($type, $title, $message) {
    $icon = $type === 'success' ? '&#10004;' : ($type === 'error' ? '&#10006;' : '&#8505;');
    $bgColor = $type === 'success' ? '#22C55E' : ($type === 'error' ? '#EF4444' : '#3B82F6');
    $accentColor = '#1E4ED8';

    http_response_code($type === 'error' ? 400 : 200);
    header('Content-Type: text/html; charset=UTF-8');

    echo <<<HTML
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Saber+ - Verificacion</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .card {
            background: white;
            border-radius: 24px;
            padding: 48px 32px;
            max-width: 440px;
            width: 100%;
            text-align: center;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }
        .icon {
            width: 80px;
            height: 80px;
            border-radius: 50%;
            background: {$bgColor};
            color: white;
            font-size: 40px;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0 auto 24px;
            font-weight: bold;
        }
        .logo {
            width: 120px;
            margin: 0 auto 16px;
            display: block;
        }
        .title {
            font-size: 24px;
            font-weight: 800;
            color: #1a1a2e;
            margin-bottom: 12px;
        }
        .message {
            font-size: 16px;
            color: #555;
            line-height: 1.6;
            margin-bottom: 32px;
        }
        .btn {
            display: inline-block;
            background: {$accentColor};
            color: white;
            padding: 14px 40px;
            border-radius: 14px;
            text-decoration: none;
            font-size: 16px;
            font-weight: 700;
            transition: transform 0.2s;
        }
        .btn:hover { transform: scale(1.05); }
        .footer {
            margin-top: 24px;
            font-size: 12px;
            color: #999;
        }
    </style>
</head>
<body>
    <div class="card">
        <div class="icon">{$icon}</div>
        <h1 class="title">{$title}</h1>
        <p class="message">{$message}</p>
        <a href="https://corpoinstel.edu.co" class="btn">Ir a Saber+</a>
        <p class="footer">&copy; 2026 Saber+ - Preparacion ICFES Saber 11</p>
    </div>
</body>
</html>
HTML;
}
