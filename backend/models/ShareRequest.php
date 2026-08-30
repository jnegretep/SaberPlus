<?php
/**
 * models/ShareRequest.php
 */

declare(strict_types=1);

class ShareRequest
{
    public static function create(PDO $db, array $data): int
    {
        $stmt = $db->prepare(
            'INSERT INTO share_requests (evidence_id, from_user_id, to_user_id, course_id, message, status)
             VALUES (?, ?, ?, ?, ?, \'pending\')'
        );
        $stmt->execute([
            $data['evidence_id'],
            $data['from_user_id'],
            $data['to_user_id'],
            $data['course_id'],
            $data['message'] ?? null,
        ]);
        $shareId = (int)$db->lastInsertId();

        // Marcar evidencia como compartida
        Evidence::setStatus($db, $data['evidence_id'], 'shared');

        // Crear notificación para el director destino
        Notification::create($db, $data['to_user_id'], 'Nueva evidencia compartida',
            'Tienes una nueva evidencia para revisar.', 'share_received', $shareId);

        return $shareId;
    }

    public static function pendingForUser(PDO $db, int $userId): array
    {
        $stmt = $db->prepare(
            'SELECT sr.*, e.evidence_date, e.file_path, e.file_thumb_path, e.description,
                    dt.name AS doc_type_name, dt.code AS doc_type_code, dt.color_hex AS doc_type_color,
                    s.name AS subject_name,
                    st.first_name AS student_first_name, st.last_name AS student_last_name,
                    c.name AS course_name,
                    fu.first_name AS from_first_name, fu.last_name AS from_last_name
             FROM share_requests sr
             JOIN evidence e ON e.id = sr.evidence_id
             LEFT JOIN document_types dt ON dt.id = e.document_type_id
             LEFT JOIN subjects s ON s.id = e.subject_id
             LEFT JOIN students st ON st.id = e.student_id
             LEFT JOIN courses c ON c.id = sr.course_id
             LEFT JOIN users fu ON fu.id = sr.from_user_id
             WHERE sr.to_user_id = ? AND sr.status = \'pending\'
             ORDER BY sr.created_at DESC'
        );
        $stmt->execute([$userId]);
        return $stmt->fetchAll();
    }

    public static function findById(PDO $db, int $id): ?array
    {
        $stmt = $db->prepare('SELECT * FROM share_requests WHERE id = ?');
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    public static function approve(PDO $db, int $id, int $reviewerId): void
    {
        $db->prepare(
            'UPDATE share_requests SET status = \'approved\', reviewed_at = NOW() WHERE id = ?'
        )->execute([$id]);

        $share = self::findById($db, $id);
        if ($share) {
            Evidence::setStatus($db, (int)$share['evidence_id'], 'approved', $reviewerId);
            Notification::create($db, (int)$share['from_user_id'], 'Evidencia aprobada',
                'El director aprobó tu evidencia compartida.', 'evidence_approved', (int)$share['evidence_id']);
        }
    }

    public static function reject(PDO $db, int $id, int $reviewerId, string $reason): void
    {
        $db->prepare(
            'UPDATE share_requests SET status = \'rejected\', reviewed_at = NOW(), rejection_reason = ? WHERE id = ?'
        )->execute([$reason, $id]);

        $share = self::findById($db, $id);
        if ($share) {
            Evidence::setStatus($db, (int)$share['evidence_id'], 'rejected', $reviewerId, $reason);
            Notification::create($db, (int)$share['from_user_id'], 'Evidencia rechazada',
                'El director rechazó tu evidencia. Motivo: ' . $reason, 'evidence_rejected', (int)$share['evidence_id']);
        }
    }
}
