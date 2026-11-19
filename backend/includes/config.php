<?php
// /var/www/html/api/prepsaber/backend/includes/config.php
// ============================================================
// Saber+ — Configuración centralizada del backend
// ============================================================
// Este es el ÚNICO lugar donde se definen las URLs del sistema.
// Todos los demás archivos PHP deben usar estas constantes.
//
// Para cambiar de servidor, solo se modifica este archivo.
// ============================================================

// ── URLs del sistema ──
// Moodle (plataforma de cursos)
if (!defined('MOODLE_BASE_URL')) {
    define('MOODLE_BASE_URL', 'https://preicfes.corpoinstel.edu.co');
}

// Backend (esta API)
if (!defined('BACKEND_BASE_URL')) {
    define('BACKEND_BASE_URL', 'https://corpoinstel.edu.co/api/prepsaber/backend');
}

// ── Endpoints de Moodle ──
if (!defined('MOODLE_WS_ENDPOINT')) {
    define('MOODLE_WS_ENDPOINT', '/webservice/rest/server.php');
}

if (!defined('MOODLE_LOGIN_ENDPOINT')) {
    define('MOODLE_LOGIN_ENDPOINT', '/login/token.php');
}

// ── Token del Web Service de Moodle ──
// Token con permisos de lectura/escritura para los WS de Moodle
if (!defined('MOODLE_WS_TOKEN')) {
    define('MOODLE_WS_TOKEN', '37663518c05c753401b5fa535ceb7316');
}

// ── Servicio de Moodle Mobile App ──
if (!defined('MOODLE_SERVICE_NAME')) {
    define('MOODLE_SERVICE_NAME', 'moodle_mobile_app');
}

// ── Formato de respuesta de Moodle WS ──
if (!defined('MOODLE_WS_FORMAT')) {
    define('MOODLE_WS_FORMAT', 'json');
}

// ── Helpers de URL ──

/**
 * Construye la URL completa del endpoint REST de Moodle.
 * @return string Ej: https://preicfes.corpoinstel.edu.co/webservice/rest/server.php
 */
if (!function_exists('getMoodleWsUrl')) {
    function getMoodleWsUrl(): string {
        return rtrim(MOODLE_BASE_URL, '/') . MOODLE_WS_ENDPOINT;
    }
}

/**
 * Construye la URL del endpoint de login de Moodle.
 * @return string Ej: https://preicfes.corpoinstel.edu.co/login/token.php
 */
if (!function_exists('getMoodleLoginUrl')) {
    function getMoodleLoginUrl(): string {
        return rtrim(MOODLE_BASE_URL, '/') . MOODLE_LOGIN_ENDPOINT;
    }
}

/**
 * Construye la URL del proxy de archivos del backend.
 * @return string Ej: https://corpoinstel.edu.co/api/prepsaber/backend/get_file.php
 */
if (!function_exists('getBackendFileProxyUrl')) {
    function getBackendFileProxyUrl(): string {
        return rtrim(BACKEND_BASE_URL, '/') . '/get_file.php';
    }
}

/**
 * Construye la URL de avatares del backend.
 * @param string|null $avatarPath Path relativo del avatar (ej: "avatar_123.jpg")
 * @return string|null URL completa o null si no hay avatar
 */
if (!function_exists('getAvatarUrl')) {
    function getAvatarUrl(?string $avatarPath): ?string {
        if (empty($avatarPath)) return null;

        // Si ya es URL completa, devolverla tal cual
        if (str_starts_with($avatarPath, 'http://') ||
            str_starts_with($avatarPath, 'https://') ||
            str_starts_with($avatarPath, 'data:')) {
            return $avatarPath;
        }

        // Limpiar path
        $cleanPath = ltrim($avatarPath, '/');
        if (str_starts_with($cleanPath, 'uploads/avatars/')) {
            $cleanPath = substr($cleanPath, strlen('uploads/avatars/'));
        }

        return rtrim(BACKEND_BASE_URL, '/') . '/uploads/avatars/' . $cleanPath;
    }
}

/**
 * Construye la URL de un archivo en el backend (reports, etc.).
 * @param string $relativePath Path relativo (ej: "reports/reporte_123.pdf")
 * @return string URL completa
 */
if (!function_exists('getBackendFileUrl')) {
    function getBackendFileUrl(string $relativePath): string {
        $cleanPath = ltrim($relativePath, '/');
        return rtrim(BACKEND_BASE_URL, '/') . '/' . $cleanPath;
    }
}
