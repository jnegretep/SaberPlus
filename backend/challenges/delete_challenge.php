<?php
// /var/www/html/api/prepsaber/backend/challenges/delete_challenge.php
declare(strict_types=1);

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Authorization, Content-Type, X-Requested-With");
header("Access-Control-Allow-Methods: POST, DELETE, OPTIONS");

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
    if ($value === null) return '';
    return mb_convert_encoding(
        trim((string)$value),
        'UTF-8',
        'UTF-8, ISO-8859-1, ISO-8859-15'
    );
}

/* ==========================
   INPUT
   ========================== */

$data = json_decode(file_get_contents('php://input'), true);
if (!is_array($data)) {
    $data = $_POST;
}

$authUser = $GLOBALS['authUser'] ?? null;
if (!$authUser || empty($authUser['id_usuario'])) {
    respond(['status'=>'error','msg'=>'No autenticado'], 401);
}

$challengeId = (int)($data['challenge_id'] ?? 0);
$userId      = (int)$authUser['id_usuario'];
$userName    = safeText($authUser['nombre'] ?? 'El creador');

if ($challengeId <= 0) {
    respond(['status'=>'error','msg'=>'challenge_id inválido'], 400);
}

/* ==========================
   LOGIC
   ========================== */

try {

    // 1) Obtener reto
    $stmt = $conexion->prepare("
        SELECT id, creator_id, title, area, level, deleted_at
        FROM challenges
        WHERE id = ?
        LIMIT 1
    ");
    $stmt->execute([$challengeId]);
    $challenge = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$challenge) {
        respond(['status'=>'error','msg'=>'Reto no encontrado'], 404);
    }

    if (!empty($challenge['deleted_at'])) {
        respond(['status'=>'error','msg'=>'El reto ya fue eliminado'], 409);
    }

    if ((int)$challenge['creator_id'] !== $userId) {
        respond(['status'=>'error','msg'=>'Solo el creador puede eliminar este reto'], 403);
    }

    // 2) Participantes (antes de borrar)
    $stmt = $conexion->prepare("
        SELECT user_id
        FROM challenge_participants
        WHERE challenge_id = ?
    ");
    $stmt->execute([$challengeId]);

    $participants = array_values(
        array_filter(
            array_map('intval', $stmt->fetchAll(PDO::FETCH_COLUMN)),
            fn($uid) => $uid !== $userId
        )
    );

    // 3) Transacción
    $conexion->beginTransaction();

    $stmt = $conexion->prepare("
        DELETE FROM challenge_participants
        WHERE challenge_id = ?
    ");
    $stmt->execute([$challengeId]);

    $stmt = $conexion->prepare("
        UPDATE challenges
        SET deleted_at = NOW(),
            status = 'eliminado'
        WHERE id = ?
    ");
    $stmt->execute([$challengeId]);

    $conexion->commit();

    /* ==========================
       NOTIFICACIONES
       ========================== */

    if (!empty($participants)) {

        sendNotificationToMany(
            $participants,
            'challenge_deleted',
            [
                "challenge_id"    => $challengeId,
                "challenge_title" => safeText($challenge['title']),
                "area"            => safeText($challenge['area']),
                "level"           => safeText($challenge['level']),
                "actor" => [
                    "id"   => $userId,
                    "name" => $userName
                ]
            ]
        );

        error_log("[delete_challenge] challenge_deleted -> " . json_encode($participants));
    }

    respond([
        'status'       => 'ok',
        'msg'          => 'Reto eliminado correctamente',
        'challenge_id' => $challengeId
    ]);

} catch (Throwable $e) {

    if ($conexion->inTransaction()) {
        $conexion->rollBack();
    }

    error_log("[delete_challenge][ERROR] " . $e->getMessage());

    respond([
        'status' => 'error',
        'msg'    => 'Error interno al eliminar el reto'
    ], 500);
}
