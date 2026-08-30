<?php
/** DELETE /api/evidence/delete.php?id= */
require_once __DIR__ . '/../../helpers/bootstrap.php';
EvidenceController::delete($pdo);
