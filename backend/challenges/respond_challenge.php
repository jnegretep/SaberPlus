<?php
// /var/www/html/api/prepsaber/backend/challenges/respond_challenge.php
declare(strict_types=1);

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Authorization, Content-Type, X-Requested-With");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo '{"ok":true}';
    exit;
}

require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../auth_middleware.php';
require __DIR__ . '/../send_to_many.php';

/* ==========================
   HELPERS
   ========================== */

function respond(array $payload, int $status = 200): void {
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
}

function safeText($value): string {
    if ($value === null || $value === '') return '';
    
    $value = trim((string)$value);
    
    // Si ya es UTF-8 válido, devolverlo tal cual
    if (mb_check_encoding($value, 'UTF-8')) {
        // Verificar si tiene double encoding y corregirlo
        if (preg_match('/\xC3[\x80-\xBF]/', $value)) {
            $value = mb_convert_encoding($value, 'UTF-8', 'UTF-8');
        }
        return $value;
    }
    
    // Si no es UTF-8, convertirlo desde ISO-8859-1
    return mb_convert_encoding($value, 'UTF-8', 'ISO-8859-1');
}

/* ==========================
   INPUT
   ========================== */

$data = json_decode(file_get_contents("php://input"), true);
if (!is_array($data)) {
    respond(['status'=>'error','msg'=>'JSON inválido'], 400);
}

$authUser = $GLOBALS['authUser'] ?? null;
if (!$authUser || empty($authUser['id_usuario'])) {
    respond(['status'=>'error','msg'=>'No autenticado'], 401);
}

$userId = (int)$authUser['id_usuario'];
    
// Obtener nombre REAL del usuario desde la base de datos
$userName = "Un participante";
try {
    $stmt = $conexion->prepare("SELECT nombre FROM usuarios WHERE id_usuario = ?");
    $stmt->execute([$userId]);
    $userRow = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if ($userRow && !empty($userRow['nombre'])) {
        $userName = safeText($userRow['nombre']);
    } else {
        // Fallback a la sesión si no hay en BD
        $userName = safeText($authUser['nombre'] ?? 'Un participante');
    }
    
    error_log("[respond_challenge] userId={$userId}, nombreObtenido={$userName}");
} catch (\Exception $e) {
    $userName = safeText($authUser['nombre'] ?? 'Un participante');
    error_log("[respond_challenge] Error obteniendo nombre: " . $e->getMessage());
}

$challengeId = (int)($data['challenge_id'] ?? 0);
$action      = strtolower(trim($data['action'] ?? ''));

if ($challengeId <= 0 || !in_array($action, ['accept', 'reject'], true)) {
    respond(['status'=>'error','msg'=>'Parámetros inválidos'], 400);
}

/* ==========================
   LOGIC
   ========================== */

try {

    // 1) Reto
    $stmt = $conexion->prepare("SELECT * FROM challenges WHERE id = ?");
    $stmt->execute([$challengeId]);
    $challenge = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$challenge) {
        respond(['status'=>'error','msg'=>'Reto no encontrado'], 404);
    }

    // 2) Participante
    $stmt = $conexion->prepare("
        SELECT id FROM challenge_participants
        WHERE challenge_id=? AND user_id=?
        LIMIT 1
    ");
    $stmt->execute([$challengeId, $userId]);
    $participant = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$participant) {
        respond(['status'=>'error','msg'=>'No estás invitado'], 403);
    }

    // 3) Actualizar estado
    $newStatus = ($action === 'accept') ? 'aceptado' : 'rechazado';

    $stmt = $conexion->prepare("
        UPDATE challenge_participants
        SET invitation_status=?
        WHERE id=?
    ");
    $stmt->execute([$newStatus, $participant['id']]);

    /* ==========================
       NOTIFICACIONES
       ========================== */

    $stmt = $conexion->prepare("
        SELECT user_id FROM challenge_participants
        WHERE challenge_id = ?
    ");
    $stmt->execute([$challengeId]);

    $targets = array_values(
        array_filter(
            array_map('intval', $stmt->fetchAll(PDO::FETCH_COLUMN)),
            fn($uid) => $uid !== $userId
        )
    );

    if (!empty($targets)) {

        $type = ($newStatus === 'aceptado')
            ? 'challenge_accepted'
            : 'challenge_rejected';

        // Asegurar que el título del reto esté limpio
        $challengeTitle = safeText($challenge['title'] ?? '');
        if (empty($challengeTitle)) {
            $challengeTitle = "Reto #{$challengeId}";
        }

        sendNotificationToMany(
            $targets,
            $type,
            [
                "challenge_id"    => $challengeId,
                "challenge_title" => $challengeTitle,
                "area"            => safeText($challenge['area'] ?? ''),
                "level"           => safeText($challenge['level'] ?? ''),
                "actor" => [
                    "id"   => $userId,
                    "name" => $userName
                ]
            ]
        );

        error_log("[respond_challenge] {$type} enviado a " . json_encode($targets) . 
                  " challenge_id={$challengeId}, actor={$userName}, title={$challengeTitle}");
    }

    /* ==========================
       RESPONSE
       ========================== */

    respond([
        'status' => 'ok',
        'msg'    => "Has {$newStatus} la invitación",
        'challenge_id' => $challengeId
    ]);

} catch (Throwable $e) {

    error_log("[respond_challenge][ERROR] " . $e->getMessage());

    respond([
        'status' => 'error',
        'msg'    => 'Error interno'
    ], 500);
}