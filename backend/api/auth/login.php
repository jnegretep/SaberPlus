<?php
/** POST /api/auth/login.php */
require_once __DIR__ . '/../../helpers/bootstrap.php';
require_once __DIR__ . '/../../controllers/AuthController.php';
AuthController::login($pdo);
