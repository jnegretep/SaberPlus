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
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
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
    exit(json_encode(['status' => 'error', 'msg' => 'No autorizado']));
}

try {
    $decoded = JWT::decode($m[1], new Key($configJwt['secret'], 'HS256'));
    $usuarioId = (int)$decoded->data->moodle_userid;
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Token inválido']));
}

// -------------------------------
// 2) Validar parámetro simulacro_id
// -------------------------------
$simulacroId = filter_input(INPUT_GET, 'simulacro_id', FILTER_VALIDATE_INT);
if (!$simulacroId) {
    http_response_code(400);
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'Parámetro simulacro_id faltante o inválido'
    ]));
}

// -------------------------------
// 3) Obtener resultado del usuario + datos de ámbito desde usuarios
// -------------------------------
$sqlUser = "
    SELECT
        sr.*,
        u.colegio,
        u.ciudad,
        u.departamento
    FROM simulacro_resultados sr
    JOIN usuarios u ON u.moodle_id = sr.usuario_id
    WHERE sr.usuario_id = :uid
      AND sr.simulacro_id = :sid
    LIMIT 1
";

$stmt = $conexion->prepare($sqlUser);
$stmt->execute([
    ':uid' => $usuarioId,
    ':sid' => $simulacroId,
]);
$userRow = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$userRow) {
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'No hay resultado registrado para este simulacro'
    ]));
}

// Datos base del usuario para filtros (texto)
$colegio      = $userRow['colegio'] ?? null;
$ciudad       = $userRow['ciudad'] ?? null;
$departamento = $userRow['departamento'] ?? null;

// -------------------------------
// 4) Armar bloque user
// -------------------------------
$userData = [
    'puntaje_global'        => isset($userRow['puntaje_global']) ? (float)$userRow['puntaje_global'] : null,
    'lectura_puntaje'       => isset($userRow['lectura_puntaje']) ? (float)$userRow['lectura_puntaje'] : null,
    'matematicas_puntaje'   => isset($userRow['matematicas_puntaje']) ? (float)$userRow['matematicas_puntaje'] : null,
    'sociales_puntaje'      => isset($userRow['sociales_puntaje']) ? (float)$userRow['sociales_puntaje'] : null,
    'naturales_puntaje'     => isset($userRow['naturales_puntaje']) ? (float)$userRow['naturales_puntaje'] : null,
    'ingles_puntaje'        => isset($userRow['ingles_puntaje']) ? (float)$userRow['ingles_puntaje'] : null,

    'lectura_correctas'     => isset($userRow['lectura_correctas']) ? (int)$userRow['lectura_correctas'] : null,
    'matematicas_correctas' => isset($userRow['matematicas_correctas']) ? (int)$userRow['matematicas_correctas'] : null,
    'sociales_correctas'    => isset($userRow['sociales_correctas']) ? (int)$userRow['sociales_correctas'] : null,
    'naturales_correctas'   => isset($userRow['naturales_correctas']) ? (int)$userRow['naturales_correctas'] : null,
    'ingles_correctas'      => isset($userRow['ingles_correctas']) ? (int)$userRow['ingles_correctas'] : null,

    'tiempo_empleado'       => isset($userRow['tiempo_empleado']) ? (int)$userRow['tiempo_empleado'] : null,
    'fecha_realizacion'     => $userRow['fecha_realizacion'] ?? null,
];

// -------------------------------
// 5) Helper para promedios por ámbito (uniendo usuarios)
// -------------------------------
function getScopeStats(PDO $conexion, int $simulacroId, array $whereClauses, array $params): array {
    $sql = "
        SELECT
            COUNT(*) AS sample_size,
            AVG(sr.puntaje_global)      AS puntaje_global,
            AVG(sr.lectura_puntaje)     AS lectura_puntaje,
            AVG(sr.matematicas_puntaje) AS matematicas_puntaje,
            AVG(sr.sociales_puntaje)    AS sociales_puntaje,
            AVG(sr.naturales_puntaje)   AS naturales_puntaje,
            AVG(sr.ingles_puntaje)      AS ingles_puntaje
        FROM simulacro_resultados sr
        JOIN usuarios u ON u.moodle_id = sr.usuario_id
        WHERE sr.simulacro_id = :sid
    ";

    $paramsLocal = [':sid' => $simulacroId];

    // Añadir filtros por texto (colegio/ciudad/departamento)
    foreach ($whereClauses as $clause => $paramName) {
        $sql .= " AND {$clause}";
        $paramsLocal[$paramName] = $params[$paramName];
    }

    $stmt = $conexion->prepare($sql);
    $stmt->execute($paramsLocal);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row || (int)$row['sample_size'] === 0) {
        return [
            'sample_size'         => 0,
            'puntaje_global'      => null,
            'lectura_puntaje'     => null,
            'matematicas_puntaje' => null,
            'sociales_puntaje'    => null,
            'naturales_puntaje'   => null,
            'ingles_puntaje'      => null,
        ];
    }

    return [
        'sample_size'         => (int)$row['sample_size'],
        'puntaje_global'      => $row['puntaje_global'] !== null ? (float)$row['puntaje_global'] : null,
        'lectura_puntaje'     => $row['lectura_puntaje'] !== null ? (float)$row['lectura_puntaje'] : null,
        'matematicas_puntaje' => $row['matematicas_puntaje'] !== null ? (float)$row['matematicas_puntaje'] : null,
        'sociales_puntaje'    => $row['sociales_puntaje'] !== null ? (float)$row['sociales_puntaje'] : null,
        'naturales_puntaje'   => $row['naturales_puntaje'] !== null ? (float)$row['naturales_puntaje'] : null,
        'ingles_puntaje'      => $row['ingles_puntaje'] !== null ? (float)$row['ingles_puntaje'] : null,
    ];
}

// -------------------------------
// 6) Cálculo de promedios por ámbito
// -------------------------------
$stats = [
    'colegio'      => null,
    'ciudad'       => null,
    'departamento' => null,
    'nacional'     => null,
];

// Colegio (texto)
if (!empty($colegio)) {
    $stats['colegio'] = getScopeStats(
        $conexion,
        $simulacroId,
        ['u.colegio = :colegio' => ':colegio'],
        [':colegio' => $colegio]
    );
}

// Ciudad (texto)
if (!empty($ciudad)) {
    $stats['ciudad'] = getScopeStats(
        $conexion,
        $simulacroId,
        ['u.ciudad = :ciudad' => ':ciudad'],
        [':ciudad' => $ciudad]
    );
}

// Departamento (texto)
if (!empty($departamento)) {
    $stats['departamento'] = getScopeStats(
        $conexion,
        $simulacroId,
        ['u.departamento = :departamento' => ':departamento'],
        [':departamento' => $departamento]
    );
}

// Nacional (todos los registros para ese simulacro, sin filtro)
$stats['nacional'] = getScopeStats(
    $conexion,
    $simulacroId,
    [],
    []
);

// -------------------------------
// 7) Respuesta final
// -------------------------------
echo json_encode([
    'status' => 'ok',
    'user'   => $userData,
    'stats'  => $stats,
], JSON_UNESCAPED_UNICODE);
