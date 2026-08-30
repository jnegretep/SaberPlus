<?php
/**
 * models/Evidence.php
 */

declare(strict_types=1);

class Evidence
{
    public static function create(PDO $db, array $data): int
    {
        $stmt = $db->prepare(
            'INSERT INTO evidence
             (institution_id, course_id, student_id, document_type_id, subject_id, period_id,
              uploaded_by, evidence_date, file_path, file_thumb_path, file_size, mime_type,
              ocr_raw_text, ocr_student_name, ocr_doc_type_hint, ocr_confidence, description, status)
             VALUES
             (:institution_id, :course_id, :student_id, :document_type_id, :subject_id, :period_id,
              :uploaded_by, :evidence_date, :file_path, :file_thumb_path, :file_size, :mime_type,
              :ocr_raw_text, :ocr_student_name, :ocr_doc_type_hint, :ocr_confidence, :description, :status)'
        );
        $stmt->execute([
            ':institution_id'    => $data['institution_id'],
            ':course_id'         => $data['course_id'],
            ':student_id'        => $data['student_id'] ?? null,
            ':document_type_id'  => $data['document_type_id'],
            ':subject_id'        => $data['subject_id'] ?? null,
            ':period_id'         => $data['period_id'] ?? null,
            ':uploaded_by'       => $data['uploaded_by'],
            ':evidence_date'     => $data['evidence_date'],
            ':file_path'         => $data['file_path'],
            ':file_thumb_path'   => $data['file_thumb_path'] ?? null,
            ':file_size'         => $data['file_size'] ?? null,
            ':mime_type'         => $data['mime_type'] ?? null,
            ':ocr_raw_text'      => $data['ocr_raw_text'] ?? null,
            ':ocr_student_name'  => $data['ocr_student_name'] ?? null,
            ':ocr_doc_type_hint' => $data['ocr_doc_type_hint'] ?? null,
            ':ocr_confidence'    => $data['ocr_confidence'] ?? null,
            ':description'       => $data['description'] ?? null,
            ':status'            => $data['status'] ?? 'draft',
        ]);
        return (int)$db->lastInsertId();
    }

