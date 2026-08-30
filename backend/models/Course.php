<?php
/**
 * models/Course.php
 */

declare(strict_types=1);

class Course
{
    public static function all(PDO $db, int $institutionId): array
    {
        $stmt = $db->prepare(
            'SELECT c.*, u.first_name AS director_first_name, u.last_name AS director_last_name,
                    (SELECT COUNT(*) FROM students s WHERE s.course_id = c.id AND s.is_active = 1) AS students_count
             FROM courses c
             LEFT JOIN users u ON u.id = c.group_director_id
             WHERE c.institution_id = ? AND c.is_active = 1
             ORDER BY c.grade_level DESC, c.section'
        );
        $stmt->execute([$institutionId]);
        return $stmt->fetchAll();
    }

    public static function findById(PDO $db, int $id, int $institutionId): ?array
    {
        $stmt = $db->prepare(
            'SELECT c.*, u.first_name AS director_first_name, u.last_name AS director_last_name
             FROM courses c
             LEFT JOIN users u ON u.id = c.group_director_id
             WHERE c.id = ? AND c.institution_id = ?'
        );
        $stmt->execute([$id, $institutionId]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    public static function create(PDO $db, array $data): int
    {
        $stmt = $db->prepare(
            'INSERT INTO courses (institution_id, name, grade_level, section, school_year, group_director_id)
             VALUES (?, ?, ?, ?, ?, ?)'
        );
        $stmt->execute([
            $data['institution_id'],
            $data['name'],
            $data['grade_level'] ?? null,
            $data['section'] ?? null,
            $data['school_year'] ?? date('Y'),
            $data['group_director_id'] ?? null,
        ]);
        return (int)$db->lastInsertId();
    }

    /**
     * Asigna / cambia el director de grupo de un curso.
     */
    public static function setDirector(PDO $db, int $courseId, int $userId): void
    {
        $db->prepare('UPDATE courses SET group_director_id = ? WHERE id = ?')
            ->execute([$userId, $courseId]);
    }

    /**
     * Devuelve los cursos en los que un docente está vinculado
     * (como profesor de asignatura o como director de grupo).
     */
    public static function byTeacher(PDO $db, int $userId): array
    {
        // Director de grupo
        $stmt = $db->prepare(
            "SELECT c.id, c.name, c.grade_level, c.section, c.school_year,
                    'director' AS relation,
                    NULL AS subject_name,
                    (SELECT COUNT(*) FROM students s WHERE s.course_id = c.id AND s.is_active = 1) AS students_count
             FROM courses c
             WHERE c.group_director_id = ? AND c.is_active = 1
             UNION
             SELECT c.id, c.name, c.grade_level, c.section, c.school_year,
                    'teacher' AS relation,
                    s.name AS subject_name,
                    (SELECT COUNT(*) FROM students st WHERE st.course_id = c.id AND st.is_active = 1) AS students_count
             FROM course_user cu
             JOIN courses c ON c.id = cu.course_id
             LEFT JOIN subjects s ON s.id = cu.subject_id
             WHERE cu.user_id = ? AND c.is_active = 1
             ORDER BY name"
        );
        $stmt->execute([$userId, $userId]);
        return $stmt->fetchAll();
    }
}
