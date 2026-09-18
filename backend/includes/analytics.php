<?php
declare(strict_types=1);

/**
 * includes/analytics.php — Saber+ v1.6.0
 *
 * Helpers centralizados para:
 *  - Registrar eventos de analítica en la tabla `app_events`
 *    (espejo propio de Firebase Analytics, visible en el panel admin).
 *  - Registrar errores en `error_logs` (app y backend).
 *
 * Ambos son BEST-EFFORT: nunca lanzan excepción ni interrumpen la
 * respuesta al cliente. Si la tabla no existe aún (migración 003 no
 * aplicada), el intento queda registrado en error_log de PHP y se
 * continúa normalmente.
 *
 * Requiere la conexión PDO global $conexion.
 */

require_once __DIR__ . '/../env.php';

if (!function_exists('saberplus_registrar_evento')) {

    /**
     * Inserta un evento de analítica en app_events.
     *
     * @param PDO         $conexion   Conexión activa.
     * @param int|null    $userId     ID del usuario (null = anónimo).
     * @param string      $eventName  Nombre del evento (máx 64 chars).
     * @param array       $params     Payload adicional (se serializa a JSON, máx ~2 KB).
     * @param string|null $platform   android | ios | web (null = deducir del User-Agent).
     * @param string|null $appVersion Versión de la app reportada.
     */
    function saberplus_registrar_evento(
        PDO $conexion,
        ?int $userId,
        string $eventName,
        array $params = [],
        ?string $platform = null,
        ?string $appVersion = null
    ): void {
        try {
            if ($platform === null) {
                $ua = strtolower($_SERVER['HTTP_USER_AGENT'] ?? '');
                if (str_contains($ua, 'android')) {
                    $platform = 'android';
                } elseif (str_contains($ua, 'iphone') || str_contains($ua, 'ipad')) {
                    $platform = 'ios';
                } else {
                    $platform = 'web';
                }
            }

            $json = json_encode($params, JSON_UNESCAPED_UNICODE);
            if (strlen((string)$json) > 2048) {
                $json = json_encode(['truncated' => true], JSON_UNESCAPED_UNICODE);
            }

            $stmt = $conexion->prepare(
                "INSERT INTO app_events (user_id, event_name, platform, app_version, params)
                 VALUES (?, ?, ?, ?, ?)"
            );
            $stmt->execute([
                $userId,
                substr($eventName, 0, 64),
                substr($platform, 0, 16),
                $appVersion !== null ? substr($appVersion, 0, 24) : null,
                $json,
            ]);
        } catch (Throwable $e) {
            error_log('[ANALYTICS] No se pudo registrar evento "' . $eventName . '": ' . $e->getMessage());
        }
    }
}

if (!function_exists('saberplus_log_error')) {

    /**
     * Inserta un error en error_logs.
     *
     * @param PDO         $conexion  Conexión activa.
     * @param string      $source    'app' (reportado por la app) o 'backend'.
     * @param string      $message   Mensaje del error.
     * @param array       $context   Contexto adicional (pantalla, request, etc.).
     * @param string|null $errorCode Código corto (DioException, PDOException...).
     * @param string|null $severity  info | warning | error | fatal.
     * @param int|null    $userId    Usuario afectado (si se conoce).
     * @param string|null $stack     Stack trace.
     */
    function saberplus_log_error(
        PDO $conexion,
        string $source,
        string $message,
        array $context = [],
        ?string $errorCode = null,
        ?string $severity = 'error',
        ?int $userId = null,
        ?string $stack = null
    ): void {
        try {
            $json = json_encode($context, JSON_UNESCAPED_UNICODE);
            if (strlen((string)$json) > 2048) {
                $json = null;
            }

            $stmt = $conexion->prepare(
                "INSERT INTO error_logs
                    (user_id, source, severity, error_code, message, stack_trace, context, platform, app_version)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
            );
            $stmt->execute([
                $userId,
                substr($source, 0, 16),
                in_array($severity, ['info', 'warning', 'error', 'fatal'], true) ? $severity : 'error',
                $errorCode !== null ? substr($errorCode, 0, 48) : null,
                substr($message, 0, 65535),
                $stack !== null ? substr($stack, 0, 65535) : null,
                $json,
                null,
                null,
            ]);
        } catch (Throwable $e) {
            error_log('[ERROR_LOG] No se pudo registrar error: ' . $e->getMessage());
        }
    }
}
