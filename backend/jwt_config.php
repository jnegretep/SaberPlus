<?php
// jwt_config.php
return [
    'secret'         => '90c5de59689bec58fe84e8f2006a6e7bafaffb906e4996e63ceee55fe2cfc9a9',
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