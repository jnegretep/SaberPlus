<?php
/**
 * controllers/StudentController.php
 */

declare(strict_types=1);

class StudentController
{
    /** GET /api/students/list.php?course_id= */
    public static function list(PDO $db): void
    {
        $payload = require_auth();
        $courseId = (int)($_GET['course_id'] ?? 0);
        if (!$courseId) send_error('course_id requerido.', 'MISSING_PARAM', 422);

        $students = Student::findByCourse($db, $courseId);
        $public = array_map(function ($s) {
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
                'guardian_email' => $s['guardian_email'],
                'is_active'      => (bool)$s['is_active'],
            ];
        }, $students);

        send_json(true, $public);
    }

    /** GET /api/students/match.php?course_id=&ocr_text= */
    public static function match(PDO $db): void
    {
        $payload = require_auth();
        $courseId = (int)($_GET['course_id'] ?? 0);
        $ocrText  = $_GET['ocr_text'] ?? '';
        if (!$courseId || !$ocrText) {
            send_error('course_id y ocr_text son requeridos.', 'MISSING_PARAM', 422);
        }

        $match = Student::matchByName($db, $courseId, $ocrText);
        $student = $match['student'];
        $publicStudent = $student ? [
            'id'             => (int)$student['id'],
            'first_name'     => $student['first_name'],
            'last_name'      => $student['last_name'],
            'full_name'      => trim($student['first_name'] . ' ' . $student['last_name']),
            'student_code'   => $student['student_code'],
            'document_id'    => $student['document_id'],
        ] : null;

        send_json(true, [
            'student'      => $publicStudent,
            'confidence'   => $match['confidence'],
            'alternatives' => $match['alternatives'],
        ]);
    }
}
