<?php
// force_finish_challenge.php
header('Content-Type: application/json');
require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../auth_middleware.php';
require __DIR__ . '/../includes/moodle.php';

$data = json_decode(file_get_contents('php://input'), true);
$challenge_id = $data['challenge_id'] ?? null;
$user_id = $GLOBALS['authUser']['id_usuario'] ?? null;

if (!$challenge_id || !$user_id) {
    echo json_encode(['status' => 'error', 'msg' => 'Datos incompletos']);
    exit;
}

try {
    // Obtener información del reto
    $stmt = $conexion->prepare("
        SELECT status, started_at, duration_minutes 
        FROM challenges 
        WHERE id = ? 
        LIMIT 1
    ");
    $stmt->execute([$challenge_id]);
    $challenge = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$challenge) {
        echo json_encode(['status' => 'error', 'msg' => 'Reto no encontrado']);
        exit;
    }
    
    // Si el reto ya está finalizado, no hacer nada
    if ($challenge['status'] === 'finalizado') {
        echo json_encode([
            'status' => 'ok',
            'msg' => 'Reto ya finalizado',
            'all_finished' => true
        ]);
        exit;
    }
    
    // Obtener TODOS los participantes pendientes, no solo el usuario actual
    $stmt = $conexion->prepare("
        SELECT 
            cp.id,
            cp.user_id,
            cp.moodle_attempt_id,
            cp.start_time,
            cp.end_time,
            u.moodle_token
        FROM challenge_participants cp
        JOIN usuarios u ON u.id_usuario = cp.user_id
        WHERE cp.challenge_id = ? 
        AND cp.invitation_status = 'aceptado'
        AND cp.ready_status != 'terminado'
    ");
    $stmt->execute([$challenge_id]);
    $pendingParticipants = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    // Procesar cada participante pendiente
    foreach ($pendingParticipants as $participant) {
        $score = 0;
        $answersJson = null;
        
        // Si tiene intento en Moodle, obtener puntaje real
        if (!empty($participant['moodle_attempt_id']) && !empty($participant['moodle_token'])) {
            try {
                $mc = getMoodleClient();
                $review = $mc->request($participant['moodle_token'], 'mod_quiz_get_attempt_review', [
                    'attemptid' => (int)$participant['moodle_attempt_id']
                ]);
                
                if (isset($review['grade'])) {
                    $score = (float)$review['grade'];
                }
                
                // También intentar obtener las respuestas si están disponibles
                if (isset($review['attempt']['timestart']) && isset($review['attempt']['timefinish'])) {
                    $answersJson = json_encode([
                        'grade' => $score,
                        'timestart' => $review['attempt']['timestart'],
                        'timefinish' => $review['attempt']['timefinish']
                    ]);
                }
            } catch (Exception $e) {
                error_log("Error obteniendo puntaje de Moodle para user_id={$participant['user_id']}: " . $e->getMessage());
                // Continuar con score=0
            }
        }
        
        // Calcular tiempo empleado real
        $elapsed = 0;
        if (!empty($participant['start_time'])) {
            $start = new DateTime($participant['start_time']);
            $end = new DateTime(); // Momento actual (cuando se fuerza)
            $elapsed = $end->getTimestamp() - $start->getTimestamp();
            
            // Asegurarse de que no sea negativo
            $elapsed = max(0, $elapsed);
        }
        
        // Actualizar el participante con score y tiempo real
        $updateStmt = $conexion->prepare("
            UPDATE challenge_participants 
            SET ready_status = 'terminado', 
                finished_at = NOW(),
                end_time = NOW(),
                score = ?,
                answers_json = ?,
                elapsed_seconds = ?
            WHERE id = ?
        ");
        $updateStmt->execute([
            $score,
            $answersJson,
            $elapsed,
            $participant['id']
        ]);
    }
    
    // Marcar el reto como finalizado
    $updateChallenge = $conexion->prepare("
        UPDATE challenges 
        SET status = 'finalizado',
            ended_at = NOW()
        WHERE id = ?
    ");
    $updateChallenge->execute([$challenge_id]);
    
    // Verificar estado final
    $stmt = $conexion->prepare("
        SELECT 
            COUNT(*) as total,
            SUM(CASE WHEN ready_status = 'terminado' THEN 1 ELSE 0 END) as terminados
        FROM challenge_participants
        WHERE challenge_id = ? AND invitation_status = 'aceptado'
    ");
    $stmt->execute([$challenge_id]);
    $result = $stmt->fetch(PDO::FETCH_ASSOC);
    
    echo json_encode([
        'status' => 'ok',
        'msg' => 'Reto finalizado forzosamente para todos los participantes',
        'all_finished' => ($result['terminados'] == $result['total']),
        'updated_participants' => count($pendingParticipants)
    ]);
    
} catch (Exception $e) {
    error_log("Error en force_finish_challenge: " . $e->getMessage());
    echo json_encode(['status' => 'error', 'msg' => $e->getMessage()]);
}
?>