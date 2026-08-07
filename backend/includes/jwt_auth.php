<?php
// jwt_auth.php - Middleware de autenticación JWT unificado
declare(strict_types=1);

require __DIR__ . '/../vendor/autoload.php';
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

/**
 * Valida el JWT y retorna los datos del usuario
 * @return array Datos del usuario (id_usuario, tipo_usuario, moodle_userid, etc.)
 */
function validateJWT(): array {
    $headers = getallheaders();
    $authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    
    if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $matches)) {
        http_response_code(401);
        exit(json_encode(['status' => 'error', 'msg' => 'Token no proporcionado']));
    }

    try {
        $decoded = JWT::decode($matches[1], new Key($configJwt['secret'], 'HS256'));
        return (array) $decoded->data;
    } catch (Exception $e) {
        http_response_code(401);
        exit(json_encode(['status' => 'error', 'msg' => 'Token inválido o expirado']));
    }
}

/**
 * Extrae parámetros de filtro para profesores del request
 * @return array [grado, anio, simulacro_id]
 */
function getTeacherFilters(): array {
    $method = $_SERVER['REQUEST_METHOD'];
    
    if ($method === 'GET') {
        return [
            'grado' => $_GET['grado'] ?? null,
            'anio' => $_GET['anio'] ?? date('Y'),
            'simulacro_id' => isset($_GET['simulacro_id']) ? (int)$_GET['simulacro_id'] : null
        ];
    } elseif ($method === 'POST') {
        $input = json_decode(file_get_contents('php://input'), true) ?? [];
        return [
            'grado' => $input['grado'] ?? null,
            'anio' => $input['anio'] ?? date('Y'),
            'simulacro_id' => isset($input['simulacro_id']) ? (int)$input['simulacro_id'] : null
        ];
    }
    
    return ['grado' => null, 'anio' => date('Y'), 'simulacro_id' => null];
}

/**
 * Genera la cláusula WHERE para filtros de profesor
 * @param PDO $conexion
 * @param string $colegioProfesor
 * @param string|null $grado
 * @param string|null $anio
 * @param int|null $simulacro_id
 * @return array [where, params] Cláusula WHERE y parámetros
 */
function buildTeacherWhereClause(PDO $conexion, string $colegioProfesor, ?string $grado, ?string $anio, ?int $simulacro_id): array {
    $where = "u.colegio = :colegio";
    $params = [':colegio' => $colegioProfesor];
    
    if ($grado) {
        $where .= " AND u.grado = :grado";
        $params[':grado'] = $grado;
    }
    
    if ($anio) {
        $where .= " AND YEAR(sr.fecha_realizacion) = :anio";
        $params[':anio'] = $anio;
    }
    
    if ($simulacro_id) {
        $where .= " AND sr.simulacro_id = :simulacro_id";
        $params[':simulacro_id'] = $simulacro_id;
    }
    
    return ['where' => $where, 'params' => $params];
}

/**
 * Calcula estadísticas para un grupo de estudiantes
 * @param PDO $conexion
 * @param string $colegio
 * @param string|null $grado
 * @param string|null $anio
 * @param int|null $simulacro_id
 * @return array Estadísticas del grupo
 */
function calculateGroupStats(PDO $conexion, string $colegio, ?string $grado, ?string $anio, ?int $simulacro_id): array {
    $clause = buildTeacherWhereClause($conexion, $colegio, $grado, $anio, $simulacro_id);
    
    $sql = "
        SELECT 
            COUNT(DISTINCT u.id_usuario) as total_estudiantes,
            COUNT(DISTINCT sr.id) as total_simulacros,
            AVG(sr.puntaje_global) as promedio_global,
            AVG(sr.lectura_puntaje) as lectura_promedio,
            AVG(sr.matematicas_puntaje) as matematicas_promedio,
            AVG(sr.sociales_puntaje) as sociales_promedio,
            AVG(sr.naturales_puntaje) as naturales_promedio,
            AVG(sr.ingles_puntaje) as ingles_promedio,
            MIN(sr.puntaje_global) as puntaje_minimo,
            MAX(sr.puntaje_global) as puntaje_maximo,
            STD(sr.puntaje_global) as desviacion_estandar
        FROM usuarios u
        LEFT JOIN simulacro_resultados sr ON u.moodle_id = sr.usuario_id
        WHERE u.tipo_usuario = 'estudiante' AND {$clause['where']}
    ";
    
    $stmt = $conexion->prepare($sql);
    $stmt->execute($clause['params']);
    $stats = $stmt->fetch(PDO::FETCH_ASSOC);
    
    return $stats ?: [];
}