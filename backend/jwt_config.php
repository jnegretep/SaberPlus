<?php
// jwt_config.php
// ⚠️ El secreto se lee de la variable de entorno JWT_SECRET (backend/.env).
//    Genera uno nuevo con: openssl rand -hex 32
require_once __DIR__ . '/env.php';

return [
    'secret'         => env_required('JWT_SECRET'),
    'algo'           => 'HS256',
    'issuer'         => 'prep-saber',
    'audience'       => 'prep-saber-users',
    'expiry_seconds' => 86400, // 24 horas
    
    // Validación adicional
    'validate' => function($config) {
        if (empty($config['secret']) || strlen($config['secret']) < 32) {
            throw new Exception('JWT secret must be at least 32 characters');
        }
        if (!in_array($config['algo'], ['HS256', 'HS384', 'HS512'])) {
            throw new Exception('Invalid JWT algorithm');
        }
        return true;
    }
];