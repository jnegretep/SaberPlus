<?php
// update_hash.php
require 'includes/conexion.php';

// Configuración
$email_usuario = 'juanprueba@example.com';
$nueva_contrasena = '123456'; // La misma contraseña que tenía antes

try {
    // 1. Generar nuevo hash seguro
    $nuevo_hash = password_hash($nueva_contrasena, PASSWORD_DEFAULT);
    
    // 2. Actualizar en la base de datos
    $stmt = $conexion->prepare("UPDATE usuarios SET contrasena_hash = ? WHERE email = ?");
    $stmt->execute([$nuevo_hash, $email_usuario]);
    
    // 3. Verificar resultado
    $filas_afectadas = $stmt->rowCount();
    
    if ($filas_afectadas > 0) {
        echo "? Hash actualizado correctamente para $email_usuario\n";
        echo "Nuevo hash: $nuevo_hash\n";
    } else {
        echo "?? No se encontró el usuario con email $email_usuario\n";
    }
    
} catch (PDOException $e) {
    echo "? Error al actualizar: " . $e->getMessage() . "\n";
}