<?php
/** GET /api/courses/detail.php?id= */
require_once __DIR__ . '/../../helpers/bootstrap.php';
CourseController::detail($pdo);
