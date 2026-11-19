<?php
/**
 * TRAZA - Middleware de Autenticación
 * Valida el token JWT en cada petición protegida
 */

require_once __DIR__ . '/../config/database.php';

/**
 * Verificar autenticación y retornar datos del usuario
 */
function authenticate(): array {
    $headers = getallheaders();
    $authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    
    if (empty($authHeader)) {
        jsonResponse(['error' => 'Token de autenticación requerido'], 401);
    }
    
    // Extraer Bearer token
    if (preg_match('/Bearer\s+(\S+)/', $authHeader, $matches)) {
        $token = $matches[1];
    } else {
        jsonResponse(['error' => 'Formato de token inválido. Use: Bearer <token>'], 401);
    }
    
    $payload = validateJWT($token);
    if (!$payload) {
        jsonResponse(['error' => 'Token inválido o expirado'], 401);
    }
    
    // Verificar que el usuario sigue activo
    $db = getDB();
    $stmt = $db->prepare('SELECT id, full_name, email, role, subject, is_active FROM users WHERE id = ?');
    $stmt->execute([$payload['user_id']]);
    $user = $stmt->fetch();
    
    if (!$user || !$user['is_active']) {
        jsonResponse(['error' => 'Usuario inactivo o no encontrado'], 401);
    }
    
    return $user;
}

/**
 * Verificar que el usuario es director de grupo
 */
function requireDirector(array $user): void {
    if ($user['role'] !== 'director' && $user['role'] !== 'admin') {
        jsonResponse(['error' => 'Se requiere rol de director de grupo'], 403);
    }
}

/**
 * Verificar que el usuario es admin
 */
function requireAdmin(array $user): void {
    if ($user['role'] !== 'admin') {
        jsonResponse(['error' => 'Se requiere rol de administrador'], 403);
    }
}
