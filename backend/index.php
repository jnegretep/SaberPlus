<?php
/**
 * Punto de entrada raíz del backend.
 * Devuelve información básica del servicio para health check.
 */
require_once __DIR__ . '/helpers/bootstrap.php';

send_json(true, [
    'name'    => APP_NAME,
    'version' => APP_VERSION,
    'env'     => APP_ENV,
    'time'    => date('c'),
], 'API Evidencias Docentes operativa.');
