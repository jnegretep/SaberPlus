<?php
/**
 * includes/firebase_factory.php — Inicialización unificada de Firebase (FCM)
 *
 * PROBLEMA que resuelve: los scripts de notificaciones referenciaban el
 * service account en DOS rutas distintas:
 *   - backend/saberplus-XXXX-firebase-adminsdk-XXXX.json (raíz)
 *   - backend/config/firebase-service-account.json
 * Según qué archivo estuviera en el servidor, unos scripts funcionaban y
 * otros morían con "Error Firebase" → notificaciones intermitentes.
 *
 * SOLUCIÓN: un único helper que busca el service account en varias rutas
 * (configurable vía FIREBASE_SERVICE_ACCOUNT en backend/.env) y crea el
 * Messaging listo para usar. Además, expone utilidades para limpiar tokens
 * FCM muertos (dispositivos desinstalados/reinstalados), que tras el cambio
 * de nombre de la app (PrepSaber → Saber+) quedaron huérfanos en la BD.
 *
 * Uso:
 *   require_once __DIR__ . '/firebase_factory.php';
 *   $messaging = saberplus_fcm_messaging();
 *   // enviar... y luego limpiar inválidos:
 *   saberplus_fcm_limpiar_tokens_invalidos($conexion, $report);
 */

declare(strict_types=1);

require_once __DIR__ . '/../env.php';

/**
 * Devuelve la ruta del service account de Firebase disponible.
 * Orden: FIREBASE_SERVICE_ACCOUNT (.env) → config/ → raíz (patrón *firebase-adminsdk*).
 * Lanza Exception si no hay ninguno (con mensaje claro de qué hacer).
 */
function saberplus_service_account_path(): string {
    // 1. Ruta explícita en backend/.env
    $explicit = env('FIREBASE_SERVICE_ACCOUNT', '');
    if ($explicit !== '' && $explicit !== null && is_readable($explicit)) {
        return $explicit;
    }
    if ($explicit !== '' && $explicit !== null && is_readable(__DIR__ . '/../' . $explicit)) {
        return __DIR__ . '/../' . $explicit;
    }

    // 2. Ruta canónica en config/
    $configPath = __DIR__ . '/../config/firebase-service-account.json';
    if (is_readable($configPath)) {
        return $configPath;
    }

    // 3. Cualquier *firebase-adminsdk*.json en la raíz del backend
    foreach (glob(__DIR__ . '/../saberplus-*-firebase-adminsdk-*.json') ?: [] as $f) {
        if (is_readable($f)) {
            return $f;
        }
    }
    foreach (glob(__DIR__ . '/../*firebase-adminsdk*.json') ?: [] as $f) {
        if (is_readable($f)) {
            return $f;
        }
    }

    throw new RuntimeException(
        'No se encontró el service account de Firebase. Colócalo en '
        . 'backend/config/firebase-service-account.json (o define '
        . 'FIREBASE_SERVICE_ACCOUNT en backend/.env). Descárgalo de '
        . 'Firebase Console → Configuración del proyecto → Cuentas de servicio '
        . '→ Generar clave privada.'
    );
}

/**
 * Crea el objeto Messaging de Firebase Kreait.
 */
function saberplus_fcm_messaging(): \Kreait\Firebase\Messaging {
    $factory = (new \Kreait\Firebase\Factory())
        ->withServiceAccount(saberplus_service_account_path());
    return $factory->createMessaging();
}

/**
 * Elimina de la BD los tokens FCM que Firebase reporta como inválidos
 * (UNREGISTERED / INVALID_ARGUMENT / SENDER_ID_MISMATCH). Así la tabla no
 * acumula tokens de instalaciones viejas y las métricas de envío son reales.
 *
 * @param PDO $conexion   Conexión a la BD Saber+
 * @param array $tokensInvalidos  Lista de tokens a borrar
 * @return int Número de tokens eliminados
 */
function saberplus_fcm_limpiar_tokens(array $tokensInvalidos, PDO $conexion): int {
    $tokensInvalidos = array_values(array_unique(array_filter($tokensInvalidos)));
    if (empty($tokensInvalidos)) {
        return 0;
    }
    try {
        $placeholders = implode(',', array_fill(0, count($tokensInvalidos), '?'));
        $stmt = $conexion->prepare("UPDATE usuarios SET fcm_token = NULL WHERE fcm_token IN ($placeholders)");
        $stmt->execute($tokensInvalidos);
        $n = $stmt->rowCount();
        if ($n > 0) {
            error_log('[FCM][LIMPIEZA] ' . $n . ' tokens inválidos eliminados de la BD');
        }
        return $n;
    } catch (Throwable $e) {
        error_log('[FCM][LIMPIEZA] Error limpiando tokens: ' . $e->getMessage());
        return 0;
    }
}

/**
 * ¿El error de FCM significa que el token está muerto y debe borrarse?
 */
function saberplus_fcm_token_muerto(string $mensajeError): bool {
    $m = strtolower($mensajeError);
    return str_contains($m, 'unregistered')
        || str_contains($m, 'not a valid fcm token')
        || str_contains($m, 'invalid_argument')
        || str_contains($m, 'sender id mismatch')
        || str_contains($m, 'registration-token-not-registered')
        || str_contains($m, 'it is not known to firebase');
}

/**
 * Guard de acceso para endpoints administrativos de envío:
 * sesión de admin O cabecera X-Internal-Token (backend/.env).
 * Evita que CUALQUIERA pueda disparar notificaciones masivas.
 */
function saberplus_guard_admin_fcm(): void {
    if (session_status() === PHP_SESSION_NONE) {
        session_start();
    }
    $esAdmin = isset($_SESSION['admin_logged_in']) && $_SESSION['admin_logged_in'] === true;
    if ($esAdmin) {
        return;
    }
    // CLI permitido (crons del servidor)
    if (PHP_SAPI === 'cli') {
        return;
    }
    $internalToken = env('INTERNAL_TOKEN', '');
    $headerToken   = $_SERVER['HTTP_X_INTERNAL_TOKEN'] ?? '';
    if (($internalToken !== '' && $internalToken !== null)
        && hash_equals($internalToken, (string)$headerToken)) {
        return;
    }
    http_response_code(403);
    header('Content-Type: application/json; charset=UTF-8');
    exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
}
