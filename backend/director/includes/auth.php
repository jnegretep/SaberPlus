<?php
/**
 * includes/auth.php — Guard de sesión del Panel del Director (Saber+)
 *
 * Todas las páginas del panel empiezan con:
 *     require_once __DIR__ . '/includes/auth.php';
 *     require_once __DIR__ . '/includes/ui.php';
 *     $director = require_director($conexion);
 *
 * - Inicia la sesión con cookie HttpOnly y SameSite=Lax.
 * - Genera/reusa el token CSRF en $_SESSION['csrf'].
 * - Exige $_SESSION['director_id'] Y que el director siga activo en BD
 *   (si el admin lo desactiva, su sesión deja de valer al instante).
 * - Si algo falla → redirect a login.php.
 */

if (session_status() === PHP_SESSION_NONE) {
    // Cookies de sesión endurecidas (httponly ya es default, lo dejamos explícito)
    session_set_cookie_params([
        'httponly' => true,
        'samesite' => 'Lax',
    ]);
    session_start();
}

require_once __DIR__ . '/../../includes/conexion.php';

// ── Token CSRF de sesión ──
if (empty($_SESSION['csrf']) || !is_string($_SESSION['csrf'])) {
    $_SESSION['csrf'] = bin2hex(random_bytes(32));
}

/** Devuelve el token CSRF actual de la sesión. */
function csrf_token(): string
{
    return $_SESSION['csrf'];
}

/** Campo hidden listo para incrustar en cualquier <form method="POST">. */
function csrf_field(): string
{
    return '<input type="hidden" name="csrf" value="'
        . htmlspecialchars(csrf_token(), ENT_QUOTES, 'UTF-8') . '">';
}

/** Verifica el token CSRF de un POST; corta la ejecución si es inválido. */
function csrf_verify(): void
{
    $enviado = (string)($_POST['csrf'] ?? '');
    if ($enviado === '' || !hash_equals($_SESSION['csrf'], $enviado)) {
        http_response_code(403);
        exit('Token CSRF inválido. Vuelve al panel e inténtalo de nuevo.');
    }
}

/** htmlspecialchars abreviado: usar en TODA salida HTML de datos de BD. */
function e($texto): string
{
    return htmlspecialchars((string)$texto, ENT_QUOTES, 'UTF-8');
}

/**
 * Guard principal del panel: exige sesión de director válida y activa.
 * Devuelve array con id, nombre, email y colegio del director.
 */
function require_director(PDO $conexion): array
{
    if (empty($_SESSION['director_id'])) {
        header('Location: login.php');
        exit;
    }

    try {
        $stmt = $conexion->prepare(
            "SELECT id, nombre, email, colegio
             FROM directores
             WHERE id = :id AND activo = 1
             LIMIT 1"
        );
        $stmt->execute([':id' => (int)$_SESSION['director_id']]);
        $director = $stmt->fetch(PDO::FETCH_ASSOC);
    } catch (PDOException $ex) {
        error_log('[DIRECTOR] Error cargando director: ' . $ex->getMessage());
        $director = false;
    }

    if (!$director) {
        // Sesión inválida, o el admin desactivó al director → fuera
        $_SESSION = [];
        session_destroy();
        header('Location: login.php');
        exit;
    }

    return $director;
}
