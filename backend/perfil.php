<?php
// perfil.php - Versión compatible con PHP < 7.0
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['status' => 'error', 'msg' => 'Método no permitido']);
    exit;
}

require 'auth_middleware.php';
require __DIR__ . '/includes/moodle.php';
require_once __DIR__ . '/moodle/MoodleClient.php';

try {
    $endpoint = rtrim(MOODLE_BASE_URL, '/') . MOODLE_WS_ENDPOINT;
    $mc = new MoodleClient($endpoint, 'json');

    // Funciones utilitarias - versión compatible
    $isException = function($resp) {
        return is_array($resp) && isset($resp['exception']);
    };
    
    $isUserList = function($resp) {
        return is_array($resp) && isset($resp[0]) && is_array($resp[0]) && isset($resp[0]['id']);
    };

    // 1) Obtener datos del usuario autenticado desde auth_middleware
    error_log("[PERFIL] Usuario autenticado: " . json_encode($authUser));
    
    // Verificar que tenemos datos mínimos
    if (!isset($authUser['id_usuario']) && !isset($authUser['moodle_userid'])) {
        http_response_code(401);
        echo json_encode(['status' => 'error', 'msg' => 'Usuario no autenticado']);
        exit;
    }

    // 2) Consultar datos locales PRIMERO
    $localUser = null;
    
    if (!empty($authUser['id_usuario'])) {
        try {
            // CONSULTA MODIFICADA: Incluir todos los campos necesarios
            $stmt = $conexion->prepare("
                SELECT 
                    id_usuario, email, nombre, tipo_usuario, moodle_username, moodle_id,
                    avatar_path, telefono, departamento, ciudad, colegio, grado,
                    email_verificado, access_level, is_early_user,
                    DATE_FORMAT(fecha_registro, '%Y-%m-%d %H:%i:%s') as fecha_registro,
                    DATE_FORMAT(ultimo_login, '%Y-%m-%d %H:%i:%s') as ultimo_login
                FROM usuarios 
                WHERE id_usuario = ? 
                LIMIT 1
            ");
            $stmt->execute([$authUser['id_usuario']]);
            $localUser = $stmt->fetch(PDO::FETCH_ASSOC);
            
            if ($localUser) {
                error_log("[PERFIL] Usuario local encontrado. ID: " . $localUser['id_usuario'] . 
                         ", Tipo: " . $localUser['tipo_usuario']);
            }
        } catch (Exception $e) {
            error_log("[PERFIL] Error consultando usuario local: " . $e->getMessage());
        }
    }

    // 3) Obtener datos de Moodle si tenemos moodle_id
    $moodleUser = null;
    $moodleUserId = isset($authUser['moodle_userid']) ? $authUser['moodle_userid'] : 
                   (isset($localUser['moodle_id']) ? $localUser['moodle_id'] : null);
    
    if ($moodleUserId) {
        try {
            $paramsById = array(
                'field' => 'id',
                'values' => array($moodleUserId)
            );

            // Intentar con token del usuario
            $token = isset($authUser['moodle_token']) ? $authUser['moodle_token'] : 
                    (isset($localUser['moodle_token']) ? $localUser['moodle_token'] : '');
            
            if ($token) {
                try {
                    $resp = $mc->request($token, 'core_user_get_users_by_field', $paramsById);
                    if ($isUserList($resp)) {
                        $moodleUser = $resp[0];
                        error_log("[PERFIL] Datos Moodle obtenidos con token usuario");
                    }
                } catch (Exception $e) {
                    error_log("[PERFIL] Error con token usuario Moodle: " . $e->getMessage());
                }
            }
            
            // Fallback a token de servicio
            if (!$moodleUser) {
                try {
                    $resp = $mc->request(MOODLE_WS_TOKEN, 'core_user_get_users_by_field', $paramsById);
                    if ($isUserList($resp)) {
                        $moodleUser = $resp[0];
                        error_log("[PERFIL] Datos Moodle obtenidos con token servicio");
                    }
                } catch (Exception $e) {
                    error_log("[PERFIL] Fallback token servicio falló: " . $e->getMessage());
                }
            }
            
        } catch (Exception $e) {
            error_log("[PERFIL] Error general obteniendo datos Moodle: " . $e->getMessage());
        }
    }

    // 4) Construir respuesta combinando datos
    $userData = array();
    
    // ID del usuario (prioridad a local)
    $userData['id_usuario'] = isset($localUser['id_usuario']) ? (int)$localUser['id_usuario'] : 
                             (isset($authUser['id_usuario']) ? (int)$authUser['id_usuario'] : 0);
    
    // Moodle ID
    $userData['moodle_id'] = isset($localUser['moodle_id']) ? (int)$localUser['moodle_id'] : 
                            (isset($authUser['moodle_userid']) ? (int)$authUser['moodle_userid'] : 0);
    
    // Nombre (prioridad: local -> moodle -> auth)
    if (isset($localUser['nombre']) && !empty($localUser['nombre'])) {
        $userData['nombre'] = $localUser['nombre'];
    } elseif ($moodleUser && isset($moodleUser['firstname']) && isset($moodleUser['lastname'])) {
        $userData['nombre'] = trim($moodleUser['firstname'] . ' ' . $moodleUser['lastname']);
    } elseif ($moodleUser && isset($moodleUser['fullname'])) {
        $userData['nombre'] = $moodleUser['fullname'];
    } else {
        $userData['nombre'] = isset($authUser['email']) ? $authUser['email'] : '';
    }
    
    // Tipo de usuario (CRÍTICO) - prioridad: local -> auth -> default
    if (isset($localUser['tipo_usuario']) && !empty($localUser['tipo_usuario'])) {
        $userData['tipo_usuario'] = $localUser['tipo_usuario'];
    } elseif (isset($authUser['tipo_usuario']) && !empty($authUser['tipo_usuario'])) {
        $userData['tipo_usuario'] = $authUser['tipo_usuario'];
    } else {
        $userData['tipo_usuario'] = 'estudiante'; // Valor por defecto
    }
    
    // Email
    $userData['email'] = isset($localUser['email']) ? $localUser['email'] : 
                        (isset($authUser['email']) ? $authUser['email'] : '');
    
    // Otros campos locales
    $userData['username'] = isset($localUser['moodle_username']) ? $localUser['moodle_username'] : '';
    $userData['telefono'] = isset($localUser['telefono']) ? $localUser['telefono'] : '';
    $userData['departamento'] = isset($localUser['departamento']) ? $localUser['departamento'] : '';
    $userData['ciudad'] = isset($localUser['ciudad']) ? $localUser['ciudad'] : '';
    $userData['colegio'] = isset($localUser['colegio']) ? $localUser['colegio'] : '';
    $userData['grado'] = isset($localUser['grado']) ? $localUser['grado'] : '';
    $userData['avatar'] = isset($localUser['avatar_path']) ? $localUser['avatar_path'] : '';
    $userData['email_verificado'] = isset($localUser['email_verificado']) ? (bool)$localUser['email_verificado'] : false;
    $userData['access_level'] = isset($localUser['access_level']) ? $localUser['access_level'] : 'free';
    $userData['is_early_user'] = isset($localUser['is_early_user']) ? (bool)$localUser['is_early_user'] : false;
    $userData['fecha_registro'] = isset($localUser['fecha_registro']) ? $localUser['fecha_registro'] : null;
    $userData['ultimo_login'] = isset($localUser['ultimo_login']) ? $localUser['ultimo_login'] : null;

    // 5) Si es profesor, obtener datos adicionales
    if ($userData['tipo_usuario'] === 'profesor' && !empty($userData['colegio'])) {
        try {
            // Estadísticas básicas del colegio
            $statsStmt = $conexion->prepare("
                SELECT 
                    COUNT(DISTINCT u.id_usuario) as total_estudiantes,
                    COUNT(DISTINCT sr.id) as total_simulacros,
                    AVG(sr.puntaje_global) as promedio_colegio
                FROM usuarios u
                LEFT JOIN simulacro_resultados sr ON u.moodle_id = sr.usuario_id
                WHERE u.colegio = ? 
                AND u.tipo_usuario = 'estudiante'
                AND u.grado IS NOT NULL
            ");
            
            $statsStmt->execute([$userData['colegio']]);
            $colegioStats = $statsStmt->fetch(PDO::FETCH_ASSOC);
            
            if ($colegioStats) {
                $userData['colegio_stats'] = $colegioStats;
            } else {
                $userData['colegio_stats'] = array(
                    'total_estudiantes' => 0,
                    'total_simulacros' => 0,
                    'promedio_colegio' => null
                );
            }
            
            // Grados disponibles
            $gradosStmt = $conexion->prepare("
                SELECT DISTINCT grado 
                FROM usuarios 
                WHERE colegio = ? 
                AND tipo_usuario = 'estudiante'
                AND grado IS NOT NULL 
                AND grado != ''
                ORDER BY grado
            ");
            
            $gradosStmt->execute([$userData['colegio']]);
            $grados = $gradosStmt->fetchAll(PDO::FETCH_COLUMN);
            
            $userData['grados_disponibles'] = $grados ? $grados : array();
            
        } catch (Exception $e) {
            error_log("[PERFIL] Error obteniendo datos de profesor: " . $e->getMessage());
            $userData['colegio_stats'] = array(
                'total_estudiantes' => 0,
                'total_simulacros' => 0,
                'promedio_colegio' => null
            );
            $userData['grados_disponibles'] = array();
        }
    }

    // 6) Validar respuesta mínima
    if (empty($userData['id_usuario']) && empty($userData['email'])) {
        http_response_code(404);
        echo json_encode(array(
            'status' => 'error', 
            'msg' => 'No se pudo construir el perfil del usuario'
        ));
        exit;
    }

    // 7) Actualizar último acceso
    if (!empty($localUser['id_usuario'])) {
        try {
            $updStmt = $conexion->prepare("UPDATE usuarios SET ultimo_login = NOW() WHERE id_usuario = ?");
            $updStmt->execute([$localUser['id_usuario']]);
        } catch (Exception $e) {
            error_log("[PERFIL] Error actualizando último login: " . $e->getMessage());
        }
    }

    // 8) Responder con datos
    error_log("[PERFIL] Perfil obtenido: ID=" . $userData['id_usuario'] . 
              ", Tipo=" . $userData['tipo_usuario'] . 
              ", Colegio=" . (!empty($userData['colegio']) ? $userData['colegio'] : 'N/A'));
    
    echo json_encode(array(
        'status' => 'ok',
        'user' => $userData
    ));

} catch (Exception $e) {
    error_log("[PERFIL][ERROR] " . $e->getMessage());
    http_response_code(500);
    echo json_encode(array(
        'status' => 'error',
        'msg' => 'Error interno del servidor'
    ));
}