    public static function findById(PDO $db, int $id): ?array
    {
        $stmt = $db->prepare(
            'SELECT e.*, dt.name AS doc_type_name, dt.code AS doc_type_code, dt.color_hex AS doc_type_color,
                    s.name AS subject_name, p.name AS period_name,
                    c.name AS course_name, st.first_name AS student_first_name, st.last_name AS student_last_name,
                    u.first_name AS uploader_first_name, u.last_name AS uploader_last_name
             FROM evidence e
             LEFT JOIN document_types dt ON dt.id = e.document_type_id
             LEFT JOIN subjects s ON s.id = e.subject_id
             LEFT JOIN academic_periods p ON p.id = e.period_id
             LEFT JOIN courses c ON c.id = e.course_id
             LEFT JOIN students st ON st.id = e.student_id
             LEFT JOIN users u ON u.id = e.uploaded_by
             WHERE e.id = ?'
        );
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    public static function byStudent(PDO $db, int $studentId, ?int $periodId = null): array
    {
        $sql = 'SELECT e.*, dt.name AS doc_type_name, dt.code AS doc_type_code, dt.color_hex AS doc_type_color,
                       s.name AS subject_name
                FROM evidence e
                LEFT JOIN document_types dt ON dt.id = e.document_type_id
                LEFT JOIN subjects s ON s.id = e.subject_id
                WHERE e.student_id = ?';
        $params = [$studentId];
        if ($periodId) {
            $sql .= ' AND e.period_id = ?';
            $params[] = $periodId;
        }
        $sql .= ' ORDER BY e.evidence_date DESC, e.created_at DESC';
        $stmt = $db->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll();
    }

    public static function byCourse(PDO $db, int $courseId, ?int $studentId = null, ?string $status = null): array
    {
        $sql = 'SELECT e.*, dt.name AS doc_type_name, dt.code AS doc_type_code, dt.color_hex AS doc_type_color,
                       s.name AS subject_name,
                       st.first_name AS student_first_name, st.last_name AS student_last_name
                FROM evidence e
                LEFT JOIN document_types dt ON dt.id = e.document_type_id
                LEFT JOIN subjects s ON s.id = e.subject_id
                LEFT JOIN students st ON st.id = e.student_id
                WHERE e.course_id = ?';
        $params = [$courseId];
        if ($studentId) {
            $sql .= ' AND e.student_id = ?';
            $params[] = $studentId;
        }
        if ($status) {
            $sql .= ' AND e.status = ?';
            $params[] = $status;
        }
        $sql .= ' ORDER BY e.evidence_date DESC, e.created_at DESC';
        $stmt = $db->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll();
    }

    public static function byUploader(PDO $db, int $userId, ?string $status = null): array
    {
        $sql = 'SELECT e.*, dt.name AS doc_type_name, dt.code AS doc_type_code, dt.color_hex AS doc_type_color,
                       c.name AS course_name,
                       st.first_name AS student_first_name, st.last_name AS student_last_name
                FROM evidence e
                LEFT JOIN document_types dt ON dt.id = e.document_type_id
                LEFT JOIN courses c ON c.id = e.course_id
                LEFT JOIN students st ON st.id = e.student_id
                WHERE e.uploaded_by = ?';
        $params = [$userId];
        if ($status) {
            $sql .= ' AND e.status = ?';
            $params[] = $status;
        }
        $sql .= ' ORDER BY e.created_at DESC';
        $stmt = $db->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll();
    }

    public static function setStatus(PDO $db, int $id, string $status, ?int $reviewerId = null, ?string $reason = null): void
    {
        $fields = ['status = ?'];
        $params = [$status];
        if (in_array($status, ['approved', 'rejected'], true)) {
            $fields[] = 'reviewed_at = NOW()';
            if ($reviewerId) {
                $fields[] = 'reviewed_by = ?';
                $params[] = $reviewerId;
            }
            if ($status === 'rejected' && $reason !== null) {
                $fields[] = 'rejection_reason = ?';
                $params[] = $reason;
            }
        }
        if ($status === 'shared') {
            $fields[] = 'shared_at = NOW()';
        }
        $params[] = $id;
        $sql = 'UPDATE evidence SET ' . implode(', ', $fields) . ' WHERE id = ?';
        $db->prepare($sql)->execute($params);
    }

    public static function updateStudent(PDO $db, int $id, ?int $studentId): void
    {
        $db->prepare('UPDATE evidence SET student_id = ? WHERE id = ?')
            ->execute([$studentId, $id]);
    }

    public static function updateDocType(PDO $db, int $id, int $docTypeId): void
    {
        $db->prepare('UPDATE evidence SET document_type_id = ? WHERE id = ?')
            ->execute([$docTypeId, $id]);
    }

    public static function delete(PDO $db, int $id): void
    {
        // Traer file_path antes de borrar para limpiar disco
        $stmt = $db->prepare('SELECT file_path, file_thumb_path FROM evidence WHERE id = ?');
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        if ($row) {
            foreach (['file_path', 'file_thumb_path'] as $field) {
                if (!empty($row[$field])) {
                    $abs = UPLOADS_DIR . '/' . ltrim($row[$field], '/');
                    if (is_file($abs)) @unlink($abs);
                }
            }
        }
        $db->prepare('DELETE FROM evidence WHERE id = ?')->execute([$id]);
    }

    /**
     * Dossier consolidado: todas las evidencias aprobadas de un estudiante
     * agrupadas por período y tipo.
     */
    public static function dossierByStudent(PDO $db, int $studentId, ?int $periodId = null): array
    {
        $sql = 'SELECT e.*, dt.name AS doc_type_name, dt.code AS doc_type_code, dt.color_hex AS doc_type_color,
                       s.name AS subject_name, p.name AS period_name, p.code AS period_code,
                       u.first_name AS uploader_first_name, u.last_name AS uploader_last_name
                FROM evidence e
                LEFT JOIN document_types dt ON dt.id = e.document_type_id
                LEFT JOIN subjects s ON s.id = e.subject_id
                LEFT JOIN academic_periods p ON p.id = e.period_id
                LEFT JOIN users u ON u.id = e.uploaded_by
                WHERE e.student_id = ? AND e.status IN (\'approved\', \'archived\')';
        $params = [$studentId];
        if ($periodId) {
            $sql .= ' AND e.period_id = ?';
            $params[] = $periodId;
        }
        $sql .= ' ORDER BY p.start_date DESC, dt.sort_order, e.evidence_date';
        $stmt = $db->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll();
    }
}
