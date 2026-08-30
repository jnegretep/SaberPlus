<?php
/**
 * GET /api/students/match.php?course_id=&ocr_text=
 *
 * Recibe el nombre extraído del documento por OCR en la app
 * y devuelve el estudiante más probable de la lista del curso.
 */
require_once __DIR__ . '/../../helpers/bootstrap.php';
StudentController::match($pdo);
