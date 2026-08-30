<?php
/**
 * helpers/response.php
 * Función única para emitir JSON consistente.
 */

declare(strict_types=1);

/**
 * Envía una respuesta JSON estándar y termina la ejecución.
 *
 * @param bool       $success
 * @param mixed      $data
 * @param string     $message
 * @param int        $httpCode
 * @param array|null $errors   Detalles de errores de validación.
 */
function send_json(bool $success, $data = null, string $message = '', int $httpCode = 200, ?array $errors = null): void
{
    http_response_code($httpCode);
    header('Content-Type: application/json; charset=utf-8');

    $payload = [
        'success' => $success,
        'message' => $message,
        'data'    => $data,
    ];
    if ($errors !== null) {
        $payload['errors'] = $errors;
    }

    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

/** Acceso directo a payload de error. */
function send_error(string $message, string $code = 'ERROR', int $httpCode = 400, $details = null): void
{
    send_json(false, ['code' => $code, 'details' => $details], $message, $httpCode);
}
