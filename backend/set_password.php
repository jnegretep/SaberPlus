<?php
// /var/www/html/api/prepsaber/backend/set_password.php

// ======== CORS y JSON =========
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// Configuración de error reporting
error_reporting(E_ALL);
ini_set('display_errors', '0');
ini_set('log_errors', '1');

require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/includes/moodle.php';

// Función helper para respuestas JSON consistentes
function respond($code, $data) {
    $json = json_encode($data, JSON_UNESCAPED_UNICODE);
    while (ob_get_level() > 0) ob_end_clean();
    http_response_code($code);
    header('Content-Type: application/json; charset=UTF-8');
    header('Content-Length: ' . strlen($json));
    echo $json;
    flush();
    exit;
}

// Función para manejar errores de Moodle de manera elegante
function handleMoodleError($operation, $e) {
    $errorMsg = $e->getMessage();
    
    // Si es error de duplicado, no es crítico
    if (strpos($errorMsg, 'Duplicate entry') !== false) {
        error_log("[set_password][INFO] $operation: Elemento ya existe (no crítico) - " . $errorMsg);
        return false;
    }
    
    // Si es error de respuesta inesperada, puede ser temporal
    if (strpos($errorMsg, 'Respuesta inesperada') !== false || 
        strpos($errorMsg, 'Unexpected response') !== false) {
        error_log("[set_password][WARN] $operation: Error temporal en Moodle - " . $errorMsg);
        return false;
    }
    
    // Otros errores son críticos
    error_log("[set_password][ERROR] $operation: Error crítico - " . $errorMsg);
    return true;
}

