<?php
// update_profile.php - VERSIÓN FINAL CONSISTENTE CON REGISTER.PHP Y SET_PASSWORD.PHP
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require __DIR__ . '/auth_middleware.php';
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/includes/moodle.php';

$input = json_decode(file_get_contents('php://input'), true);

if (!$input) {
    echo json_encode(["status" => "error", "msg" => "Datos inválidos"]);
    exit;
}

// Obtener ID del usuario autenticado
$userId = $authUser['id_usuario'] ?? null;
if (!$userId) {
    http_response_code(401);
    echo json_encode(["status" => "error", "msg" => "No autenticado"]);
    exit;
}

// SOLO campos editables
$nombre       = trim($input['nombre'] ?? '');
$telefono     = trim($input['telefono'] ?? '');
$avatarBase64 = trim($input['avatar'] ?? '');

if (empty($nombre) || strlen($nombre) < 2) {
    echo json_encode(["status" => "error", "msg" => "Nombre inválido"]);
    exit;
}

// DEPURACIÓN: Verificar que MOODLE_WS_TOKEN sea string
if (!defined('MOODLE_WS_TOKEN')) {
    error_log("[UPDATE_PROFILE] ERROR: MOODLE_WS_TOKEN no está definido");
    echo json_encode(["status" => "error", "msg" => "Error de configuración del servidor"]);
    exit;
}

if (!is_string(MOODLE_WS_TOKEN)) {
    error_log("[UPDATE_PROFILE] ERROR: MOODLE_WS_TOKEN no es string, es: " . gettype(MOODLE_WS_TOKEN));
    echo json_encode(["status" => "error", "msg" => "Error de configuración del servidor"]);
    exit;
}

