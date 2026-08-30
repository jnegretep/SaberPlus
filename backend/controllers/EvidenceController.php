<?php
/**
 * controllers/EvidenceController.php
 */

declare(strict_types=1);

class EvidenceController
{
    /**
     * POST /api/evidence/upload.php
     * Multipart form-data:
     *   - file          (archivo de imagen)
     *   - course_id     (int)
     *   - student_id    (int, opcional: si OCR lo identificó)
     *   - document_type_id (int)
     *   - subject_id    (int, opcional)
     *   - period_id     (int, opcional)
     *   - evidence_date (YYYY-MM-DD)
     *   - ocr_raw_text  (texto extraído por ML Kit en el cliente)
     *   - ocr_student_name (nombre reconocido)
     *   - ocr_doc_type_hint (tipo sugerido por OCR)
     *   - ocr_confidence (0..100)
     *   - description   (string, opcional)
     *   - auto_share    (1|0): enviar automáticamente al director de grupo
     */
    public static function upload(PDO $db): void
    {
        $payload = require_auth();
        $userId = (int)$payload['sub'];
        $institutionId = (int)$payload['inst'];

        $courseId = (int)($_POST['course_id'] ?? 0);
        $docTypeId = (int)($_POST['document_type_id'] ?? 0);
        $evidenceDate = $_POST['evidence_date'] ?? date('Y-m-d');

        if (!$courseId)        send_error('course_id requerido.', 'MISSING_FIELD', 422);
        if (!$docTypeId)      send_error('document_type_id requerido.', 'MISSING_FIELD', 422);
        if (!isset($_FILES['file'])) send_error('Archivo de imagen no recibido.', 'NO_FILE', 422);

        $file = $_FILES['file'];
        if ($file['error'] !== UPLOAD_ERR_OK) {
            send_error('Error en la subida del archivo (código ' . $file['error'] . ').', 'UPLOAD_ERROR', 400);
        }
        if ($file['size'] > UPLOADS_MAX_SIZE) {
            send_error('El archivo excede el tamaño máximo permitido.', 'FILE_TOO_LARGE', 413);
        }

        $mime = mime_content_type($file['tmp_name']);
        if (!in_array($mime, UPLOADS_ALLOWED_MIME, true)) {
            send_error('Tipo de archivo no permitido.', 'INVALID_MIME', 415);
        }

        // Verificar curso y tipo de doc pertenecen a la institución
        $course = Course::findById($db, $courseId, $institutionId);
        if (!$course) send_error('Curso no encontrado.', 'NOT_FOUND', 404);

        $docType = DocumentType::findById($db, $docTypeId);
        if (!$docType || (int)$docType['institution_id'] !== $institutionId) {
            send_error('Tipo de documento inválido.', 'INVALID_DOC_TYPE', 422);
        }

        // Guardar archivo en disco
       switch ($mime) {
    case 'image/jpeg':
        $ext = 'jpg';
        break;

    case 'image/png':
        $ext = 'png';
        break;

    case 'image/webp':
        $ext = 'webp';
        break;

    default:
        $ext = 'img';
        break;
}

        $relDir = sprintf('%d/%d/%s', $courseId, $docTypeId, date('Ym'));
        $absDir = UPLOADS_DIR . '/' . $relDir;
        if (!is_dir($absDir)) {
            @mkdir($absDir, 0775, true);
        }
        $fileName = sprintf('%s_%s.%s',
            date('Ymd_His'),
            substr(slugify($_POST['ocr_student_name'] ?? 'evidencia'), 0, 30),
            $ext
        );
        $relPath = $relDir . '/' . $fileName;
        $absPath = $absDir . '/' . $fileName;

        if (!move_uploaded_file($file['tmp_name'], $absPath)) {
            send_error('No se pudo guardar el archivo en disco.', 'MOVE_FAILED', 500);
        }

        $studentId = !empty($_POST['student_id']) ? (int)$_POST['student_id'] : null;
        if ($studentId) {
            $student = Student::findById($db, $studentId);
            if (!$student || (int)$student['course_id'] !== $courseId) {
                $studentId = null; // desvincular si es inválido
            }
        }

        $evidenceId = Evidence::create($db, [
            'institution_id'    => $institutionId,
            'course_id'         => $courseId,
            'student_id'        => $studentId,
            'document_type_id'  => $docTypeId,
            'subject_id'        => !empty($_POST['subject_id']) ? (int)$_POST['subject_id'] : null,
            'period_id'         => !empty($_POST['period_id']) ? (int)$_POST['period_id'] : null,
            'uploaded_by'       => $userId,
            'evidence_date'     => $evidenceDate,
            'file_path'         => $relPath,
            'file_thumb_path'   => null, // se puede generar thumbnail en cliente
            'file_size'         => (int)$file['size'],
            'mime_type'         => $mime,
            'ocr_raw_text'      => $_POST['ocr_raw_text'] ?? null,
            'ocr_student_name'  => $_POST['ocr_student_name'] ?? null,
            'ocr_doc_type_hint' => $_POST['ocr_doc_type_hint'] ?? null,
            'ocr_confidence'    => isset($_POST['ocr_confidence']) ? (int)$_POST['ocr_confidence'] : null,
            'description'       => $_POST['description'] ?? null,
            'status'            => 'draft',
        ]);

        // Auto-compartir con el director de grupo del curso
        $autoShare = !empty($_POST['auto_share']);
        $shareRequestId = null;
        if ($autoShare) {
            $director = User::directorOfCourse($db, $courseId);
            if ($director && (int)$director['id'] !== $userId) {
                $shareRequestId = ShareRequest::create($db, [
                    'evidence_id'  => $evidenceId,
                    'from_user_id' => $userId,
                    'to_user_id'   => (int)$director['id'],
                    'course_id'    => $courseId,
                    'message'      => 'Evidencia compartida desde la app móvil.',
                ]);
            }
        }

        $evidence = Evidence::findById($db, $evidenceId);
        send_json(true, [
            'evidence'        => self::publicEvidence($evidence, $institutionId),
            'share_request_id' => $shareRequestId,
        ], 'Evidencia guardada correctamente.', 201);
    }

