<?php
/**
 * helpers/auth.php
 * Autoload de archivos compartidos + bootstrap de conexión.
 */

declare(strict_types=1);

// Cargar config primero
require_once __DIR__ . '/../config/config.php';
require_once __DIR__ . '/../config/cors.php';
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../controllers/AuthController.php';
require_once __DIR__ . '/../controllers/CourseController.php';
require_once __DIR__ . '/../controllers/ShareController.php';
require_once __DIR__ . '/../controllers/EvidenceController.php';
require_once __DIR__ . '/../controllers/StudentController.php';
require_once __DIR__ . '/../controllers/DocumentTypeController.php';
require_once __DIR__ . '/../models/User.php';
require_once __DIR__ . '/../models/Course.php';
require_once __DIR__ . '/../models/Student.php';
require_once __DIR__ . '/../models/Evidence.php';
require_once __DIR__ . '/../models/ShareRequest.php';
require_once __DIR__ . '/../models/DocumentType.php';

// Helpers
require_once __DIR__ . '/response.php';
require_once __DIR__ . '/request.php';
require_once __DIR__ . '/jwt.php';

// Modelos (autoload simple)
foreach (glob(__DIR__ . '/../models/*.php') as $modelFile) {
    require_once $modelFile;
}
