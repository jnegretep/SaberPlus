<?php
// change_password.php - VERSIÓN DEFINITIVA, SIN RESPUESTAS VACÍAS

// ==========================
// CONFIGURACIÓN INICIAL
// ==========================
ini_set('display_errors', 0);
ini_set('display_startup_errors', 0);
error_reporting(E_ALL);
ob_start();

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo json_encode(["status" => "ok"]);
    exit;
}

// ==========================
// INCLUDES
// ==========================
require __DIR__ . '/auth_middleware.php';
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/includes/moodle.php';

// ==========================
// LECTURA DE INPUT
// ==========================
$rawInput = file_get_contents('php://input');
$input = json_decode($rawInput, true);

if (!$input) {
    ob_clean();
    echo json_encode([
        "status" => "error",
        "msg" => "Datos inválidos o cuerpo vacío"
    ]);
    exit;
}

$currentPassword = trim($input['current_password'] ?? '');
$newPassword = trim($input['new_password'] ?? '');
$confirmPassword = trim($input['confirm_password'] ?? '');

// ==========================
// VALIDACIONES
// ==========================
if (empty($currentPassword) || empty($newPassword) || empty($confirmPassword)) {
    ob_clean();
    echo json_encode([
        "status" => "error",
        "msg" => "Todos los campos son obligatorios"
    ]);
    exit;
}

if ($newPassword !== $confirmPassword) {
    ob_clean();
    echo json_encode([
        "status" => "error",
        "msg" => "Las contraseñas no coinciden"
    ]);
    exit;
}

if (strlen($newPassword) < 6) {
    ob_clean();
    echo json_encode([
        "status" => "error",
        "msg" => "La contraseña debe tener al menos 6 caracteres"
    ]);
    exit;
}

if ($currentPassword === $newPassword) {
    ob_clean();
    echo json_encode([
        "status" => "error",
        "msg" => "La nueva contraseña debe ser diferente de la actual"
    ]);
    exit;
}

try {

    // ==========================
    // USUARIO AUTENTICADO
    // ==========================
    if (!isset($authUser['id_usuario'])) {
        throw new Exception("Usuario no autenticado");
    }

    $userId = $authUser['id_usuario'];

    error_log("[CHANGE_PASSWORD] Token válido, id_usuario=$userId");

    // ==========================
    // OBTENER DATOS DEL USUARIO
    // ==========================
    $stmt = $conexion->prepare("
        SELECT moodle_username, moodle_id, email 
        FROM usuarios 
        WHERE id_usuario = ?
        LIMIT 1
    ");
    $stmt->execute([$userId]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        throw new Exception("Usuario no encontrado en la base de datos");
    }

    $moodleId = $user['moodle_id'];

    if (empty($moodleId)) {
        throw new Exception("Usuario no tiene ID de Moodle asociado");
    }

    error_log("[CHANGE_PASSWORD] Solicitud para user_id=$userId moodle_id=$moodleId");

    // ==========================
    // CAMBIO DE CONTRASEÑA EN MOODLE
    // ==========================
    $mc = getMoodleClient();

    $params = [
        "users" => [
            [
                "id" => (int)$moodleId,
                "password" => $newPassword
            ]
        ]
    ];

    $resp = $mc->request(MOODLE_WS_TOKEN, "core_user_update_users", $params);

    if (isset($resp['exception'])) {
        $errorMsg = $resp['message'] ?? 'Error desconocido de Moodle';
        throw new Exception("Moodle: " . $errorMsg);
    }

    error_log("[CHANGE_PASSWORD] Contraseña actualizada correctamente en Moodle");

    // ==========================
    // RESPUESTA FINAL (SIEMPRE JSON)
    // ==========================
    ob_clean();
    echo json_encode([
        "status" => "ok",
        "msg" => "Contraseña cambiada exitosamente",
        "requires_relogin" => true
    ]);
    exit;

} catch (Exception $e) {

    error_log("[CHANGE_PASSWORD] ERROR: " . $e->getMessage());

    ob_clean();
    echo json_encode([
        "status" => "error",
        "msg" => $e->getMessage()
    ]);
    exit;
}
