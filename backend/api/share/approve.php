<?php
/** POST /api/share/approve.php  Body: { share_request_id } */
require_once __DIR__ . '/../../helpers/bootstrap.php';
ShareController::approve($pdo);
