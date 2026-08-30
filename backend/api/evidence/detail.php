<?php
/** GET /api/evidence/detail.php?id= */
require_once __DIR__ . '/../../helpers/bootstrap.php';
EvidenceController::detail($pdo);
