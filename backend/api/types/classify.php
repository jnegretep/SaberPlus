<?php
/** GET /api/types/classify.php?ocr_text= */
require_once __DIR__ . '/../../helpers/bootstrap.php';
DocumentTypeController::classify($pdo);
