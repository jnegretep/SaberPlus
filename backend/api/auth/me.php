<?php
/** GET /api/auth/me.php */
require_once __DIR__ . '/../../helpers/bootstrap.php';
AuthController::me($pdo);