    /** GET /api/evidence/list.php?course_id=&student_id=&status= */
    public static function list(PDO $db): void
    {
        $payload = require_auth();
        $institutionId = (int)$payload['inst'];

        $courseId   = (int)($_GET['course_id'] ?? 0);
        $studentId  = (int)($_GET['student_id'] ?? 0);
        $status     = $_GET['status'] ?? null;

        $rows = [];
        if ($studentId) {
            $rows = Evidence::byStudent($db, $studentId);
        } elseif ($courseId) {
            $rows = Evidence::byCourse($db, $courseId, null, $status);
        } else {
            // Mis evidencias
            $rows = Evidence::byUploader($db, (int)$payload['sub'], $status);
        }

        $list = array_map(fn($e) => self::publicEvidence($e, $institutionId), $rows);
        send_json(true, $list);
    }

    /** GET /api/evidence/detail.php?id= */
    public static function detail(PDO $db): void
    {
        $payload = require_auth();
        $id = (int)($_GET['id'] ?? 0);
        if (!$id) send_error('id requerido.', 'MISSING_PARAM', 422);

        $e = Evidence::findById($db, $id);
        if (!$e) send_error('Evidencia no encontrada.', 'NOT_FOUND', 404);

        send_json(true, self::publicEvidence($e, (int)$payload['inst']));
    }

    /** DELETE /api/evidence/delete.php?id= */
    public static function delete(PDO $db): void
    {
        $payload = require_auth();
        $id = (int)($_GET['id'] ?? 0);
        if (!$id) send_error('id requerido.', 'MISSING_PARAM', 422);

        $e = Evidence::findById($db, $id);
        if (!$e) send_error('Evidencia no encontrada.', 'NOT_FOUND', 404);
        if ((int)$e['uploaded_by'] !== (int)$payload['sub'] && $payload['role'] !== ROLE_ADMIN) {
            send_error('No puede eliminar una evidencia que no le pertenece.', 'FORBIDDEN', 403);
        }

        Evidence::delete($db, $id);
        send_json(true, null, 'Evidencia eliminada.');
    }

