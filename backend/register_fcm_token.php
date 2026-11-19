<?php
declare(strict_types=1);

/**
 * register_fcm_token.php — Registro del token FCM del dispositivo.
 *
 * v3 (2026-10): RESTAURADO el fix de seguridad que se perdió en v1.7.0.
 *   ⚠️ El id de usuario SIEMPRE sale del JWT autenticado — NUNCA del body.
 *   (La versión anterior lo aceptaba del body: cualquiera podía
 *   sobrescribir el token de otro usuario y robarle/bloquearle las
 *   notificaciones. Además, como la app solo envía {fcm_token}, el id
 *   llegaba NULL y respondía "Datos incompletos" → el token NUNCA se
 *   guardaba → notificaciones muertas.)
 *
 * La app usa save_fcm_token.php como endpoint principal; este archivo es
 * el alias histórico (mismo comportamiento, mismas respuestas) para
 * compatibilidad con versiones viejas instaladas.
 */

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/auth_middleware.php'; // valida JWT y define $authUser

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// Capturar el body crudo una sola vez (auth_middleware no debe consumirlo)
$rawBody = file_get_contents("php://input");

try {
    $data = json_decode($rawBody, true) ?? [];

    // ⚠️ SEGURIDAD: id del JWT, no del body
    $id_usuario = $authUser['id_usuario'] ?? null;
    $fcm_token = $data['fcm_token'] ?? $data['token'] ?? null;

    if (empty($id_usuario) || empty($fcm_token) || strlen((string)$fcm_token) < 20) {
        http_response_code(400);
        echo json_encode(["status" => "error", "msg" => "Datos incompletos"]);
        exit;
    }

    $stmt = $conexion->prepare("
        UPDATE usuarios
        SET fcm_token = :fcm_token
        WHERE id_usuario = :id_usuario
    ");
    $stmt->execute([
        ":fcm_token" => $fcm_token,
        ":id_usuario" => $id_usuario
    ]);

    echo json_encode([
        "status" => "ok",
        "msg" => "Token registrado correctamente"
    ]);

} catch (Exception $e) {
    error_log("[register_fcm_token] Error: " . $e->getMessage());
    http_response_code(500);
    echo json_encode(["status" => "error", "msg" => "Error interno"]);
    exit;
}
