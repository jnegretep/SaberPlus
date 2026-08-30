<?php
/** GET /api/courses/list.php */
require_once __DIR__ . '/../../helpers/bootstrap.php';
CourseController::list($pdo);