try {
    // ======== Leer y validar JSON ========
    $input = file_get_contents('php://input');
    $data = json_decode($input, true);
    
    if (json_last_error() !== JSON_ERROR_NONE) {
        error_log("[set_password] JSON inválido: " . json_last_error_msg());
        respond(400, ['status' => 'error', 'msg' => 'JSON inválido']);
    }

    $email = strtolower(trim($data['email'] ?? ''));
    $userId = $data['user_id'] ?? null;
    $password = $data['password'] ?? '';
    $resetToken = $data['reset_token'] ?? null; // ?? RECUPERACIÓN

    if (empty($email) || empty($userId) || empty($password)) {
        error_log("[set_password] Datos incompletos");
        respond(400, ['status' => 'error', 'msg' => 'Email, user_id y password son requeridos']);
    }

    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        error_log("[set_password] Email inválido: $email");
        respond(400, ['status' => 'error', 'msg' => 'Email inválido']);
    }

    // ======== Verificar usuario local ========
    $stmt = $conexion->prepare("
        SELECT id_usuario, email_verificado, avatar_path, moodle_id
        FROM usuarios 
        WHERE email = ? AND id_usuario = ?
        LIMIT 1
    ");
    $stmt->execute([$email, $userId]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        error_log("[set_password] Usuario no encontrado: $email (ID: $userId)");
        respond(404, ['status' => 'error', 'msg' => 'Usuario no encontrado']);
    }

    // ?? RECUPERACIÓN: validar token si viene
    if (!empty($resetToken)) {
        if (strlen($resetToken) !== 6 || !ctype_digit($resetToken)) {
            respond(400, ['status' => 'error', 'msg' => 'Código de recuperación inválido']);
        }

        $stmt = $conexion->prepare("
            SELECT id, expires_at
            FROM password_resets
            WHERE user_id = ? AND token = ?
            LIMIT 1
        ");
        $stmt->execute([$user['id_usuario'], $resetToken]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$row) {
            respond(400, ['status' => 'error', 'msg' => 'Código inválido']);
        }

        if (strtotime($row['expires_at']) < time()) {
            respond(400, ['status' => 'error', 'msg' => 'Código expirado']);
        }

        error_log("[set_password] Token de recuperación validado para user_id={$user['id_usuario']}");
    } else {
        // ======== MODO REGISTRO: exigir email verificado ========
        if ($user['email_verificado'] != 1) {
            error_log("[set_password] Correo no verificado para user_id={$user['id_usuario']}");
            respond(400, ['status' => 'error', 'msg' => 'Debe verificar el correo antes de establecer la contraseña']);
        }
    }

    // ======== Validar fortaleza de contraseña ========
    if (!preg_match('/^(?=.*[A-Z])(?=.*\d).{8,}$/', $password)) {
        error_log("[set_password] Contraseña débil para user_id={$user['id_usuario']}");
        respond(400, [
            'status' => 'error', 
            'msg' => 'La contraseña debe tener mínimo 8 caracteres, una mayúscula y un número'
        ]);
    }

    // ======== Actualizar hash local ========
    $hash = password_hash($password, PASSWORD_BCRYPT);
    $upd = $conexion->prepare("UPDATE usuarios SET contrasena_hash = ? WHERE id_usuario = ?");
    $upd->execute([$hash, $user['id_usuario']]);
    
    error_log("[set_password] Contraseña local guardada para user_id={$user['id_usuario']}");

    // ?? RECUPERACIÓN: invalidar token (uso único)
    if (!empty($resetToken)) {
        $del = $conexion->prepare("DELETE FROM password_resets WHERE user_id = ?");
        $del->execute([$user['id_usuario']]);
        error_log("[set_password] Token de recuperación eliminado para user_id={$user['id_usuario']}");
    }

    // Inicializar array para tracking de operaciones
    $moodleOperations = [
        'user_created_updated' => false,
        'role_assigned' => false,
        'courses_enrolled' => 0,
        'avatar_updated' => false
    ];

    // ======== Sincronizar con Moodle (si no tiene moodle_id) ========
    if (empty($user['moodle_id'])) {
        $mc = getMoodleClient();
        $moodleId = null;
        
        // Obtener datos completos del usuario
        $stmt = $conexion->prepare("
            SELECT nombre, email, departamento, ciudad, colegio, grado, 
                   moodle_username, avatar_path, telefono
            FROM usuarios 
            WHERE id_usuario = ?
        ");
        $stmt->execute([$user['id_usuario']]);
        $u = $stmt->fetch(PDO::FETCH_ASSOC);

        $parts = preg_split('/\s+/', trim($u['nombre']), 2, PREG_SPLIT_NO_EMPTY);
        $firstname = $parts[0] ?? 'Nombre';
        $lastname = $parts[1] ?? 'Usuario';
        $username = $u['moodle_username'] ?? preg_replace('/[^a-z0-9._-]/i', '', strtolower($u['email']));
        $telefonoLocal = isset($u['telefono']) ? trim($u['telefono']) : '';

        error_log("[set_password] Iniciando sincronización Moodle para {$u['email']}");

        // 1. Buscar si ya existe en Moodle por email
        try {
            $existing = $mc->request(MOODLE_WS_TOKEN, 'core_user_get_users_by_field', [
                'field' => 'email',
                'values' => [$u['email']]
            ]);
            
            if (!empty($existing)) {
                $moodleId = (int)$existing[0]['id'];
                error_log("[set_password] Usuario encontrado en Moodle con id=$moodleId");
                
                // 1.1. Actualizar usuario existente
                $updateUser = [
                    'id' => $moodleId,
                    'firstname' => $firstname,
                    'lastname' => $lastname,
                    'country' => 'CO',
                    'phone1' => $telefonoLocal,
                    'customfields' => [
                        ['type' => 'departamento', 'value' => $u['departamento'] ?? ''],
                        ['type' => 'ciudad', 'value' => $u['ciudad'] ?? ''],
                        ['type' => 'colegio', 'value' => $u['colegio'] ?? ''],
                        ['type' => 'grado', 'value' => $u['grado'] ?? ''],
                    ],
                ];
                
                $mc->request(MOODLE_WS_TOKEN, 'core_user_update_users', ['users' => [$updateUser]]);
                error_log("[set_password] Usuario actualizado en Moodle");
                
            } else {
                // 1.2. Crear nuevo usuario en Moodle
                $usersPayload = [
                    'users' => [[
                        'username' => $username,
                        'password' => $password,
                        'firstname' => $firstname,
                        'lastname' => $lastname,
                        'email' => $u['email'],
                        'country' => 'CO',
                        'phone1' => $telefonoLocal,
                        'customfields' => [
                            ['type' => 'departamento', 'value' => $u['departamento'] ?? ''],
                            ['type' => 'ciudad', 'value' => $u['ciudad'] ?? ''],
                            ['type' => 'colegio', 'value' => $u['colegio'] ?? ''],
                            ['type' => 'grado', 'value' => $u['grado'] ?? ''],
                        ],
                    ]]
                ];
                
                $created = $mc->request(MOODLE_WS_TOKEN, 'core_user_create_users', $usersPayload);
                $moodleId = isset($created[0]['id']) ? (int)$created[0]['id'] : null;
                
                if ($moodleId) {
                    error_log("[set_password] Usuario creado en Moodle con id=$moodleId");
                }
            }
            
            if ($moodleId) {
                // Guardar moodle_id en la base de datos local
                $upd = $conexion->prepare("UPDATE usuarios SET moodle_id = ? WHERE id_usuario = ?");
                $upd->execute([$moodleId, $user['id_usuario']]);
                $moodleOperations['user_created_updated'] = true;
            }
            
        } catch (Exception $e) {
            $isCritical = handleMoodleError("Creación/actualización usuario", $e);
            if ($isCritical) {
                error_log("[set_password] Error crítico en Moodle, continuando sin moodle_id");
            }
        }

        // 2. Asignar rol global
        if ($moodleId) {
            try {
                $mc->request(MOODLE_WS_TOKEN, 'core_role_assign_roles', [
                    'assignments' => [[
                        'roleid' => 10,
                        'userid' => $moodleId,
                        'contextid' => 1,
                    ]]
                ]);
                error_log("[set_password] Rol global asignado");
                $moodleOperations['role_assigned'] = true;
            } catch (Exception $e) {
                handleMoodleError("Asignación de rol global", $e);
            }
        }

        // 3. Matricular en cursos
        if ($moodleId) {
            $courseIds = [2,3,4,5,6,7,8,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55];
            $batchSize = 5;
            $batches = array_chunk($courseIds, $batchSize);
            
            foreach ($batches as $batchIndex => $batch) {
                $enrolments = [];
                foreach ($batch as $courseid) {
                    $enrolments[] = [
                        'roleid' => 5,
                        'userid' => $moodleId,
                        'courseid' => $courseid,
                    ];
                }
                
                try {
                    $mc->request(MOODLE_WS_TOKEN, 'enrol_manual_enrol_users', [
                        'enrolments' => $enrolments
                    ]);
                    $moodleOperations['courses_enrolled'] += count($batch);
                    error_log("[set_password] Lote $batchIndex matriculado: " . count($batch) . " cursos");
                } catch (Exception $e) {
                    handleMoodleError("Matrícula lote $batchIndex", $e);
                }
                
                if ($batchIndex < count($batches) - 1) {
                    usleep(100000);
                }
            }
        }

        // 4. Subir avatar
        if ($moodleId && !empty($u['avatar_path'])) {
            $avatarPath = __DIR__ . '/uploads/avatars/' . $u['avatar_path'];
            
            if (file_exists($avatarPath) && is_readable($avatarPath)) {
                try {
                    $uploadUrl = rtrim(MOODLE_BASE_URL, '/') . '/webservice/upload.php';
                    $post = [
                        'token' => MOODLE_WS_TOKEN,
                        'filearea' => 'draft',
                        'itemid' => 0,
                        'file' => new CURLFile($avatarPath)
                    ];

                    $ch = curl_init($uploadUrl);
                    curl_setopt($ch, CURLOPT_POST, true);
                    curl_setopt($ch, CURLOPT_POSTFIELDS, $post);
                    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
                    $resp = curl_exec($ch);
                    
                    if ($resp === false) {
                        throw new RuntimeException("Error cURL upload: " . curl_error($ch));
                    }
                    
                    curl_close($ch);
                    $respData = json_decode($resp, true);
                    
                    if (is_array($respData) && !empty($respData[0]['itemid'])) {
                        $draftitemid = $respData[0]['itemid'];
                        $mc->request(MOODLE_WS_TOKEN, 'core_user_update_picture', [
                            'userid' => $moodleId,
                            'draftitemid' => $draftitemid,
                        ]);
                        error_log("[set_password] Avatar actualizado en Moodle");
                        $moodleOperations['avatar_updated'] = true;
                    }
                } catch (Exception $e) {
                    handleMoodleError("Actualización de avatar", $e);
                }
            }
        }
    } else {
        error_log("[set_password] Usuario ya tiene moodle_id: {$user['moodle_id']}");
        $moodleId = $user['moodle_id'];
        $moodleOperations['user_created_updated'] = true;
    }

// ======== ACTUALIZAR CONTRASEÑA EN MOODLE ========
try {
    $mc = getMoodleClient();

    $mc->request(MOODLE_WS_TOKEN, 'core_user_update_users', [
        'users' => [[
            'id' => (int)$moodleId,
            'password' => $password
        ]]
    ]);

    error_log("[set_password] Contraseña actualizada en Moodle para moodle_id={$moodleId}");
    $moodleOperations['password_updated'] = true;

} catch (Exception $e) {
    handleMoodleError("Actualización de contraseña Moodle", $e);
}


    // ======== Respuesta exitosa ========
    $response = [
        'status' => 'ok',
        'msg' => 'Contraseña establecida exitosamente',
        'user_id' => $user['id_usuario'],
        'moodle_id' => $moodleId ?? null,
    ];
    
    if ($moodleId) {
        $response['moodle_operations'] = $moodleOperations;
        $response['msg'] .= ' y sincronizado con Moodle';
    } else {
        $response['msg'] .= ' (sincronización con Moodle pendiente)';
    }
    
    respond(200, $response);

} catch (Throwable $e) {
    error_log("[set_password][CRITICAL] Error general: " . $e->getMessage());
    error_log("[set_password][TRACE] " . $e->getTraceAsString());
    
    respond(500, [
        'status' => 'error',
        'msg' => 'Error interno del servidor',
        'debug' => $_ENV['APP_ENV'] === 'development' ? $e->getMessage() : null
    ]);
}
