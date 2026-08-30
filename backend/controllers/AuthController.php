<?php
/**
 * controllers/AuthController.php
 */

declare(strict_types=1);

class AuthController
{
    /**
     * POST /api/auth/login.php
     * Body: { email, password }
     */
    public static function login(PDO $db): void
    {
        $data = read_json_body();
        $email = strtolower(trim(input_required($data, 'email')));
        $password = input_required($data, 'password');

        if (!is_valid_email($email)) {
            send_error('Email inválido.', 'INVALID_EMAIL', 422);
        }

        $user = User::findByEmail($db, $email);
        if (!$user || !password_verify($password, $user['password_hash'])) {
            send_error('Credenciales incorrectas.', 'AUTH_FAILED', 401);
        }
        if (!$user['is_active']) {
            send_error('Usuario inactivo. Contacte al administrador.', 'USER_INACTIVE', 403);
        }

        User::touchLastLogin($db, (int)$user['id']);

        $token = jwt_create([
            'sub'  => (int)$user['id'],
            'role' => $user['role'],
            'inst' => (int)$user['institution_id'],
            'name' => trim($user['first_name'] . ' ' . $user['last_name']),
        ]);

        send_json(true, [
            'token' => $token,
            'user'  => User::publicArray($user),
        ], 'Inicio de sesión exitoso.');
    }

    /**
     * POST /api/auth/register.php
     * Solo admin puede crear usuarios.
     */
    public static function register(PDO $db): void
    {
        $payload = require_role(ROLE_ADMIN);
        $data = read_json_body();

        $email = strtolower(trim(input_required($data, 'email')));
        if (!is_valid_email($email)) {
            send_error('Email inválido.', 'INVALID_EMAIL', 422);
        }
        if (strlen($data['password'] ?? '') < 8) {
            send_error('La contraseña debe tener al menos 8 caracteres.', 'WEAK_PASSWORD', 422);
        }
        if (User::findByEmail($db, $email)) {
            send_error('Ya existe un usuario con ese email.', 'EMAIL_TAKEN', 409);
        }
        $role = $data['role'] ?? ROLE_TEACHER;
        if (!in_array($role, [ROLE_ADMIN, ROLE_DIRECTOR, ROLE_TEACHER], true)) {
            send_error('Rol inválido.', 'INVALID_ROLE', 422);
        }

        $userId = User::create($db, [
            'institution_id' => $payload['inst'],
            'role'           => $role,
            'first_name'     => input_required($data, 'first_name'),
            'last_name'      => input_required($data, 'last_name'),
            'email'          => $email,
            'password'       => $data['password'],
            'phone'          => $data['phone'] ?? null,
            'document_id'    => $data['document_id'] ?? null,
        ]);

        $user = User::findById($db, $userId);
        send_json(true, ['user' => User::publicArray($user)], 'Usuario creado correctamente.', 201);
    }

    /**
     * GET /api/auth/me.php
     */
    public static function me(PDO $db): void
    {
        $payload = require_auth();
        $user = User::findById($db, (int)$payload['sub']);
        if (!$user) send_error('Usuario no encontrado.', 'NOT_FOUND', 404);
        send_json(true, ['user' => User::publicArray($user)]);
    }
}
