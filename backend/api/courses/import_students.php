<?php
/**
 * POST /api/courses/import_students.php
 *
 * Recibe un JSON con la lista de estudiantes parseados desde Excel/CSV
 * en el cliente Flutter.
 *
 * Body:
 * {
 *   "course_id": 1,
 *   "students": [
 *     { "first_name": "Pedrito", "last_name": "Pereira", "student_code": "EST-001", "document_id": "1102345678", "guardian_name": "Carlos Pereira", "guardian_phone": "3015551111" },
 *     ...
 *   ]
 * }
 */
require_once __DIR__ . '/../../helpers/bootstrap.php';
CourseController::importStudents($pdo);
