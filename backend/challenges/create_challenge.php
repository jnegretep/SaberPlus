<?php

declare(strict_types=1);

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../auth_middleware.php';
require __DIR__ . '/../send_to_many.php';

/* ==========================
   HELPERS
   ========================== */

function respond(array $res){
    echo json_encode($res, JSON_UNESCAPED_UNICODE);
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
   ENTRADA
   ========================== */

try {

    $data = json_decode(file_get_contents("php://input"), true);
    if (!is_array($data)) {
        respond(["status"=>"error","msg"=>"JSON inválido"]);
    }

    $authUser = $GLOBALS['authUser'] ?? null;
    if (!$authUser) {
        respond(["status"=>"error","msg"=>"No autenticado"]);
    }

    $creatorId = (int)$authUser["id_usuario"];
    
    // Obtener nombre REAL del usuario desde la base de datos
    $creatorName = "Un usuario";
    try {
        $stmt = $conexion->prepare("SELECT nombre FROM usuarios WHERE id_usuario = ?");
        $stmt->execute([$creatorId]);
        $userRow = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if ($userRow && !empty($userRow['nombre'])) {
            $creatorName = safeText($userRow['nombre']);
        } else {
            // Fallback a la sesión si no hay en BD
            $creatorName = safeText($authUser["nombre"] ?? "Un usuario");
        }
        
        error_log("[create_challenge] creatorId={$creatorId}, nombreObtenido={$creatorName}");
    } catch (\Exception $e) {
        $creatorName = safeText($authUser["nombre"] ?? "Un usuario");
        error_log("[create_challenge] Error obteniendo nombre: " . $e->getMessage());
    }

    $title     = safeText($data["title"] ?? "");
    $area      = safeText($data["area"] ?? "");
    $level     = safeText($data["level"] ?? "");
    $quizId    = (int)($data["quiz_id"] ?? 0);
    $scheduled = $data["scheduled_datetime"] ?? "";
    $duration  = (int)($data["duration_minutes"] ?? 20);
    $userIds   = is_array($data["user_ids"] ?? null) ? $data["user_ids"] : [];

    if ($title === '' || !$quizId || !$scheduled) {
        respond(["status"=>"error","msg"=>"Datos incompletos"]);
    }

    /* ======================
       TRANSACCIÓN
       ====================== */

    $conexion->beginTransaction();

    // Crear reto
    $stmt = $conexion->prepare("
        INSERT INTO challenges
        (creator_id,title,area,level,quiz_id,scheduled_datetime,duration_minutes,status)
        VALUES (?,?,?,?,?,?,?,'pendiente')
    ");
    $stmt->execute([
        $creatorId,
        $title,
        $area,
        $level,
        $quizId,
        date("Y-m-d H:i:s", strtotime($scheduled)),
        $duration
    ]);

    $challengeId = (int)$conexion->lastInsertId();
    if ($challengeId <= 0) {
        throw new Exception("No se pudo crear el reto");
    }

    // Insertar creador como participante
    $stmt = $conexion->prepare("
        INSERT INTO challenge_participants
        (challenge_id,user_id,invitation_status,ready_status)
        VALUES (?,?, 'aceptado','esperando')
    ");
    $stmt->execute([$challengeId, $creatorId]);

    if ($stmt->rowCount() !== 1) {
        throw new Exception("No se pudo agregar al creador");
    }

    // Insertar invitados
    $insInv = $conexion->prepare("
        INSERT IGNORE INTO challenge_participants
        (challenge_id,user_id,invitation_status,ready_status)
        VALUES (?,?, 'pendiente','esperando')
    ");

    $notifyUsers = [];

    foreach (array_unique(array_map('intval', $userIds)) as $uid) {
        if ($uid <= 0 || $uid === $creatorId) continue;

        $insInv->execute([$challengeId, $uid]);
        if ($insInv->rowCount() === 1) {
            $notifyUsers[] = $uid;
        }
    }

    $conexion->commit();

} catch (Throwable $e) {

    if ($conexion->inTransaction()) {
        $conexion->rollBack();
    }

    respond([
        "status" => "error",
        "msg"    => $e->getMessage()
    ]);
}

/* ===========================
   NOTIFICACIONES (POST-COMMIT)
   =========================== */

try {

    if (!empty($notifyUsers)) {

        sendNotificationToMany(
            $notifyUsers,
            'challenge_created',
            [
                // Identidad del reto
                "challenge_id"    => $challengeId,
                "challenge_title" => $title,
                "area"            => $area,
                "level"           => $level,

                // Actor normalizado
                "actor" => [
                    "id"   => $creatorId,
                    "name" => $creatorName
                ]
            ]
        );

        error_log(
            "[create_challenge] challenge_created enviado a "
            . json_encode($notifyUsers)
            . " challenge_id={$challengeId}"
        );

    } else {
        error_log("[create_challenge] No hay invitados para notificar");
    }

} catch (Throwable $e) {
    error_log("[create_challenge][notify_error] ".$e->getMessage());
}

/* ===========================
   RESPUESTA FINAL
   =========================== */

respond([
    "status"       => "success",
    "challenge_id" => $challengeId
]);