<?php
/**
 * logout.php — Cierre de sesión del Panel del Director (Saber+)
 */

require_once __DIR__ . '/includes/auth.php';

// Limpiar la sesión por completo
$_SESSION = [];

// Expirar la cookie de sesión en el navegador
if (ini_get('session.use_cookies')) {
    $params = session_get_cookie_params();
    setcookie(
        session_name(),
        '',
        time() - 42000,
        $params['path'],
        $params['domain'],
        $params['secure'],
        $params['httponly']
    );
}

session_destroy();

header('Location: login.php');
exit;
