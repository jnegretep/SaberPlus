<?php
/**
 * models/Student.php
 */

declare(strict_types=1);

class Student
{
    public static function findByCourse(PDO $db, int $courseId, bool $onlyActive = true): array
    {
        $sql = 'SELECT * FROM students WHERE course_id = ?';
        if ($onlyActive) $sql .= ' AND is_active = 1';
        $sql .= ' ORDER BY last_name, first_name';
        $stmt = $db->prepare($sql);
        $stmt->execute([$courseId]);
        return $stmt->fetchAll();
    }

    public static function findById(PDO $db, int $id): ?array
    {
        $stmt = $db->prepare('SELECT * FROM students WHERE id = ?');
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    public static function create(PDO $db, array $data): int
    {
        $stmt = $db->prepare(
            'INSERT INTO students (institution_id, course_id, first_name, last_name, student_code, document_id, birthdate, gender, guardian_name, guardian_phone, guardian_email)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $stmt->execute([
            $data['institution_id'],
            $data['course_id'],
            $data['first_name'],
            $data['last_name'],
            $data['student_code'] ?? null,
            $data['document_id'] ?? null,
            $data['birthdate'] ?? null,
            $data['gender'] ?? null,
            $data['guardian_name'] ?? null,
            $data['guardian_phone'] ?? null,
            $data['guardian_email'] ?? null,
        ]);
        return (int)$db->lastInsertId();
    }

    public static function update(PDO $db, int $id, array $data): void
    {
        $fields = [];
        $values = [];
        foreach (['first_name','last_name','student_code','document_id','birthdate','gender','guardian_name','guardian_phone','guardian_email','is_active'] as $f) {
            if (array_key_exists($f, $data)) {
                $fields[] = "$f = ?";
                $values[] = $data[$f];
            }
        }
        if (!$fields) return;
        $values[] = $id;
        $sql = 'UPDATE students SET ' . implode(', ', $fields) . ' WHERE id = ?';
        $db->prepare($sql)->execute($values);
    }

    public static function delete(PDO $db, int $id): void
    {
        $db->prepare('DELETE FROM students WHERE id = ?')->execute([$id]);
    }

    /**
     * Busca el estudiante cuyo nombre más se parece al texto reconocido por OCR.
     * Usa la columna full_name_search que ya contiene "FIRST LAST" en mayúsculas.
     *
     * @return array ['student' => ?array, 'confidence' => int 0..100, 'alternatives' => array]
     */
    public static function matchByName(PDO $db, int $courseId, string $ocrText, int $limit = 5): array
    {
        // Limpieza básica del OCR: pasar a mayúsculas, conservar letras y espacios
        $clean = mb_strtoupper($ocrText, 'UTF-8');
        $clean = preg_replace('/[^A-ZÁÉÍÓÚÑ ]/', ' ', $clean);
        $clean = preg_replace('/\s+/', ' ', trim($clean));

        if ($clean === '') {
            return ['student' => null, 'confidence' => 0, 'alternatives' => []];
        }

        // Traer todos los estudiantes activos del curso
        $students = self::findByCourse($db, $courseId);

        $scored = [];
        foreach ($students as $s) {
            $fullName = mb_strtoupper(($s['first_name'] . ' ' . $s['last_name']), 'UTF-8');
            similar_text($clean, $fullName, $percent);
            // Coincidencia adicional: buscar apellido dentro del OCR
            $lastName = mb_strtoupper($s['last_name'], 'UTF-8');
            $hasLastName = ($lastName !== '' && mb_strpos($clean, $lastName) !== false);
            $score = (int)$percent + ($hasLastName ? 15 : 0);

            $scored[] = [
                'student'      => $s,
                'confidence'   => min(100, $score),
                'matched'      => $hasLastName,
            ];
        }

        usort($scored, fn($a, $b) => $b['confidence'] <=> $a['confidence']);

        $top = $scored[0] ?? null;
        $alternatives = array_slice(array_map(fn($x) => [
            'id'         => (int)$x['student']['id'],
            'full_name'  => trim($x['student']['first_name'] . ' ' . $x['student']['last_name']),
            'confidence' => $x['confidence'],
        ], $scored), 0, $limit);

        return [
            'student'      => $top ? $top['student'] : null,
            'confidence'   => $top ? $top['confidence'] : 0,
            'alternatives' => $alternatives,
        ];
    }
}
