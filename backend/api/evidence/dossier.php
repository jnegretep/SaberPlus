<?php
/**
 * GET /api/evidence/dossier.php?student_id=&period_id=
 *
 * Devuelve todas las evidencias aprobadas del estudiante agrupadas
 * por período y tipo de documento, listas para exportar a PDF.
 */
require_once __DIR__ . '/../../helpers/bootstrap.php';
EvidenceController::dossier($pdo);
