<?php
/**
 * models/Subject.php
 */

declare(strict_types=1);

class Subject
{
    public static function all(PDO $db, int $institutionId): array
    {
        $stmt = $db->prepare(
            'SELECT * FROM subjects WHERE institution_id = ? ORDER BY name'
        );
        $stmt->execute([$institutionId]);
        return $stmt->fetchAll();
    }
}
