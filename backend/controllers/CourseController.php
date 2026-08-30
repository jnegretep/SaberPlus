<?php
/**
 * controllers/CourseController.php
 */

declare(strict_types=1);

class CourseController
{
    /** GET /api/courses/list.php */
    public static function list(PDO $db): void
    {
        $payload = require_auth();
        $institutionId = (int)$payload['inst'];

        $courses = Course::all($db, $institutionId);

        $result = array_map(function ($c) {
            return [
                'id'              => (int)$c['id'],
                'name'            => $c['name'],
                'grade_level'     => $c['grade_level'],
                'section'         => $c['section'],
                'school_year'     => $c['school_year'],
                'director_name'   => trim(($c['director_first_name'] ?? '') . ' ' . ($c['director_last_name'] ?? '')) ?: null,
                'students_count'  => (int)($c['students_count'] ?? 0),
                'is_active'       => (bool)$c['is_active'],
            ];
        }, $courses);

        send_json(true, $result);
    }

    /** GET /api/courses/by_teacher.php */
    public static function byTeacher(PDO $db): void
    {
        $payload = require_auth();
        $courses = Course::byTeacher($db, (int)$payload['sub']);

        $result = array_map(function ($c) {
            return [
                'id'             => (int)$c['id'],
                'name'           => $c['name'],
                'grade_level'    => $c['grade_level'],
                'section'        => $c['section'],
                'school_year'    => $c['school_year'],
                'relation'       => $c['relation'],
                'subject_name'   => $c['subject_name'] ?? null,
                'students_count' => (int)($c['students_count'] ?? 0),
            ];
        }, $courses);

        send_json(true, $result);
    }

    /** GET /api/courses/detail.php?id= */
    public static function detail(PDO $db): void
    {
        $payload = require_auth();
        $id = (int)($_GET['id'] ?? 0);
        if (!$id) send_error('ID requerido.', 'MISSING_ID', 422);

        $course = Course::findById($db, $id, (int)$payload['inst']);
        if (!$course) send_error('Curso no encontrado.', 'NOT_FOUND', 404);

        $students = Student::findByCourse($db, $id);
        $director = User::directorOfCourse($db, $id);

        send_json(true, [
            'id'            => (int)$course['id'],
            'name'          => $course['name'],
            'grade_level'   => $course['grade_level'],
            'section'       => $course['section'],
            'school_year'   => $course['school_year'],
            'director'      => $director ? [
                'id'         => (int)$director['id'],
                'full_name'  => trim($director['first_name'] . ' ' . $director['last_name']),
                'email'      => $director['email'],
            ] : null,
            'students'      => array_map(fn($s) => self::publicStudent($s), $students),
            'students_count'=> count($students),
        ]);
    }

    /** POST /api/courses/create.php */
    public static function create(PDO $db): void
    {
        $payload = require_role(ROLE_ADMIN, ROLE_DIRECTOR);
        $data = read_json_body();

        $name = input_required($data, 'name'); // "11B"
        $courseId = Course::create($db, [
            'institution_id'    => (int)$payload['inst'],
            'name'              => $name,
            'grade_level'       => $data['grade_level'] ?? null,
            'section'           => $data['section'] ?? null,
            'school_year'       => $data['school_year'] ?? date('Y'),
            'group_director_id' => $data['group_director_id'] ?? null,
        ]);

        $course = Course::findById($db, $courseId, (int)$payload['inst']);
        send_json(true, ['id' => $courseId], 'Curso creado.', 201);
    }

    /**
     * POST /api/courses/import_students.php
     * Body: { course_id, students: [ {first_name,last_name,student_code,document_id,...}, ... ] }
     * Maneja carga masiva desde Excel/CSV previamente parseado en el cliente.
     */
    public static function importStudents(PDO $db): void
    {
        $payload = require_auth();
        $data = read_json_body();

        $courseId = (int)input_required($data, 'course_id');
        $students = input_required($data, 'students');

        $course = Course::findById($db, $courseId, (int)$payload['inst']);
        if (!$course) send_error('Curso no encontrado.', 'NOT_FOUND', 404);

        if (!is_array($students) || count($students) === 0) {
            send_error('Lista de estudiantes vacía.', 'EMPTY_LIST', 422);
        }

        $created = 0;
        $errors  = [];
        foreach ($students as $i => $s) {
            try {
                if (empty($s['first_name']) || empty($s['last_name'])) {
                    $errors[] = ['row' => $i + 1, 'error' => 'Nombres y apellidos requeridos'];
                    continue;
                }
                Student::create($db, [
                    'institution_id' => (int)$payload['inst'],
                    'course_id'      => $courseId,
                    'first_name'     => trim($s['first_name']),
                    'last_name'      => trim($s['last_name']),
                    'student_code'   => $s['student_code'] ?? null,
                    'document_id'    => $s['document_id'] ?? null,
                    'birthdate'      => $s['birthdate'] ?? null,
                    'gender'         => $s['gender'] ?? null,
                    'guardian_name'  => $s['guardian_name'] ?? null,
                    'guardian_phone' => $s['guardian_phone'] ?? null,
                    'guardian_email' => $s['guardian_email'] ?? null,
                ]);
                $created++;
            } catch (Throwable $e) {
                $errors[] = ['row' => $i + 1, 'error' => $e->getMessage()];
            }
        }

        send_json(true, [
            'created'  => $created,
            'errors'   => $errors,
            'total'    => count($students),
        ], "Importación finalizada: $created estudiantes agregados.");
    }

    private static function publicStudent(array $s): array
    {
        return [
            'id'             => (int)$s['id'],
            'first_name'     => $s['first_name'],
            'last_name'      => $s['last_name'],
            'full_name'      => trim($s['first_name'] . ' ' . $s['last_name']),
            'student_code'   => $s['student_code'],
            'document_id'    => $s['document_id'],
            'gender'         => $s['gender'],
            'guardian_name'  => $s['guardian_name'],
            'guardian_phone' => $s['guardian_phone'],
            'is_active'      => (bool)$s['is_active'],
        ];
    }
}
