<?php
/** POST /api/share/send.php  Body: { evidence_id, to_user_id?, message? } */
require_once __DIR__ . '/../../helpers/bootstrap.php';
ShareController::send($pdo);
