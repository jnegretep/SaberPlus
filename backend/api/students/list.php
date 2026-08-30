<?php
/** GET /api/students/list.php?course_id= */
require_once __DIR__ . '/../../helpers/bootstrap.php';
StudentController::list($pdo);
