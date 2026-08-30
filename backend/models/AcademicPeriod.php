<?php
/**
 * models/AcademicPeriod.php
 */

declare(strict_types=1);

class AcademicPeriod
{
    public static function all(PDO $db, int $institutionId): array
    {
        $stmt = $db->prepare(
            'SELECT * FROM academic_periods WHERE institution_id = ? ORDER BY start_date'
        );
        $stmt->execute([$institutionId]);
        return $stmt->fetchAll();
    }

    public static function current(PDO $db, int $institutionId): ?array
    {
        $stmt = $db->prepare(
            'SELECT * FROM academic_periods WHERE institution_id = ? AND is_current = 1 LIMIT 1'
        );
        $stmt->execute([$institutionId]);
        $row = $stmt->fetch();
        return $row ?: null;
    }
}
