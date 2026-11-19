<?php
declare(strict_types=1);

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
    exit(json_encode(['status'=>'error','msg'=>'Método no permitido']));
}

require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php';
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

// -------------------------------
// 1) Autenticación JWT
// -------------------------------
$hdrs = function_exists('getallheaders') ? getallheaders() : [];
$authHeader = $hdrs['Authorization']
    ?? $hdrs['authorization']
    ?? ($_SERVER['HTTP_AUTHORIZATION'] ?? '');

if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
    http_response_code(401);
    exit(json_encode(['status'=>'error','msg'=>'No autorizado']));
}

try {
    $decoded = JWT::decode($m[1], new Key($configJwt['secret'], 'HS256'));
    $usuarioId = (int)$decoded->data->moodle_userid;
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status'=>'error','msg'=>'Token inválido']));
}

// -------------------------------
// 2) Validar simulacro_id
// -------------------------------
$simulacroId = filter_input(INPUT_GET, 'simulacro_id', FILTER_VALIDATE_INT);
if (!$simulacroId) {
    exit(json_encode(['status'=>'error','msg'=>'Parámetro simulacro_id faltante']));
}

// -------------------------------
// 3) Obtener datos del usuario
// -------------------------------
$sqlUser = "
    SELECT sr.*, u.colegio, u.ciudad, u.departamento, u.nombre
    FROM simulacro_resultados sr
    JOIN usuarios u ON u.moodle_id = sr.usuario_id
    WHERE sr.usuario_id = :uid
      AND sr.simulacro_id = :sid
    LIMIT 1
";

$stmt = $conexion->prepare($sqlUser);
$stmt->execute([':uid'=>$usuarioId, ':sid'=>$simulacroId]);
$userRow = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$userRow) {
    exit(json_encode(['status'=>'error','msg'=>'No hay resultado para este simulacro']));
}

$colegio     = $userRow['colegio'];
$ciudad      = $userRow['ciudad'];
$departamento= $userRow['departamento'];

// -------------------------------
// 4) Función para ranking
// -------------------------------
function getRank(PDO $db, int $simulacroId, string $where, array $params, float $userScore): int {
    $sql = "
        SELECT COUNT(*)+1 AS user_rank
        FROM simulacro_resultados sr
        JOIN usuarios u ON u.moodle_id = sr.usuario_id
        WHERE sr.simulacro_id = :sid
          AND sr.puntaje_global > :userScore
          $where
    ";
    $stmt = $db->prepare($sql);
    $stmt->execute(array_merge([
        ':sid'=>$simulacroId,
        ':userScore'=>$userScore
    ], $params));
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return (int)$row['user_rank'];
}

function getTop(PDO $db, int $simulacroId, string $where, array $params): array {
    $sql = "
        SELECT sr.*, u.nombre, u.colegio, u.ciudad, u.departamento
        FROM simulacro_resultados sr
        JOIN usuarios u ON u.moodle_id = sr.usuario_id
        WHERE sr.simulacro_id = :sid
        $where
        ORDER BY sr.puntaje_global DESC
        LIMIT 10
    ";
    $stmt = $db->prepare($sql);
    $stmt->execute(array_merge([':sid'=>$simulacroId], $params));
    return $stmt->fetchAll(PDO::FETCH_ASSOC);
}

// -------------------------------
// 5) Calcular rankings
// -------------------------------
$userScore = (float)$userRow['puntaje_global'];

$ranking = [
    'colegio_rank'      => getRank($conexion, $simulacroId, "AND u.colegio = :colegio", [':colegio'=>$colegio], $userScore),
    'ciudad_rank'       => getRank($conexion, $simulacroId, "AND u.ciudad = :ciudad", [':ciudad'=>$ciudad], $userScore),
    'departamento_rank' => getRank($conexion, $simulacroId, "AND u.departamento = :dep", [':dep'=>$departamento], $userScore),
    'nacional_rank'     => getRank($conexion, $simulacroId, "", [], $userScore),
];

// -------------------------------
// 6) Obtener top 10 por ámbito
// -------------------------------
$top = [
    'colegio'     => getTop($conexion, $simulacroId, "AND u.colegio = :colegio", [':colegio'=>$colegio]),
    'ciudad'      => getTop($conexion, $simulacroId, "AND u.ciudad = :ciudad", [':ciudad'=>$ciudad]),
    'departamento'=> getTop($conexion, $simulacroId, "AND u.departamento = :dep", [':dep'=>$departamento]),
    'nacional'    => getTop($conexion, $simulacroId, "", []),
];

// -------------------------------
// 7) Respuesta final
// -------------------------------
echo json_encode([
    'status'=>'ok',
    'user'=>$ranking,
    'top'=>$top
], JSON_UNESCAPED_UNICODE);
