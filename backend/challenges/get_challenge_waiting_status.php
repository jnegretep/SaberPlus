<?php
// get_challenge_waiting_status.php
header('Content-Type: application/json');
require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../auth_middleware.php';

$challenge_id = $_GET['challenge_id'] ?? null;

if (!$challenge_id) {
    echo json_encode(['status' => 'error', 'msg' => 'ID de reto requerido']);
    exit;
}

// Obtener tiempo restante del reto
$stmt = $conexion->prepare("
    SELECT 
        TIMESTAMPDIFF(SECOND, NOW(), ended_at) as remaining_seconds
    FROM challenges 
    WHERE id = ?
");
$stmt->execute([$challenge_id]);
$challenge = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$challenge) {
    echo json_encode(['status' => 'error', 'msg' => 'Reto no encontrado']);
    exit;
}

// Calcular tiempo restante y asegurar que sea entero
$remaining_seconds = isset($challenge['remaining_seconds'])
    ? max(0, (int)$challenge['remaining_seconds'])
    : 0;

// Obtener lista de participantes que aún no han terminado
$stmt = $conexion->prepare("
    SELECT 
        u.id_usuario,
        u.nombre,
        cp.finished_at,
        cp.ready_status
    FROM challenge_participants cp
    JOIN usuarios u ON u.id_usuario = cp.user_id
    WHERE cp.challenge_id = ? 
      AND cp.invitation_status = 'aceptado'
      AND (cp.finished_at IS NULL OR cp.ready_status != 'terminado')
");
$stmt->execute([$challenge_id]);
$pending_users = $stmt->fetchAll(PDO::FETCH_ASSOC);

echo json_encode([
    'status' => 'ok',
    'remaining_seconds' => $remaining_seconds,
    'pending_users' => $pending_users
]);
?>
