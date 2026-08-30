<?php
/** POST /api/share/reject.php  Body: { share_request_id, reason } */
require_once __DIR__ . '/../../helpers/bootstrap.php';
ShareController::reject($pdo);
