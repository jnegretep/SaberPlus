<?php
/**
 * controllers/ShareController.php
 */

declare(strict_types=1);

class ShareController
{
    /**
     * POST /api/share/send.php
     * Body: { evidence_id, to_user_id?, message? }
     * Si no se indica to_user_id, se asume el director de grupo del curso.
     */
    public static function send(PDO $db): void
    {
        $payload = require_auth();
        $data = read_json_body();

        $evidenceId = (int)input_required($data, 'evidence_id');
        $message    = $data['message'] ?? null;

        $evidence = Evidence::findById($db, $evidenceId);
        if (!$evidence) send_error('Evidencia no encontrada.', 'NOT_FOUND', 404);

        if ((int)$evidence['uploaded_by'] !== (int)$payload['sub'] && $payload['role'] !== ROLE_ADMIN) {
            send_error('No puede compartir una evidencia que no es suya.', 'FORBIDDEN', 403);
        }

        $toUserId = !empty($data['to_user_id']) ? (int)$data['to_user_id'] : null;
        if (!$toUserId) {
            $director = User::directorOfCourse($db, (int)$evidence['course_id']);
            if (!$director) send_error('El curso no tiene director de grupo asignado.', 'NO_DIRECTOR', 422);
            $toUserId = (int)$director['id'];
        }
        if ($toUserId === (int)$payload['sub']) {
            send_error('No puede compartir evidencia consigo mismo.', 'INVALID_TARGET', 422);
        }

        $shareId = ShareRequest::create($db, [
            'evidence_id'  => $evidenceId,
            'from_user_id' => (int)$payload['sub'],
            'to_user_id'   => $toUserId,
            'course_id'    => (int)$evidence['course_id'],
            'message'      => $message,
        ]);

        send_json(true, ['share_request_id' => $shareId], 'Evidencia compartida con el director.', 201);
    }

    /** GET /api/share/pending.php */
    public static function pending(PDO $db): void
    {
        $payload = require_auth();
        $rows = ShareRequest::pendingForUser($db, (int)$payload['sub']);

        $list = array_map(function ($s) {
            return [
                'id'                => (int)$s['id'],
                'evidence_id'       => (int)$s['evidence_id'],
                'course_name'       => $s['course_name'],
                'student_name'      => isset($s['student_first_name'])
                                        ? trim($s['student_first_name'] . ' ' . $s['student_last_name'])
                                        : null,
                'doc_type_name'     => $s['doc_type_name'] ?? null,
                'doc_type_code'     => $s['doc_type_code'] ?? null,
                'doc_type_color'    => $s['doc_type_color'] ?? null,
                'subject_name'      => $s['subject_name'] ?? null,
                'evidence_date'     => $s['evidence_date'],
                'file_url'          => $s['file_path'] ? (UPLOADS_BASE_URL . '/' . $s['file_path']) : null,
                'file_thumb_url'    => !empty($s['file_thumb_path']) ? (UPLOADS_BASE_URL . '/' . $s['file_thumb_path']) : null,
                'description'       => $s['description'] ?? null,
                'from_user_name'    => trim(($s['from_first_name'] ?? '') . ' ' . ($s['from_last_name'] ?? '')) ?: null,
                'message'           => $s['message'] ?? null,
                'status'            => $s['status'],
                'created_at'        => $s['created_at'],
            ];
        }, $rows);

        send_json(true, $list);
    }

    /** POST /api/share/approve.php  Body: { share_request_id } */
    public static function approve(PDO $db): void
    {
        $payload = require_auth();
        $data = read_json_body();
        $id = (int)input_required($data, 'share_request_id');

        $share = ShareRequest::findById($db, $id);
        if (!$share) send_error('Solicitud no encontrada.', 'NOT_FOUND', 404);
        if ((int)$share['to_user_id'] !== (int)$payload['sub']) {
            send_error('Esta solicitud está dirigida a otro usuario.', 'FORBIDDEN', 403);
        }

        ShareRequest::approve($db, $id, (int)$payload['sub']);
        send_json(true, null, 'Evidencia aprobada y consolidada en el dossier del estudiante.');
    }

    /** POST /api/share/reject.php  Body: { share_request_id, reason } */
    public static function reject(PDO $db): void
    {
        $payload = require_auth();
        $data = read_json_body();
        $id = (int)input_required($data, 'share_request_id');
        $reason = trim($data['reason'] ?? '');
        if (strlen($reason) < 3) {
            send_error('Indique el motivo del rechazo (mínimo 3 caracteres).', 'REASON_REQUIRED', 422);
        }

        $share = ShareRequest::findById($db, $id);
        if (!$share) send_error('Solicitud no encontrada.', 'NOT_FOUND', 404);
        if ((int)$share['to_user_id'] !== (int)$payload['sub']) {
            send_error('Esta solicitud está dirigida a otro usuario.', 'FORBIDDEN', 403);
        }

        ShareRequest::reject($db, $id, (int)$payload['sub'], $reason);
        send_json(true, null, 'Evidencia rechazada. Se notificará al docente.');
    }
}
