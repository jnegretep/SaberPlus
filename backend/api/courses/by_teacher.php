<?php
/** GET /api/courses/by_teacher.php */
require_once __DIR__ . '/../../helpers/bootstrap.php';
CourseController::byTeacher($pdo);
