<?php
/** GET /api/evidence/list.php?course_id=&student_id=&status= */
require_once __DIR__ . '/../../helpers/bootstrap.php';
EvidenceController::list($pdo);
