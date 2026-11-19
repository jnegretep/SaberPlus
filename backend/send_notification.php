<?php
declare(strict_types=1);

/**
 * send_notification.php — Notificación FCM a UN usuario + registro en bandeja.
 *
 * v2 (2026-10):
 *   - ?? AUTENTICACIÓN OBLIGATORIA: JWT del propio usuario (solo puede
 *     notificarse a sí mismo) o sesión/token interno de admin.
 *   - ?? Service account unificado (includes/firebase_factory.php).
 *   - ?? Si el token del usuario está muerto (app desinstalada/reinstalada),
 *     se borra de la BD para que se re-registre en el próximo inicio.
 *
 * v2.0.1 (2026-11-07):
 *   - ?? FIX: `require_once __DIR__ . '/jwt_config.php'` no capturaba el
 *     array que retorna el archivo ? `$configJwt` era null ? JWT::decode()
 *     explotaba con `Key material must be a string` (HTTP 500). Ahora se
 *     usa `$configJwt = require __DIR__ . '/jwt_config.php'`.
 */

require_once __DIR__ . '/vendor/autoload.php';
require_once __DIR__ . '/includes/conexion.php';
require_once __DIR__ . '/includes/firebase_factory.php';

// ? FIX: captura el array retornado por jwt_config.php
$configJwt = require __DIR__ . '/jwt_config.php';

use Kreait\Firebase\Messaging\CloudMessage;
use Kreait\Firebase\Messaging\Notification;
use Firebase\JWT\JWT;
use Firebase\JWT\Key;

mb_internal_encoding("UTF-8");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: Content-Type, Authorization, X-Internal-Token");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit(json_encode(['success' => false, 'error' => 'Método no permitido']));
}

// -- Datos base --
$rawBody = file_get_contents("php://input");
$data = json_decode($rawBody, true) ?? [];
array_walk_recursive($data, function (&$item) {
    if (is_string($item) && !mb_check_encoding($item, 'UTF-8')) {
        $item = mb_convert_encoding($item, 'UTF-8', 'Windows-1252, ISO-8859-1');
    }
});

$idDestino = (int)($data['id_usuario'] ?? 0);
$type      = trim((string)($data['type'] ?? 'info'));
$eventData = is_array($data['data'] ?? null) ? $data['data'] : [];
$title     = trim((string)($data['title'] ?? ''));
$body      = trim((string)($data['body'] ?? ''));
$action    = trim((string)($eventData['action'] ?? 'go_dashboard'));

// -- Autenticación --
// Caso A: admin (sesión del panel o X-Internal-Token) ? puede notificar a cualquiera.
// Caso B: JWT de usuario ? solo puede notificarse a SÍ MISMO.
$idPermitido = null;

if (session_status() === PHP_SESSION_NONE) { @session_start(); }
$esAdminSesion = isset($_SESSION['admin_logged_in']) && $_SESSION['admin_logged_in'] === true;

$internalToken = env('INTERNAL_TOKEN', '');
$headerToken   = $_SERVER['HTTP_X_INTERNAL_TOKEN'] ?? '';
$esTokenInterno = ($internalToken !== '' && $internalToken !== null)
    && hash_equals($internalToken, (string)$headerToken);

if ($esAdminSesion || $esTokenInterno) {
    $idPermitido = $idDestino; // admin: cualquiera
} else {
    $allHeaders = function_exists('getallheaders') ? getallheaders() : [];
    $authHeader = $allHeaders['Authorization'] ?? $allHeaders['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
        try {
            $decoded = JWT::decode($m[1], new Key($configJwt['secret'], 'HS256'));
            $idPropio = (int)($decoded->data->id_usuario ?? 0);
            if ($idPropio > 0 && $idPropio === $idDestino) {
                $idPermitido = $idDestino; // usuario: solo a sí mismo
            }
        } catch (Exception $e) {
            // token inválido ? sin permiso
        }
    }
}

