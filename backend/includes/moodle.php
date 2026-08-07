<?php
// /var/www/html/api/prepsaber/backend/includes/moodle.php

require_once __DIR__ . '/../moodle/MoodleClient.php';

/**
 * Configuración de Moodle
 */
$baseUrl    = 'http://172.93.49.94/preicfes';
$wsEndpoint = '/webservice/rest/server.php';
$wsToken    = '37663518c05c753401b5fa535ceb7316';

// Validaciones
if (!is_string($baseUrl) || trim($baseUrl) === '') {
    error_log('[MOODLE_CONFIG] baseUrl inválido');
}
if (!is_string($wsEndpoint) || trim($wsEndpoint) === '') {
    error_log('[MOODLE_CONFIG] wsEndpoint inválido');
}
if (!is_string($wsToken) || trim($wsToken) === '') {
    error_log('[MOODLE_CONFIG] wsToken inválido');
}

// Constantes (por compatibilidad)
if (!defined('MOODLE_BASE_URL')) {
    define('MOODLE_BASE_URL', $baseUrl);
}
if (!defined('MOODLE_WS_ENDPOINT')) {
    define('MOODLE_WS_ENDPOINT', $wsEndpoint);
}
if (!defined('MOODLE_WS_TOKEN')) {
    define('MOODLE_WS_TOKEN', $wsToken);
}

/**
 * Helper para obtener un MoodleClient apuntando al endpoint REST
 */
if (!function_exists('getMoodleClient')) {
    function getMoodleClient(): MoodleClient
    {
        $endpoint = rtrim(MOODLE_BASE_URL, '/') . MOODLE_WS_ENDPOINT;
        return new MoodleClient($endpoint, 'json');
    }
}

/**
 * Retorno estructurado para scripts que requieren configuración
 */
return [
    'base_url'   => $baseUrl,
    'ws_endpoint'=> $wsEndpoint,
    'ws_token'   => $wsToken
];
