<?php
// /var/www/html/api/prepsaber/backend/includes/moodle.php

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/../moodle/MoodleClient.php';

/**
 * Configuración de Moodle
 * 
 * Las URLs y tokens ahora se definen en includes/config.php
 * Este archivo mantiene compatibilidad con código existente que usa
 * las constantes MOODLE_BASE_URL, MOODLE_WS_ENDPOINT, MOODLE_WS_TOKEN.
 */

// Las constantes ya están definidas en config.php, pero las validamos
if (!is_string(MOODLE_BASE_URL) || trim(MOODLE_BASE_URL) === '') {
    error_log('[MOODLE_CONFIG] MOODLE_BASE_URL inválido');
}
if (!is_string(MOODLE_WS_ENDPOINT) || trim(MOODLE_WS_ENDPOINT) === '') {
    error_log('[MOODLE_CONFIG] MOODLE_WS_ENDPOINT inválido');
}
if (!is_string(MOODLE_WS_TOKEN) || trim(MOODLE_WS_TOKEN) === '') {
    error_log('[MOODLE_CONFIG] MOODLE_WS_TOKEN inválido');
}

/**
 * Helper para obtener un MoodleClient apuntando al endpoint REST
 */
if (!function_exists('getMoodleClient')) {
    function getMoodleClient(): MoodleClient
    {
        return new MoodleClient(getMoodleWsUrl(), MOODLE_WS_FORMAT);
    }
}

/**
 * Retorno estructurado para scripts que requieren configuración
 */
return [
    'base_url'    => MOODLE_BASE_URL,
    'ws_endpoint' => MOODLE_WS_ENDPOINT,
    'ws_token'    => MOODLE_WS_TOKEN
];
