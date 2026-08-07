<?php
declare(strict_types=1);

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
    exit(json_encode(['status'=>'error','msg'=>'Método no permitido']));
}

require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle.php';
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

// --- Autenticación JWT ---
$hdrs = function_exists('getallheaders') ? getallheaders() : [];
$authHeader = $hdrs['Authorization'] ?? $hdrs['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';

if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
    http_response_code(401);
    exit(json_encode(['status'=>'error','msg'=>'No autorizado']));
}

try {
    $decoded = JWT::decode($m[1], new Key($configJwt['secret'], 'HS256'));
    $usuario_id = (int)$decoded->data->moodle_userid;
    error_log("[SAVE_RESULT] Usuario autenticado: $usuario_id");
} catch (Exception $e) {
    error_log("[SAVE_RESULT] Token inválido: " . $e->getMessage());
    http_response_code(401);
    exit(json_encode(['status'=>'error','msg'=>'Token inválido']));
}

// --- Leer JSON ---
$raw = file_get_contents("php://input");
error_log("[SAVE_RESULT] Raw input: " . $raw);

$input = json_decode($raw, true);
if (!$input) {
    error_log("[SAVE_RESULT] JSON inválido");
    exit(json_encode(['status'=>'error','msg'=>'JSON inválido']));
}
error_log("[SAVE_RESULT] Decodificado: " . json_encode($input));

// --- Validar simulacro ---
$simu_ids = [2,3,18,24,25,26,27,28,29,30,31];

$course_id = (int)($input['course_id'] ?? 0);
if (!in_array($course_id, $simu_ids)) {
    error_log("[SAVE_RESULT] course_id $course_id no es simulacro");
    exit(json_encode(['status'=>'error','msg'=>'Este curso no es un simulacro']));
}

// --- Preparar datos ---
$simulacro_id = (int)$input['simulacro_id'];
$puntaje_global = (float)$input['puntaje_global'];
$lectura_correctas = (int)$input['lectura_correctas'];
$matematicas_correctas = (int)$input['matematicas_correctas'];
$sociales_correctas = (int)$input['sociales_correctas'];
$naturales_correctas = (int)$input['naturales_correctas'];
$ingles_correctas = (int)$input['ingles_correctas'];

$lectura_puntaje = (float)$input['lectura_puntaje'];
$matematicas_puntaje = (float)$input['matematicas_puntaje'];
$sociales_puntaje = (float)$input['sociales_puntaje'];
$naturales_puntaje = (float)$input['naturales_puntaje'];
$ingles_puntaje = (float)$input['ingles_puntaje'];

$tiempo_empleado = (int)$input['tiempo_empleado'];

// --- Obtener datos del usuario ---
$stmt = $conexion->prepare("
    SELECT colegio, ciudad, departamento
    FROM usuarios
    WHERE moodle_id = :uid
    LIMIT 1
");
$stmt->execute([':uid' => $usuario_id]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);

error_log("[SAVE_RESULT] Datos usuario: " . json_encode($user));

// --- Insertar o actualizar ---
try {
    $stmt = $conexion->prepare("
        INSERT INTO simulacro_resultados (
            usuario_id, simulacro_id, course_id, fecha_realizacion,
            puntaje_global,
            lectura_correctas, matematicas_correctas, sociales_correctas, naturales_correctas, ingles_correctas,
            lectura_puntaje, matematicas_puntaje, sociales_puntaje, naturales_puntaje, ingles_puntaje,
            tiempo_empleado,
            colegio, ciudad, departamento
        ) VALUES (
            :usuario_id, :simulacro_id, :course_id, NOW(),
            :puntaje_global,
            :lc, :mt, :sc, :nt, :ing,
            :lp, :mp, :sp, :np, :ip,
            :tiempo,
            :colegio, :ciudad, :departamento
        )
        ON DUPLICATE KEY UPDATE
            fecha_realizacion = NOW(),
            puntaje_global = VALUES(puntaje_global),
            lectura_correctas = VALUES(lectura_correctas),
            matematicas_correctas = VALUES(matematicas_correctas),
            sociales_correctas = VALUES(sociales_correctas),
            naturales_correctas = VALUES(naturales_correctas),
            ingles_correctas = VALUES(ingles_correctas),
            lectura_puntaje = VALUES(lectura_puntaje),
            matematicas_puntaje = VALUES(matematicas_puntaje),
            sociales_puntaje = VALUES(sociales_puntaje),
            naturales_puntaje = VALUES(naturales_puntaje),
            ingles_puntaje = VALUES(ingles_puntaje),
            tiempo_empleado = VALUES(tiempo_empleado),
            colegio = VALUES(colegio),
            ciudad = VALUES(ciudad),
            departamento = VALUES(departamento)
    ");

    $stmt->execute([
        ':usuario_id' => $usuario_id,
        ':simulacro_id' => $simulacro_id,
        ':course_id' => $course_id,
        ':puntaje_global' => $puntaje_global,
        ':lc' => $lectura_correctas,
        ':mt' => $matematicas_correctas,
        ':sc' => $sociales_correctas,
        ':nt' => $naturales_correctas,
        ':ing' => $ingles_correctas,
        ':lp' => $lectura_puntaje,
        ':mp' => $matematicas_puntaje,
        ':sp' => $sociales_puntaje,
        ':np' => $naturales_puntaje,
        ':ip' => $ingles_puntaje,
        ':tiempo' => $tiempo_empleado,
        ':colegio' => $user['colegio'] ?? null,
        ':ciudad' => $user['ciudad'] ?? null,
        ':departamento' => $user['departamento'] ?? null,
    ]);

    error_log("[SAVE_RESULT] Insert OK");
    echo json_encode(['status' => 'ok']);
} catch (Exception $e) {
    error_log("[SAVE_RESULT] Insert ERROR: " . $e->getMessage());
    exit(json_encode(['status'=>'error','msg'=>'DB error']));
}
