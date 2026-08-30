<?php
/** GET /api/share/pending.php */
require_once __DIR__ . '/../../helpers/bootstrap.php';
ShareController::pending($pdo);
