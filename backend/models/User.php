<?php
/**
 * models/User.php
 */

declare(strict_types=1);

class User
{
    public static function findByEmail(PDO $db, string $email): ?array
    {
        $stmt = $db->prepare('SELECT * FROM users WHERE email = ? LIMIT 1');
        $stmt->execute([$email]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    public static function findById(PDO $db, int $id): ?array
    {
        $stmt = $db->prepare('SELECT * FROM users WHERE id = ? LIMIT 1');
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    public static function create(PDO $db, array $data): int
    {
        $hash = password_hash($data['password'], PASSWORD_BCRYPT);
        $stmt = $db->prepare(
            'INSERT INTO users (institution_id, role, first_name, last_name, email, password_hash, phone, document_id)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $stmt->execute([
            $data['institution_id'],
            $data['role'] ?? 'teacher',
            $data['first_name'],
            $data['last_name'],
            $data['email'],
            $hash,
            $data['phone'] ?? null,
            $data['document_id'] ?? null,
        ]);
        return (int)$db->lastInsertId();
    }

    public static function touchLastLogin(PDO $db, int $id): void
    {
        $db->prepare('UPDATE users SET last_login_at = NOW() WHERE id = ?')
            ->execute([$id]);
    }

    /**
     * Lista de profesores a los que se puede compartir evidencia
     * (los directores del mismo curso o cualquier docente activo).
     */
    public static function findActiveByInstitution(PDO $db, int $institutionId): array
    {
        $stmt = $db->prepare(
            'SELECT id, first_name, last_name, email, role, phone
             FROM users
             WHERE institution_id = ? AND is_active = 1
             ORDER BY first_name, last_name'
        );
        $stmt->execute([$institutionId]);
        return $stmt->fetchAll();
    }

    /**
     * Devuelve el director de grupo de un curso (id + nombre).
     */
    public static function directorOfCourse(PDO $db, int $courseId): ?array
    {
        $stmt = $db->prepare(
            'SELECT u.id, u.first_name, u.last_name, u.email, u.role
             FROM courses c
             JOIN users u ON u.id = c.group_director_id
             WHERE c.id = ? AND u.is_active = 1'
        );
        $stmt->execute([$courseId]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    /**
     * Quita datos sensibles antes de enviar al cliente.
     */
    public static function publicArray(array $user): array
    {
        return [
            'id'         => (int)$user['id'],
            'role'       => $user['role'],
            'first_name' => $user['first_name'],
            'last_name'  => $user['last_name'],
            'full_name'  => trim(($user['first_name'] ?? '') . ' ' . ($user['last_name'] ?? '')),
            'email'      => $user['email'],
            'phone'      => $user['phone'] ?? null,
            'avatar'     => $user['avatar_path'] ?? null,
            'institution_id' => (int)$user['institution_id'],
        ];
    }
}
