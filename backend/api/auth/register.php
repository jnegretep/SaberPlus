<?php
/** POST /api/auth/register.php  (solo admin) */
require_once __DIR__ . '/../../helpers/bootstrap.php';
AuthController::register($pdo);