    /**
     * PUT /api/evidence/update_student.php
     * Body: { evidence_id, student_id }
     * Permite corregir el estudiante asociado si OCR falló.
     */
    public static function updateStudent(PDO $db): void
    {
        $payload = require_auth();
        $data = read_json_body();
        $evidenceId = (int)input_required($data, 'evidence_id');
        $studentId = $data['student_id'] ? (int)$data['student_id'] : null;

        $e = Evidence::findById($db, $evidenceId);
        if (!$e) send_error('Evidencia no encontrada.', 'NOT_FOUND', 404);
        if ((int)$e['uploaded_by'] !== (int)$payload['sub'] && $payload['role'] !== ROLE_ADMIN) {
            send_error('No tiene permisos.', 'FORBIDDEN', 403);
        }

        Evidence::updateStudent($db, $evidenceId, $studentId);
        send_json(true, null, 'Estudiante actualizado.');
    }

    /**
     * GET /api/evidence/dossier.php?student_id=&period_id=
     * Devuelve todas las evidencias aprobadas del estudiante agrupadas
     * por período y tipo, listas para exportar.
     */
    public static function dossier(PDO $db): void
    {
        $payload = require_auth();
        $studentId = (int)($_GET['student_id'] ?? 0);
        $periodId  = (int)($_GET['period_id'] ?? 0);
        if (!$studentId) send_error('student_id requerido.', 'MISSING_PARAM', 422);

        $rows = Evidence::dossierByStudent($db, $studentId, $periodId ?: null);
        $list = array_map(fn($e) => self::publicEvidence($e, (int)$payload['inst']), $rows);

        // Agrupar por período → tipo
        $grouped = [];
        foreach ($list as $e) {
            $period = $e['period_name'] ?? 'Sin período';
            $type   = $e['doc_type_name'];
            $grouped[$period][$type][] = $e;
        }

        send_json(true, [
            'student_id' => $studentId,
            'grouped'    => $grouped,
            'flat'       => $list,
            'total'      => count($list),
        ]);
    }

    /** Convierte un registro de BD en salida pública con URLs firmadas/relativas. */
    private static function publicEvidence(array $e, int $institutionId): array
    {
        return [
            'id'                => (int)$e['id'],
            'course_id'         => (int)$e['course_id'],
            'course_name'        => $e['course_name'] ?? null,
            'student_id'         => $e['student_id'] ? (int)$e['student_id'] : null,
            'student_name'      => isset($e['student_first_name'])
                                    ? trim($e['student_first_name'] . ' ' . $e['student_last_name'])
                                    : null,
            'document_type_id'  => (int)$e['document_type_id'],
            'doc_type_name'     => $e['doc_type_name'] ?? null,
            'doc_type_code'     => $e['doc_type_code'] ?? null,
            'doc_type_color'    => $e['doc_type_color'] ?? null,
            'subject_id'        => $e['subject_id'] ? (int)$e['subject_id'] : null,
            'subject_name'      => $e['subject_name'] ?? null,
            'period_id'         => $e['period_id'] ? (int)$e['period_id'] : null,
            'period_name'       => $e['period_name'] ?? null,
            'evidence_date'     => $e['evidence_date'],
            'file_url'          => $e['file_path']
                                    ? (UPLOADS_BASE_URL . '/' . $e['file_path'])
                                    : null,
            'file_thumb_url'    => !empty($e['file_thumb_path'])
                                    ? (UPLOADS_BASE_URL . '/' . $e['file_thumb_path'])
                                    : null,
            'file_size'         => $e['file_size'] ? (int)$e['file_size'] : null,
            'mime_type'         => $e['mime_type'],
            'ocr_student_name'  => $e['ocr_student_name'] ?? null,
            'ocr_doc_type_hint' => $e['ocr_doc_type_hint'] ?? null,
            'ocr_confidence'    => $e['ocr_confidence'] !== null ? (int)$e['ocr_confidence'] : null,
            'description'       => $e['description'] ?? null,
            'status'            => $e['status'],
            'uploader_name'     => isset($e['uploader_first_name'])
                                    ? trim($e['uploader_first_name'] . ' ' . $e['uploader_last_name'])
                                    : null,
            'reviewed_at'       => $e['reviewed_at'] ?? null,
            'rejection_reason'  => $e['rejection_reason'] ?? null,
            'shared_at'         => $e['shared_at'] ?? null,
            'created_at'        => $e['created_at'],
        ];
    }
}