try {
    // ? INICIAR TRANSACCIÓN
    $conexion->beginTransaction();
    
    // 1. OBTENER DATOS ACTUALES DEL USUARIO (igual que set_password.php)
    $stmt = $conexion->prepare("
        SELECT moodle_id, avatar_path, departamento, ciudad, colegio, grado, 
               email, moodle_username, nombre as nombre_actual, telefono as telefono_actual
        FROM usuarios 
        WHERE id_usuario = ?
    ");
    $stmt->execute([$userId]);
    $currentUser = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$currentUser) {
        throw new Exception("Usuario no encontrado");
    }
    
    $moodleId = $currentUser['moodle_id'] ?? null;
    $currentAvatar = $currentUser['avatar_path'] ?? null;
    $email = $currentUser['email'] ?? null;
    $moodleUsername = $currentUser['moodle_username'] ?? null;
    
    // 2. PROCESAR AVATAR SI SE ENVÍA (EXACTAMENTE IGUAL QUE REGISTER.PHP)
    $newAvatarFilename = null;
    $avatarChanged = false;
    
    if (!empty($avatarBase64)) {
        error_log("[UPDATE_PROFILE] Procesando nuevo avatar para usuario ID: $userId");
        
        // Decodificar base64 (igual que register.php)
        $decoded = base64_decode($avatarBase64);
        if ($decoded === false) {
            throw new Exception("Avatar en formato base64 inválido");
        }
        
        // Mismo formato que register.php: 'avatar_' . uniqid() . '.jpg'
        $newAvatarFilename = 'avatar_' . uniqid() . '.jpg';
        $avatarsDir = __DIR__ . '/uploads/avatars/';
        
        // Crear directorio si no existe (igual que register.php)
        if (!is_dir($avatarsDir)) {
            mkdir($avatarsDir, 0777, true);
        }
        
        // Guardar archivo (igual que register.php - guarda binario sin conversión)
        file_put_contents($avatarsDir . $newAvatarFilename, $decoded);
        
        error_log("[UPDATE_PROFILE] Nuevo avatar guardado: $newAvatarFilename");
        $avatarChanged = true;
        
        // Eliminar avatar anterior si existe
        if ($currentAvatar) {
            $oldAvatarBasename = basename($currentAvatar);
            $oldAvatarPath = $avatarsDir . $oldAvatarBasename;
            
            if (file_exists($oldAvatarPath)) {
                unlink($oldAvatarPath);
                error_log("[UPDATE_PROFILE] Avatar anterior eliminado: $oldAvatarBasename");
            }
        }
    }
    
    // 3. ACTUALIZAR BASE DE DATOS LOCAL - SOLO CAMPOS EDITABLES
    if ($avatarChanged && $newAvatarFilename) {
        // Actualizar con nuevo avatar
        $stmt = $conexion->prepare("UPDATE usuarios SET nombre = ?, telefono = ?, avatar_path = ? WHERE id_usuario = ?");
        $stmt->execute([$nombre, $telefono, $newAvatarFilename, $userId]);
        $avatarFilename = $newAvatarFilename;
        error_log("[UPDATE_PROFILE] BD local actualizada con nuevo avatar: $newAvatarFilename");
    } else {
        // Actualizar sin cambiar avatar
        $stmt = $conexion->prepare("UPDATE usuarios SET nombre = ?, telefono = ? WHERE id_usuario = ?");
        $stmt->execute([$nombre, $telefono, $userId]);
        $avatarFilename = $currentAvatar;
        error_log("[UPDATE_PROFILE] BD local actualizada sin cambiar avatar");
    }
    
    // 4. ACTUALIZAR EN MOODLE SI TIENE MOODLE_ID (COMO SET_PASSWORD.PHP)
    $moodleUpdated = false;
    $moodleAvatarUpdated = false;
    
    if ($moodleId && $email) {
        $mc = getMoodleClient();
        
        if (!is_object($mc) || get_class($mc) !== 'MoodleClient') {
            error_log("[UPDATE_PROFILE] WARNING: getMoodleClient() no devuelve MoodleClient");
        } else {
            // 4.1. DIVIDIR EL NOMBRE EXACTAMENTE COMO SET_PASSWORD.PHP
            $parts = preg_split('/\s+/', trim($nombre), 2, PREG_SPLIT_NO_EMPTY);
            $firstname = $parts[0] ?? 'Nombre';
            $lastname = $parts[1] ?? 'Usuario'; // set_password.php usa 'Usuario' como fallback
            
            error_log("[UPDATE_PROFILE] Nombre dividido para Moodle: firstname='$firstname', lastname='$lastname'");
            
            // 4.2. PREPARAR DATOS PARA MOODLE (CONSISTENTE CON SET_PASSWORD.PHP)
            $updateUser = [
                'id' => (int)$moodleId,
                'firstname' => $firstname,
                'lastname' => $lastname,
                'country' => 'CO',
                'phone1' => $telefono, // Usar phone1 en lugar de customfield
                'customfields' => [
                    // Mantener todos los customfields como están en set_password.php
                    ['type' => 'departamento', 'value' => $currentUser['departamento'] ?? ''],
                    ['type' => 'ciudad', 'value' => $currentUser['ciudad'] ?? ''],
                    ['type' => 'colegio', 'value' => $currentUser['colegio'] ?? ''],
                    ['type' => 'grado', 'value' => $currentUser['grado'] ?? ''],
                    // Añadir teléfono también como customfield por si acaso
                    ['type' => 'telefono', 'value' => $telefono],
                ],
            ];
            
            // 4.3. ACTUALIZAR USUARIO EN MOODLE
            try {
                $resp = $mc->request(MOODLE_WS_TOKEN, 'core_user_update_users', ['users' => [$updateUser]]);
                
                if (isset($resp['exception'])) {
                    $errorMsg = $resp['message'] ?? 'Error desconocido de Moodle';
                    
                    // Intentar con 'shortname' si 'type' falla
                    if (strpos($errorMsg, 'customfields') !== false || strpos($errorMsg, 'type') !== false) {
                        error_log("[UPDATE_PROFILE] Intentando con 'shortname'...");
                        
                        $updateUser['customfields'] = [
                            ['shortname' => 'departamento', 'value' => $currentUser['departamento'] ?? ''],
                            ['shortname' => 'ciudad', 'value' => $currentUser['ciudad'] ?? ''],
                            ['shortname' => 'colegio', 'value' => $currentUser['colegio'] ?? ''],
                            ['shortname' => 'grado', 'value' => $currentUser['grado'] ?? ''],
                            ['shortname' => 'telefono', 'value' => $telefono],
                        ];
                        
                        $resp = $mc->request(MOODLE_WS_TOKEN, 'core_user_update_users', ['users' => [$updateUser]]);
                    }
                }
                
                if (!isset($resp['exception'])) {
                    $moodleUpdated = true;
                    error_log("[UPDATE_PROFILE] Datos actualizados en Moodle exitosamente para moodle_id: $moodleId");
                } else {
                    error_log("[UPDATE_PROFILE] Error al actualizar datos en Moodle: " . ($resp['message'] ?? 'Error desconocido'));
                }
            } catch (Exception $e) {
                error_log("[UPDATE_PROFILE] Excepción al actualizar datos en Moodle: " . $e->getMessage());
            }
            
            // 4.4. SUBIR AVATAR A MOODLE SI SE CAMBIÓ (IGUAL QUE SET_PASSWORD.PHP)
            if ($avatarChanged && $newAvatarFilename) {
                $avatarPath = __DIR__ . '/uploads/avatars/' . $newAvatarFilename;
                
                if (file_exists($avatarPath) && is_readable($avatarPath)) {
                    try {
                        error_log("[UPDATE_PROFILE] Subiendo avatar a Moodle...");
                        
                        // Exactamente igual que set_password.php
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
                            
                            // Actualizar imagen de perfil en Moodle
                            $mc->request(MOODLE_WS_TOKEN, 'core_user_update_picture', [
                                'userid' => $moodleId,
                                'draftitemid' => $draftitemid,
                            ]);
                            
                            error_log("[UPDATE_PROFILE] Avatar actualizado en Moodle exitosamente");
                            $moodleAvatarUpdated = true;
                        }
                    } catch (Exception $e) {
                        error_log("[UPDATE_PROFILE] Error al subir avatar a Moodle: " . $e->getMessage());
                        // No lanzamos excepción, el avatar local ya se guardó
                    }
                }
            }
        }
    } else {
        error_log("[UPDATE_PROFILE] Usuario no tiene moodle_id, solo actualización local");
    }
    
    // ? COMMIT DE LA TRANSACCIÓN
    $conexion->commit();
    
    // 5. OBTENER DATOS ACTUALIZADOS PARA RESPUESTA
    $stmt = $conexion->prepare("
        SELECT nombre, telefono, email, avatar_path, departamento, ciudad, 
               colegio, grado, moodle_username 
        FROM usuarios 
        WHERE id_usuario = ?
    ");
    $stmt->execute([$userId]);
    $updatedUser = $stmt->fetch(PDO::FETCH_ASSOC);
    
    // 6. CONSTRUIR RESPUESTA
    $baseUrl = "https://" . $_SERVER['HTTP_HOST'];
    $avatarUrl = null;
    
    if ($updatedUser['avatar_path']) {
        $avatarBasename = basename($updatedUser['avatar_path']);
        $avatarUrl = $baseUrl . '/uploads/avatars/' . $avatarBasename;
        
        // Verificar que el archivo existe
        $avatarFile = __DIR__ . '/uploads/avatars/' . $avatarBasename;
        if (!file_exists($avatarFile)) {
            error_log("[UPDATE_PROFILE] ADVERTENCIA: Archivo de avatar no encontrado: $avatarFile");
        }
    }
    
    $response = [
        "status" => "ok", 
        "msg" => "Perfil actualizado correctamente",
        "user" => [
            "id_usuario" => (int)$userId,
            "nombre" => $updatedUser['nombre'],
            "telefono" => $updatedUser['telefono'],
            "email" => $updatedUser['email'],
            "departamento" => $updatedUser['departamento'],
            "ciudad" => $updatedUser['ciudad'],
            "colegio" => $updatedUser['colegio'],
            "grado" => $updatedUser['grado'],
            "moodle_username" => $updatedUser['moodle_username'],
            "avatar_path" => $updatedUser['avatar_path'] ? basename($updatedUser['avatar_path']) : null,
            "avatar_url" => $avatarUrl
        ],
        "moodle_updated" => $moodleUpdated,
        "moodle_avatar_updated" => $moodleAvatarUpdated
    ];
    
    error_log("[UPDATE_PROFILE] Respuesta enviada con éxito");
    
    echo json_encode($response);
    
} catch (Exception $e) {
    // ? ROLLBACK EN CASO DE ERROR
    if (isset($conexion) && $conexion->inTransaction()) {
        $conexion->rollBack();
    }
    
    error_log("[UPDATE_PROFILE] Error: " . $e->getMessage());
    echo json_encode([
        "status" => "error", 
        "msg" => "Error: " . $e->getMessage()
    ]);
}
?>