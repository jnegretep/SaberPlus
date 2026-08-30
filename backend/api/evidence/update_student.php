<?php
/** PUT /api/evidence/update_student.php  Body: { evidence_id, student_id } */
require_once __DIR__ . '/../../helpers/bootstrap.php';
EvidenceController::updateStudent($pdo);
