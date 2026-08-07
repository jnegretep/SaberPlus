<?php
// get_challenge_time.php
header('Content-Type: application/json');
require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../auth_middleware.php';

$challenge_id = $_GET['challenge_id'] ?? null;

if (!$challenge_id) {
    echo json_encode(['status' => 'error', 'msg' => 'ID de reto requerido']);
    exit;
}

// Obtener tiempos del reto
$stmt = $conexion->prepare("
    SELECT 
        started_at,
        ended_at,
        duration_minutes,
        status,
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

// Calcular tiempo restante exacto y asegurar que sea entero
$remaining_seconds = isset($challenge['remaining_seconds'])
    ? max(0, (int)$challenge['remaining_seconds'])
    : 0;

// Asegurar que duration_minutes sea entero
$duration_minutes = isset($challenge['duration_minutes'])
    ? (int)$challenge['duration_minutes']
    : 0;

echo json_encode([
    'status' => 'ok',
    'server_time' => time(),
    'server_datetime' => date('Y-m-d H:i:s'),
    'challenge' => [
        'started_at' => $challenge['started_at'],
        'ended_at' => $challenge['ended_at'],
        'remaining_seconds' => $remaining_seconds,
        'duration_minutes' => $duration_minutes,
        'status' => $challenge['status']
    ]
]);
?>
