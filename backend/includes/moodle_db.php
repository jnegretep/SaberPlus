<?php
// includes/moodle_db.php
// Conexión a la base de datos de Moodle
// Datos obtenidos del config.php de Moodle

define('MOODLE_DB_HOST', 'localhost');
define('MOODLE_DB_NAME', 'preicfes');
define('MOODLE_DB_USER', 'preicfesuser2');
define('MOODLE_DB_PASS', 'Instel91.');
define('MOODLE_DB_PREFIX', 'mdl_');

function getMoodleDBConnection() {
    static $pdo = null;
    if ($pdo === null) {
        try {
            $pdo = new PDO(
                'mysql:host=' . MOODLE_DB_HOST . ';dbname=' . MOODLE_DB_NAME . ';charset=utf8mb4',
                MOODLE_DB_USER,
                MOODLE_DB_PASS,
                [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
            );
        } catch (PDOException $e) {
            error_log("[MOODLE_DB] Error de conexión: " . $e->getMessage());
            return null;
        }
    }
    return $pdo;
}