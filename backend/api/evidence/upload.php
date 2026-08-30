<?php
/**
 * POST /api/evidence/upload.php
 *
 * Recibe multipart/form-data con la imagen + metadatos.
 * La imagen se guarda en /uploads/<course>/<doctype>/<Ym>/<file>
 * El OCR se ejecuta en el cliente (ML Kit) y el texto se envía aquí.
 *
 * Si auto_share=1, crea automáticamente una share_request hacia
 * el director de grupo del curso.
 */
require_once __DIR__ . '/../../helpers/bootstrap.php';
EvidenceController::upload($pdo);
