<?php
// /var/www/html/api/prepsaber/backend/moodle/config.php
// ✅ FASE 4: URLs centralizadas en includes/config.php
// Este archivo se mantiene por compatibilidad con código antiguo.
// Las constantes se definen en includes/config.php

require_once __DIR__ . '/../includes/config.php';

// URL del endpoint REST de Moodle (compatibilidad)
if (!defined('MOODLE_WS_URL')) {
    define('MOODLE_WS_URL', getMoodleWsUrl());
}

// Formato de respuesta (json)
if (!defined('MOODLE_WS_FORMAT_LOCAL')) {
    define('MOODLE_WS_FORMAT_LOCAL', 'json');
}
