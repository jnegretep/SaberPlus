<?php
/**
 * models/Notification.php
 */

declare(strict_types=1);

class Notification
{
    public static function create(PDO $db, int $userId, string $title, ?string $body, ?string $type, ?int $refId): int
    {
        $stmt = $db->prepare(
            'INSERT INTO notifications (user_id, title, body, type, ref_id) VALUES (?, ?, ?, ?, ?)'
        );
        $stmt->execute([$userId, $title, $body, $type, $refId]);
        return (int)$db->lastInsertId();
    }

    public static function unread(PDO $db, int $userId, int $limit = 20): array
    {
        $stmt = $db->prepare(
            'SELECT * FROM notifications WHERE user_id = ? AND is_read = 0
             ORDER BY created_at DESC LIMIT ' . (int)$limit
        );
        $stmt->execute([$userId]);
        return $stmt->fetchAll();
    }

    public static function markRead(PDO $db, int $id, int $userId): void
    {
        $db->prepare('UPDATE notifications SET is_read = 1 WHERE id = ? AND user_id = ?')
            ->execute([$id, $userId]);
    }

    public static function markAllRead(PDO $db, int $userId): void
    {
        $db->prepare('UPDATE notifications SET is_read = 1 WHERE user_id = ?')
            ->execute([$userId]);
    }
}
