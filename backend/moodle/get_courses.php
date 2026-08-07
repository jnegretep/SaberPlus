<?php
declare(strict_types=1);

// DEBUG: ver cabeceras
error_log('DEBUG HTTP_AUTHORIZATION env: ' . var_export($_SERVER['HTTP_AUTHORIZATION'] ?? null, true));
error_log('DEBUG getallheaders: ' . var_export(function_exists('getallheaders') ? getallheaders() : [], true));

// 1) CORS y JSON
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: GET, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
}

// 2) Autoload y conexiones
require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php'; // PDO $conexion
require __DIR__ . '/../includes/moodle.php'; // Moodle config + getMoodleClient()
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

// 3) Extraer JWT Bearer
$allHeaders = function_exists('getallheaders') ? getallheaders() : [];
$authHeader = $allHeaders['Authorization'] ?? $allHeaders['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';

if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
}

$appToken = $m[1];

// 4) Decodificar JWT
try {
    $decoded = JWT::decode($appToken, new Key($configJwt['secret'], 'HS256'));
    $moodleUserId = (int)$decoded->data->moodle_userid;
} catch (Exception $e) {
    error_log('JWT decode error: ' . $e->getMessage());
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Token inválido']));
}

// 5) Recuperar datos del usuario (token + access_level)
$stmt = $conexion->prepare("
    SELECT moodle_token, access_level 
    FROM usuarios 
    WHERE moodle_id = :mid 
    LIMIT 1
");
$stmt->execute([':mid' => $moodleUserId]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$row) {
    http_response_code(404);
    exit(json_encode(['status' => 'error', 'msg' => 'Usuario no encontrado']));
}

$moodleToken = $row['moodle_token'];
$userAccessLevel = $row['access_level']; // free | premium | trial

// 6) Cargar reglas de acceso desde content_access
$accessRules = [];
$stmtAccess = $conexion->query("
    SELECT content_type, content_id, min_plan 
    FROM content_access
");
while ($r = $stmtAccess->fetch(PDO::FETCH_ASSOC)) {
    $key = $r['content_type'] . '_' . $r['content_id'];
    $accessRules[$key] = $r['min_plan'];
}

// Función para determinar si está bloqueado
function isLocked(string $type, int $id, string $userLevel, array $rules): bool {
    // Trial y Premium tienen acceso completo
    if ($userLevel === 'premium' || $userLevel === 'trial') {
        return false;
    }

    // Free: verificar si el contenido está marcado como premium
    $key = $type . '_' . $id;
    if (!isset($rules[$key])) {
        // No está definido => por defecto es premium
        return true;
    }

    return $rules[$key] === 'premium';
}

// 7) Llamar a Moodle WS y obtener cursos
try {
    $client = getMoodleClient();
    $courses = $client->request(
        $moodleToken,
        'core_enrol_get_users_courses',
        ['userid' => $moodleUserId]
    );

    // Clasificación fija por IDs (ajusta aquí si quieres cambiar reglas)
    $curso_ids = [4,5,6,7,8,52,53,54,55]; // Cursos
    $simu_ids = [2, 3, 18, 24, 25, 26, 27, 28, 29, 30, 31]; // Simulacros
    $retos_ids = [19, 20, 21, 22, 23,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51]; // Retos

    $courses_out = [];
    $simulacros_out = [];
    $retos_out = [];

    foreach ((array)$courses as $c) {
        $id = (int)($c['id'] ?? 0);
        $normalized = [
            'id' => $id,
            'fullname' => $c['fullname'] ?? '',
            'shortname' => $c['shortname'] ?? '',
            'startdate' => $c['startdate'] ?? null,
            'enddate' => $c['enddate'] ?? null,
            'visible' => isset($c['visible']) ? (bool)$c['visible'] : true,
        ];

        if (in_array($id, $curso_ids, true)) {
            $normalized['locked'] = isLocked('curso', $id, $userAccessLevel, $accessRules);
            $courses_out[] = $normalized;
        } elseif (in_array($id, $simu_ids, true)) {
            $normalized['locked'] = isLocked('simulacro', $id, $userAccessLevel, $accessRules);
            $simulacros_out[] = $normalized;
        } elseif (in_array($id, $retos_ids, true)) {
            $normalized['locked'] = isLocked('reto', $id, $userAccessLevel, $accessRules);
            $retos_out[] = $normalized;
        }
    }



    echo json_encode([
        'status' => 'ok',
        'access_level' => $userAccessLevel,
        'courses' => $courses_out,
        'simulacros' => $simulacros_out,
        'retos' => $retos_out,
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'msg' => 'Error Moodle WS',
        'debug' => $e->getMessage()
    ]);
}
