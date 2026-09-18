<?php
// ⚠️ Credenciales leídas de variables de entorno (backend/.env). Ver .env.example
require_once __DIR__ . '/../env.php';

$host = env('DB_HOST', 'localhost');
$dbname = env('DB_NAME', 'prepsaber');
$username = env_required('DB_USER');
$password = env_required('DB_PASS');

try {
    $conexion = new PDO(
        "mysql:host=$host;dbname=$dbname;charset=utf8mb4",
        $username,
        $password,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4"
        ]
    );

    // ?? Ajustes adicionales para asegurar codificación y zona horaria
    $conexion->exec("SET NAMES utf8mb4");
    $conexion->exec("SET time_zone = '+00:00'");
    mb_internal_encoding("UTF-8");

} catch (PDOException $e) {
    error_log("[DB ERROR] " . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'msg' => 'Error interno de base de datos'
    ], JSON_UNESCAPED_UNICODE);
    exit; // <-- muy importante
}
