<?php
/** GET /api/types/list.php */
require_once __DIR__ . '/../../helpers/bootstrap.php';
DocumentTypeController::list($pdo);
