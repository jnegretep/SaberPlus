<?php
// generar_token_prueba.php
require __DIR__ . '/vendor/autoload.php';

// ?? IMPORTANTE: capturar el array que retorna jwt_config.php
$configJwt = require __DIR__ . '/jwt_config.php';

if (!is_array($configJwt) || empty($configJwt['secret'])) {
    fwrite(STDERR, "ERROR: jwt_config.php no devolvió un array con 'secret'\n");
    exit(1);
}

use Firebase\JWT\JWT;

$payload = [
    'iat' => time(),
    'exp' => time() + 3600,   // válido 1 hora
    'data' => [
        'moodle_userid' => 123,   // ?? cámbialo por un ID real de tu BD
        'id_usuario'    => 41,    // opcional, por si el endpoint lo usa
    ],
];

$token = JWT::encode($payload, $configJwt['secret'], 'HS256');

echo $token . PHP_EOL;