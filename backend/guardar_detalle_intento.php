<?php
declare(strict_types=1);

// 1) CORS y headers
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
}

// 2) Dependencias
require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php';
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

// 3) Extraer token JWT
function extractJWTToken(): string {
    $allHeaders = function_exists('getallheaders') ? getallheaders() : [];
    $authHeader = $allHeaders['Authorization'] ?? $allHeaders['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $matches)) {
        http_response_code(401);
        exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
    }
    return $matches[1];
}

$appToken = extractJWTToken();

try {
    $decoded = JWT::decode($appToken, new Key($configJwt['secret'], 'HS256'));
    $moodleUserId = (int)($decoded->data->moodle_userid ?? 0);
    $userId = (int)($decoded->data->id_usuario ?? 0);
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Token inválido']));
}

// 4) Leer datos enviados por la app
$input = json_decode(file_get_contents('php://input'), true);
if (!$input) {
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'JSON inválido']));
}

$attemptId = (int)($input['attemptId'] ?? 0);
$quizId    = (int)($input['quizId'] ?? 0);
$questions = $input['questions'] ?? []; // array con los datos de cada pregunta

if (!$attemptId || !$quizId || empty($questions)) {
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'Faltan datos requeridos']));
}

// 5) Obtener id_usuario local
$stmtUser = $conexion->prepare("SELECT id_usuario FROM usuarios WHERE moodle_id = :moodle_id LIMIT 1");
$stmtUser->execute([':moodle_id' => $moodleUserId]);
$userRow = $stmtUser->fetch(PDO::FETCH_ASSOC);
if (!$userRow) {
    http_response_code(404);
    exit(json_encode(['status' => 'error', 'msg' => 'Usuario no encontrado']));
}
$idUsuario = (int)$userRow['id_usuario'];

// 6) Preparar inserción (reemplazar si ya existe para permitir actualización)
$sql = "INSERT INTO respuestas_detalle 
        (id_usuario, attempt_id, quiz_id, pregunta_id, slot, respuesta_usuario, es_correcta, puntaje_obtenido, puntaje_maximo, tags, fecha_respuesta)
        VALUES (:id_usuario, :attempt_id, :quiz_id, :pregunta_id, :slot, :respuesta, :correcta, :puntaje_obtenido, :puntaje_maximo, :tags, NOW())
        ON DUPLICATE KEY UPDATE
        respuesta_usuario = VALUES(respuesta_usuario),
        es_correcta = VALUES(es_correcta),
        puntaje_obtenido = VALUES(puntaje_obtenido),
        tags = VALUES(tags),
        fecha_respuesta = NOW()";

$stmt = $conexion->prepare($sql);
$inserted = 0;
$errors = [];

$conexion->beginTransaction();
try {
    foreach ($questions as $q) {
        $preguntaId = (int)($q['questionid'] ?? $q['id'] ?? 0);
        $slot = (int)($q['slot'] ?? 0);
        $respuesta = $q['user_response'] ?? '';   // Debes enviar esto desde la app
        $esCorrecta = (int)(($q['is_correct'] ?? false) ? 1 : 0);
        $puntajeObtenido = (float)($q['score'] ?? 0);
        $puntajeMaximo = (float)($q['maxscore'] ?? 1);
        $tags = $q['tags'] ?? [];
        $tagsJson = json_encode($tags, JSON_UNESCAPED_UNICODE);
        
        $stmt->execute([
            ':id_usuario' => $idUsuario,
            ':attempt_id' => $attemptId,
            ':quiz_id' => $quizId,
            ':pregunta_id' => $preguntaId,
            ':slot' => $slot,
            ':respuesta' => $respuesta,
            ':correcta' => $esCorrecta,
            ':puntaje_obtenido' => $puntajeObtenido,
            ':puntaje_maximo' => $puntajeMaximo,
            ':tags' => $tagsJson
        ]);
        $inserted++;
    }
    $conexion->commit();
    echo json_encode(['status' => 'ok', 'inserted' => $inserted, 'attemptid' => $attemptId]);
} catch (Exception $e) {
    $conexion->rollBack();
    http_response_code(500);
    echo json_encode(['status' => 'error', 'msg' => 'Error al guardar', 'debug' => $e->getMessage()]);
}