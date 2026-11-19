<?php
declare(strict_types=1);

/**
 * Autenticación multi-admin + RBAC para SABER+ Command Center.
 *
 * Reemplaza el modelo anterior de ADMIN_USER/ADMIN_PASS en .env por:
 *  - Tabla `admin_users` con hash bcrypt.
 *  - Tabla `admin_roles` con 4 roles por defecto.
 *  - Tabla `admin_permissions` con permisos granulares.
 *  - Tabla `admin_role_permissions` N:M.
 *
 * Funciones:
 *  - admin_login($email, $password): bool
 *  - admin_logout(): void
 *  - require_admin_auth(): void            (redirect si no logueado)
 *  - require_permission(string $code): void (403 si no tiene permiso)
 *  - current_admin_id(): ?int
 *  - current_admin_email(): ?string
 *  - current_admin_name(): ?string
 *  - current_admin_role(): ?string
 *  - admin_has_permission(string $code): bool
 */

// ── Rate-limit login (5 fallos / 10 min por IP+email) ──

function admin_login_rate_limit_bloqueado(string $email): bool {
    $ip = admin_client_ip();
    $key = md5($ip . '|' . $email);
    $file = sys_get_temp_dir() . '/saberplus_admin_rl_' . $key;
    if (!file_exists($file)) return false;
    $data = json_decode((string)file_get_contents($file), true);
    if (!$data) return false;
    if (($data['bloqueado_hasta'] ?? 0) > time()) return true;
    return false;
}

function admin_login_rate_limit_registrar_fallo(string $email): void {
    $ip = admin_client_ip();
    $key = md5($ip . '|' . $email);
    $file = sys_get_temp_dir() . '/saberplus_admin_rl_' . $key;
    $fp = fopen($file, 'c+');
    if (!$fp) return;
    if (flock($fp, LOCK_EX)) {
        $data = ['intentos' => 0, 'bloqueado_hasta' => 0];
        $raw = stream_get_contents($fp);
        if ($raw) {
            $decoded = json_decode($raw, true);
            if ($decoded) $data = $decoded;
        }
        $data['intentos']++;
        if ($data['intentos'] >= 5) {
            $data['bloqueado_hasta'] = time() + 600; // 10 min
            $data['intentos'] = 0;
        }
        ftruncate($fp, 0);
        rewind($fp);
        fwrite($fp, json_encode($data));
        fflush($fp);
        flock($fp, LOCK_UN);
    }
    fclose($fp);
}

function admin_login_rate_limit_limpiar(string $email): void {
    $ip = admin_client_ip();
    $key = md5($ip . '|' . $email);
    $file = sys_get_temp_dir() . '/saberplus_admin_rl_' . $key;
    if (file_exists($file)) @unlink($file);
}

// ── Login / Logout ──

function admin_login(PDO $db, string $email, string $password): array {
    $email = trim(strtolower($email));
    if ($email === '' || $password === '') {
        return ['ok' => false, 'error' => 'Email y contraseña son obligatorios'];
    }
    if (admin_login_rate_limit_bloqueado($email)) {
        return ['ok' => false, 'error' => 'Demasiados intentos fallidos. Intenta de nuevo en 10 minutos.'];
    }

    try {
        $stmt = $db->prepare(
            'SELECT u.id, u.email, u.name, u.password_hash, u.is_active, u.role_id, r.name AS role_name
             FROM admin_users u
             JOIN admin_roles r ON r.id = u.role_id
             WHERE u.email = ? LIMIT 1'
        );
        $stmt->execute([$email]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
        error_log('[admin_login] DB error: ' . $e->getMessage());
        return ['ok' => false, 'error' => 'Error interno. Intenta más tarde.'];
    }

    if (!$user || !$user['is_active']) {
        admin_login_rate_limit_registrar_fallo($email);
        return ['ok' => false, 'error' => 'Credenciales inválidas'];
    }

    // Timing-safe password verification
    if (!password_verify($password, $user['password_hash'])) {
        admin_login_rate_limit_registrar_fallo($email);
        return ['ok' => false, 'error' => 'Credenciales inválidas'];
    }

    // Login OK
    admin_login_rate_limit_limpiar($email);

    // Cargar permisos del rol
    try {
        $stmt = $db->prepare(
            'SELECT p.code FROM admin_role_permissions rp
             JOIN admin_permissions p ON p.id = rp.permission_id
             WHERE rp.role_id = ?'
        );
        $stmt->execute([$user['role_id']]);
        $perms = $stmt->fetchAll(PDO::FETCH_COLUMN);
    } catch (Throwable $e) {
        $perms = [];
    }

    // Anti session-fixation
    session_regenerate_id(true);
    $_SESSION['admin_user_id']   = (int)$user['id'];
    $_SESSION['admin_email']      = $user['email'];
    $_SESSION['admin_name']      = $user['name'];
    $_SESSION['admin_role']      = $user['role_name'];
    $_SESSION['admin_permissions'] = $perms;
    $_SESSION['admin_logged_in']  = true;
    $_SESSION['admin_login_at']   = time();

    // Actualizar last_login_at
    try {
        $upd = $db->prepare('UPDATE admin_users SET last_login_at = NOW() WHERE id = ?');
        $upd->execute([$user['id']]);
    } catch (Throwable $e) {}

    return ['ok' => true];
}

function admin_logout(): void {
    $_SESSION = [];
    if (ini_get('session.use_cookies')) {
        $p = session_get_cookie_params();
        setcookie(session_name(), '', time() - 42000,
            $p['path'], $p['domain'], $p['secure'], $p['httponly']);
    }
    session_destroy();
}

// ── Middleware ──

function require_admin_auth(): void {
    if (empty($_SESSION['admin_logged_in']) || empty($_SESSION['admin_user_id'])) {
        // Si es API (JSON), responder 401
        $wantsJson = (
            (isset($_SERVER['HTTP_ACCEPT']) && stripos($_SERVER['HTTP_ACCEPT'], 'application/json') !== false) ||
            (isset($_SERVER['CONTENT_TYPE']) && stripos($_SERVER['CONTENT_TYPE'], 'application/json') !== false)
        );
        if ($wantsJson) {
            admin_json_response(['status' => 'error', 'message' => 'No autenticado'], 401);
        }
        header('Location: login.php');
        exit;
    }
}

function require_permission(string $code): void {
    require_admin_auth();
    if (!admin_has_permission($code)) {
        $wantsJson = (
            (isset($_SERVER['HTTP_ACCEPT']) && stripos($_SERVER['HTTP_ACCEPT'], 'application/json') !== false) ||
            (isset($_SERVER['CONTENT_TYPE']) && stripos($_SERVER['CONTENT_TYPE'], 'application/json') !== false)
        );
        if ($wantsJson) {
            admin_json_response(['status' => 'error', 'message' => "Permiso insuficiente: $code"], 403);
        }
        http_response_code(403);
        exit('Permisos insuficientes para esta acción: ' . sp_h($code));
    }
}

// ── Getters ──

function current_admin_id(): ?int {
    return isset($_SESSION['admin_user_id']) ? (int)$_SESSION['admin_user_id'] : null;
}

function current_admin_email(): ?string {
    return $_SESSION['admin_email'] ?? null;
}

function current_admin_name(): ?string {
    return $_SESSION['admin_name'] ?? null;
}

function current_admin_role(): ?string {
    return $_SESSION['admin_role'] ?? null;
}

function admin_has_permission(string $code): bool {
    if (empty($_SESSION['admin_permissions'])) return false;
    return in_array($code, $_SESSION['admin_permissions'], true);
}
