<?php
// wompi_config.php
// ⚠️ TODAS las llaves se leen de variables de entorno (backend/.env).
//    Ninguna llave de producción debe estar escrita en el código.
require_once __DIR__ . '/env.php';

return [
    'public_key'   => env_required('WOMPI_PUBLIC_KEY'),
    'private_key'  => env_required('WOMPI_PRIVATE_KEY'),
    'events_secret'=> env_required('WOMPI_EVENTS_SECRET'),
    'integrity'    => env_required('WOMPI_INTEGRITY_SECRET'),

    'currency'     => 'COP',
    'redirect_url' => 'https://corpoinstel.edu.co/api/prepsaber/backend/wompi_return.php',
    'webhook_url'  => 'https://corpoinstel.edu.co/api/prepsaber/backend/wompi_webhook.php',

    // Modo: 'production' o 'sandbox'
    'environment'  => 'production',
];