if ($idPermitido === null || $idDestino <= 0) {
    http_response_code(403);
    exit(json_encode(['success' => false, 'error' => 'No autorizado'], JSON_UNESCAPED_UNICODE));
}

// -- Título/cuerpo por defecto según tipo de evento (si no vienen explícitos) --
if ($title === '' || $body === '') {
    $actorName = trim((string)($eventData['actor']['name'] ?? ''));
    switch ($type) {
        case 'reto':
            $title = $title ?: '¡Nuevo reto!';
            $body  = $body  ?: ($actorName !== '' ? "$actorName te ha retado" : 'Tienes un nuevo reto esperándote');
            $action = $action !== 'go_dashboard' ? $action : 'go_daily_challenges';
            break;
        case 'logro':
            $title = $title ?: '¡Logro desbloqueado!';
            $body  = $body  ?: 'Consigue un logro nuevo en Saber+';
            $action = $action !== 'go_dashboard' ? $action : 'go_achievements';
            break;
        case 'nivel':
            $title = $title ?: '¡Subiste de nivel!';
            $body  = $body  ?: 'Tu esfuerzo está dando resultados';
            break;
        case 'racha':
            $title = $title ?: 'Tu racha está en riesgo';
            $body  = $body  ?: 'Practica hoy para no perder tu racha';
            break;
        default:
            $title = $title ?: 'Saber+';
            $body  = $body  ?: 'Tienes una nueva notificación';
    }
}

// -- Buscar token del destino --
try {
    $stmt = $conexion->prepare("SELECT fcm_token FROM usuarios WHERE id_usuario = :id");
    $stmt->execute([":id" => $idDestino]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
} catch (Throwable $e) {
    http_response_code(500);
    exit(json_encode(['success' => false, 'error' => 'Error BD'], JSON_UNESCAPED_UNICODE));
}

if (!$row || empty($row['fcm_token'])) {
    http_response_code(404);
    exit(json_encode(['success' => false, 'error' => 'Usuario sin token FCM'], JSON_UNESCAPED_UNICODE));
}

$token = $row['fcm_token'];

// -- Enviar --
try {
    $messaging = saberplus_fcm_messaging();

    $message = CloudMessage::withTarget('token', $token)
        ->withNotification(Notification::create($title, $body))
        ->withData([
            'type' => $type,
            'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
            'action' => $action,
        ])
        // ?? Prioridad alta + canal: entrega fiable con la app en background/doze
        ->withAndroidConfig([
            'priority' => 'high',
            'notification' => [
                'channel_id' => 'saberplus_notificaciones',
                'sound' => 'default',
            ],
        ]);

    $result = $messaging->send($message);

    // Registrar en bandeja interna
    try {
        $stmtInsert = $conexion->prepare("
            INSERT INTO notifications (user_id, type, title, body, payload_json)
            VALUES (:uid, :type, :title, :body, :payload)
        ");
        $stmtInsert->execute([
            ':uid' => $idDestino,
            ':type' => $type,
            ':title' => $title,
            ':body' => $body,
            ':payload' => json_encode(['action' => $action], JSON_UNESCAPED_UNICODE),
        ]);
    } catch (Throwable $t) {
        error_log('[SEND_NOTIF] Insert bandeja: ' . $t->getMessage());
    }

    echo json_encode(['success' => true, 'fcm_result' => $result], JSON_UNESCAPED_UNICODE);

} catch (Throwable $e) {
    $msg = $e->getMessage();
    error_log('[SEND_NOTIF] Error FCM: ' . $msg);

    // ?? Token muerto ? limpiar para que se re-registre
    if (saberplus_fcm_token_muerto($msg)) {
        saberplus_fcm_limpiar_tokens([$token], $conexion);
        echo json_encode([
            'success' => false,
            'error' => 'El dispositivo ya no está registrado (se limpió el token viejo; se re-registrará al abrir la app).',
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }

    http_response_code(502);
    echo json_encode(['success' => false, 'error' => $msg], JSON_UNESCAPED_UNICODE);
}