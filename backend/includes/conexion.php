<?php

$host = "localhost";
$dbname = "prepsaber";
$username = "jnegretep";
$password = "Jnegretep1";

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
