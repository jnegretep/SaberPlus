<?php
/**
 * config/config.php
 * Constantes globales del proyecto backend.
 */

declare(strict_types=1);

date_default_timezone_set('America/Bogota');

// === Entorno ===
define('APP_ENV', getenv('APP_ENV') ?: 'development');

// === App ===
define('APP_NAME', 'Evidencias Docentes');
define('APP_VERSION', '1.0.0');

// === JWT ===
define('JWT_SECRET', getenv('JWT_SECRET') ?: 'c4mb14-3st4-cl4v3-3n-pr0duccl0n-s3gur4-2025');
define('JWT_ISS', 'evidencias-docentes');
define('JWT_AUD', 'evidencias-docentes-app');
define('JWT_EXP_HOURS', 12); // token válido 12 horas

// === Uploads ===
define('UPLOADS_DIR', __DIR__ . '/../uploads');
define('UPLOADS_MAX_SIZE', 15 * 1024 * 1024); // 15 MB
define('UPLOADS_ALLOWED_MIME', ['image/jpeg', 'image/png', 'image/webp']);
define('UPLOADS_BASE_URL', '/uploads'); // Sirven como estáticos

// === Paginación ===
define('DEFAULT_PAGE_SIZE', 20);
define('MAX_PAGE_SIZE', 100);

// === Roles ===
define('ROLE_ADMIN', 'admin');
define('ROLE_DIRECTOR', 'director');
define('ROLE_TEACHER', 'teacher');
