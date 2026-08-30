<?php
/** POST /api/courses/create.php */
require_once __DIR__ . '/../../helpers/bootstrap.php';
CourseController::create($pdo);
