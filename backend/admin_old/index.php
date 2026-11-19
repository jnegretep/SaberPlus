<?php
/**
 * admin/index.php - Saber+ Panel de Administracion
 */

// ✅ PT3: cookie de sesión endurecida — httponly (invisible para JS) y
// SameSite=Lax (mitiga CSRF en las acciones POST del panel). Debe ir
// ANTES de session_start().
session_set_cookie_params([
    'httponly' => true,
    'samesite' => 'Lax',
]);
session_start();

require_once __DIR__ . '/../includes/conexion.php';
require_once __DIR__ . '/../includes/config.php';
require_once __DIR__ . '/../env.php';
// ✅ PT7: auditoría de acciones admin (Administration & Intelligence Center)
require_once __DIR__ . '/includes/admin_audit.php';

// ── Configuracion de acceso admin (desde backend/.env) ──
$ADMIN_USER = env('ADMIN_USER', '');
$ADMIN_PASS = env('ADMIN_PASS', '');

// Fail-closed: sin credenciales configuradas, el panel queda cerrado
if ($ADMIN_USER === '' || $ADMIN_PASS === '') {
    http_response_code(503);
    exit('Panel de administracion no configurado. Define ADMIN_USER y ADMIN_PASS en backend/.env');
}

// ── ✅ PT3: rate-limit del login admin (patrón /tmp+flock del endpoint IA) ──
// 5 fallos en 10 min para el par IP+usuario → bloquea 10 minutos.
function admin_login_rate_limit_bloqueado(string $clave): bool {
    $archivo = sys_get_temp_dir() . '/saberplus_rl_admin_' . md5($clave) . '.json';
    $fp = @fopen($archivo, 'c+');
    if ($fp === false) {
        return false;
    }
    $ahora = time();
    $ventana = 600; // 10 minutos
    $fallos = [];
    try {
        if (flock($fp, LOCK_EX)) {
            $raw = stream_get_contents($fp);
            if (is_string($raw) && $raw !== '') {
                $dec = json_decode($raw, true);
                if (is_array($dec)) {
                    foreach ($dec as $t) {
                        if (is_numeric($t) && ($ahora - (int)$t) < $ventana) {
                            $fallos[] = (int)$t;
                        }
                    }
                }
            }
            ftruncate($fp, 0);
            rewind($fp);
            fwrite($fp, json_encode($fallos));
            fflush($fp);
            flock($fp, LOCK_UN);
        }
    } finally {
        fclose($fp);
    }
    return count($fallos) >= 5;
}

function admin_login_registrar_fallo(string $clave): void {
    $archivo = sys_get_temp_dir() . '/saberplus_rl_admin_' . md5($clave) . '.json';
    $fp = @fopen($archivo, 'c+');
    if ($fp === false) {
        return;
    }
    $ahora = time();
    $ventana = 600;
    $fallos = [];
    try {
        if (flock($fp, LOCK_EX)) {
            $raw = stream_get_contents($fp);
            if (is_string($raw) && $raw !== '') {
                $dec = json_decode($raw, true);
                if (is_array($dec)) {
                    foreach ($dec as $t) {
                        if (is_numeric($t) && ($ahora - (int)$t) < $ventana) {
                            $fallos[] = (int)$t;
                        }
                    }
                }
            }
            $fallos[] = $ahora;
            ftruncate($fp, 0);
            rewind($fp);
            fwrite($fp, json_encode($fallos));
            fflush($fp);
            flock($fp, LOCK_UN);
        }
    } finally {
        fclose($fp);
    }
}

function admin_login_limpiar_fallos(string $clave): void {
    @unlink(sys_get_temp_dir() . '/saberplus_rl_admin_' . md5($clave) . '.json');
}

// ── Login ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['login'])) {
    $user = $_POST['username'] ?? '';
    $pass = $_POST['password'] ?? '';

    // ✅ PT3: rate-limit por IP+usuario (5 fallos / 10 min → lock 10 min).
    $rlClave = ($_SERVER['REMOTE_ADDR'] ?? 'desconocida') . '|' . $user;
    if (admin_login_rate_limit_bloqueado($rlClave)) {
        error_log('[ADMIN] Login bloqueado por rate-limit: ip=' . ($_SERVER['REMOTE_ADDR'] ?? '?') . ' user=' . substr($user, 0, 40));
        http_response_code(429);
        $loginError = 'Demasiados intentos fallidos. Espera unos minutos e inténtalo de nuevo.';
    } elseif ($user === $ADMIN_USER && $pass === $ADMIN_PASS) {
        admin_login_limpiar_fallos($rlClave);
        // ✅ PT3: regenerar el ID de sesión tras login exitoso (anti session-fixation).
        session_regenerate_id(true);
        $_SESSION['admin_logged_in'] = true;
        // ✅ PT7: guardamos el usuario para la auditoría de acciones (admin_audit_log).
        $_SESSION['admin_user'] = $user;
        header('Location: index.php');
        exit;
    } else {
        admin_login_registrar_fallo($rlClave);
        $loginError = 'Credenciales incorrectas';
    }
}

// ── Logout ──
if (isset($_GET['logout'])) {
    session_destroy();
    header('Location: index.php');
    exit;
}

// ── Verificar sesion ──
if (!isset($_SESSION['admin_logged_in']) || $_SESSION['admin_logged_in'] !== true) {
    ?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Saber+ Admin - Login</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; display: flex; align-items: center; justify-content: center; }
        .login-card { background: white; border-radius: 24px; padding: 40px; width: 100%; max-width: 400px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); }
        .logo { text-align: center; margin-bottom: 24px; }
        .logo h1 { font-size: 28px; font-weight: 800; color: #1E4ED8; }
        .logo p { font-size: 13px; color: #999; }
        .form-group { margin-bottom: 16px; }
        label { display: block; font-size: 14px; font-weight: 600; color: #555; margin-bottom: 6px; }
        input { width: 100%; padding: 12px 16px; border: 2px solid #e2e8f0; border-radius: 12px; font-size: 15px; }
        input:focus { outline: none; border-color: #1E4ED8; }
        .btn-login { width: 100%; padding: 14px; background: #1E4ED8; color: white; border: none; border-radius: 12px; font-size: 16px; font-weight: 700; cursor: pointer; transition: 0.2s; }
        .btn-login:hover { background: #1E3A8A; }
        .error { color: #EF4444; font-size: 14px; margin-bottom: 16px; text-align: center; }
    </style>
</head>
<body>
    <div class="login-card">
        <div class="logo">
            <h1>Saber+ Admin</h1>
            <p>Panel de Administracion</p>
        </div>
        <?php if (isset($loginError)): ?>
            <div class="error"><?= htmlspecialchars($loginError) ?></div>
        <?php endif; ?>
        <form method="POST">
            <div class="form-group">
                <label>Usuario</label>
                <input type="text" name="username" required autofocus>
            </div>
            <div class="form-group">
                <label>Contraseña</label>
                <input type="password" name="password" required>
            </div>
            <button type="submit" name="login" class="btn-login">Ingresar</button>
        </form>
    </div>
</body>
</html>
    <?php
    exit;
}

// ── Router de secciones ──
 $section = $_GET['section'] ?? 'dashboard';

// ── Acciones POST del admin (v1.6.0) ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['resolve_error'])) {
    // ✅ PT3: verificación CSRF (mismo mecanismo que el resto de acciones
    // del panel — antes esta acción se podía forjar desde otro sitio).
    admin_csrf_verify();
    $errId = (int)$_POST['resolve_error'];
    try {
        $stmt = $conexion->prepare("UPDATE error_logs SET resolved = 1 WHERE id = ?");
        $stmt->execute([$errId]);
    } catch (Exception $e) {
        error_log('[ADMIN] resolve_error: ' . $e->getMessage());
    }
    header('Location: index.php?section=errors');
    exit;
}

// ── CSRF del panel admin (formularios de la sección Colegios, v1.7.0 B2B) ──
if (empty($_SESSION['admin_csrf'])) {
    $_SESSION['admin_csrf'] = bin2hex(random_bytes(32));
}

function admin_csrf_field(): string
{
    return '<input type="hidden" name="csrf" value="' . htmlspecialchars($_SESSION['admin_csrf'], ENT_QUOTES, 'UTF-8') . '">';
}

function admin_csrf_verify(): void
{
    $token = (string)($_POST['csrf'] ?? '');
    if ($token === '' || !hash_equals($_SESSION['admin_csrf'], $token)) {
        http_response_code(403);
        exit('Token CSRF invalido');
    }
}

// ── Sección Colegios (B2B): crear director ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['crear_director'])) {
    admin_csrf_verify();
    $nombre     = trim((string)($_POST['nombre'] ?? ''));
    $email      = strtolower(trim((string)($_POST['email'] ?? '')));
    $colegioDir = trim((string)($_POST['colegio'] ?? ''));
    $telefono   = trim((string)($_POST['telefono'] ?? ''));
    $password   = (string)($_POST['password'] ?? '');

    if ($nombre === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)
        || $colegioDir === '' || strlen($password) < 8) {
        header('Location: index.php?section=colegios&msg=datos_invalidos');
        exit;
    }
    try {
        $ins = $conexion->prepare("
            INSERT INTO directores (nombre, email, contrasena_hash, colegio, telefono)
            VALUES (:n, :e, :p, :c, :t)
        ");
        $ins->execute([
            ':n' => $nombre,
            ':e' => $email,
            ':p' => password_hash($password, PASSWORD_DEFAULT),
            ':c' => $colegioDir,
            ':t' => ($telefono !== '' ? $telefono : null),
        ]);
        // ✅ PT7: auditoría de la creación (nunca guarda la contraseña)
        admin_audit_log($conexion, 'crear_director', 'directores', (int)$conexion->lastInsertId(),
            json_encode(['nombre' => $nombre, 'email' => $email, 'colegio' => $colegioDir], JSON_UNESCAPED_UNICODE));
        header('Location: index.php?section=colegios&msg=director_creado');
        exit;
    } catch (PDOException $ex) {
        if ($ex->getCode() === '23000') {
            header('Location: index.php?section=colegios&msg=email_duplicado');
            exit;
        }
        error_log('[ADMIN] crear_director: ' . $ex->getMessage());
        header('Location: index.php?section=colegios&msg=error_bd');
        exit;
    }
}

// ── Sección Colegios (B2B): activar/desactivar director ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['toggle_director'])) {
    admin_csrf_verify();
    $idDirector = (int)($_POST['director_id'] ?? 0);
    try {
        $stmt = $conexion->prepare("UPDATE directores SET activo = 1 - activo WHERE id = :id");
        $stmt->execute([':id' => $idDirector]);
    } catch (PDOException $ex) {
        error_log('[ADMIN] toggle_director: ' . $ex->getMessage());
    }
    // ✅ PT7: auditoría del cambio de estado
    admin_audit_log($conexion, 'toggle_director', 'directores', $idDirector,
        json_encode(['director_id' => $idDirector]));
    header('Location: index.php?section=colegios&msg=estado_actualizado');
    exit;
}

// ── Sección Colegios (B2B): reset de contraseña de director ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['reset_director_pass'])) {
    admin_csrf_verify();
    $idDirector = (int)($_POST['director_id'] ?? 0);
    $pool = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    $nueva = '';
    for ($i = 0; $i < 12; $i++) {
        $nueva .= $pool[random_int(0, strlen($pool) - 1)];
    }
    try {
        $stmt = $conexion->prepare("UPDATE directores SET contrasena_hash = :h WHERE id = :id");
        $stmt->execute([':h' => password_hash($nueva, PASSWORD_DEFAULT), ':id' => $idDirector]);
        $_SESSION['admin_flash_pass'] = ['id' => $idDirector, 'pass' => $nueva];
    } catch (PDOException $ex) {
        error_log('[ADMIN] reset_director_pass: ' . $ex->getMessage());
    }
    // ✅ PT7: auditoría del reset (la nueva contraseña NUNCA se registra)
    admin_audit_log($conexion, 'reset_director_pass', 'directores', $idDirector,
        json_encode(['director_id' => $idDirector]));
    header('Location: index.php?section=colegios&msg=pass_reset');
    exit;
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN PROMOCIONES (v1.7.0): crear / editar / activar / eliminar
// ═══════════════════════════════════════════════════════════════

// ── Promociones: guardar (crear o actualizar) ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['promo_save'])) {
    admin_csrf_verify();
    $id          = (int)($_POST['promo_id'] ?? 0);
    $titulo      = trim((string)($_POST['titulo'] ?? ''));
    $descripcion = mb_substr(trim((string)($_POST['descripcion'] ?? '')), 0, 255);
    $tipo        = in_array($_POST['tipo'] ?? '', ['banner', 'codigo'], true) ? $_POST['tipo'] : 'banner';
    $codigo      = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string)($_POST['codigo'] ?? '')));
    $dtoTipo     = ($_POST['descuento_tipo'] ?? '') === 'monto' ? 'monto' : 'porcentaje';
    $dtoValor    = (float)($_POST['descuento_valor'] ?? 0);
    $planId      = (int)($_POST['plan_id'] ?? 0);
    $fechaInicio = (string)($_POST['fecha_inicio'] ?? '');
    $fechaFin    = (string)($_POST['fecha_fin'] ?? '');
    $maxUsos     = trim((string)($_POST['max_usos'] ?? ''));
    $activo      = isset($_POST['activo']) ? 1 : 0;

    $errores = [];
    if ($titulo === '')                              $errores[] = 'titulo';
    if ($dtoValor <= 0)                              $errores[] = 'descuento';
    if ($dtoTipo === 'porcentaje' && $dtoValor > 100) $errores[] = 'descuento';
    if ($tipo === 'codigo' && strlen($codigo) < 4)    $errores[] = 'codigo';
    $tsIni = strtotime($fechaInicio);
    $tsFin = strtotime($fechaFin);
    if ($tsIni === false || $tsFin === false || $tsFin <= $tsIni) $errores[] = 'fechas';

    if (!empty($errores)) {
        header('Location: index.php?section=promociones&msg=promo_datos_invalidos');
        exit;
    }

    $fechaInicio = date('Y-m-d H:i:s', $tsIni);
    $fechaFin    = date('Y-m-d H:i:s', $tsFin);
    $planIdSql   = $planId > 0 ? $planId : null;
    $maxUsosSql  = ($maxUsos !== '' && (int)$maxUsos > 0) ? (int)$maxUsos : null;

    try {
        if ($id > 0) {
            $stmt = $conexion->prepare("
                UPDATE promociones SET
                    titulo = :t, descripcion = :d, tipo = :ti, codigo = :c,
                    descuento_tipo = :dt, descuento_valor = :dv, plan_id = :p,
                    fecha_inicio = :fi, fecha_fin = :ff, max_usos = :mu, activo = :a
                WHERE id = :id
            ");
            $stmt->execute([
                ':t' => $titulo, ':d' => ($descripcion !== '' ? $descripcion : null),
                ':ti' => $tipo, ':c' => ($tipo === 'codigo' ? $codigo : null),
                ':dt' => $dtoTipo, ':dv' => $dtoValor, ':p' => $planIdSql,
                ':fi' => $fechaInicio, ':ff' => $fechaFin, ':mu' => $maxUsosSql,
                ':a' => $activo, ':id' => $id,
            ]);
            header('Location: index.php?section=promociones&msg=promo_actualizada');
        } else {
            $stmt = $conexion->prepare("
                INSERT INTO promociones
                    (titulo, descripcion, tipo, codigo, descuento_tipo, descuento_valor,
                     plan_id, fecha_inicio, fecha_fin, max_usos, activo)
                VALUES
                    (:t, :d, :ti, :c, :dt, :dv, :p, :fi, :ff, :mu, :a)
            ");
            $stmt->execute([
                ':t' => $titulo, ':d' => ($descripcion !== '' ? $descripcion : null),
                ':ti' => $tipo, ':c' => ($tipo === 'codigo' ? $codigo : null),
                ':dt' => $dtoTipo, ':dv' => $dtoValor, ':p' => $planIdSql,
                ':fi' => $fechaInicio, ':ff' => $fechaFin, ':mu' => $maxUsosSql,
                ':a' => $activo,
            ]);
            header('Location: index.php?section=promociones&msg=promo_creada');
        }
        // ✅ PT7: auditoría de la promoción creada/actualizada
        admin_audit_log($conexion, 'promo_save', 'promociones', $id > 0 ? $id : (int)$conexion->lastInsertId(),
            json_encode(['titulo' => $titulo, 'tipo' => $tipo, 'descuento_tipo' => $dtoTipo,
                         'descuento_valor' => $dtoValor, 'activo' => $activo], JSON_UNESCAPED_UNICODE));
        exit;
    } catch (PDOException $ex) {
        if ($ex->getCode() === '23000') {
            header('Location: index.php?section=promociones&msg=promo_codigo_duplicado');
            exit;
        }
        error_log('[ADMIN] promo_save: ' . $ex->getMessage());
        header('Location: index.php?section=promociones&msg=promo_error_bd');
        exit;
    }
}

// ── Promociones: activar/desactivar ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['promo_toggle'])) {
    admin_csrf_verify();
    try {
        $stmt = $conexion->prepare("UPDATE promociones SET activo = 1 - activo WHERE id = :id");
        $stmt->execute([':id' => (int)($_POST['promo_id'] ?? 0)]);
    } catch (PDOException $ex) {
        error_log('[ADMIN] promo_toggle: ' . $ex->getMessage());
    }
    // ✅ PT7: auditoría del cambio de estado de la promoción
    admin_audit_log($conexion, 'promo_toggle', 'promociones', (int)($_POST['promo_id'] ?? 0),
        json_encode(['promo_id' => (int)($_POST['promo_id'] ?? 0)]));
    header('Location: index.php?section=promociones&msg=promo_estado');
    exit;
}

// ── Promociones: eliminar ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['promo_delete'])) {
    admin_csrf_verify();
    try {
        $stmt = $conexion->prepare("DELETE FROM promociones WHERE id = :id");
        $stmt->execute([':id' => (int)($_POST['promo_id'] ?? 0)]);
    } catch (PDOException $ex) {
        error_log('[ADMIN] promo_delete: ' . $ex->getMessage());
    }
    // ✅ PT7: auditoría de la eliminación
    admin_audit_log($conexion, 'promo_delete', 'promociones', (int)($_POST['promo_id'] ?? 0),
        json_encode(['promo_id' => (int)($_POST['promo_id'] ?? 0)]));
    header('Location: index.php?section=promociones&msg=promo_eliminada');
    exit;
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN CÓDIGOS PREMIUM (W1B): canje desde la app → plan Premium
// Tablas: migración 008_codigos_premium.sql · Endpoint: redeem_promo_code.php
// ═══════════════════════════════════════════════════════════════

// ── Códigos Premium: guardar (crear o actualizar) ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['codigo_save'])) {
    admin_csrf_verify();
    $id           = (int)($_POST['codigo_id'] ?? 0);
    $codigo       = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string)($_POST['codigo'] ?? '')));
    $descripcion  = mb_substr(trim((string)($_POST['descripcion'] ?? '')), 0, 255);
    $notas        = mb_substr(trim((string)($_POST['notas'] ?? '')), 0, 255);
    $estado       = ($_POST['estado'] ?? '') === 'deshabilitado' ? 'deshabilitado' : 'activo';
    $maxUsosRaw   = trim((string)($_POST['max_usos'] ?? ''));
    $duracionRaw  = trim((string)($_POST['duracion_dias'] ?? ''));
    $maxUsos      = ($maxUsosRaw !== '' && (int)$maxUsosRaw > 0) ? (int)$maxUsosRaw : 1;
    $duracionDias = ($duracionRaw !== '' && (int)$duracionRaw > 0) ? (int)$duracionRaw : 365;
    $venceEn      = trim((string)($_POST['vence_en'] ?? ''));

    $errores = [];
    if (strlen($codigo) < 4) $errores[] = 'codigo';
    if ($maxUsos < 1)        $errores[] = 'max_usos';
    if ($duracionDias < 1)   $errores[] = 'duracion_dias';
    $venceSql = null;
    if ($venceEn !== '') {
        $tsV = strtotime($venceEn);
        if ($tsV === false) {
            $errores[] = 'vence_en';
        } else {
            $venceSql = date('Y-m-d H:i:s', $tsV);
        }
    }

    if (!empty($errores)) {
        header('Location: index.php?section=codigos&msg=codigo_datos_invalidos');
        exit;
    }

    try {
        if ($id > 0) {
            $stmt = $conexion->prepare("
                UPDATE codigos_premium SET
                    codigo = :c, descripcion = :d, estado = :e, vence_en = :v,
                    max_usos = :mu, duracion_dias = :dd, notas = :n
                WHERE id = :id
            ");
            $stmt->execute([
                ':c' => $codigo,
                ':d' => ($descripcion !== '' ? $descripcion : null),
                ':e' => $estado, ':v' => $venceSql,
                ':mu' => $maxUsos, ':dd' => $duracionDias,
                ':n' => ($notas !== '' ? $notas : null),
                ':id' => $id,
            ]);
            header('Location: index.php?section=codigos&msg=codigo_actualizado');
        } else {
            $stmt = $conexion->prepare("
                INSERT INTO codigos_premium
                    (codigo, descripcion, estado, vence_en, max_usos, duracion_dias, notas)
                VALUES
                    (:c, :d, :e, :v, :mu, :dd, :n)
            ");
            $stmt->execute([
                ':c' => $codigo,
                ':d' => ($descripcion !== '' ? $descripcion : null),
                ':e' => $estado, ':v' => $venceSql,
                ':mu' => $maxUsos, ':dd' => $duracionDias,
                ':n' => ($notas !== '' ? $notas : null),
            ]);
            header('Location: index.php?section=codigos&msg=codigo_creado');
        }
        // ✅ Auditoría del código creado/actualizado
        admin_audit_log($conexion, 'codigo_save', 'codigos_premium', $id > 0 ? $id : (int)$conexion->lastInsertId(),
            json_encode(['codigo' => $codigo, 'estado' => $estado, 'max_usos' => $maxUsos,
                         'duracion_dias' => $duracionDias, 'vence_en' => $venceSql], JSON_UNESCAPED_UNICODE));
        exit;
    } catch (PDOException $ex) {
        if ($ex->getCode() === '23000') {
            header('Location: index.php?section=codigos&msg=codigo_duplicado');
            exit;
        }
        if ($ex->getCode() === '42S02') {
            header('Location: index.php?section=codigos&msg=codigo_no_migrado');
            exit;
        }
        error_log('[ADMIN] codigo_save: ' . $ex->getMessage());
        header('Location: index.php?section=codigos&msg=codigo_error_bd');
        exit;
    }
}

// ── Códigos Premium: habilitar/deshabilitar ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['codigo_toggle'])) {
    admin_csrf_verify();
    $idCodigo = (int)($_POST['codigo_id'] ?? 0);
    try {
        $stmt = $conexion->prepare("UPDATE codigos_premium SET estado = IF(estado = 'activo', 'deshabilitado', 'activo') WHERE id = :id");
        $stmt->execute([':id' => $idCodigo]);
    } catch (PDOException $ex) {
        error_log('[ADMIN] codigo_toggle: ' . $ex->getMessage());
    }
    // ✅ Auditoría del cambio de estado
    admin_audit_log($conexion, 'codigo_toggle', 'codigos_premium', $idCodigo,
        json_encode(['codigo_id' => $idCodigo]));
    header('Location: index.php?section=codigos&msg=codigo_estado');
    exit;
}

// ── Códigos Premium: eliminar (el CASCADE borra también los canjes) ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['codigo_delete'])) {
    admin_csrf_verify();
    $idCodigo = (int)($_POST['codigo_id'] ?? 0);
    try {
        $stmt = $conexion->prepare("DELETE FROM codigos_premium WHERE id = :id");
        $stmt->execute([':id' => $idCodigo]);
    } catch (PDOException $ex) {
        error_log('[ADMIN] codigo_delete: ' . $ex->getMessage());
    }
    // ✅ Auditoría de la eliminación
    admin_audit_log($conexion, 'codigo_delete', 'codigos_premium', $idCodigo,
        json_encode(['codigo_id' => $idCodigo]));
    header('Location: index.php?section=codigos&msg=codigo_eliminado');
    exit;
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN SOPORTE (v1.7.0): responder / cambiar estado de quejas
// ═══════════════════════════════════════════════════════════════
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['queja_update'])) {
    admin_csrf_verify();
    $id        = (int)($_POST['queja_id'] ?? 0);
    $respuesta = trim((string)($_POST['respuesta'] ?? ''));
    $estado    = in_array($_POST['estado'] ?? '', ['nuevo', 'en_proceso', 'resuelto', 'descartado'], true)
        ? $_POST['estado'] : 'en_proceso';

    if ($id > 0) {
        try {
            $stmt = $conexion->prepare("
                UPDATE quejas_sugerencias
                SET estado = :e,
                    respuesta_admin = :r
                WHERE id = :id
            ");
            $stmt->execute([
                ':e' => $estado,
                ':r' => ($respuesta !== '' ? mb_substr($respuesta, 0, 2000) : null),
                ':id' => $id,
            ]);
            // ✅ PT7: auditoría de la respuesta de soporte (no registra el texto)
            admin_audit_log($conexion, 'queja_update', 'quejas_sugerencias', $id,
                json_encode(['queja_id' => $id, 'estado' => $estado, 'con_respuesta' => $respuesta !== ''], JSON_UNESCAPED_UNICODE));
            header('Location: index.php?section=soporte&msg=queja_actualizada&view=' . $id);
            exit;
        } catch (PDOException $ex) {
            error_log('[ADMIN] queja_update: ' . $ex->getMessage());
            header('Location: index.php?section=soporte&msg=queja_error');
            exit;
        }
    }
    header('Location: index.php?section=soporte');
    exit;
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN USUARIOS (v1.7.0): editar perfil de cualquier usuario
// ═══════════════════════════════════════════════════════════════
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['user_save'])) {
    admin_csrf_verify();
    $idUsuario = (int)($_POST['user_id'] ?? 0);

    $nombre       = trim((string)($_POST['nombre'] ?? ''));
    $email        = strtolower(trim((string)($_POST['email'] ?? '')));
    $telefono     = trim((string)($_POST['telefono'] ?? ''));
    $departamento = trim((string)($_POST['departamento'] ?? ''));
    $ciudad       = trim((string)($_POST['ciudad'] ?? ''));
    $colegio      = trim((string)($_POST['colegio'] ?? ''));
    $grado        = trim((string)($_POST['grado'] ?? ''));

    $tiposValidos  = ['estudiante', 'profesor', 'admin'];
    $nivelesValidos = ['free', 'premium', 'early_bird'];
    $tipoUsuario   = in_array($_POST['tipo_usuario'] ?? '', $tiposValidos, true) ? $_POST['tipo_usuario'] : 'estudiante';
    $accessLevel   = in_array($_POST['access_level'] ?? '', $nivelesValidos, true) ? $_POST['access_level'] : 'free';
    $emailVerif    = isset($_POST['email_verificado']) ? 1 : 0;
    $activo        = isset($_POST['activo']) ? 1 : 0;

    if ($idUsuario <= 0 || $nombre === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
        header('Location: index.php?section=users&msg=user_datos_invalidos');
        exit;
    }

    try {
        $stmt = $conexion->prepare("
            UPDATE usuarios SET
                nombre = :n, email = :e, telefono = :t, departamento = :dep,
                ciudad = :c, colegio = :col, grado = :g,
                tipo_usuario = :tu, access_level = :al, email_verificado = :ev
            WHERE id_usuario = :id
        ");
        $stmt->execute([
            ':n' => $nombre, ':e' => $email,
            ':t' => ($telefono !== '' ? $telefono : null),
            ':dep' => ($departamento !== '' ? $departamento : null),
            ':c' => ($ciudad !== '' ? $ciudad : null),
            ':col' => ($colegio !== '' ? $colegio : null),
            ':g' => ($grado !== '' ? $grado : null),
            ':tu' => $tipoUsuario, ':al' => $accessLevel, ':ev' => $emailVerif,
            ':id' => $idUsuario,
        ]);

        // Columna activo (migración 005): puede no existir aún → reintento sin ella
        try {
            $stmtA = $conexion->prepare("UPDATE usuarios SET activo = :a WHERE id_usuario = :id");
            $stmtA->execute([':a' => $activo, ':id' => $idUsuario]);
        } catch (PDOException $exA) {
            error_log('[ADMIN] user_save activo (columna inexistente): ' . $exA->getMessage());
        }

        // ✅ PT7: auditoría de la edición de perfil
        admin_audit_log($conexion, 'user_save', 'usuarios', $idUsuario,
            json_encode(['email' => $email, 'tipo_usuario' => $tipoUsuario,
                         'access_level' => $accessLevel, 'email_verificado' => $emailVerif,
                         'activo' => $activo], JSON_UNESCAPED_UNICODE));

        header('Location: index.php?section=users&edit=' . $idUsuario . '&msg=user_guardado');
        exit;
    } catch (PDOException $ex) {
        if ($ex->getCode() === '23000') {
            header('Location: index.php?section=users&edit=' . $idUsuario . '&msg=user_email_duplicado');
            exit;
        }
        error_log('[ADMIN] user_save: ' . $ex->getMessage());
        header('Location: index.php?section=users&edit=' . $idUsuario . '&msg=user_error_bd');
        exit;
    }
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN CURSOS MOODLE (W2E): catálogo dinámico + matrícula masiva
// Tabla: migración 009_course_catalog.sql · WS usados:
//   core_course_get_courses · core_enrol_get_enrolled_users_count
//   enrol_manual_enrol_users (mismo formato de params que set_password.php)
// ═══════════════════════════════════════════════════════════════
require_once __DIR__ . '/../includes/moodle.php'; // getMoodleClient() + MOODLE_WS_TOKEN

/**
 * W2E: segmentos válidos de la matrícula masiva (whitelist).
 */
function admin_cursos_segmentos_validos(): array
{
    return ['todos', 'verificados', 'trial', 'premium', 'free', 'nuevos_7d'];
}

/**
 * W2E: WHERE del segmento (sin la condición de `activo`, que se añade aparte
 * si la columna existe). $segmento DEBE venir validado contra la whitelist:
 * el fragmento se interpola en SQL sin parámetros.
 */
function admin_cursos_segmento_where(string $segmento): string
{
    switch ($segmento) {
        case 'verificados': return "moodle_id > 0 AND email_verificado = 1";
        case 'trial':       return "moodle_id > 0 AND access_level = 'trial'";
        case 'premium':     return "moodle_id > 0 AND access_level IN ('premium', 'early_bird')";
        case 'free':        return "moodle_id > 0 AND access_level = 'free'";
        case 'nuevos_7d':   return "moodle_id > 0 AND registration_date >= DATE_SUB(NOW(), INTERVAL 7 DAY)";
        case 'todos':
        default:            return "moodle_id > 0";
    }
}

/**
 * W2E: ¿la tabla usuarios tiene la columna `activo` (migración 005)?
 * SHOW COLUMNS una sola vez por request (cache estático).
 */
function admin_cursos_usuarios_tienen_activo(PDO $conexion): bool
{
    static $cache = null;
    if ($cache === null) {
        try {
            $stmt = $conexion->query("SHOW COLUMNS FROM usuarios LIKE 'activo'");
            $cache = ($stmt !== false && $stmt->fetchColumn() !== false);
        } catch (Exception $e) {
            $cache = false;
        }
    }
    return $cache;
}

/**
 * W2E: ids de curso desde $_POST['course_ids'] → ints únicos > 0, ordenados,
 * con tope defensivo de 200 cursos por operación.
 */
function admin_cursos_ids_desde_post($raw): array
{
    if (!is_array($raw)) {
        return [];
    }
    $ids = [];
    foreach ($raw as $v) {
        $iv = (int)$v;
        if ($iv > 0) {
            $ids[$iv] = true;
        }
    }
    $ids = array_keys($ids);
    sort($ids);
    return array_slice($ids, 0, 200);
}

/**
 * W2E: nombres de cursos desde Moodle (id => fullname). Si Moodle no
 * responde devuelve [] y la UI muestra "Curso Moodle #id". NUNCA lanza.
 */
function admin_cursos_nombres_moodle(): array
{
    $nombres = [];
    try {
        $mc = getMoodleClient();
        $todos = $mc->request(MOODLE_WS_TOKEN, 'core_course_get_courses', []);
        foreach ((array)$todos as $c) {
            $id = (int)($c['id'] ?? 0);
            if ($id > 0) {
                $nombres[$id] = (string)($c['fullname'] ?? '');
            }
        }
    } catch (Exception $e) {
        error_log('[ADMIN][cursos] No se pudieron obtener nombres de Moodle: ' . $e->getMessage());
    }
    return $nombres;
}

// ── Cursos Moodle: guardar clasificación de UN curso ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['curso_clasif'])) {
    admin_csrf_verify();
    $courseId   = (int)($_POST['course_id'] ?? 0);
    $courseTipo = (string)($_POST['course_type'] ?? '');
    $courseVis  = isset($_POST['visible']) ? 1 : 0;

    if ($courseId <= 0 || !in_array($courseTipo, ['curso', 'simulacro', 'reto', 'otro'], true)) {
        header('Location: index.php?section=cursos&msg=curso_datos_invalidos');
        exit;
    }

    try {
        // ✅ W2E: upsert — si el curso ya tenía sort_order/visible se conserva
        // el sort_order; tipo y visibilidad se actualizan con lo enviado.
        $stmt = $conexion->prepare("
            INSERT INTO course_catalog (course_id, course_type, visible, sort_order)
            VALUES (:cid, :ct, :v, 0)
            ON DUPLICATE KEY UPDATE course_type = VALUES(course_type), visible = VALUES(visible)
        ");
        $stmt->execute([':cid' => $courseId, ':ct' => $courseTipo, ':v' => $courseVis]);

        // ✅ Auditoría de la clasificación
        admin_audit_log($conexion, 'curso_clasif', 'course_catalog', $courseId,
            json_encode(['course_id' => $courseId, 'course_type' => $courseTipo, 'visible' => $courseVis], JSON_UNESCAPED_UNICODE));

        header('Location: index.php?section=cursos&msg=curso_clasif_ok');
        exit;
    } catch (PDOException $exCurso) {
        if ($exCurso->getCode() === '42S02') {
            header('Location: index.php?section=cursos&msg=cursos_no_migrado');
            exit;
        }
        error_log('[ADMIN] curso_clasif: ' . $exCurso->getMessage());
        header('Location: index.php?section=cursos&msg=curso_error_bd');
        exit;
    }
}

// ── Cursos Moodle: clasificación MASIVA (checkboxes, transacción) ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['curso_clasif_bulk'])) {
    admin_csrf_verify();
    $tipoDestino = (string)($_POST['course_type'] ?? '');
    $idsBulk     = admin_cursos_ids_desde_post($_POST['course_ids'] ?? []);

    if (!in_array($tipoDestino, ['curso', 'simulacro', 'reto', 'otro'], true) || empty($idsBulk)) {
        header('Location: index.php?section=cursos&msg=curso_datos_invalidos');
        exit;
    }

    try {
        $conexion->beginTransaction();
        // ✅ W2E: mismo upsert por cada curso. En los ya existentes se conserva
        // su flag `visible` (solo cambia el tipo); los nuevos entran visibles.
        $stmt = $conexion->prepare("
            INSERT INTO course_catalog (course_id, course_type, visible, sort_order)
            VALUES (:cid, :ct, 1, 0)
            ON DUPLICATE KEY UPDATE course_type = VALUES(course_type)
        ");
        foreach ($idsBulk as $cidBulk) {
            $stmt->execute([':cid' => $cidBulk, ':ct' => $tipoDestino]);
        }
        $conexion->commit();

        // ✅ Auditoría de la clasificación masiva (con cantidad)
        admin_audit_log($conexion, 'curso_clasif_bulk', 'course_catalog', null,
            json_encode(['tipo' => $tipoDestino, 'cantidad' => count($idsBulk)], JSON_UNESCAPED_UNICODE));

        header('Location: index.php?section=cursos&msg=curso_bulk_ok&n=' . count($idsBulk));
        exit;
    } catch (PDOException $exBulk) {
        if ($conexion->inTransaction()) {
            $conexion->rollBack();
        }
        if ($exBulk->getCode() === '42S02') {
            header('Location: index.php?section=cursos&msg=cursos_no_migrado');
            exit;
        }
        error_log('[ADMIN] curso_clasif_bulk: ' . $exBulk->getMessage());
        header('Location: index.php?section=cursos&msg=curso_error_bd');
        exit;
    }
}

// ── Cursos Moodle: matrícula masiva — PASO 1 (resumen previo, no ejecuta) ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['curso_enrol_preview'])) {
    admin_csrf_verify();
    if (($_GET['section'] ?? '') !== 'cursos') {
        header('Location: index.php?section=cursos');
        exit;
    }

    $idsEnrol    = admin_cursos_ids_desde_post($_POST['course_ids'] ?? []);
    $segmentoRaw = (string)($_POST['segmento'] ?? '');
    $segmento    = in_array($segmentoRaw, admin_cursos_segmentos_validos(), true) ? $segmentoRaw : '';

    if (empty($idsEnrol) || $segmento === '') {
        header('Location: index.php?section=cursos&msg=curso_datos_invalidos');
        exit;
    }

    // Nombres de los cursos seleccionados (degradación elegante sin Moodle)
    $nombresPreview = admin_cursos_nombres_moodle();
    $cursosPreview  = [];
    foreach ($idsEnrol as $cidPrev) {
        $cursosPreview[] = [
            'id'     => $cidPrev,
            'nombre' => $nombresPreview[$cidPrev] ?? ('Curso Moodle #' . $cidPrev),
        ];
    }

    // Segmento SQL (whitelist) + columna activo si existe
    $whereSeg = admin_cursos_segmento_where($segmento);
    $tieneActivo = admin_cursos_usuarios_tienen_activo($conexion);
    if ($tieneActivo) {
        $whereSeg .= " AND activo = 1";
    }

    try {
        $stmtCnt = $conexion->prepare("SELECT COUNT(*) FROM usuarios WHERE $whereSeg");
        $stmtCnt->execute();
        $totalSeg = (int)$stmtCnt->fetchColumn();

        $stmtMuestra = $conexion->prepare("SELECT nombre, email, moodle_id FROM usuarios WHERE $whereSeg ORDER BY id_usuario ASC LIMIT 20");
        $stmtMuestra->execute();
        $muestraSeg = $stmtMuestra->fetchAll(PDO::FETCH_ASSOC);
    } catch (PDOException $exSeg) {
        error_log('[ADMIN] curso_enrol_preview: ' . $exSeg->getMessage());
        header('Location: index.php?section=cursos&msg=curso_error_bd');
        exit;
    }

    $cursoEnrolPreview = [
        'cursos'     => $cursosPreview,
        'segmento'   => $segmento,
        'total'      => $totalSeg,
        'muestra'    => $muestraSeg,
        'con_activo' => $tieneActivo,
    ];
    // Sin redirect: la sección 'cursos' renderiza la pantalla de resumen (paso 1 de 2).
}

// ── Cursos Moodle: matrícula masiva — PASO 2 (ejecución) ──
// ⚠️ SOLO AÑADE matrículas (enrol_manual_enrol_users, roleid 5, lotes de 5
// con usleep(100000) — formato idéntico a set_password.php). NUNCA desmatricula.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['curso_enrol_confirm'])) {
    admin_csrf_verify();
    if (($_GET['section'] ?? '') !== 'cursos') {
        header('Location: index.php?section=cursos');
        exit;
    }

    $idsEnrol    = admin_cursos_ids_desde_post($_POST['course_ids'] ?? []);
    $segmentoRaw = (string)($_POST['segmento'] ?? '');
    $segmento    = in_array($segmentoRaw, admin_cursos_segmentos_validos(), true) ? $segmentoRaw : '';

    if (empty($idsEnrol) || $segmento === '') {
        header('Location: index.php?section=cursos&msg=curso_datos_invalidos');
        exit;
    }

    // Operación potencialmente larga (usuarios × cursos): sin límite de tiempo.
    set_time_limit(0);

    $whereSeg = admin_cursos_segmento_where($segmento);
    if (admin_cursos_usuarios_tienen_activo($conexion)) {
        $whereSeg .= " AND activo = 1";
    }

    try {
        $stmtUsuarios = $conexion->prepare("SELECT id_usuario, nombre, email, moodle_id FROM usuarios WHERE $whereSeg ORDER BY id_usuario ASC");
        $stmtUsuarios->execute();
        $usuariosEnrol = $stmtUsuarios->fetchAll(PDO::FETCH_ASSOC);
    } catch (PDOException $exUsr) {
        error_log('[ADMIN] curso_enrol_confirm (usuarios): ' . $exUsr->getMessage());
        header('Location: index.php?section=cursos&msg=curso_error_bd');
        exit;
    }

    $statsPorCurso = [];
    foreach ($idsEnrol as $cidInit) {
        $statsPorCurso[$cidInit] = ['ok' => 0, 'ya' => 0, 'err' => 0];
    }
    $totalesEnrol = [
        'usuarios' => count($usuariosEnrol), // usuarios procesados
        'ok'       => 0,                     // matrículas nuevas
        'ya'       => 0,                     // ya estaban matriculados (alreadyenrolled)
        'err'      => 0,                     // errores reales
        'saltados' => 0,                     // sin cuenta Moodle (moodle_id = 0)
    ];

    $mcEnrol = getMoodleClient();
    $esPrimeraLlamada = true;

    foreach ($usuariosEnrol as $uEnrol) {
        $midEnrol = (int)($uEnrol['moodle_id'] ?? 0);
        if ($midEnrol <= 0) {
            $totalesEnrol['saltados']++;
            continue;
        }

        // Lotes de 5 cursos por llamada (mismo patrón que set_password.php)
        foreach (array_chunk($idsEnrol, 5) as $loteCursos) {
            if (!$esPrimeraLlamada) {
                usleep(100000); // 100 ms entre lotes para no saturar Moodle
            }
            $esPrimeraLlamada = false;

            $enrolments = [];
            foreach ($loteCursos as $cidLote) {
                $enrolments[] = [
                    'roleid'   => 5,
                    'userid'   => $midEnrol,
                    'courseid' => $cidLote,
                ];
            }

            try {
                $mcEnrol->request(MOODLE_WS_TOKEN, 'enrol_manual_enrol_users', ['enrolments' => $enrolments]);
                foreach ($loteCursos as $cidOk) {
                    $statsPorCurso[$cidOk]['ok']++;
                }
                $totalesEnrol['ok'] += count($loteCursos);
            } catch (Exception $eLote) {
                $msgLote = $eLote->getMessage();
                if (stripos($msgLote, 'alreadyenrolled') !== false || stripos($msgLote, 'already enrolled') !== false) {
                    // Algún curso del lote ya tenía al usuario → reintentar curso
                    // por curso para separar "ya matriculados" de nuevos/errores.
                    foreach ($enrolments as $enr) {
                        usleep(100000);
                        $cidUno = (int)$enr['courseid'];
                        try {
                            $mcEnrol->request(MOODLE_WS_TOKEN, 'enrol_manual_enrol_users', ['enrolments' => [$enr]]);
                            $statsPorCurso[$cidUno]['ok']++;
                            $totalesEnrol['ok']++;
                        } catch (Exception $eUno) {
                            $msgUno = $eUno->getMessage();
                            if (stripos($msgUno, 'alreadyenrolled') !== false || stripos($msgUno, 'already enrolled') !== false) {
                                $statsPorCurso[$cidUno]['ya']++;
                                $totalesEnrol['ya']++;
                            } else {
                                $statsPorCurso[$cidUno]['err']++;
                                $totalesEnrol['err']++;
                                error_log('[ADMIN] curso_enrol user=' . $midEnrol . ' course=' . $cidUno . ': ' . $msgUno);
                            }
                        }
                    }
                } else {
                    foreach ($loteCursos as $cidErr) {
                        $statsPorCurso[$cidErr]['err']++;
                    }
                    $totalesEnrol['err'] += count($loteCursos);
                    error_log('[ADMIN] curso_enrol user=' . $midEnrol . ' lote fallido: ' . $msgLote);
                }
            }
        }
    }

    // ✅ Auditoría de la matrícula masiva: cursos=X, usuarios=Y, ok=Z...
    admin_audit_log($conexion, 'curso_enrol', null, null,
        json_encode([
            'segmento' => $segmento,
            'cursos'   => count($idsEnrol),
            'usuarios' => $totalesEnrol['usuarios'],
            'ok'       => $totalesEnrol['ok'],
            'ya'       => $totalesEnrol['ya'],
            'err'      => $totalesEnrol['err'],
            'saltados' => $totalesEnrol['saltados'],
        ], JSON_UNESCAPED_UNICODE));

    // Nombres para la pantalla de resultado (degradación elegante si falla)
    $nombresResultado = admin_cursos_nombres_moodle();
    $cursosResultado  = [];
    foreach ($idsEnrol as $cidRes) {
        $cursosResultado[] = [
            'id'     => $cidRes,
            'nombre' => $nombresResultado[$cidRes] ?? ('Curso Moodle #' . $cidRes),
        ];
    }

    $cursoEnrolResultado = [
        'cursos'   => $cursosResultado,
        'stats'    => $statsPorCurso,
        'totales'  => $totalesEnrol,
        'segmento' => $segmento,
    ];
    // Sin redirect: la sección 'cursos' renderiza la pantalla de resultado.
}

// ── Obtener estadisticas globales ──
// 🔧 FIX: cada stat en su propio try/catch. Si una query falla (columna
// inexistente, tabla ausente, etc.), las demás siguen calculándose en
// lugar de dejar todo el array $stats vacío.
$stats = [];

$safeStat = function (string $key, callable $fn, $default = 0) use (&$stats) {
    try {
        $stats[$key] = $fn();
    } catch (Throwable $e) {
        error_log("[ADMIN] stat '$key' falló: " . $e->getMessage());
        $stats[$key] = $default;
    }
};

// ✅ PT7: consulta escalar con prepared statement (sin parámetros de usuario,
// pero siempre prepare/execute para cumplir la regla del backend).
$adminScalar = function (string $sql) use ($conexion) {
    $st = $conexion->prepare($sql);
    $st->execute();
    return $st->fetchColumn();
};

// ✅ PT7: consulta de filas con prepared statement (mismo criterio).
$adminFilas = function (string $sql) use ($conexion): array {
    $st = $conexion->prepare($sql);
    $st->execute();
    return $st->fetchAll(PDO::FETCH_ASSOC);
};

$safeStat('total_users', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE email_verificado = 1")->fetchColumn());

$safeStat('active_users_7d', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE ultimo_login >= DATE_SUB(NOW(), INTERVAL 7 DAY)")->fetchColumn());

$safeStat('active_users_today', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE ultimo_login >= CURDATE()")->fetchColumn());

$safeStat('total_simulacros', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM simulacro_resultados")->fetchColumn());

$safeStat('avg_score', fn() =>
    round((float)$conexion->query("SELECT AVG(puntaje_global) FROM simulacro_resultados")->fetchColumn(), 1));

$safeStat('premium_users', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE access_level IN ('premium', 'early_bird')")->fetchColumn());

$safeStat('free_users', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE access_level = 'free'")->fetchColumn());

// 🔧 FIX: la tabla `challenges` usa `status` (enum en español), no `estado`.
// Valores válidos: 'pendiente','en_curso','finalizado','eliminado'.
$safeStat('total_challenges', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM challenges WHERE status = 'finalizado'")->fetchColumn());

$safeStat('total_xp', fn() =>
    (int)$conexion->query("SELECT COALESCE(SUM(total_xp), 0) FROM user_gamification")->fetchColumn());

$safeStat('notifications_today', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM notifications WHERE DATE(created_at) = CURDATE()")->fetchColumn());

$safeStat('new_users_today', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE DATE(registration_date) = CURDATE()")->fetchColumn());

$safeStat('new_users_week', fn() =>
    (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE registration_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)")->fetchColumn());

// ── ✅ PT7: Administration & Intelligence Center — salud del negocio ──
$safeStat('total_users_all', fn() =>
    (int)$adminScalar("SELECT COUNT(*) FROM usuarios"));

$safeStat('conversion_premium', fn() =>
    round((float)$adminScalar("SELECT ROUND(100 * SUM(access_level IN ('premium', 'early_bird')) / COUNT(*), 1) FROM usuarios"), 1));

$safeStat('tiempo_medio_simulacro', fn() =>
    (int)round((float)$adminScalar("SELECT AVG(tiempo_empleado) FROM simulacro_resultados")));

// ── ✅ PT7: serie diaria de 30 días con degradación elegante (patrón $safeStat).
// Devuelve ['ok' => bool, 'dias' => ['Y-m-d' => valor], 'total' => int].
// Rellena los días sin datos con 0 para que el gráfico sea continuo.
$adminSerie30d = function (string $sql) use ($conexion): array {
    $dias = [];
    for ($i = 29; $i >= 0; $i--) {
        $dias[date('Y-m-d', strtotime("-{$i} days"))] = 0;
    }
    try {
        $stmt = $conexion->prepare($sql);
        $stmt->execute();
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $fila) {
            $clave = (string)($fila['d'] ?? '');
            if ($clave !== '' && array_key_exists($clave, $dias)) {
                $dias[$clave] = (int)$fila['c'];
            }
        }
        return ['ok' => true, 'dias' => $dias, 'total' => array_sum($dias)];
    } catch (Throwable $e) {
        error_log('[ADMIN] serie 30d falló: ' . $e->getMessage());
        return ['ok' => false, 'dias' => $dias, 'total' => 0];
    }
};

/**
 * ✅ PT7: gráfico SVG inline (línea + área rellena) — 100% de ancho, ~160px
 * de alto, generado 100% en PHP: cero JS, cero CDN. $dias: ['Y-m-d' => valor]
 * (se asumen 30 puntos consecutivos; $titulo para accesibilidad).
 */
function admin_svg_serie(array $dias, string $color, string $titulo): string
{
    $fechas = array_keys($dias);
    $valores = array_values($dias);
    $n = count($valores);
    if ($n < 2) {
        $fechas = ['x', 'y'];
        $valores = [0, 0];
        $n = 2;
    }
    $max = max(1, max($valores));

    $w = 720; $h = 160;
    $padIzq = 12; $padDer = 12; $padSup = 16; $padInf = 24;
    $anchoUtil = $w - $padIzq - $padDer;
    $altoUtil = $h - $padSup - $padInf;
    $baseY = $padSup + $altoUtil;
    $paso = $anchoUtil / ($n - 1);

    $puntos = [];
    foreach ($valores as $i => $v) {
        $puntos[] = [$padIzq + $i * $paso, $baseY - ($v / $max) * $altoUtil];
    }

    $trazo = '';
    foreach ($puntos as $p) {
        $trazo .= sprintf(' L%.1f,%.1f', $p[0], $p[1]);
    }
    $primero = $puntos[0];
    $ultimo = $puntos[count($puntos) - 1];
    $area = sprintf('M%.1f,%.1f%s L%.1f,%.1f Z', $primero[0], $baseY, $trazo, $ultimo[0], $baseY);
    $polilinea = implode(' ', array_map(
        fn($p) => sprintf('%.1f,%.1f', $p[0], $p[1]),
        $puntos
    ));

    $fechaIni = htmlspecialchars((string)reset($fechas), ENT_QUOTES, 'UTF-8');
    $fechaFin = htmlspecialchars((string)end($fechas), ENT_QUOTES, 'UTF-8');
    $tituloSvg = htmlspecialchars($titulo, ENT_QUOTES, 'UTF-8');
    $colorSeguro = htmlspecialchars($color, ENT_QUOTES, 'UTF-8');

    $svg = '<svg viewBox="0 0 ' . $w . ' ' . $h . '" style="width:100%; height:auto; display:block;" role="img" aria-label="' . $tituloSvg . '">';
    // Líneas guía horizontales (misma paleta atenuada del panel)
    foreach ([0, 0.5, 1] as $fraccion) {
        $y = $baseY - $fraccion * $altoUtil;
        $svg .= '<line x1="' . $padIzq . '" y1="' . sprintf('%.1f', $y) . '" x2="' . ($w - $padDer) . '" y2="' . sprintf('%.1f', $y) . '" stroke="#e2e8f0" stroke-width="1" stroke-dasharray="4,4" />';
    }
    $svg .= '<path d="' . $area . '" fill="' . $colorSeguro . '" fill-opacity="0.12" />';
    $svg .= '<polyline points="' . $polilinea . '" fill="none" stroke="' . $colorSeguro . '" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round" />';
    // Punto de énfasis en el último valor
    $svg .= '<circle cx="' . sprintf('%.1f', $ultimo[0]) . '" cy="' . sprintf('%.1f', $ultimo[1]) . '" r="4" fill="' . $colorSeguro . '" />';
    // Etiquetas: máximo, fechas extremos
    $svg .= '<text x="' . $padIzq . '" y="' . ($padSup - 4) . '" font-size="10" fill="#94A3B8">' . number_format($max) . '</text>';
    $svg .= '<text x="' . $padIzq . '" y="' . ($h - 6) . '" font-size="10" fill="#94A3B8">' . $fechaIni . '</text>';
    $svg .= '<text x="' . ($w - $padDer) . '" y="' . ($h - 6) . '" font-size="10" fill="#94A3B8" text-anchor="end">' . $fechaFin . '</text>';
    $svg .= '</svg>';
    return $svg;
}
?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Saber+ Admin</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f4f6fa; color: #1a1a2e; }
        .sidebar { position: fixed; left: 0; top: 0; width: 240px; height: 100vh; background: #1E4ED8; color: white; padding: 24px 0; overflow-y: auto; z-index: 100; }
        .sidebar-header { text-align: center; margin-bottom: 32px; }
        .sidebar-header h1 { font-size: 22px; font-weight: 800; }
        .sidebar-header p { font-size: 11px; opacity: 0.7; }
        .nav-item { display: flex; align-items: center; gap: 12px; padding: 12px 24px; color: rgba(255,255,255,0.8); text-decoration: none; font-size: 14px; font-weight: 500; transition: 0.2s; border-left: 3px solid transparent; }
        .nav-item:hover, .nav-item.active { background: rgba(255,255,255,0.1); color: white; border-left-color: #FACC15; }
        .nav-icon { font-size: 18px; width: 24px; text-align: center; }
        .main-content { margin-left: 240px; padding: 32px; min-height: 100vh; }
        .header-bar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 32px; }
        .header-bar h2 { font-size: 24px; font-weight: 800; }
        .logout-btn { background: #EF4444; color: white; padding: 8px 16px; border-radius: 8px; text-decoration: none; font-size: 13px; font-weight: 600; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; margin-bottom: 32px; }
        .stat-card { background: white; border-radius: 16px; padding: 24px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }
        .stat-card .stat-icon { width: 48px; height: 48px; border-radius: 12px; display: flex; align-items: center; justify-content: center; font-size: 24px; margin-bottom: 12px; }
        .stat-card .stat-value { font-size: 32px; font-weight: 800; }
        .stat-card .stat-label { font-size: 13px; color: #888; margin-top: 4px; }
        .stat-card .stat-change { font-size: 12px; margin-top: 8px; }
        .stat-up { color: #22C55E; }
        .stat-down { color: #EF4444; }
        .table-container { background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.06); margin-bottom: 24px; }
        table { width: 100%; border-collapse: collapse; }
        th { background: #f8fafc; padding: 12px 16px; text-align: left; font-size: 12px; font-weight: 700; color: #64748b; text-transform: uppercase; }
        td { padding: 12px 16px; border-top: 1px solid #f1f5f9; font-size: 14px; }
        tr:hover td { background: #f8fafc; }
        .badge { display: inline-block; padding: 4px 10px; border-radius: 20px; font-size: 11px; font-weight: 700; }
        .badge-green { background: #D1FAE5; color: #065F46; }
        .badge-blue { background: #DBEAFE; color: #1E40AF; }
        .badge-orange { background: #FED7AA; color: #9A3412; }
        .badge-purple { background: #E9D5FF; color: #6B21A8; }
        .section-card { background: white; border-radius: 16px; padding: 24px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); margin-bottom: 24px; }
        .section-title { font-size: 18px; font-weight: 700; margin-bottom: 16px; }
        .btn { display: inline-block; padding: 10px 20px; border-radius: 10px; font-size: 14px; font-weight: 600; text-decoration: none; cursor: pointer; border: none; transition: 0.2s; }
        .btn-primary { background: #1E4ED8; color: white; }
        .btn-success { background: #22C55E; color: white; }
        .btn-danger { background: #EF4444; color: white; }
        .btn:hover { opacity: 0.9; }
        .form-group { margin-bottom: 16px; }
        .form-group label { display: block; font-size: 13px; font-weight: 600; margin-bottom: 6px; color: #555; }
        .form-group input, .form-group select, .form-group textarea { width: 100%; padding: 10px 14px; border: 2px solid #e2e8f0; border-radius: 10px; font-size: 14px; }
        .form-group input:focus, .form-group select:focus { outline: none; border-color: #1E4ED8; }
        .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }
        .badge-red { background: #FEE2E2; color: #991B1B; }
        .badge-gray { background: #E5E7EB; color: #374151; }
        .badge-yellow { background: #FEF3C7; color: #92400E; }
        .mono { font-family: ui-monospace, 'SF Mono', Menlo, Consolas, monospace; font-size: 12px; }
        .bar-row { display: flex; align-items: center; gap: 10px; margin-bottom: 6px; }
        .bar-label { width: 84px; font-size: 12px; color: #64748b; text-align: right; flex-shrink: 0; }
        .bar-track { flex: 1; background: #f1f5f9; border-radius: 6px; height: 18px; overflow: hidden; }
        .bar-fill { height: 100%; background: #1E4ED8; border-radius: 6px; min-width: 2px; }
        .bar-fill.green { background: #22C55E; }
        .bar-value { width: 46px; font-size: 12px; font-weight: 700; color: #334155; flex-shrink: 0; }
        .muted { color: #94A3B8; font-size: 13px; }
        .flash { padding: 12px 18px; border-radius: 12px; margin-bottom: 20px; font-size: 14px; font-weight: 600; }
        .flash-ok { background: #D1FAE5; color: #065F46; }
        .flash-err { background: #FEE2E2; color: #991B1B; }
        @media (max-width: 768px) { .sidebar { display: none; } .main-content { margin-left: 0; padding: 16px; } .grid-2 { grid-template-columns: 1fr; } }
    </style>
</head>
<body>

<!-- Sidebar -->
<div class="sidebar">
    <div class="sidebar-header">
        <h1>Saber+</h1>
        <p>Panel Admin</p>
    </div>
    <a href="index.php" class="nav-item <?= $section === 'dashboard' ? 'active' : '' ?>"><span class="nav-icon">&#128202;</span> Dashboard</a>
    <a href="index.php?section=users" class="nav-item <?= $section === 'users' ? 'active' : '' ?>"><span class="nav-icon">&#128100;</span> Usuarios</a>
    <a href="index.php?section=colegios" class="nav-item <?= $section === 'colegios' ? 'active' : '' ?>"><span class="nav-icon">&#127979;</span> Colegios</a>
    <a href="index.php?section=cursos" class="nav-item <?= $section === 'cursos' ? 'active' : '' ?>"><span class="nav-icon">&#128218;</span> Cursos Moodle</a>
    <a href="index.php?section=ads" class="nav-item <?= $section === 'ads' ? 'active' : '' ?>"><span class="nav-icon">&#128227;</span> Anuncios</a>
    <a href="index.php?section=plans" class="nav-item <?= $section === 'plans' ? 'active' : '' ?>"><span class="nav-icon">&#128179;</span> Planes</a>
    <a href="index.php?section=promociones" class="nav-item <?= $section === 'promociones' ? 'active' : '' ?>"><span class="nav-icon">&#127873;</span> Promociones</a>
    <a href="index.php?section=codigos" class="nav-item <?= $section === 'codigos' ? 'active' : '' ?>"><span class="nav-icon">&#127903;</span> Códigos Premium</a>
    <a href="index.php?section=notifications" class="nav-item <?= $section === 'notifications' ? 'active' : '' ?>"><span class="nav-icon">&#128276;</span> Notificaciones</a>
    <a href="index.php?section=soporte" class="nav-item <?= $section === 'soporte' ? 'active' : '' ?>"><span class="nav-icon">&#128172;</span> Soporte</a>
    <a href="index.php?section=analytics" class="nav-item <?= $section === 'analytics' ? 'active' : '' ?>"><span class="nav-icon">&#128200;</span> Analítica</a>
    <a href="index.php?section=ingresos" class="nav-item <?= $section === 'ingresos' ? 'active' : '' ?>"><span class="nav-icon">&#128176;</span> Ingresos</a>
    <a href="index.php?section=academica" class="nav-item <?= $section === 'academica' ? 'active' : '' ?>"><span class="nav-icon">&#127891;</span> Académica</a>
    <a href="index.php?section=errors" class="nav-item <?= $section === 'errors' ? 'active' : '' ?>"><span class="nav-icon">&#9888;</span> Errores</a>
    <a href="index.php?section=activity" class="nav-item <?= $section === 'activity' ? 'active' : '' ?>"><span class="nav-icon">&#128293;</span> Actividad</a>
    <a href="index.php?section=rankings" class="nav-item <?= $section === 'rankings' ? 'active' : '' ?>"><span class="nav-icon">&#127942;</span> Rankings Inst.</a>
    <a href="index.php?section=reports" class="nav-item <?= $section === 'reports' ? 'active' : '' ?>"><span class="nav-icon">&#128196;</span> Reportes</a>
    <a href="index.php?section=config" class="nav-item <?= $section === 'config' ? 'active' : '' ?>"><span class="nav-icon">&#9881;</span> Configuracion</a>
    <a href="index.php?section=auditoria" class="nav-item <?= $section === 'auditoria' ? 'active' : '' ?>"><span class="nav-icon">&#128220;</span> Auditoría</a>
    <a href="index.php?logout=1" class="nav-item" style="margin-top: 32px; color: rgba(255,255,255,0.5);"><span class="nav-icon">&#10148;</span> Cerrar Sesion</a>
</div>

<!-- Main Content -->
<div class="main-content">
    <div class="header-bar">
        <?php
        // ✅ PT7: títulos legibles para las secciones nuevas del Intelligence
        // Center (fallback al patrón existente ucfirst para el resto).
        $titulosAdmin = [
            'ingresos'  => 'Ingresos',
            'academica' => 'Analítica Educativa',
            'auditoria' => 'Auditoría',
            'codigos'   => 'Códigos Premium',
            'cursos'    => 'Cursos Moodle',
        ];
        $tituloAdmin = $titulosAdmin[$section] ?? ucfirst($section === 'dashboard' ? 'Dashboard' : $section);
        ?>
        <h2><?= htmlspecialchars($tituloAdmin) ?></h2>
        <a href="index.php?logout=1" class="logout-btn">Cerrar Sesion</a>
    </div>

    <?php if ($section === 'dashboard'): ?>
        <!-- DASHBOARD -->
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-icon" style="background: #DBEAFE;">&#128100;</div>
                <div class="stat-value"><?= $stats['total_users'] ?></div>
                <div class="stat-label">Usuarios Registrados</div>
                <div class="stat-change stat-up">+<?= $stats['new_users_week'] ?> esta semana</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #D1FAE5;">&#128640;</div>
                <div class="stat-value"><?= $stats['active_users_today'] ?></div>
                <div class="stat-label">Activos Hoy</div>
                <div class="stat-change">Activos 7 dias: <?= $stats['active_users_7d'] ?></div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #FEF3C7;">&#128221;</div>
                <div class="stat-value"><?= $stats['total_simulacros'] ?></div>
                <div class="stat-label">Simulacros Realizados</div>
                <div class="stat-change">Promedio: <?= $stats['avg_score'] ?></div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #E9D5FF;">&#11088;</div>
                <div class="stat-value"><?= $stats['premium_users'] ?></div>
                <div class="stat-label">Usuarios Premium</div>
                <div class="stat-change">Free: <?= $stats['free_users'] ?></div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #FED7AA;">&#9889;</div>
                <div class="stat-value"><?= number_format($stats['total_xp']) ?></div>
                <div class="stat-label">XP Distribuida</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #FEE2E2;">&#128276;</div>
                <div class="stat-value"><?= $stats['notifications_today'] ?></div>
                <div class="stat-label">Notificaciones Hoy</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #DBEAFE;">&#128101;</div>
                <div class="stat-value"><?= $stats['new_users_today'] ?></div>
                <div class="stat-label">Nuevos Hoy</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #D1FAE5;">&#127942;</div>
                <div class="stat-value"><?= $stats['total_challenges'] ?></div>
                <div class="stat-label">Retos Completados</div>
            </div>
        </div>

        <!-- ✅ PT7: DASHBOARD EJECUTIVO — series de 30 días (SVG inline, sin JS) -->
        <?php
        // Columnas reales verificadas en el código existente:
        // usuarios.registration_date · simulacro_resultados.fecha_realizacion ·
        // xp_transactions.created_at · user_daily_activity.activity_date
        $serieRegistros  = $adminSerie30d("SELECT DATE(registration_date) AS d, COUNT(*) AS c FROM usuarios WHERE registration_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) GROUP BY DATE(registration_date)");
        $serieSimulacros = $adminSerie30d("SELECT DATE(fecha_realizacion) AS d, COUNT(*) AS c FROM simulacro_resultados WHERE fecha_realizacion >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) GROUP BY DATE(fecha_realizacion)");
        $serieXp         = $adminSerie30d("SELECT DATE(created_at) AS d, SUM(xp_amount) AS c FROM xp_transactions WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) AND xp_amount > 0 GROUP BY DATE(created_at)");
        // DAU aproximado (migración 002): si la tabla no existe → tarjeta oculta
        $serieDau        = $adminSerie30d("SELECT DATE(activity_date) AS d, COUNT(DISTINCT user_id) AS c FROM user_daily_activity WHERE activity_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) GROUP BY DATE(activity_date)");
        ?>
        <div class="grid-2">
            <div class="section-card">
                <h3 class="section-title">&#128100; Nuevos registros por día</h3>
                <p class="muted" style="margin-bottom:8px;">Últimos 30 días · Total: <strong><?= number_format($serieRegistros['total']) ?></strong> usuarios</p>
                <?php if ($serieRegistros['ok']): ?>
                    <?= admin_svg_serie($serieRegistros['dias'], '#1E4ED8', 'Nuevos registros por día') ?>
                <?php else: ?>
                    <p class="muted">Serie no disponible en este momento (consulta fallida — revisa el log).</p>
                <?php endif; ?>
            </div>
            <div class="section-card">
                <h3 class="section-title">&#128221; Simulacros por día</h3>
                <p class="muted" style="margin-bottom:8px;">Últimos 30 días · Total: <strong><?= number_format($serieSimulacros['total']) ?></strong> simulacros</p>
                <?php if ($serieSimulacros['ok']): ?>
                    <?= admin_svg_serie($serieSimulacros['dias'], '#22C55E', 'Simulacros por día') ?>
                <?php else: ?>
                    <p class="muted">Serie no disponible en este momento (consulta fallida — revisa el log).</p>
                <?php endif; ?>
            </div>
            <div class="section-card">
                <h3 class="section-title">&#9889; XP otorgada por día</h3>
                <p class="muted" style="margin-bottom:8px;">Últimos 30 días · Total: <strong><?= number_format($serieXp['total']) ?></strong> XP</p>
                <?php if ($serieXp['ok']): ?>
                    <?= admin_svg_serie($serieXp['dias'], '#F59E0B', 'XP otorgada por día') ?>
                <?php else: ?>
                    <p class="muted">Serie no disponible (tabla <code>xp_transactions</code> ausente — migración 002).</p>
                <?php endif; ?>
            </div>
            <?php if ($serieDau['ok']): ?>
            <div class="section-card">
                <h3 class="section-title">&#128293; Actividad reciente (usuarios únicos/día)</h3>
                <p class="muted" style="margin-bottom:8px;">DAU aproximado · Últimos 30 días</p>
                <?= admin_svg_serie($serieDau['dias'], '#8B5CF6', 'Usuarios únicos activos por día') ?>
            </div>
            <?php endif; ?>
        </div>

        <!-- ✅ PT7: mini-grid "Salud del negocio" -->
        <?php
        $tiempoSeg = (int)($stats['tiempo_medio_simulacro'] ?? 0);
        $tiempoTxt = $tiempoSeg >= 3600
            ? floor($tiempoSeg / 3600) . ' h ' . round(($tiempoSeg % 3600) / 60) . ' min'
            : max(1, (int)round($tiempoSeg / 60)) . ' min';
        ?>
        <div class="stats-grid" style="grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));">
            <div class="stat-card">
                <div class="stat-icon" style="background: #E9D5FF;">&#128176;</div>
                <div class="stat-value"><?= number_format((float)($stats['conversion_premium'] ?? 0), 1) ?>%</div>
                <div class="stat-label">Conversión a Premium</div>
                <div class="stat-change"><?= $stats['premium_users'] ?> premium / <?= number_format($stats['total_users_all']) ?> usuarios</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #DBEAFE;">&#127891;</div>
                <div class="stat-value"><?= $stats['avg_score'] ?></div>
                <div class="stat-label">Promedio Global Simulacros</div>
                <div class="stat-change">Escala ICFES 0–500</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #D1FAE5;">&#9201;</div>
                <div class="stat-value"><?= htmlspecialchars($tiempoTxt) ?></div>
                <div class="stat-label">Tiempo Medio por Simulacro</div>
                <div class="stat-change">Promedio de tiempo_empleado</div>
            </div>
        </div>

        <!-- Top 10 usuarios -->
        <div class="table-container">
            <table>
                <thead><tr><th>#</th><th>Usuario</th><th>Email</th><th>XP</th><th>Nivel</th><th>Racha</th><th>Plan</th><th>Ultimo Login</th></tr></thead>
                <tbody>
                <?php
                $topUsers = $conexion->query("
                    SELECT u.nombre, u.email, u.access_level, u.ultimo_login,
                           COALESCE(ug.total_xp, 0) as xp, COALESCE(ug.current_level, 1) as level,
                           COALESCE(ug.current_streak, 0) as streak
                    FROM usuarios u
                    LEFT JOIN user_gamification ug ON u.id_usuario = ug.user_id
                    WHERE u.email_verificado = 1
                    ORDER BY xp DESC LIMIT 10
                ")->fetchAll(PDO::FETCH_ASSOC);
                foreach ($topUsers as $i => $u):
                ?>
                    <tr>
                        <td><?= $i + 1 ?></td>
                        <td><?= htmlspecialchars($u['nombre']) ?></td>
                        <td><?= htmlspecialchars($u['email']) ?></td>
                        <td><strong><?= number_format($u['xp']) ?></strong></td>
                        <td>Nivel <?= $u['level'] ?></td>
                        <td><?= $u['streak'] ?> dias</td>
                        <td><span class="badge <?= $u['access_level'] === 'premium' ? 'badge-purple' : 'badge-blue' ?>"><?= ucfirst($u['access_level']) ?></span></td>
                        <td><?= $u['ultimo_login'] ?? 'Nunca' ?></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>

    <?php elseif ($section === 'users'):
        // ── USUARIOS (v1.7.0: búsqueda + edición de perfil) ──
        $q = trim((string)($_GET['q'] ?? ''));
        $editId = (int)($_GET['edit'] ?? 0);

        // Mensajes flash
        $msgsUsers = [
            'user_guardado'        => ['ok',  'Perfil actualizado correctamente.'],
            'user_datos_invalidos' => ['err', 'Datos inválidos: nombre y correo válido son obligatorios.'],
            'user_email_duplicado' => ['err', 'Ya existe otro usuario con ese correo.'],
            'user_error_bd'        => ['err', 'Error de base de datos. Revisa el log del servidor.'],
        ];
        $msgKeyU = (string)($_GET['msg'] ?? '');
        if ($msgKeyU !== '' && isset($msgsUsers[$msgKeyU])): ?>
            <div class="flash flash-<?= $msgsUsers[$msgKeyU][0] ?>"><?= $msgsUsers[$msgKeyU][1] ?></div>
        <?php endif;

        if ($editId > 0):
            // ── Formulario de edición de usuario ──
            $stmt = $conexion->prepare("
                SELECT id_usuario, moodle_id, nombre, email, telefono, departamento, ciudad,
                       colegio, grado, tipo_usuario, access_level, email_verificado,
                       registration_date, ultimo_login
                FROM usuarios WHERE id_usuario = :id LIMIT 1
            ");
            $stmt->execute([':id' => $editId]);
            $eu = $stmt->fetch(PDO::FETCH_ASSOC);
            $euActivo = 1;
            if ($eu) {
                try {
                    $stmtA = $conexion->prepare("SELECT activo FROM usuarios WHERE id_usuario = :id");
                    $stmtA->execute([':id' => $editId]);
                    $euActivo = (int)($stmtA->fetchColumn() ?: 1);
                } catch (Exception $exA) { /* columna aún no migrada */ }
            }
        ?>
        <?php if (!$eu): ?>
            <div class="section-card"><p>Usuario no encontrado. <a href="index.php?section=users">Volver al listado</a>.</p></div>
        <?php else: ?>
            <div class="section-card">
                <h3 class="section-title">&#9998; Editar usuario #<?= (int)$eu['id_usuario'] ?></h3>
                <p class="muted" style="margin-bottom:16px;">
                    Registro: <?= htmlspecialchars((string)$eu['registration_date']) ?> ·
                    Último login: <?= htmlspecialchars((string)($eu['ultimo_login'] ?? 'Nunca')) ?> ·
                    Moodle ID: <?= (int)($eu['moodle_id'] ?? 0) ?>
                </p>
                <form method="POST">
                    <?= admin_csrf_field() ?>
                    <input type="hidden" name="user_id" value="<?= (int)$eu['id_usuario'] ?>">
                    <div class="grid-2">
                        <div class="form-group"><label>Nombre completo</label>
                            <input type="text" name="nombre" required value="<?= htmlspecialchars($eu['nombre']) ?>"></div>
                        <div class="form-group"><label>Correo electrónico</label>
                            <input type="email" name="email" required value="<?= htmlspecialchars($eu['email']) ?>"></div>
                        <div class="form-group"><label>Teléfono</label>
                            <input type="text" name="telefono" value="<?= htmlspecialchars($eu['telefono'] ?? '') ?>"></div>
                        <div class="form-group"><label>Departamento</label>
                            <input type="text" name="departamento" value="<?= htmlspecialchars($eu['departamento'] ?? '') ?>"></div>
                        <div class="form-group"><label>Ciudad</label>
                            <input type="text" name="ciudad" value="<?= htmlspecialchars($eu['ciudad'] ?? '') ?>"></div>
                        <div class="form-group"><label>Colegio</label>
                            <input type="text" name="colegio" value="<?= htmlspecialchars($eu['colegio'] ?? '') ?>"></div>
                        <div class="form-group"><label>Grado</label>
                            <input type="text" name="grado" value="<?= htmlspecialchars($eu['grado'] ?? '') ?>"></div>
                        <div class="form-group"><label>Tipo de usuario</label>
                            <select name="tipo_usuario">
                                <?php foreach (['estudiante', 'profesor', 'admin'] as $tp): ?>
                                    <option value="<?= $tp ?>" <?= $eu['tipo_usuario'] === $tp ? 'selected' : '' ?>><?= ucfirst($tp) ?></option>
                                <?php endforeach; ?>
                            </select></div>
                        <div class="form-group"><label>Nivel de acceso (plan)</label>
                            <select name="access_level">
                                <?php foreach (['free', 'premium', 'early_bird'] as $al): ?>
                                    <option value="<?= $al ?>" <?= $eu['access_level'] === $al ? 'selected' : '' ?>><?= ucfirst($al) ?></option>
                                <?php endforeach; ?>
                            </select></div>
                        <div class="form-group" style="display:flex; align-items:center; gap:24px; padding-top:26px;">
                            <label style="display:flex; align-items:center; gap:8px; margin:0;">
                                <input type="checkbox" name="email_verificado" style="width:auto;" <?= $eu['email_verificado'] ? 'checked' : '' ?>> Email verificado
                            </label>
                            <label style="display:flex; align-items:center; gap:8px; margin:0;">
                                <input type="checkbox" name="activo" style="width:auto;" <?= $euActivo ? 'checked' : '' ?>> Cuenta activa
                            </label>
                        </div>
                    </div>
                    <div style="display:flex; gap:12px; margin-top:8px;">
                        <button type="submit" name="user_save" value="1" class="btn btn-primary">Guardar cambios</button>
                        <a href="index.php?section=users&q=<?= urlencode($q) ?>" class="btn" style="background:#e2e8f0; color:#334155;">Cancelar</a>
                    </div>
                </form>
            </div>
        <?php endif; ?>

        <?php else: ?>
        <!-- Listado con búsqueda -->
        <div class="section-card" style="padding:16px 20px;">
            <form method="GET" action="index.php" style="display:flex; gap:12px; align-items:center; flex-wrap:wrap;">
                <input type="hidden" name="section" value="users">
                <input type="text" name="q" placeholder="Buscar por nombre, correo o ID..." value="<?= htmlspecialchars($q) ?>" style="flex:1; min-width:220px; padding:10px 14px; border:2px solid #e2e8f0; border-radius:10px; font-size:14px;">
                <button type="submit" class="btn btn-primary">Buscar</button>
                <?php if ($q !== ''): ?>
                    <a href="index.php?section=users" class="btn" style="background:#e2e8f0; color:#334155;">Limpiar</a>
                <?php endif; ?>
                <!-- ✅ PT7: exportación CSV del listado de usuarios -->
                <a href="export_csv.php?type=usuarios" class="btn btn-success">&#11015; Exportar CSV</a>
            </form>
        </div>
        <div class="table-container">
            <table>
                <thead><tr><th>ID</th><th>Nombre</th><th>Email</th><th>Tipo</th><th>Plan</th><th>Verificado</th><th>Ciudad</th><th>Colegio</th><th>Registro</th><th>Ultimo Login</th><th></th></tr></thead>
                <tbody>
                <?php
                try {
                    if ($q !== '') {
                        $stmt = $conexion->prepare("
                            SELECT id_usuario, nombre, email, tipo_usuario, access_level,
                                   email_verificado, ciudad, colegio, registration_date, ultimo_login
                            FROM usuarios
                            WHERE nombre LIKE :q OR email LIKE :q OR id_usuario = :qid
                            ORDER BY id_usuario DESC LIMIT 100
                        ");
                        $stmt->execute([':q' => '%' . $q . '%', ':qid' => (int)$q]);
                    } else {
                        $stmt = $conexion->prepare("
                            SELECT id_usuario, nombre, email, tipo_usuario, access_level,
                                   email_verificado, ciudad, colegio, registration_date, ultimo_login
                            FROM usuarios ORDER BY id_usuario DESC LIMIT 100
                        ");
                        $stmt->execute();
                    }
                    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);
                } catch (Exception $exU) {
                    $users = $conexion->query("
                        SELECT id_usuario, nombre, email, tipo_usuario, access_level,
                               email_verificado, ciudad, colegio, registration_date, ultimo_login
                        FROM usuarios ORDER BY id_usuario DESC LIMIT 100
                    ")->fetchAll(PDO::FETCH_ASSOC);
                }
                foreach ($users as $u):
                ?>
                    <tr>
                        <td><?= $u['id_usuario'] ?></td>
                        <td><?= htmlspecialchars($u['nombre']) ?></td>
                        <td><?= htmlspecialchars($u['email']) ?></td>
                        <td><?= ucfirst($u['tipo_usuario']) ?></td>
                        <td><span class="badge <?= $u['access_level'] === 'premium' ? 'badge-purple' : 'badge-blue' ?>"><?= ucfirst($u['access_level']) ?></span></td>
                        <td><?= $u['email_verificado'] ? '<span class="badge badge-green">Si</span>' : '<span class="badge badge-orange">No</span>' ?></td>
                        <td><?= htmlspecialchars($u['ciudad'] ?? '-') ?></td>
                        <td><?= htmlspecialchars($u['colegio'] ?? '-') ?></td>
                        <td><?= $u['registration_date'] ?? '-' ?></td>
                        <td><?= $u['ultimo_login'] ?? 'Nunca' ?></td>
                        <td><a class="btn btn-primary" style="padding:6px 12px; font-size:12px;" href="index.php?section=users&edit=<?= $u['id_usuario'] ?>&q=<?= urlencode($q) ?>">Editar</a></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>
        <?php endif; ?>

    <?php elseif ($section === 'promociones'):
        // ── PROMOCIONES (v1.7.0) ──
        $promoEdit = null;
        $editPromoId = (int)($_GET['edit'] ?? 0);
        $promosDisponibles = true;
        try {
            $promos = $conexion->query("SELECT * FROM promociones ORDER BY id DESC")->fetchAll(PDO::FETCH_ASSOC);
            $planesLista = $conexion->query("SELECT id, name FROM plans ORDER BY price ASC")->fetchAll(PDO::FETCH_ASSOC);
            if ($editPromoId > 0) {
                $stmtPE = $conexion->prepare("SELECT * FROM promociones WHERE id = :id");
                $stmtPE->execute([':id' => $editPromoId]);
                $promoEdit = $stmtPE->fetch(PDO::FETCH_ASSOC);
            }
        } catch (Exception $exP) {
            $promosDisponibles = false;
            $promos = [];
            $planesLista = [];
        }

        $msgsPromo = [
            'promo_creada'          => ['ok',  'Promoción creada. Se verá en la app de inmediato.'],
            'promo_actualizada'     => ['ok',  'Promoción actualizada.'],
            'promo_eliminada'       => ['ok',  'Promoción eliminada.'],
            'promo_estado'          => ['ok',  'Estado de la promoción actualizado.'],
            'promo_datos_invalidos' => ['err', 'Datos inválidos. Revisa título, descuento, código (mín. 4 caracteres) y fechas (fin > inicio).'],
            'promo_codigo_duplicado'=> ['err', 'Ya existe una promoción con ese código.'],
            'promo_error_bd'        => ['err', 'Error de base de datos. Revisa el log del servidor.'],
        ];
        $msgKeyP = (string)($_GET['msg'] ?? '');
        if ($msgKeyP !== '' && isset($msgsPromo[$msgKeyP])): ?>
            <div class="flash flash-<?= $msgsPromo[$msgKeyP][0] ?>"><?= $msgsPromo[$msgKeyP][1] ?></div>
        <?php endif; ?>

        <?php if (!$promosDisponibles): ?>
            <div class="section-card">
                <h3 class="section-title">Migración pendiente</h3>
                <p class="muted">Ejecuta <code>backend/migrations/006_promociones_quejas.sql</code> en MySQL para habilitar esta sección.</p>
            </div>
        <?php else: ?>

        <!-- Formulario crear/editar -->
        <div class="section-card">
            <h3 class="section-title"><?= $promoEdit ? '&#9998; Editar promoción #' . (int)$promoEdit['id'] : '&#127873; Nueva promoción' ?></h3>
            <p class="muted" style="margin-bottom:16px;">
                Los <strong>banners</strong> con descuento aparecen en la pantalla Premium del app al instante y se aplican automáticamente al pagar en la web (Wompi).
                Los <strong>códigos</strong> los escribe el usuario al pagar en la web.
                <em>Nota Google Play: en Android los precios los fija Play Console — usa los códigos promociales de Play para equivalentes.</em>
            </p>
            <form method="POST">
                <?= admin_csrf_field() ?>
                <input type="hidden" name="promo_id" value="<?= (int)($promoEdit['id'] ?? 0) ?>">
                <div class="grid-2">
                    <div class="form-group"><label>Título *</label>
                        <input type="text" name="titulo" required maxlength="120" value="<?= htmlspecialchars($promoEdit['titulo'] ?? '') ?>" placeholder="Ej: Vuelta al cole -30%"></div>
                    <div class="form-group"><label>Descripción (opcional)</label>
                        <input type="text" name="descripcion" maxlength="255" value="<?= htmlspecialchars($promoEdit['descripcion'] ?? '') ?>" placeholder="Ej: 30% de descuento en el plan anual por inicio de clases"></div>
                    <div class="form-group"><label>Tipo</label>
                        <select name="tipo" id="promoTipo">
                            <option value="banner" <?= ($promoEdit['tipo'] ?? '') === 'banner' ? 'selected' : '' ?>>Banner (visible en el app)</option>
                            <option value="codigo" <?= ($promoEdit['tipo'] ?? '') === 'codigo' ? 'selected' : '' ?>>Código canjeable (web)</option>
                        </select></div>
                    <div class="form-group"><label>Código (solo tipo código)</label>
                        <div style="display:flex; gap:8px;">
                            <input type="text" name="codigo" id="promoCodigo" maxlength="40" value="<?= htmlspecialchars($promoEdit['codigo'] ?? '') ?>" placeholder="Ej: VUELTAALCOLE30">
                            <button type="button" class="btn" style="background:#e2e8f0; color:#334155; white-space:nowrap;" onclick="generarCodigo()">Generar</button>
                        </div></div>
                    <div class="form-group"><label>Tipo de descuento</label>
                        <select name="descuento_tipo">
                            <option value="porcentaje" <?= ($promoEdit['descuento_tipo'] ?? '') === 'porcentaje' ? 'selected' : '' ?>>Porcentaje (%)</option>
                            <option value="monto" <?= ($promoEdit['descuento_tipo'] ?? '') === 'monto' ? 'selected' : '' ?>>Monto fijo (COP)</option>
                        </select></div>
                    <div class="form-group"><label>Valor del descuento *</label>
                        <input type="number" name="descuento_valor" step="any" min="1" required value="<?= htmlspecialchars((string)($promoEdit['descuento_valor'] ?? '')) ?>" placeholder="Ej: 30"></div>
                    <div class="form-group"><label>Aplica a</label>
                        <select name="plan_id">
                            <option value="0">Todos los planes</option>
                            <?php foreach ($planesLista as $pl): ?>
                                <option value="<?= (int)$pl['id'] ?>" <?= (int)($promoEdit['plan_id'] ?? 0) === (int)$pl['id'] ? 'selected' : '' ?>><?= htmlspecialchars($pl['name']) ?></option>
                            <?php endforeach; ?>
                        </select></div>
                    <div class="form-group"><label>Usos máximos (vacío = ilimitado)</label>
                        <input type="number" name="max_usos" min="1" value="<?= htmlspecialchars((string)($promoEdit['max_usos'] ?? '')) ?>" placeholder="Ej: 100"></div>
                    <div class="form-group"><label>Fecha inicio *</label>
                        <input type="datetime-local" name="fecha_inicio" required value="<?= !empty($promoEdit['fecha_inicio']) ? date('Y-m-d\TH:i', strtotime($promoEdit['fecha_inicio'])) : date('Y-m-d\TH:i') ?>"></div>
                    <div class="form-group"><label>Fecha fin *</label>
                        <input type="datetime-local" name="fecha_fin" required value="<?= !empty($promoEdit['fecha_fin']) ? date('Y-m-d\TH:i', strtotime($promoEdit['fecha_fin'])) : date('Y-m-d\TH:i', strtotime('+30 days')) ?>"></div>
                </div>
                <div class="form-group" style="display:flex; align-items:center; gap:8px;">
                    <input type="checkbox" name="activo" id="promoActivo" style="width:auto;" <?= (int)($promoEdit['activo'] ?? 1) ? 'checked' : '' ?>>
                    <label for="promoActivo" style="margin:0;">Activa (visible y aplicable)</label>
                </div>
                <div style="display:flex; gap:12px;">
                    <button type="submit" name="promo_save" value="1" class="btn btn-primary"><?= $promoEdit ? 'Guardar cambios' : 'Crear promoción' ?></button>
                    <?php if ($promoEdit): ?>
                        <a href="index.php?section=promociones" class="btn" style="background:#e2e8f0; color:#334155;">Cancelar</a>
                    <?php endif; ?>
                </div>
            </form>
            <script>
                function generarCodigo() {
                    var pool = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
                    var out = '';
                    for (var i = 0; i < 10; i++) out += pool.charAt(Math.floor(Math.random() * pool.length));
                    document.getElementById('promoCodigo').value = out;
                }
            </script>
        </div>

        <!-- Listado -->
        <div class="table-container">
            <table>
                <thead><tr><th>ID</th><th>Título</th><th>Tipo</th><th>Descuento</th><th>Plan</th><th>Vigencia</th><th>Estado</th><th>Usos</th><th>Acciones</th></tr></thead>
                <tbody>
                <?php if (empty($promos)): ?>
                    <tr><td colspan="9" class="muted" style="text-align:center;padding:24px;">Aún no hay promociones. Crea la primera arriba.</td></tr>
                <?php else: foreach ($promos as $pr):
                    $ahora = time();
                    $tsIni = strtotime($pr['fecha_inicio']);
                    $tsFin = strtotime($pr['fecha_fin']);
                    $sinCupo = $pr['max_usos'] !== null && (int)$pr['usos'] >= (int)$pr['max_usos'];
                    if (!$pr['activo']) { $estadoTxt = 'Inactiva'; $estadoCls = 'badge-gray'; }
                    elseif ($sinCupo)  { $estadoTxt = 'Sin cupo'; $estadoCls = 'badge-red'; }
                    elseif ($ahora < $tsIni) { $estadoTxt = 'Programada'; $estadoCls = 'badge-blue'; }
                    elseif ($ahora > $tsFin) { $estadoTxt = 'Vencida'; $estadoCls = 'badge-orange'; }
                    else { $estadoTxt = 'Vigente'; $estadoCls = 'badge-green'; }
                ?>
                    <tr>
                        <td><?= (int)$pr['id'] ?></td>
                        <td><strong><?= htmlspecialchars($pr['titulo']) ?></strong><?= $pr['descripcion'] ? '<br><span class="muted">' . htmlspecialchars($pr['descripcion']) . '</span>' : '' ?></td>
                        <td><?= $pr['tipo'] === 'codigo'
                            ? '<span class="badge badge-purple">Código</span><br><code class="mono">' . htmlspecialchars($pr['codigo'] ?? '') . '</code>'
                            : '<span class="badge badge-blue">Banner</span>' ?></td>
                        <td><strong><?= $pr['descuento_tipo'] === 'porcentaje' ? rtrim(rtrim((string)$pr['descuento_valor'], '0'), '.') . '%' : '$' . number_format((float)$pr['descuento_valor']) . ' COP' ?></strong></td>
                        <td><?= $pr['plan_id'] ? 'Plan #' . (int)$pr['plan_id'] : 'Todos' ?></td>
                        <td class="muted" style="font-size:12px;"><?= date('d/m/Y H:i', $tsIni) ?><br>a <?= date('d/m/Y H:i', $tsFin) ?></td>
                        <td><span class="badge <?= $estadoCls ?>"><?= $estadoTxt ?></span></td>
                        <td><?= (int)$pr['usos'] ?><?= $pr['max_usos'] !== null ? ' / ' . (int)$pr['max_usos'] : '' ?></td>
                        <td style="white-space:nowrap;">
                            <a class="btn btn-primary" style="padding:6px 12px; font-size:12px;" href="index.php?section=promociones&edit=<?= (int)$pr['id'] ?>">Editar</a>
                            <form method="POST" style="display:inline;" onsubmit="return confirm('¿<?= $pr['activo'] ? 'Desactivar' : 'Activar' ?> esta promoción?');">
                                <?= admin_csrf_field() ?>
                                <input type="hidden" name="promo_id" value="<?= (int)$pr['id'] ?>">
                                <button type="submit" name="promo_toggle" value="1" class="btn <?= $pr['activo'] ? 'btn-danger' : 'btn-success' ?>" style="padding:6px 12px; font-size:12px;"><?= $pr['activo'] ? 'Desactivar' : 'Activar' ?></button>
                            </form>
                            <form method="POST" style="display:inline;" onsubmit="return confirm('¿ELIMINAR definitivamente esta promoción?');">
                                <?= admin_csrf_field() ?>
                                <input type="hidden" name="promo_id" value="<?= (int)$pr['id'] ?>">
                                <button type="submit" name="promo_delete" value="1" class="btn btn-danger" style="padding:6px 12px; font-size:12px;">Eliminar</button>
                            </form>
                        </td>
                    </tr>
                <?php endforeach; endif; ?>
                </tbody>
            </table>
        </div>
        <?php endif; ?>

    <?php elseif ($section === 'codigos'):
        // ── CÓDIGOS PREMIUM (W1B): canje desde la app → plan Premium ──
        $codigoEdit = null;
        $editCodigoId = (int)($_GET['edit'] ?? 0);
        $codigosDisponibles = true;
        $codigosLista = [];
        $ultimosCanjes = [];
        try {
            $codigosLista = $conexion->query("
                SELECT c.*,
                       (SELECT COUNT(*) FROM codigos_premium_usos u WHERE u.codigo_id = c.id) AS usos,
                       (c.vence_en IS NOT NULL AND c.vence_en < NOW()) AS vencido
                FROM codigos_premium c
                ORDER BY c.id DESC
            ")->fetchAll(PDO::FETCH_ASSOC);
            if ($editCodigoId > 0) {
                $stmtCE = $conexion->prepare("SELECT * FROM codigos_premium WHERE id = :id");
                $stmtCE->execute([':id' => $editCodigoId]);
                $codigoEdit = $stmtCE->fetch(PDO::FETCH_ASSOC);
            }
            $stmtCj = $conexion->prepare("
                SELECT u.id, u.usado_en, c.codigo, us.nombre, us.email
                FROM codigos_premium_usos u
                JOIN codigos_premium c ON c.id = u.codigo_id
                JOIN usuarios us ON us.id_usuario = u.id_usuario
                ORDER BY u.id DESC
                LIMIT 20
            ");
            $stmtCj->execute();
            $ultimosCanjes = $stmtCj->fetchAll(PDO::FETCH_ASSOC);
        } catch (Exception $exC) {
            $codigosDisponibles = false;
        }

        $msgsCodigo = [
            'codigo_creado'          => ['ok',  'Código creado. Ya puede canjearse desde la app (Perfil → Planes).'],
            'codigo_actualizado'     => ['ok',  'Código actualizado.'],
            'codigo_eliminado'       => ['ok',  'Código eliminado junto con su historial de canjes.'],
            'codigo_estado'          => ['ok',  'Estado del código actualizado.'],
            'codigo_datos_invalidos' => ['err', 'Datos inválidos. Revisa el código (mín. 4 caracteres alfanuméricos), los usos (mín. 1) y la duración (mín. 1 día).'],
            'codigo_duplicado'       => ['err', 'Ya existe un código con ese nombre.'],
            'codigo_no_migrado'      => ['err', 'La tabla codigos_premium no existe. Ejecuta la migración 008_codigos_premium.sql.'],
            'codigo_error_bd'        => ['err', 'Error de base de datos. Revisa el log del servidor.'],
        ];
        $msgKeyC = (string)($_GET['msg'] ?? '');
        if ($msgKeyC !== '' && isset($msgsCodigo[$msgKeyC])): ?>
            <div class="flash flash-<?= $msgsCodigo[$msgKeyC][0] ?>"><?= $msgsCodigo[$msgKeyC][1] ?></div>
        <?php endif; ?>

        <?php if (!$codigosDisponibles): ?>
            <div class="section-card">
                <h3 class="section-title">Migración pendiente</h3>
                <p class="muted">Ejecuta <code>backend/migrations/008_codigos_premium.sql</code> en MySQL para habilitar esta sección.</p>
            </div>
        <?php else: ?>

        <!-- Badge de ayuda -->
        <div class="section-card" style="background:#EEF2FF; border:1px solid #C7D2FE;">
            <p style="font-size:14px; line-height:1.7; margin:0;">
                <span class="badge badge-blue">&#127903; Códigos Premium</span>
                Los códigos Premium <strong>activan el plan Premium al canjearse desde la app</strong> (Perfil → Planes), igual que un pago aprobado pero sin costo.
                <span class="badge badge-purple">max_usos = 1</span> = código individual de uso único (un mismo usuario no puede canjearlo dos veces).
                Con <strong>max_usos &gt; 1</strong> el mismo código activa Premium a varios usuarios (ej: un colegio completo); <strong>Vence en</strong> limita hasta cuándo puede canjearse.
            </p>
        </div>

        <!-- Formulario crear/editar -->
        <div class="section-card">
            <h3 class="section-title"><?= $codigoEdit ? '&#9998; Editar código #' . (int)$codigoEdit['id'] : '&#127903; Nuevo código Premium' ?></h3>
            <form method="POST">
                <?= admin_csrf_field() ?>
                <input type="hidden" name="codigo_id" value="<?= (int)($codigoEdit['id'] ?? 0) ?>">
                <div class="grid-2">
                    <div class="form-group"><label>Código *</label>
                        <div style="display:flex; gap:8px;">
                            <input type="text" name="codigo" id="codigoPremium" required maxlength="40" value="<?= htmlspecialchars($codigoEdit['codigo'] ?? '') ?>" placeholder="Ej: SABERPRO2026">
                            <button type="button" class="btn" style="background:#e2e8f0; color:#334155; white-space:nowrap;" onclick="generarCodigoPremium()">Generar código</button>
                        </div></div>
                    <div class="form-group"><label>Descripción (opcional)</label>
                        <input type="text" name="descripcion" maxlength="255" value="<?= htmlspecialchars($codigoEdit['descripcion'] ?? '') ?>" placeholder="Ej: Cortesía colegio San José (grupo 11B)"></div>
                    <div class="form-group"><label>Estado</label>
                        <select name="estado">
                            <option value="activo" <?= ($codigoEdit['estado'] ?? 'activo') === 'activo' ? 'selected' : '' ?>>Activo (canjeable)</option>
                            <option value="deshabilitado" <?= ($codigoEdit['estado'] ?? '') === 'deshabilitado' ? 'selected' : '' ?>>Deshabilitado (no canjeable)</option>
                        </select></div>
                    <div class="form-group"><label>Vence en (opcional — vacío = sin vencimiento)</label>
                        <input type="datetime-local" name="vence_en" value="<?= !empty($codigoEdit['vence_en']) ? date('Y-m-d\TH:i', strtotime($codigoEdit['vence_en'])) : '' ?>"></div>
                    <div class="form-group"><label>Usos máximos (1 = código individual de uso único)</label>
                        <input type="number" name="max_usos" min="1" value="<?= (int)($codigoEdit['max_usos'] ?? 1) ?: 1 ?>"></div>
                    <div class="form-group"><label>Duración del Premium (días, informativa)</label>
                        <input type="number" name="duracion_dias" min="1" value="<?= (int)($codigoEdit['duracion_dias'] ?? 365) ?: 365 ?>"></div>
                    <div class="form-group"><label>Notas internas (opcional, no visibles en la app)</label>
                        <input type="text" name="notas" maxlength="255" value="<?= htmlspecialchars($codigoEdit['notas'] ?? '') ?>" placeholder="Ej: Entregado a la directora el 12/03"></div>
                </div>
                <div style="display:flex; gap:12px;">
                    <button type="submit" name="codigo_save" value="1" class="btn btn-primary"><?= $codigoEdit ? 'Guardar cambios' : 'Crear código' ?></button>
                    <?php if ($codigoEdit): ?>
                        <a href="index.php?section=codigos" class="btn" style="background:#e2e8f0; color:#334155;">Cancelar</a>
                    <?php endif; ?>
                </div>
            </form>
            <script>
                function generarCodigoPremium() {
                    var pool = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
                    var out = '';
                    for (var i = 0; i < 10; i++) out += pool.charAt(Math.floor(Math.random() * pool.length));
                    document.getElementById('codigoPremium').value = out;
                }
            </script>
        </div>

        <!-- Listado -->
        <div class="table-container">
            <table>
                <thead><tr><th>Código</th><th>Descripción</th><th>Estado</th><th>Usos</th><th>Vence</th><th>Creado</th><th>Acciones</th></tr></thead>
                <tbody>
                <?php if (empty($codigosLista)): ?>
                    <tr><td colspan="7" class="muted" style="text-align:center;padding:24px;">Aún no hay códigos Premium. Crea el primero arriba.</td></tr>
                <?php else: foreach ($codigosLista as $cd):
                    $usos = (int)$cd['usos'];
                    $maxU = (int)$cd['max_usos'];
                    if ($cd['estado'] === 'deshabilitado') { $estadoTxt = 'Deshabilitado'; $estadoCls = 'badge-gray'; }
                    elseif ($usos >= $maxU)                { $estadoTxt = 'Agotado';        $estadoCls = 'badge-red'; }
                    elseif ((int)$cd['vencido'] === 1)     { $estadoTxt = 'Vencido';        $estadoCls = 'badge-orange'; }
                    else                                   { $estadoTxt = 'Vigente';        $estadoCls = 'badge-green'; }
                    $confirmEliminar = $usos > 0
                        ? '¿ELIMINAR este código? Se borrarán también sus ' . $usos . ' canjes registrados. Esta acción no se puede deshacer.'
                        : '¿ELIMINAR este código? Esta acción no se puede deshacer.';
                ?>
                    <tr>
                        <td><code class="mono"><strong><?= htmlspecialchars($cd['codigo']) ?></strong></code></td>
                        <td><?= $cd['descripcion'] ? '<strong>' . htmlspecialchars($cd['descripcion']) . '</strong>' : '<span class="muted">—</span>' ?><?= !empty($cd['notas']) ? '<br><span class="muted" title="' . htmlspecialchars($cd['notas']) . '">' . htmlspecialchars(mb_substr($cd['notas'], 0, 60)) . '</span>' : '' ?></td>
                        <td><span class="badge <?= $estadoCls ?>"><?= $estadoTxt ?></span></td>
                        <td><strong><?= $usos ?></strong> / <?= $maxU ?></td>
                        <td class="muted" style="font-size:12px;"><?= $cd['vence_en'] !== null ? date('d/m/Y H:i', strtotime($cd['vence_en'])) : '—' ?></td>
                        <td class="muted" style="font-size:12px;"><?= date('d/m/Y', strtotime($cd['creado_en'])) ?></td>
                        <td style="white-space:nowrap;">
                            <a class="btn btn-primary" style="padding:6px 12px; font-size:12px;" href="index.php?section=codigos&edit=<?= (int)$cd['id'] ?>">Editar</a>
                            <form method="POST" style="display:inline;" onsubmit="return confirm('¿<?= $cd['estado'] === 'activo' ? 'Deshabilitar' : 'Habilitar' ?> este código?');">
                                <?= admin_csrf_field() ?>
                                <input type="hidden" name="codigo_id" value="<?= (int)$cd['id'] ?>">
                                <button type="submit" name="codigo_toggle" value="1" class="btn <?= $cd['estado'] === 'activo' ? 'btn-danger' : 'btn-success' ?>" style="padding:6px 12px; font-size:12px;"><?= $cd['estado'] === 'activo' ? 'Deshabilitar' : 'Habilitar' ?></button>
                            </form>
                            <form method="POST" style="display:inline;" onsubmit="return confirm('<?= htmlspecialchars($confirmEliminar, ENT_QUOTES, 'UTF-8') ?>');">
                                <?= admin_csrf_field() ?>
                                <input type="hidden" name="codigo_id" value="<?= (int)$cd['id'] ?>">
                                <button type="submit" name="codigo_delete" value="1" class="btn btn-danger" style="padding:6px 12px; font-size:12px;">Eliminar</button>
                            </form>
                        </td>
                    </tr>
                <?php endforeach; endif; ?>
                </tbody>
            </table>
        </div>

        <!-- Últimos canjes -->
        <div class="section-card">
            <h3 class="section-title">&#128293; Últimos canjes</h3>
            <div class="table-container" style="box-shadow:none; margin-bottom:0;">
                <table>
                    <thead><tr><th>Fecha</th><th>Código</th><th>Usuario</th><th>Email</th></tr></thead>
                    <tbody>
                    <?php if (!$ultimosCanjes): ?>
                        <tr><td colspan="4" class="muted" style="text-align:center;padding:24px;">Sin canjes todavía. Cuando un usuario canjee un código desde la app (Perfil → Planes), aparecerá aquí.</td></tr>
                    <?php else: foreach ($ultimosCanjes as $cj): ?>
                        <tr>
                            <td class="mono"><?= htmlspecialchars((string)$cj['usado_en']) ?></td>
                            <td><code class="mono"><?= htmlspecialchars($cj['codigo']) ?></code></td>
                            <td><strong><?= htmlspecialchars($cj['nombre']) ?></strong></td>
                            <td><?= htmlspecialchars($cj['email']) ?></td>
                        </tr>
                    <?php endforeach; endif; ?>
                    </tbody>
                </table>
            </div>
            <p class="muted" style="margin-top:12px;">Últimos 20 canjes. Cada canje activa el plan Premium del usuario al instante (access_level = 'premium').</p>
        </div>
        <?php endif; ?>

    <?php elseif ($section === 'soporte'):
        // ── SOPORTE: quejas y sugerencias de los usuarios (v1.7.0) ──
        $soporteDisponible = true;
        $filtroEstado = (string)($_GET['estado'] ?? '');
        $verQuejaId = (int)($_GET['view'] ?? 0);
        $quejaDetalle = null;
        try {
            $estadosValidos = ['nuevo', 'en_proceso', 'resuelto', 'descartado'];
            if ($filtroEstado !== '' && in_array($filtroEstado, $estadosValidos, true)) {
                $stmt = $conexion->prepare("
                    SELECT q.*, u.nombre AS user_nombre, u.email AS user_email
                    FROM quejas_sugerencias q
                    JOIN usuarios u ON u.id_usuario = q.user_id
                    WHERE q.estado = :e
                    ORDER BY q.creado_en DESC LIMIT 200
                ");
                $stmt->execute([':e' => $filtroEstado]);
            } else {
                $stmt = $conexion->prepare("
                    SELECT q.*, u.nombre AS user_nombre, u.email AS user_email
                    FROM quejas_sugerencias q
                    JOIN usuarios u ON u.id_usuario = q.user_id
                    ORDER BY q.creado_en DESC LIMIT 200
                ");
                $stmt->execute();
            }
            $quejas = $stmt->fetchAll(PDO::FETCH_ASSOC);

            $contadorEstados = ['nuevo' => 0, 'en_proceso' => 0, 'resuelto' => 0, 'descartado' => 0];
            foreach ($quejas as $qq) {
                if (isset($contadorEstados[$qq['estado']])) $contadorEstados[$qq['estado']]++;
            }

            if ($verQuejaId > 0) {
                $stmtQ = $conexion->prepare("
                    SELECT q.*, u.nombre AS user_nombre, u.email AS user_email
                    FROM quejas_sugerencias q
                    JOIN usuarios u ON u.id_usuario = q.user_id
                    WHERE q.id = :id LIMIT 1
                ");
                $stmtQ->execute([':id' => $verQuejaId]);
                $quejaDetalle = $stmtQ->fetch(PDO::FETCH_ASSOC);
            }
        } catch (Exception $exQ) {
            $soporteDisponible = false;
            $quejas = [];
            $contadorEstados = ['nuevo' => 0, 'en_proceso' => 0, 'resuelto' => 0, 'descartado' => 0];
        }

        $msgsSoporte = [
            'queja_actualizada' => ['ok',  'Respuesta guardada. El usuario la verá en la app al instante.'],
            'queja_error'       => ['err', 'Error de base de datos al actualizar.'],
        ];
        $msgKeyS = (string)($_GET['msg'] ?? '');
        if ($msgKeyS !== '' && isset($msgsSoporte[$msgKeyS])): ?>
            <div class="flash flash-<?= $msgsSoporte[$msgKeyS][0] ?>"><?= $msgsSoporte[$msgKeyS][1] ?></div>
        <?php endif; ?>

        <?php if (!$soporteDisponible): ?>
            <div class="section-card">
                <h3 class="section-title">Migración pendiente</h3>
                <p class="muted">Ejecuta <code>backend/migrations/006_promociones_quejas.sql</code> en MySQL para habilitar esta sección.</p>
            </div>
        <?php else: ?>

        <?php if ($quejaDetalle): ?>
            <!-- Detalle de la queja -->
            <div class="section-card">
                <div style="display:flex; justify-content:space-between; align-items:flex-start; gap:16px; flex-wrap:wrap; margin-bottom:16px;">
                    <div>
                        <h3 class="section-title" style="margin-bottom:4px;">&#128172; Ticket #<?= (int)$quejaDetalle['id'] ?> — <?= htmlspecialchars($quejaDetalle['user_nombre']) ?></h3>
                        <p class="muted"><?= htmlspecialchars($quejaDetalle['user_email']) ?> · <?= htmlspecialchars((string)$quejaDetalle['creado_en']) ?></p>
                    </div>
                    <a href="index.php?section=soporte" class="btn" style="background:#e2e8f0; color:#334155;">&larr; Volver</a>
                </div>
                <div style="background:#f8fafc; border-radius:12px; padding:16px; margin-bottom:16px;">
                    <p style="margin-bottom:8px;">
                        <span class="badge badge-purple"><?= htmlspecialchars(strtoupper($quejaDetalle['tipo'])) ?></span>
                        <?php if (!empty($quejaDetalle['asunto'])): ?><strong><?= htmlspecialchars($quejaDetalle['asunto']) ?></strong><?php endif; ?>
                    </p>
                    <p style="white-space:pre-wrap; line-height:1.6;"><?= htmlspecialchars($quejaDetalle['mensaje']) ?></p>
                </div>
                <form method="POST">
                    <?= admin_csrf_field() ?>
                    <input type="hidden" name="queja_id" value="<?= (int)$quejaDetalle['id'] ?>">
                    <div class="form-group">
                        <label>Respuesta para el estudiante (la verá en el app en "Mis envíos")</label>
                        <textarea name="respuesta" rows="4" maxlength="2000" style="width:100%; padding:10px 14px; border:2px solid #e2e8f0; border-radius:10px; font-size:14px; font-family:inherit;" placeholder="Ej: ¡Gracias por reportarnos! Ya corregimos el error..."><?= htmlspecialchars($quejaDetalle['respuesta_admin'] ?? '') ?></textarea>
                    </div>
                    <div style="display:flex; gap:12px; align-items:center; flex-wrap:wrap;">
                        <div class="form-group" style="margin:0;">
                            <select name="estado">
                                <option value="nuevo" <?= $quejaDetalle['estado'] === 'nuevo' ? 'selected' : '' ?>>Recibido</option>
                                <option value="en_proceso" <?= $quejaDetalle['estado'] === 'en_proceso' ? 'selected' : '' ?>>En revisión</option>
                                <option value="resuelto" <?= $quejaDetalle['estado'] === 'resuelto' ? 'selected' : '' ?>>Resuelto</option>
                                <option value="descartado" <?= $quejaDetalle['estado'] === 'descartado' ? 'selected' : '' ?>>Cerrado</option>
                            </select>
                        </div>
                        <button type="submit" name="queja_update" value="1" class="btn btn-primary">Guardar respuesta</button>
                    </div>
                </form>
            </div>
        <?php else: ?>
            <!-- Bandeja -->
            <div class="stats-grid" style="grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));">
                <div class="stat-card"><div class="stat-value" style="color:#EF4444;"><?= (int)$contadorEstados['nuevo'] ?></div><div class="stat-label">Nuevos</div></div>
                <div class="stat-card"><div class="stat-value" style="color:#F59E0B;"><?= (int)$contadorEstados['en_proceso'] ?></div><div class="stat-label">En revisión</div></div>
                <div class="stat-card"><div class="stat-value" style="color:#22C55E;"><?= (int)$contadorEstados['resuelto'] ?></div><div class="stat-label">Resueltos</div></div>
                <div class="stat-card"><div class="stat-value" style="color:#94A3B8;"><?= (int)$contadorEstados['descartado'] ?></div><div class="stat-label">Cerrados</div></div>
            </div>
            <div class="section-card" style="padding:12px 20px;">
                <div style="display:flex; gap:8px; flex-wrap:wrap;">
                    <a class="btn <?= $filtroEstado === '' ? 'btn-primary' : '' ?>" style="<?= $filtroEstado === '' ? '' : 'background:#e2e8f0; color:#334155;' ?>" href="index.php?section=soporte">Todos</a>
                    <?php foreach (['nuevo' => 'Nuevos', 'en_proceso' => 'En revisión', 'resuelto' => 'Resueltos', 'descartado' => 'Cerrados'] as $estK => $estL): ?>
                        <a class="btn <?= $filtroEstado === $estK ? 'btn-primary' : '' ?>" style="<?= $filtroEstado === $estK ? '' : 'background:#e2e8f0; color:#334155;' ?>" href="index.php?section=soporte&estado=<?= $estK ?>"><?= $estL ?></a>
                    <?php endforeach; ?>
                </div>
            </div>
            <div class="table-container">
                <table>
                    <thead><tr><th>#</th><th>Fecha</th><th>Usuario</th><th>Tipo</th><th>Asunto / Mensaje</th><th>Estado</th><th>Respuesta</th><th></th></tr></thead>
                    <tbody>
                    <?php if (empty($quejas)): ?>
                        <tr><td colspan="8" class="muted" style="text-align:center;padding:24px;">No hay mensajes todavía. Los que envíen los estudiantes desde el app aparecen aquí.</td></tr>
                    <?php else: foreach ($quejas as $qj):
                        $badgeEst = ['nuevo' => 'badge-red', 'en_proceso' => 'badge-yellow', 'resuelto' => 'badge-green', 'descartado' => 'badge-gray'][$qj['estado']] ?? 'badge-gray';
                        $txtEst = ['nuevo' => 'Recibido', 'en_proceso' => 'En revisión', 'resuelto' => 'Resuelto', 'descartado' => 'Cerrado'][$qj['estado']] ?? $qj['estado'];
                    ?>
                        <tr>
                            <td><?= (int)$qj['id'] ?></td>
                            <td class="muted" style="font-size:12px;"><?= date('d/m/Y H:i', strtotime($qj['creado_en'])) ?></td>
                            <td><strong><?= htmlspecialchars($qj['user_nombre']) ?></strong><br><span class="muted" style="font-size:12px;"><?= htmlspecialchars($qj['user_email']) ?></span></td>
                            <td><span class="badge badge-purple"><?= htmlspecialchars(strtoupper($qj['tipo'])) ?></span></td>
                            <td style="max-width:320px;"><strong><?= htmlspecialchars($qj['asunto'] ?? '(sin asunto)') ?></strong><br><span class="muted" style="font-size:12px;"><?= htmlspecialchars(mb_substr($qj['mensaje'], 0, 90)) ?><?= mb_strlen($qj['mensaje']) > 90 ? '...' : '' ?></span></td>
                            <td><span class="badge <?= $badgeEst ?>"><?= $txtEst ?></span></td>
                            <td><?= !empty($qj['respuesta_admin']) ? '<span class="badge badge-green">Sí</span>' : '<span class="badge badge-gray">No</span>' ?></td>
                            <td><a class="btn btn-primary" style="padding:6px 12px; font-size:12px;" href="index.php?section=soporte&view=<?= (int)$qj['id'] ?>">Ver</a></td>
                        </tr>
                    <?php endforeach; endif; ?>
                    </tbody>
                </table>
            </div>
        <?php endif; ?>
        <?php endif; ?>

    <?php elseif ($section === 'ads'): ?>
        <!-- ANUNCIOS -->
        <div class="section-card">
            <h3 class="section-title">Gestionar Anuncios</h3>
            <p style="color: #666; margin-bottom: 16px;">
                Los anuncios se gestionan desde la tabla <code>ads</code> en la base de datos.
                Sube las imagenes a <code>backend/uploads/ads/</code> y registra el anuncio aqui.
            </p>
        </div>
        <div class="table-container">
            <table>
                <thead><tr><th>ID</th><th>Titulo</th><th>Imagen</th><th>URL Destino</th><th>Estado</th><th>Impresiones</th><th>Clicks</th><th>CTR</th></tr></thead>
                <tbody>
                <?php
                $ads = $conexion->query("SELECT * FROM ads ORDER BY id DESC")->fetchAll(PDO::FETCH_ASSOC);
                foreach ($ads as $ad):
                    $impressions = (int)($ad['impressions'] ?? 0);
                    $clicks = (int)($ad['clicks'] ?? 0);
                    $ctr = $impressions > 0 ? round(($clicks / $impressions) * 100, 1) : 0;
                ?>
                    <tr>
                        <td><?= $ad['id'] ?></td>
                        <td><?= htmlspecialchars($ad['title'] ?? '') ?></td>
                        <td><?= htmlspecialchars($ad['image_url'] ?? '') ?></td>
                        <td><?= htmlspecialchars($ad['click_url'] ?? '-') ?></td>
                        <td><?= ($ad['is_active'] ?? 0) ? '<span class="badge badge-green">Activo</span>' : '<span class="badge badge-orange">Inactivo</span>' ?></td>
                        <td><?= number_format($impressions) ?></td>
                        <td><?= number_format($clicks) ?></td>
                        <td><?= $ctr ?>%</td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>

    <?php elseif ($section === 'plans'): ?>
        <!-- PLANES -->
        <div class="section-card">
            <h3 class="section-title">Planes y Precios</h3>
            <p style="color: #666; margin-bottom: 16px;">
                Gestiona los planes desde la tabla <code>plans</code> y <code>plan_features</code>.
                Los precios se configuran en COP (Pesos Colombianos).
                El precio del plan premium debe ser <strong>$25.000 COP</strong>.
            </p>
        </div>
        <div class="table-container">
            <table>
                <thead><tr><th>ID</th><th>Codigo</th><th>Nombre</th><th>Precio</th><th>Producto Play</th><th>Vitalicio</th><th>Estado</th></tr></thead>
                <tbody>
                <?php
                $plans = $conexion->query("SELECT * FROM plans ORDER BY sort_order")->fetchAll(PDO::FETCH_ASSOC);
                foreach ($plans as $p):
                ?>
                    <tr>
                        <td><?= $p['id'] ?></td>
                        <td><?= htmlspecialchars($p['code'] ?? '') ?></td>
                        <td><?= htmlspecialchars($p['name'] ?? '') ?></td>
                        <td>$<?= number_format($p['price'] ?? 0) ?> COP</td>
                        <td><?= htmlspecialchars($p['play_product_id'] ?? '-') ?></td>
                        <td><?= ($p['is_lifetime'] ?? 0) ? 'Si' : 'No' ?></td>
                        <td><?= ($p['is_active'] ?? 0) ? '<span class="badge badge-green">Activo</span>' : '<span class="badge badge-orange">Inactivo</span>' ?></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>
        <!-- Caracteristicas de planes -->
        <div class="section-card" style="margin-top: 24px;">
            <h3 class="section-title">Caracteristicas por Plan</h3>
            <div class="table-container">
                <table>
                    <thead><tr><th>Plan</th><th>Caracteristica</th><th>Incluida</th><th>Orden</th></tr></thead>
                    <tbody>
                    <?php
                    $features = $conexion->query("
                        SELECT pf.*, p.name as plan_name
                        FROM plan_features pf
                        JOIN plans p ON pf.plan_id = p.id
                        ORDER BY pf.plan_id, pf.sort_order
                    ")->fetchAll(PDO::FETCH_ASSOC);
                    foreach ($features as $f):
                    ?>
                        <tr>
                            <td><?= htmlspecialchars($f['plan_name']) ?></td>
                            <td><?= htmlspecialchars($f['text']) ?></td>
                            <td><?= $f['included'] ? '<span class="badge badge-green">Si</span>' : '<span class="badge badge-orange">No</span>' ?></td>
                            <td><?= $f['sort_order'] ?></td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>

    <?php elseif ($section === 'config'): ?>
        <!-- CONFIGURACION -->
        <div class="section-card">
            <h3 class="section-title">Enlaces Externos</h3>
            <p style="color: #666; margin-bottom: 16px;">
                Los enlaces se cargan dinamicamente en la app. Modifica los valores en la tabla <code>app_config</code>.
            </p>
        </div>
        <div class="table-container">
            <table>
                <thead><tr><th>Clave</th><th>Valor</th><th>Grupo</th><th>Descripcion</th></tr></thead>
                <tbody>
                <?php
                $config = $conexion->query("SELECT * FROM app_config ORDER BY grupo, clave")->fetchAll(PDO::FETCH_ASSOC);
                foreach ($config as $c):
                ?>
                    <tr>
                        <td><code><?= htmlspecialchars($c['clave']) ?></code></td>
                        <td style="word-break: break-all;"><?= htmlspecialchars($c['valor']) ?></td>
                        <td><span class="badge badge-blue"><?= htmlspecialchars($c['grupo']) ?></span></td>
                        <td><?= htmlspecialchars($c['descripcion'] ?? '') ?></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>
        <!-- Referidos -->
        <div class="section-card" style="margin-top: 24px;">
            <h3 class="section-title">Sistema de Referidos</h3>
            <div class="table-container">
                <table>
                    <thead><tr><th>Invitador</th><th>Invitados Calificados</th><th>Recompensas Otorgadas</th></tr></thead>
                    <tbody>
                    <?php
                    $refStats = $conexion->query("
                        SELECT u.nombre,
                            (SELECT COUNT(*) FROM referrals r WHERE r.referrer_id = u.id_usuario AND r.status = 'calificado') as invited,
                            (SELECT COUNT(*) FROM referral_rewards rw WHERE rw.user_id = u.id_usuario) as rewards
                        FROM usuarios u
                        WHERE u.codigo_referido IS NOT NULL
                        ORDER BY invited DESC
                        LIMIT 20
                    ")->fetchAll(PDO::FETCH_ASSOC);
                    foreach ($refStats as $r):
                    ?>
                        <tr>
                            <td><?= htmlspecialchars($r['nombre']) ?></td>
                            <td><?= $r['invited'] ?></td>
                            <td><?= $r['rewards'] ?>/2</td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>

    <?php elseif ($section === 'notifications'): ?>
        <!-- NOTIFICACIONES -->
        <div class="section-card">
            <h3 class="section-title">Enviar Notificacion Masiva</h3>
            <form method="POST" action="send_bulk.php">
                <div class="form-group">
                    <label>Titulo</label>
                    <input type="text" name="title" required>
                </div>
                <div class="form-group">
                    <label>Mensaje</label>
                    <textarea name="body" rows="3" required style="width:100%;padding:10px 14px;border:2px solid #e2e8f0;border-radius:10px;font-size:14px;"></textarea>
                </div>
                <div class="form-group">
                    <label>Tipo</label>
                    <select name="type">
                        <option value="info">Informacion</option>
                        <option value="promo">Promocion</option>
                        <option value="update">Actualizacion</option>
                    </select>
                </div>
                <button type="submit" class="btn btn-primary">Enviar a todos los usuarios</button>
            </form>
        </div>
        <div class="section-card">
            <h3 class="section-title">Notificaciones Recientes</h3>
            <div class="table-container">
                <table>
                    <thead><tr><th>Fecha</th><th>Usuario</th><th>Titulo</th><th>Tipo</th></tr></thead>
                    <tbody>
                    <?php
                    $notifs = $conexion->query("
                        SELECT n.created_at, u.nombre, n.title, n.type
                        FROM notifications n
                        LEFT JOIN usuarios u ON n.user_id = u.id_usuario
                        ORDER BY n.id DESC LIMIT 20
                    ")->fetchAll(PDO::FETCH_ASSOC);
                    foreach ($notifs as $n):
                    ?>
                        <tr>
                            <td><?= $n['created_at'] ?></td>
                            <td><?= htmlspecialchars($n['nombre'] ?? 'N/A') ?></td>
                            <td><?= htmlspecialchars($n['title']) ?></td>
                            <td><span class="badge badge-blue"><?= $n['type'] ?></span></td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>

    <?php elseif ($section === 'reports'): ?>
        <!-- REPORTES -->
        <div class="section-card">
            <h3 class="section-title">Reportes Generales</h3>
            <div class="grid-2">
                <div>
                    <h4 style="margin-bottom:12px;">Usuarios por Ciudad</h4>
                    <div class="table-container">
                        <table>
                            <thead><tr><th>Ciudad</th><th>Usuarios</th></tr></thead>
                            <tbody>
                            <?php
                            $cities = $conexion->query("SELECT ciudad, COUNT(*) as count FROM usuarios WHERE ciudad IS NOT NULL AND ciudad != '' GROUP BY ciudad ORDER BY count DESC LIMIT 10")->fetchAll(PDO::FETCH_ASSOC);
                            foreach ($cities as $c):
                            ?>
                                <tr><td><?= htmlspecialchars($c['ciudad']) ?></td><td><?= $c['count'] ?></td></tr>
                            <?php endforeach; ?>
                            </tbody>
                        </table>
                    </div>
                </div>
                <div>
                    <h4 style="margin-bottom:12px;">Promedio por Area</h4>
                    <div class="table-container">
                        <table>
                            <thead><tr><th>Area</th><th>Promedio</th></tr></thead>
                            <tbody>
                            <?php
                            $areas = $conexion->query("SELECT ROUND(AVG(lectura_puntaje),1) as lectura, ROUND(AVG(matematicas_puntaje),1) as matematicas, ROUND(AVG(sociales_puntaje),1) as sociales, ROUND(AVG(naturales_puntaje),1) as naturales, ROUND(AVG(ingles_puntaje),1) as ingles FROM simulacro_resultados")->fetch(PDO::FETCH_ASSOC);
                            $areaNames = ['Lectura Critica' => 'lectura', 'Matematicas' => 'matematicas', 'Sociales' => 'sociales', 'Naturales' => 'naturales', 'Ingles' => 'ingles'];
                            foreach ($areaNames as $name => $key):
                            ?>
                                <tr><td><?= $name ?></td><td><?= $areas[$key] ?? 0 ?></td></tr>
                            <?php endforeach; ?>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>
        <div class="section-card">
            <h3 class="section-title">Crecimiento de Usuarios (ultimos 30 dias)</h3>
            <div class="table-container">
                <table>
                    <thead><tr><th>Fecha</th><th>Nuevos Usuarios</th></tr></thead>
                    <tbody>
                    <?php
                    $growth = $conexion->query("SELECT DATE(registration_date) as fecha, COUNT(*) as count FROM usuarios WHERE registration_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) GROUP BY DATE(registration_date) ORDER BY fecha DESC")->fetchAll(PDO::FETCH_ASSOC);
                    foreach ($growth as $g):
                    ?>
                        <tr><td><?= $g['fecha'] ?></td><td><?= $g['count'] ?></td></tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
    <?php elseif ($section === 'analytics'): ?>
        <!-- ANALITICA (v1.6.0) -->
        <?php
        $analyticsAvailable = true;
        $an = [];
        try {
            $an['eventos_hoy']    = (int)$conexion->query("SELECT COUNT(*) FROM app_events WHERE created_at >= CURDATE()")->fetchColumn();
            $an['eventos_7d']     = (int)$conexion->query("SELECT COUNT(*) FROM app_events WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)")->fetchColumn();
            $an['usuarios_act_hoy'] = (int)$conexion->query("SELECT COUNT(DISTINCT user_id) FROM app_events WHERE created_at >= CURDATE() AND user_id IS NOT NULL")->fetchColumn();
            $an['usuarios_act_7d']  = (int)$conexion->query("SELECT COUNT(DISTINCT user_id) FROM app_events WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY) AND user_id IS NOT NULL")->fetchColumn();
            $an['errores_app_7d']   = (int)$conexion->query("SELECT COUNT(*) FROM error_logs WHERE source = 'app' AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)")->fetchColumn();
        } catch (Exception $e) {
            $analyticsAvailable = false;
        }
        ?>
        <?php if (!$analyticsAvailable): ?>
            <div class="section-card">
                <h3 class="section-title">Analítica no disponible</h3>
                <p class="muted">Las tablas <code>app_events</code> / <code>error_logs</code> no existen todavía.
                Ejecuta la migración: <code>mysql -u jnegretep -p prepsaber &lt; backend/migrations/003_analytics_admin.sql</code></p>
            </div>
        <?php else: ?>
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-icon" style="background: #DBEAFE;">&#128200;</div>
                <div class="stat-value"><?= number_format($an['eventos_hoy']) ?></div>
                <div class="stat-label">Eventos Hoy</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #D1FAE5;">&#128640;</div>
                <div class="stat-value"><?= number_format($an['eventos_7d']) ?></div>
                <div class="stat-label">Eventos 7 días</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #FEF3C7;">&#128100;</div>
                <div class="stat-value"><?= $an['usuarios_act_hoy'] ?></div>
                <div class="stat-label">Usuarios Activos Hoy (eventos)</div>
                <div class="stat-change">7 días: <?= $an['usuarios_act_7d'] ?></div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #FEE2E2;">&#9888;</div>
                <div class="stat-value"><?= $an['errores_app_7d'] ?></div>
                <div class="stat-label">Errores de App (7 días)</div>
            </div>
        </div>

        <div class="section-card">
            <h3 class="section-title">Eventos por Tipo (últimos 7 días)</h3>
            <?php
            $topEvents = $conexion->query("
                SELECT event_name, COUNT(*) as total
                FROM app_events
                WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
                GROUP BY event_name ORDER BY total DESC LIMIT 12
            ")->fetchAll(PDO::FETCH_ASSOC);
            $maxEvent = max(1, (int)($topEvents[0]['total'] ?? 1));
            if (!$topEvents): ?>
                <p class="muted">Aún no hay eventos registrados. Los eventos llegan desde la app v1.6.0+.</p>
            <?php else: foreach ($topEvents as $ev): ?>
                <div class="bar-row">
                    <div class="bar-label"><?= htmlspecialchars($ev['event_name']) ?></div>
                    <div class="bar-track"><div class="bar-fill" style="width: <?= round($ev['total'] / $maxEvent * 100) ?>%"></div></div>
                    <div class="bar-value"><?= number_format($ev['total']) ?></div>
                </div>
            <?php endforeach; endif; ?>
        </div>

        <div class="grid-2">
            <div class="section-card">
                <h3 class="section-title">Plataformas (30 días)</h3>
                <?php
                $platforms = $conexion->query("
                    SELECT platform, COUNT(*) as total
                    FROM app_events
                    WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                    GROUP BY platform ORDER BY total DESC
                ")->fetchAll(PDO::FETCH_ASSOC);
                $maxPlat = max(1, (int)($platforms[0]['total'] ?? 1));
                if (!$platforms): ?>
                    <p class="muted">Sin datos aún.</p>
                <?php else: foreach ($platforms as $p): ?>
                    <div class="bar-row">
                        <div class="bar-label"><?= htmlspecialchars($p['platform']) ?></div>
                        <div class="bar-track"><div class="bar-fill green" style="width: <?= round($p['total'] / $maxPlat * 100) ?>%"></div></div>
                        <div class="bar-value"><?= number_format($p['total']) ?></div>
                    </div>
                <?php endforeach; endif; ?>
            </div>
            <div class="section-card">
                <h3 class="section-title">Retención aproximada</h3>
                <?php
                try {
                    $act1 = (int)$conexion->query("SELECT COUNT(DISTINCT user_id) FROM app_events WHERE user_id IS NOT NULL AND created_at >= CURDATE()")->fetchColumn();
                    $act7 = (int)$conexion->query("SELECT COUNT(DISTINCT user_id) FROM app_events WHERE user_id IS NOT NULL AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)")->fetchColumn();
                    $total = (int)$conexion->query("SELECT COUNT(*) FROM usuarios WHERE email_verificado = 1")->fetchColumn();
                    $retencion = $act7 > 0 ? round(($act1 / $act7) * 100, 1) : 0;
                } catch (Exception $e) { $act1 = $act7 = $total = 0; $retencion = 0; }
                ?>
                <div class="bar-row"><div class="bar-label">DAU/WAU</div><div class="bar-track"><div class="bar-fill" style="width: <?= min(100, $retencion) ?>%"></div></div><div class="bar-value"><?= $retencion ?>%</div></div>
                <p class="muted" style="margin-top:12px;">DAU (hoy): <strong><?= $act1 ?></strong> · WAU (7d): <strong><?= $act7 ?></strong> · Verificados: <strong><?= $total ?></strong></p>
                <p class="muted">Ratio calculado con usuarios que generaron eventos (app v1.6.0+). Complementa con Firebase Analytics para datos completos.</p>
            </div>
        </div>
        <?php endif; ?>

    <?php elseif ($section === 'errors'): ?>
        <!-- ERRORES (v1.6.0) -->
        <?php
        $errorsAvailable = true;
        $errStats = [];
        try {
            $errStats['total'] = (int)$conexion->query("SELECT COUNT(*) FROM error_logs")->fetchColumn();
            $errStats['unresolved'] = (int)$conexion->query("SELECT COUNT(*) FROM error_logs WHERE resolved = 0")->fetchColumn();
            $errStats['fatal_7d'] = (int)$conexion->query("SELECT COUNT(*) FROM error_logs WHERE severity = 'fatal' AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)")->fetchColumn();
        } catch (Exception $e) {
            $errorsAvailable = false;
        }
        ?>
        <?php if (!$errorsAvailable): ?>
            <div class="section-card">
                <h3 class="section-title">Visor de errores no disponible</h3>
                <p class="muted">Ejecuta la migración 003: <code>backend/migrations/003_analytics_admin.sql</code></p>
            </div>
        <?php else: ?>
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-icon" style="background: #FEE2E2;">&#128680;</div>
                <div class="stat-value"><?= number_format($errStats['total']) ?></div>
                <div class="stat-label">Errores Totales</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #FEF3C7;">&#9888;</div>
                <div class="stat-value"><?= number_format($errStats['unresolved']) ?></div>
                <div class="stat-label">Sin Resolver</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #FED7AA;">&#128165;</div>
                <div class="stat-value"><?= number_format($errStats['fatal_7d']) ?></div>
                <div class="stat-label">Fatales (7 días)</div>
            </div>
        </div>
        <div class="table-container">
            <table>
                <thead><tr><th>Fecha</th><th>Origen</th><th>Severidad</th><th>Código</th><th>Mensaje</th><th>Usuario</th><th>Plataforma</th><th>Estado</th><th></th></tr></thead>
                <tbody>
                <?php
                $errores = $conexion->query("
                    SELECT e.*, u.nombre
                    FROM error_logs e
                    LEFT JOIN usuarios u ON e.user_id = u.id_usuario
                    ORDER BY e.created_at DESC LIMIT 100
                ")->fetchAll(PDO::FETCH_ASSOC);
                foreach ($errores as $er):
                    $sevBadge = match($er['severity']) {
                        'fatal' => 'badge-red',
                        'warning' => 'badge-yellow',
                        'info' => 'badge-gray',
                        default => 'badge-orange',
                    };
                ?>
                    <tr>
                        <td class="mono"><?= $er['created_at'] ?></td>
                        <td><span class="badge badge-blue"><?= htmlspecialchars($er['source']) ?></span></td>
                        <td><span class="badge <?= $sevBadge ?>"><?= htmlspecialchars($er['severity']) ?></span></td>
                        <td class="mono"><?= htmlspecialchars($er['error_code'] ?? '-') ?></td>
                        <td title="<?= htmlspecialchars(mb_substr($er['message'], 0, 300)) ?>"><?= htmlspecialchars(mb_substr($er['message'], 0, 90)) ?><?= mb_strlen($er['message']) > 90 ? '...' : '' ?></td>
                        <td><?= $er['user_id'] ? htmlspecialchars($er['nombre'] ?? ('#' . $er['user_id'])) : '-' ?></td>
                        <td><?= htmlspecialchars($er['platform'] ?? '-') ?></td>
                        <td><?= $er['resolved'] ? '<span class="badge badge-green">Resuelto</span>' : '<span class="badge badge-orange">Abierto</span>' ?></td>
                        <td>
                            <?php if (!$er['resolved']): ?>
                            <form method="POST" style="display:inline;">
                                <input type="hidden" name="resolve_error" value="<?= $er['id'] ?>">
                                <?= admin_csrf_field() ?>
                                <button type="submit" class="btn btn-success" style="padding:4px 10px;font-size:11px;">✓</button>
                            </form>
                            <?php endif; ?>
                        </td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>
        <?php endif; ?>

    <?php elseif ($section === 'activity'): ?>
        <!-- ACTIVIDAD (v1.6.0) -->
        <?php
        $activityAvailable = true;
        $eventos = [];
        try {
            $eventos = $conexion->query("
                SELECT e.*, u.nombre
                FROM app_events e
                LEFT JOIN usuarios u ON e.user_id = u.id_usuario
                ORDER BY e.created_at DESC LIMIT 100
            ")->fetchAll(PDO::FETCH_ASSOC);
        } catch (Exception $e) {
            $activityAvailable = false;
        }
        ?>
        <?php if (!$activityAvailable): ?>
            <div class="section-card">
                <h3 class="section-title">Actividad no disponible</h3>
                <p class="muted">Ejecuta la migración 003: <code>backend/migrations/003_analytics_admin.sql</code></p>
            </div>
        <?php else: ?>
        <div class="table-container">
            <table>
                <thead><tr><th>Fecha</th><th>Usuario</th><th>Evento</th><th>Plataforma</th><th>Versión</th><th>Parámetros</th></tr></thead>
                <tbody>
                <?php if (!$eventos): ?>
                    <tr><td colspan="6" class="muted" style="text-align:center;padding:24px;">Sin eventos aún — llegarán desde la app v1.6.0+</td></tr>
                <?php else: foreach ($eventos as $ev): ?>
                    <tr>
                        <td class="mono"><?= $ev['created_at'] ?></td>
                        <td><?= $ev['user_id'] ? htmlspecialchars($ev['nombre'] ?? ('#' . $ev['user_id'])) : '<span class="muted">anónimo</span>' ?></td>
                        <td><span class="badge badge-blue"><?= htmlspecialchars($ev['event_name']) ?></span></td>
                        <td><?= htmlspecialchars($ev['platform'] ?? '-') ?></td>
                        <td class="mono"><?= htmlspecialchars($ev['app_version'] ?? '-') ?></td>
                        <td class="mono" title="<?= htmlspecialchars((string)$ev['params']) ?>"><?= htmlspecialchars(mb_substr((string)$ev['params'], 0, 60)) ?><?= mb_strlen((string)$ev['params']) > 60 ? '...' : '' ?></td>
                    </tr>
                <?php endforeach; endif; ?>
                </tbody>
            </table>
        </div>
        <?php endif; ?>

    <?php elseif ($section === 'rankings'): ?>
        <!-- RANKINGS INSTITUCIONALES (v1.6.0) -->
        <div class="grid-2">
            <div class="section-card">
                <h3 class="section-title">🏆 Top Colegios por XP</h3>
                <div class="table-container">
                    <table>
                        <thead><tr><th>#</th><th>Colegio</th><th>Depto</th><th>Usuarios</th><th>XP Total</th><th>Nivel Prom.</th></tr></thead>
                        <tbody>
                        <?php
                        $colegiosTop = $conexion->query("
                            SELECT TRIM(u.colegio) as colegio, MAX(TRIM(u.departamento)) as depto,
                                   COUNT(DISTINCT u.id_usuario) as usuarios,
                                   SUM(ug.total_xp) as xp, ROUND(AVG(ug.current_level),1) as nivel
                            FROM usuarios u JOIN user_gamification ug ON ug.user_id = u.id_usuario
                            WHERE u.colegio IS NOT NULL AND TRIM(u.colegio) <> '' AND u.email_verificado = 1 AND ug.total_xp > 0
                            GROUP BY TRIM(u.colegio) ORDER BY xp DESC LIMIT 25
                        ")->fetchAll(PDO::FETCH_ASSOC);
                        if (!$colegiosTop): ?>
                            <tr><td colspan="6" class="muted" style="text-align:center;padding:24px;">Sin datos aún.</td></tr>
                        <?php else: foreach ($colegiosTop as $i => $c): ?>
                            <tr>
                                <td><?= $i + 1 ?></td>
                                <td><?= htmlspecialchars($c['colegio']) ?></td>
                                <td><?= htmlspecialchars($c['depto'] ?? '-') ?></td>
                                <td><?= $c['usuarios'] ?></td>
                                <td><strong><?= number_format((float)$c['xp']) ?></strong></td>
                                <td><?= $c['nivel'] ?></td>
                            </tr>
                        <?php endforeach; endif; ?>
                        </tbody>
                    </table>
                </div>
            </div>
            <div class="section-card">
                <h3 class="section-title">🗺️ Top Departamentos por XP</h3>
                <div class="table-container">
                    <table>
                        <thead><tr><th>#</th><th>Departamento</th><th>Usuarios</th><th>XP Total</th><th>Nivel Prom.</th></tr></thead>
                        <tbody>
                        <?php
                        $deptosTop = $conexion->query("
                            SELECT TRIM(u.departamento) as depto,
                                   COUNT(DISTINCT u.id_usuario) as usuarios,
                                   SUM(ug.total_xp) as xp, ROUND(AVG(ug.current_level),1) as nivel
                            FROM usuarios u JOIN user_gamification ug ON ug.user_id = u.id_usuario
                            WHERE u.departamento IS NOT NULL AND TRIM(u.departamento) <> '' AND u.email_verificado = 1 AND ug.total_xp > 0
                            GROUP BY TRIM(u.departamento) ORDER BY xp DESC LIMIT 25
                        ")->fetchAll(PDO::FETCH_ASSOC);
                        if (!$deptosTop): ?>
                            <tr><td colspan="5" class="muted" style="text-align:center;padding:24px;">Sin datos aún.</td></tr>
                        <?php else: foreach ($deptosTop as $i => $d): ?>
                            <tr>
                                <td><?= $i + 1 ?></td>
                                <td><?= htmlspecialchars($d['depto']) ?></td>
                                <td><?= $d['usuarios'] ?></td>
                                <td><strong><?= number_format((float)$d['xp']) ?></strong></td>
                                <td><?= $d['nivel'] ?></td>
                            </tr>
                        <?php endforeach; endif; ?>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

    <?php elseif ($section === 'colegios'): ?>
        <!-- COLEGIOS (B2B, v1.7.0): gestión de directores -->
        <?php
        $colegiosAvailable = true;
        $directores = [];
        $colegiosDatalist = [];
        $sugerenciaPass = '';
        try {
            $stmtDir = $conexion->prepare("
                SELECT d.id, d.nombre, d.email, d.colegio, d.telefono, d.activo, d.ultimo_login,
                       (SELECT COUNT(*) FROM usuarios u
                         WHERE u.colegio = d.colegio AND u.tipo_usuario = 'estudiante') AS estudiantes
                FROM directores d
                ORDER BY d.activo DESC, d.id DESC
            ");
            $stmtDir->execute();
            $directores = $stmtDir->fetchAll(PDO::FETCH_ASSOC);

            $stmtCol = $conexion->prepare("
                SELECT DISTINCT colegio
                FROM usuarios
                WHERE colegio IS NOT NULL AND colegio <> ''
                ORDER BY colegio
            ");
            $stmtCol->execute();
            $colegiosDatalist = $stmtCol->fetchAll(PDO::FETCH_COLUMN);

            // Sugerencia de contraseña segura (10 aleatorios + 2 fijos = 12)
            $pool = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
            for ($i = 0; $i < 10; $i++) {
                $sugerenciaPass .= $pool[random_int(0, strlen($pool) - 1)];
            }
            $sugerenciaPass .= '!7a';
        } catch (Exception $e) {
            $colegiosAvailable = false;
        }
        ?>
        <?php if (!$colegiosAvailable): ?>
            <div class="section-card">
                <h3 class="section-title">Sección Colegios no disponible</h3>
                <p class="muted">La tabla <code>directores</code> no existe todavía.
                Ejecuta la migración: <code>mysql -u jnegretep -p prepsaber &lt; backend/migrations/005_directores.sql</code></p>
            </div>
        <?php else: ?>

            <?php
            // Mensajes flash por querystring
            $msgs = [
                'director_creado'   => ['ok',  'Director creado correctamente. Comparte las credenciales de forma segura.'],
                'email_duplicado'   => ['err', 'Ya existe un director con ese correo.'],
                'datos_invalidos'   => ['err', 'Datos inválidos: nombre, correo y colegio son obligatorios; la contraseña debe tener al menos 8 caracteres.'],
                'estado_actualizado'=> ['ok',  'Estado del director actualizado.'],
                'error_bd'          => ['err', 'Error de base de datos. Revisa el log del servidor.'],
            ];
            $msgKey = (string)($_GET['msg'] ?? '');
            if ($msgKey !== '' && isset($msgs[$msgKey])): ?>
                <div class="flash flash-<?= $msgs[$msgKey][0] ?>"><?= $msgs[$msgKey][1] ?></div>
            <?php endif; ?>

            <?php if (!empty($_SESSION['admin_flash_pass'])):
                $flashPass = $_SESSION['admin_flash_pass'];
                unset($_SESSION['admin_flash_pass']); // se muestra UNA sola vez ?>
                <div class="section-card" style="border: 2px solid #22C55E;">
                    <h3 class="section-title">&#128273; Contraseña restablecida (Director #<?= (int)$flashPass['id'] ?>)</h3>
                    <p style="margin-bottom: 12px;">Guarda esta contraseña ahora — <strong>no volverá a mostrarse</strong>:</p>
                    <div style="display:flex; gap:12px; align-items:center; flex-wrap:wrap;">
                        <code class="mono" id="passGenerada" style="font-size: 18px; background: #f1f5f9; padding: 10px 16px; border-radius: 8px;"><?= htmlspecialchars($flashPass['pass'], ENT_QUOTES, 'UTF-8') ?></code>
                        <button type="button" class="btn btn-primary" id="btnCopiarPass">Copiar</button>
                    </div>
                    <script>
                        document.getElementById('btnCopiarPass').addEventListener('click', function () {
                            var texto = document.getElementById('passGenerada').textContent;
                            function ok() { var b = document.getElementById('btnCopiarPass'); b.textContent = '¡Copiada!'; b.disabled = true; }
                            if (navigator.clipboard && navigator.clipboard.writeText) {
                                navigator.clipboard.writeText(texto).then(ok);
                            } else {
                                var tmp = document.createElement('input');
                                document.body.appendChild(tmp);
                                tmp.value = texto;
                                tmp.select();
                                document.execCommand('copy');
                                document.body.removeChild(tmp);
                                ok();
                            }
                        });
                    </script>
                </div>
            <?php endif; ?>

            <!-- Listado de directores -->
            <div class="table-container">
                <table>
                    <thead><tr><th>ID</th><th>Nombre</th><th>Email</th><th>Colegio</th><th>Estudiantes</th><th>Estado</th><th>Último login</th><th>Acciones</th></tr></thead>
                    <tbody>
                    <?php if (!$directores): ?>
                        <tr><td colspan="8" class="muted" style="text-align:center;padding:24px;">Aún no hay directores. Crea el primero con el formulario de abajo.</td></tr>
                    <?php else: foreach ($directores as $d): ?>
                        <tr>
                            <td><?= (int)$d['id'] ?></td>
                            <td><?= htmlspecialchars($d['nombre']) ?></td>
                            <td><?= htmlspecialchars($d['email']) ?></td>
                            <td><?= htmlspecialchars($d['colegio']) ?></td>
                            <td><strong><?= (int)$d['estudiantes'] ?></strong></td>
                            <td><?= ((int)$d['activo'] === 1) ? '<span class="badge badge-green">Activo</span>' : '<span class="badge badge-red">Inactivo</span>' ?></td>
                            <td><?= $d['ultimo_login'] ?? 'Nunca' ?></td>
                            <td style="white-space:nowrap;">
                                <form method="POST" style="display:inline;">
                                    <?= admin_csrf_field() ?>
                                    <input type="hidden" name="toggle_director" value="1">
                                    <input type="hidden" name="director_id" value="<?= (int)$d['id'] ?>">
                                    <button type="submit" class="btn <?= ((int)$d['activo'] === 1) ? 'btn-danger' : 'btn-success' ?>" style="padding:6px 12px;font-size:12px;"><?= ((int)$d['activo'] === 1) ? 'Desactivar' : 'Activar' ?></button>
                                </form>
                                <form method="POST" style="display:inline;" onsubmit="return confirm('¿Restablecer la contraseña de este director?');">
                                    <?= admin_csrf_field() ?>
                                    <input type="hidden" name="reset_director_pass" value="1">
                                    <input type="hidden" name="director_id" value="<?= (int)$d['id'] ?>">
                                    <button type="submit" class="btn btn-primary" style="padding:6px 12px;font-size:12px;">Reset contraseña</button>
                                </form>
                            </td>
                        </tr>
                    <?php endforeach; endif; ?>
                    </tbody>
                </table>
            </div>

            <!-- Crear director -->
            <div class="section-card">
                <h3 class="section-title">&#10133; Crear director de colegio</h3>
                <p class="muted" style="margin-bottom:16px;">
                    El director solo verá los estudiantes cuyo colegio coincida exactamente con el asignado.
                    Podrá consultar reportes de simulacros y activar/desactivar estudiantes de su colegio
                    (ingresa en <code>backend/director/login.php</code>).
                </p>
                <form method="POST">
                    <?= admin_csrf_field() ?>
                    <input type="hidden" name="crear_director" value="1">
                    <div class="grid-2">
                        <div class="form-group">
                            <label>Nombre completo</label>
                            <input type="text" name="nombre" required maxlength="120">
                        </div>
                        <div class="form-group">
                            <label>Email</label>
                            <input type="email" name="email" required maxlength="190">
                        </div>
                        <div class="form-group">
                            <label>Colegio (selecciona uno existente o escribe uno nuevo)</label>
                            <input type="text" name="colegio" list="listaColegios" required maxlength="190">
                            <datalist id="listaColegios">
                                <?php foreach ($colegiosDatalist as $col): ?>
                                    <option value="<?= htmlspecialchars((string)$col) ?>"></option>
                                <?php endforeach; ?>
                            </datalist>
                        </div>
                        <div class="form-group">
                            <label>Teléfono (opcional)</label>
                            <input type="tel" name="telefono" maxlength="30">
                        </div>
                        <div class="form-group" style="grid-column: 1 / -1;">
                            <label>Contraseña (sugerencia segura autogenerada — puedes cambiarla, mínimo 8 caracteres)</label>
                            <input type="text" name="password" value="<?= htmlspecialchars($sugerenciaPass, ENT_QUOTES, 'UTF-8') ?>" minlength="8" required autocomplete="off" class="mono">
                        </div>
                    </div>
                    <button type="submit" class="btn btn-primary">Crear director</button>
                </form>
            </div>

        <?php endif; ?>

    <?php elseif ($section === 'cursos'):
        // ── CURSOS MOODLE (W2E): catálogo dinámico + matrícula masiva ──
        $cursosTiposLabels = [
            'curso'     => 'Curso',
            'simulacro' => 'Simulacro',
            'reto'      => 'Reto',
            'otro'      => 'Otro',
        ];
        $cursosTiposBadge = [
            'curso'     => 'badge-blue',
            'simulacro' => 'badge-purple',
            'reto'      => 'badge-orange',
            'otro'      => 'badge-gray',
        ];
        $cursosSegmentosLabels = [
            'todos'       => 'Todos (con cuenta Moodle)',
            'verificados' => 'Email verificado',
            'trial'       => 'Plan Trial',
            'premium'     => 'Plan Premium (incluye early_bird)',
            'free'        => 'Plan Free',
            'nuevos_7d'   => 'Nuevos (últimos 7 días)',
        ];

        // Mensajes flash de las acciones POST de esta sección
        $msgsCursos = [
            'curso_clasif_ok'       => ['ok',  'Clasificación guardada. La app la aplica de inmediato.'],
            'curso_bulk_ok'         => ['ok',  'Cursos clasificados correctamente.'],
            'curso_datos_invalidos' => ['err', 'Datos inválidos: selecciona al menos un curso y un tipo/segmento válido.'],
            'cursos_no_migrado'     => ['err', 'La tabla course_catalog no existe. Ejecuta la migración 009_course_catalog.sql.'],
            'curso_error_bd'        => ['err', 'Error de base de datos. Revisa el log del servidor.'],
        ];
        $msgKeyCursos = (string)($_GET['msg'] ?? '');
        $flashCursos = null;
        if ($msgKeyCursos !== '' && isset($msgsCursos[$msgKeyCursos])) {
            $flashCursos = $msgsCursos[$msgKeyCursos];
            if ($msgKeyCursos === 'curso_bulk_ok' && isset($_GET['n']) && (int)$_GET['n'] > 0) {
                $flashCursos = ['ok', (int)$_GET['n'] . ' cursos clasificados correctamente. La app aplica el cambio de inmediato.'];
            }
        }
        if ($flashCursos !== null): ?>
        <div class="flash flash-<?= $flashCursos[0] ?>"><?= htmlspecialchars($flashCursos[1]) ?></div>
        <?php endif; ?>

        <?php if (isset($cursoEnrolPreview)):
            // ── PASO 1 DE 2: resumen de matrícula masiva (no se ha ejecutado nada) ──
            $pv = $cursoEnrolPreview;
            $nCursosPv = count($pv['cursos']);
            $nUsuariosPv = (int)$pv['total'];
            $segLabelPv = $cursosSegmentosLabels[$pv['segmento']] ?? $pv['segmento'];
        ?>
        <div class="section-card" style="background:#FFFBEB; border:1px solid #FDE68A;">
            <h3 class="section-title">&#9888;&#65039; Resumen de matrícula masiva (paso 1 de 2)</h3>
            <p style="font-size:14px; line-height:1.7;">
                Segmento: <strong><?= htmlspecialchars($segLabelPv) ?></strong>
                <?= $pv['con_activo'] ? ' · solo cuentas activas' : '' ?>
                · solo usuarios con cuenta Moodle (moodle_id &gt; 0).
            </p>

            <p style="margin-top:12px;"><strong>Cursos seleccionados (<?= (int)$nCursosPv ?>):</strong></p>
            <ul style="margin:8px 0 16px 24px; font-size:14px; line-height:1.6;">
                <?php foreach ($pv['cursos'] as $cPv): ?>
                    <li>#<?= (int)$cPv['id'] ?> — <?= htmlspecialchars($cPv['nombre']) ?></li>
                <?php endforeach; ?>
            </ul>

            <p>
                <strong>Usuarios que coinciden: <?= number_format($nUsuariosPv) ?></strong>
                &nbsp;→&nbsp; hasta <strong><?= number_format($nUsuariosPv * $nCursosPv) ?></strong> matrículas
                (<?= (int)$nCursosPv ?> cursos por usuario).
            </p>
            <?php if ($nUsuariosPv * $nCursosPv > 2000): ?>
                <p class="muted">Operación grande: puede tardar varios minutos (lotes de 5 con pausas de 100 ms). No cierres esta pestaña mientras se ejecuta.</p>
            <?php endif; ?>

            <p class="muted">Muestra de los primeros 20 usuarios del segmento:</p>
            <div class="table-container" style="margin-bottom:16px;">
                <table>
                    <thead><tr><th>Nombre</th><th>Email</th><th>Moodle ID</th></tr></thead>
                    <tbody>
                    <?php if (empty($pv['muestra'])): ?>
                        <tr><td colspan="3" class="muted" style="text-align:center;padding:24px;">Ningún usuario coincide con el segmento.</td></tr>
                    <?php else: foreach ($pv['muestra'] as $uPv): ?>
                        <tr>
                            <td><?= htmlspecialchars((string)($uPv['nombre'] ?? '')) ?></td>
                            <td><?= htmlspecialchars((string)($uPv['email'] ?? '')) ?></td>
                            <td class="mono"><?= (int)($uPv['moodle_id'] ?? 0) ?></td>
                        </tr>
                    <?php endforeach; endif; ?>
                    </tbody>
                </table>
            </div>

            <?php if ($nUsuariosPv > 0 && $nCursosPv > 0): ?>
            <form method="POST" action="index.php?section=cursos"
                  onsubmit="return confirm('¿CONFIRMAR la matrícula de <?= (int)$nUsuariosPv ?> usuarios en <?= (int)$nCursosPv ?> cursos? Esta acción solo AÑADE matrículas; nunca las elimina.');">
                <?= admin_csrf_field() ?>
                <?php foreach ($pv['cursos'] as $cPvH): ?>
                    <input type="hidden" name="course_ids[]" value="<?= (int)$cPvH['id'] ?>">
                <?php endforeach; ?>
                <input type="hidden" name="segmento" value="<?= htmlspecialchars($pv['segmento']) ?>">
                <div style="display:flex; gap:12px; align-items:center; flex-wrap:wrap;">
                    <button type="submit" name="curso_enrol_confirm" value="1" class="btn btn-danger" style="padding:14px 24px; font-size:15px;">
                        CONFIRMAR MATRÍCULA DE <?= number_format($nUsuariosPv) ?> USUARIOS EN <?= (int)$nCursosPv ?> CURSOS
                    </button>
                    <a href="index.php?section=cursos" class="btn" style="background:#e2e8f0; color:#334155;">Cancelar</a>
                </div>
            </form>
            <?php else: ?>
            <div style="display:flex; gap:12px;">
                <a href="index.php?section=cursos" class="btn" style="background:#e2e8f0; color:#334155;">&larr; Volver</a>
            </div>
            <?php endif; ?>
            <p class="muted" style="margin-top:12px;">&#128274; Esta herramienta solo AÑADE matrículas; nunca las elimina.</p>
        </div>

        <?php elseif (isset($cursoEnrolResultado)):
            // ── PASO 2 DE 2: resultado de la matrícula masiva ──
            $res = $cursoEnrolResultado;
            $tRes = $res['totales'];
            $segLabelRes = $cursosSegmentosLabels[$res['segmento']] ?? $res['segmento'];
        ?>
        <div class="section-card">
            <h3 class="section-title">&#9989; Resultado de la matrícula masiva</h3>
            <p style="font-size:14px; line-height:1.8;">
                Segmento: <strong><?= htmlspecialchars($segLabelRes) ?></strong> ·
                Usuarios procesados: <strong><?= number_format((int)$tRes['usuarios']) ?></strong> ·
                Cursos: <strong><?= count($res['cursos']) ?></strong>
            </p>
            <p style="margin-bottom:16px;">
                <span class="badge badge-green">Matrículas nuevas: <?= number_format((int)$tRes['ok']) ?></span>
                <span class="badge badge-blue">Ya estaban matriculados: <?= number_format((int)$tRes['ya']) ?></span>
                <span class="badge badge-red">Errores: <?= number_format((int)$tRes['err']) ?></span>
                <span class="badge badge-gray">Saltados (sin cuenta Moodle): <?= number_format((int)$tRes['saltados']) ?></span>
            </p>
            <div class="table-container">
                <table>
                    <thead><tr><th>Curso</th><th>Matrículas nuevas</th><th>Ya matriculados</th><th>Errores</th></tr></thead>
                    <tbody>
                    <?php foreach ($res['cursos'] as $cRes):
                        $stRes = $res['stats'][$cRes['id']] ?? ['ok' => 0, 'ya' => 0, 'err' => 0];
                    ?>
                        <tr>
                            <td>#<?= (int)$cRes['id'] ?> — <?= htmlspecialchars($cRes['nombre']) ?></td>
                            <td><?= (int)$stRes['ok'] ?></td>
                            <td class="muted"><?= (int)$stRes['ya'] ?></td>
                            <td <?= (int)$stRes['err'] > 0 ? 'style="color:#991B1B; font-weight:700;"' : '' ?>><?= (int)$stRes['err'] ?></td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
            <a href="index.php?section=cursos" class="btn btn-primary">&larr; Volver a Cursos Moodle</a>
            <p class="muted" style="margin-top:12px;">&#128274; Esta herramienta solo AÑADE matrículas; nunca las elimina.</p>
        </div>

        <?php else:
            // ── LISTADO: catálogo local (course_catalog) + cursos de Moodle ──
            $catalogoCursos = [];
            $catalogoExiste = true;
            try {
                $stmtCatList = $conexion->query("SELECT course_id, course_type, visible, sort_order, updated_at FROM course_catalog");
                foreach ($stmtCatList->fetchAll(PDO::FETCH_ASSOC) as $filaCatList) {
                    $catalogoCursos[(int)$filaCatList['course_id']] = $filaCatList;
                }
            } catch (PDOException $exCatList) {
                $catalogoExiste = false;
                error_log('[ADMIN][cursos] course_catalog no disponible: ' . $exCatList->getMessage());
            }

            // Cursos del sitio desde Moodle (token global, mismo client que get_courses.php)
            $moodleCursosOk = true;
            $moodleCursosError = '';
            $cursosMoodleLista = [];
            $mcCursos = null;
            if ($catalogoExiste) {
                try {
                    $mcCursos = getMoodleClient();
                    $cursosMoodleLista = $mcCursos->request(MOODLE_WS_TOKEN, 'core_course_get_courses', []);
                    if (!is_array($cursosMoodleLista)) {
                        $cursosMoodleLista = [];
                    }
                } catch (Exception $exMoodleLista) {
                    $moodleCursosOk = false;
                    $moodleCursosError = trim(str_replace('[MoodleClient]', '', $exMoodleLista->getMessage()));
                    if (mb_strlen($moodleCursosError) > 160) {
                        $moodleCursosError = mb_substr($moodleCursosError, 0, 157) . '...';
                    }
                    $cursosMoodleLista = [];
                }
            }

            // Filtros (GET): búsqueda por nombre y tipo
            $qCursos = trim((string)($_GET['q'] ?? ''));
            $tipoFiltro = (string)($_GET['tipo'] ?? 'todos');
            if (!in_array($tipoFiltro, ['todos', 'curso', 'simulacro', 'reto', 'otro', 'sin'], true)) {
                $tipoFiltro = 'todos';
            }
            $pagCursos = max(1, (int)($_GET['pag'] ?? 1));
            $porPaginaCursos = 50;

            // Fusión: curso Moodle + su fila del catálogo (si existe)
            $fusionCursos = [];
            foreach ($cursosMoodleLista as $cMoodle) {
                $idMoodle = (int)($cMoodle['id'] ?? 0);
                if ($idMoodle <= 0) {
                    continue;
                }
                $enCatalogo = isset($catalogoCursos[$idMoodle]);
                $fusionCursos[] = [
                    'id'             => $idMoodle,
                    'fullname'       => (string)($cMoodle['fullname'] ?? ''),
                    'shortname'      => (string)($cMoodle['shortname'] ?? ''),
                    'category'       => (int)($cMoodle['categoryid'] ?? $cMoodle['category'] ?? 0),
                    'moodle_visible' => (int)($cMoodle['visible'] ?? 1),
                    'tipo'           => $enCatalogo ? (string)$catalogoCursos[$idMoodle]['course_type'] : null,
                    'cat_visible'    => $enCatalogo ? (int)$catalogoCursos[$idMoodle]['visible'] : null,
                    'sort_order'     => $enCatalogo ? (int)$catalogoCursos[$idMoodle]['sort_order'] : 0,
                ];
            }

            // Filtro por texto (fullname, shortname o id exacto)
            if ($qCursos !== '') {
                $qCursosLow = mb_strtolower($qCursos);
                $qCursosInt = (int)$qCursos;
                $fusionCursos = array_values(array_filter($fusionCursos, function (array $cF) use ($qCursosLow, $qCursosInt): bool {
                    return ($qCursosInt > 0 && $cF['id'] === $qCursosInt)
                        || mb_strpos(mb_strtolower($cF['fullname']), $qCursosLow) !== false
                        || mb_strpos(mb_strtolower($cF['shortname']), $qCursosLow) !== false;
                }));
            }

            // Filtro por tipo ('sin' = sin clasificar)
            if ($tipoFiltro !== 'todos') {
                $fusionCursos = array_values(array_filter($fusionCursos, function (array $cF) use ($tipoFiltro): bool {
                    return $tipoFiltro === 'sin' ? $cF['tipo'] === null : $cF['tipo'] === $tipoFiltro;
                }));
            }

            // Orden: tipo (curso→simulacro→reto→otro→sin clasificar), sort_order, id
            $cursosRankTipo = ['curso' => 1, 'simulacro' => 2, 'reto' => 3, 'otro' => 4];
            usort($fusionCursos, function (array $a, array $b) use ($cursosRankTipo): int {
                $ra = $cursosRankTipo[$a['tipo']] ?? 5;
                $rb = $cursosRankTipo[$b['tipo']] ?? 5;
                if ($ra !== $rb) { return $ra <=> $rb; }
                if ($a['sort_order'] !== $b['sort_order']) { return $a['sort_order'] <=> $b['sort_order']; }
                return $a['id'] <=> $b['id'];
            });

            $totalFiltradoCursos = count($fusionCursos);
            $totalPaginasCursos = max(1, (int)ceil($totalFiltradoCursos / $porPaginaCursos));
            $pagCursos = min($pagCursos, $totalPaginasCursos);
            $paginaCursos = array_slice($fusionCursos, ($pagCursos - 1) * $porPaginaCursos, $porPaginaCursos);

            // Matriculados por curso: SOLO la página actual (máx. 50 llamadas).
            // Si el WS no existe en este Moodle (exception) → "—" y se deja de intentar.
            $countsCursos = [];
            if ($moodleCursosOk && $mcCursos !== null && !empty($paginaCursos)) {
                foreach ($paginaCursos as $cCount) {
                    try {
                        $respCount = $mcCursos->request(MOODLE_WS_TOKEN, 'core_enrol_get_enrolled_users_count', ['courseid' => $cCount['id']]);
                        $valorCount = null;
                        if (is_array($respCount)) {
                            if (isset($respCount['count'])) {
                                $valorCount = (int)$respCount['count'];
                            } elseif (isset($respCount['enrolledusers'])) {
                                $valorCount = (int)$respCount['enrolledusers'];
                            } else {
                                foreach ($respCount as $itemCount) {
                                    if (is_array($itemCount) && (int)($itemCount['courseid'] ?? 0) === $cCount['id']) {
                                        $valorCount = (int)($itemCount['count'] ?? $itemCount['enrolledusers'] ?? 0);
                                        break;
                                    }
                                }
                            }
                        }
                        $countsCursos[$cCount['id']] = $valorCount;
                    } catch (Exception $exCount) {
                        // WS no disponible / error → el resto de la página se muestra con "—"
                        $countsCursos[$cCount['id']] = null;
                        break;
                    }
                }
            }
        ?>

        <?php if (!$catalogoExiste): ?>
            <div class="section-card">
                <h3 class="section-title">Migración pendiente</h3>
                <p class="muted">Ejecuta <code>backend/migrations/009_course_catalog.sql</code> en MySQL para habilitar esta sección.</p>
            </div>
        <?php elseif (!$moodleCursosOk): ?>
            <!-- Moodle caído: aviso elegante + tabla local del catálogo (la página NO muere) -->
            <div class="section-card" style="background:#FEF2F2; border:1px solid #FECACA;">
                <h3 class="section-title">&#9888;&#65039; No se pudo conectar con Moodle</h3>
                <p class="muted">No se pudo conectar con Moodle: <?= htmlspecialchars($moodleCursosError) ?></p>
                <p class="muted">Mientras tanto se muestra solo el catálogo local (tabla <code>course_catalog</code>). Reintenta en unos minutos.</p>
            </div>
            <div class="table-container">
                <table>
                    <thead><tr><th>ID curso</th><th>Tipo</th><th>Visible en app</th><th>Orden</th><th>Actualizado</th></tr></thead>
                    <tbody>
                    <?php if (empty($catalogoCursos)): ?>
                        <tr><td colspan="5" class="muted" style="text-align:center;padding:24px;">El catálogo está vacío. Ejecuta la migración 009 con su siembra inicial.</td></tr>
                    <?php else: foreach ($catalogoCursos as $idCatTd => $filaCatTd): ?>
                        <tr>
                            <td><?= (int)$idCatTd ?></td>
                            <td><span class="badge <?= $cursosTiposBadge[$filaCatTd['course_type']] ?? 'badge-gray' ?>"><?= htmlspecialchars($cursosTiposLabels[$filaCatTd['course_type']] ?? (string)$filaCatTd['course_type']) ?></span></td>
                            <td><?= (int)$filaCatTd['visible'] === 1 ? '<span class="badge badge-green">Sí</span>' : '<span class="badge badge-red">No</span>' ?></td>
                            <td><?= (int)$filaCatTd['sort_order'] ?></td>
                            <td class="muted"><?= htmlspecialchars((string)($filaCatTd['updated_at'] ?? '-')) ?></td>
                        </tr>
                    <?php endforeach; endif; ?>
                    </tbody>
                </table>
            </div>
        <?php else: ?>
            <!-- Ayuda -->
            <div class="section-card" style="background:#EEF2FF; border:1px solid #C7D2FE;">
                <p style="font-size:14px; line-height:1.7; margin:0;">
                    <span class="badge badge-blue">&#128218; Catálogo dinámico</span>
                    Clasifica cada curso de Moodle como <strong>curso</strong>, <strong>simulacro</strong> o <strong>reto</strong>: la app lo aplica de inmediato (get_courses.php lee esta tabla). Los cursos <em>sin clasificar</em> o con tipo <em>otro</em> no se muestran en la app. La matrícula de usuarios nuevos (set_password.php) cubre todos los cursos visibles del catálogo.
                    <br><strong>&#128274; La matrícula masiva solo AÑADE matrículas; nunca las elimina.</strong>
                </p>
            </div>

            <!-- Filtros -->
            <div class="section-card" style="padding:16px 20px;">
                <form method="GET" action="index.php" style="display:flex; gap:12px; align-items:center; flex-wrap:wrap;">
                    <input type="hidden" name="section" value="cursos">
                    <input type="text" name="q" placeholder="Buscar por nombre o ID de curso..." value="<?= htmlspecialchars($qCursos) ?>" style="flex:1; min-width:220px; padding:10px 14px; border:2px solid #e2e8f0; border-radius:10px; font-size:14px;">
                    <select name="tipo" style="padding:10px 14px; border:2px solid #e2e8f0; border-radius:10px; font-size:14px;">
                        <?php foreach (['todos' => 'Todos los tipos', 'curso' => 'Cursos', 'simulacro' => 'Simulacros', 'reto' => 'Retos', 'otro' => 'Otro', 'sin' => 'Sin clasificar'] as $tipoFK => $tipoFL): ?>
                            <option value="<?= $tipoFK ?>" <?= $tipoFiltro === $tipoFK ? 'selected' : '' ?>><?= htmlspecialchars($tipoFL) ?></option>
                        <?php endforeach; ?>
                    </select>
                    <button type="submit" class="btn btn-primary">Filtrar</button>
                    <?php if ($qCursos !== '' || $tipoFiltro !== 'todos'): ?>
                        <a href="index.php?section=cursos" class="btn" style="background:#e2e8f0; color:#334155;">Limpiar</a>
                    <?php endif; ?>
                    <span class="muted"><?= number_format($totalFiltradoCursos) ?> cursos</span>
                </form>
            </div>

            <!-- Acciones masivas: los checkboxes de la tabla reportan a este form (atributo form=) -->
            <div class="section-card">
                <h3 class="section-title">Acciones masivas</h3>
                <form method="POST" action="index.php?section=cursos" id="formCursosBulk">
                    <?= admin_csrf_field() ?>
                    <div style="display:flex; gap:24px; align-items:flex-end; flex-wrap:wrap;">
                        <div class="form-group" style="margin:0;">
                            <label>Clasificar seleccionados como</label>
                            <div style="display:flex; gap:8px;">
                                <select name="course_type" style="width:auto;">
                                    <?php foreach ($cursosTiposLabels as $tipoOptK => $tipoOptL): ?>
                                        <option value="<?= $tipoOptK ?>"><?= htmlspecialchars($tipoOptL) ?></option>
                                    <?php endforeach; ?>
                                </select>
                                <button type="submit" name="curso_clasif_bulk" value="1" class="btn btn-primary" onclick="return validarSeleccionCursos('¿Clasificar los cursos seleccionados con el tipo elegido?');">Clasificar seleccionados</button>
                            </div>
                        </div>
                        <div class="form-group" style="margin:0;">
                            <label>Matrícula masiva del segmento</label>
                            <div style="display:flex; gap:8px;">
                                <select name="segmento" style="width:auto;">
                                    <?php foreach ($cursosSegmentosLabels as $segK => $segL): ?>
                                        <option value="<?= $segK ?>"><?= htmlspecialchars($segL) ?></option>
                                    <?php endforeach; ?>
                                </select>
                                <button type="submit" name="curso_enrol_preview" value="1" class="btn btn-success" onclick="return validarSeleccionCursos('');">Previsualizar matrícula</button>
                            </div>
                        </div>
                    </div>
                </form>
                <p class="muted" style="margin-top:10px;">
                    Marca cursos con la primera columna. La clasificación se aplica al instante; la matrícula muestra un resumen y pide confirmación antes de ejecutarse.
                    <strong>&#128274; Solo AÑADE matrículas; nunca las elimina.</strong>
                </p>
                <script>
                    function validarSeleccionCursos(mensajeClasif) {
                        var n = document.querySelectorAll('input[name="course_ids[]"]:checked').length;
                        if (n === 0) {
                            alert('Selecciona al menos un curso con la primera columna.');
                            return false;
                        }
                        if (mensajeClasif) {
                            return confirm(mensajeClasif + ' (' + n + ' curso(s))');
                        }
                        return true;
                    }
                </script>
            </div>

            <!-- Tabla de cursos -->
            <div class="table-container">
                <table>
                    <thead><tr><th></th><th>ID</th><th>Nombre</th><th>Categoría</th><th>Tipo</th><th>Matriculados</th><th>Visible en app</th><th>Acción</th></tr></thead>
                    <tbody>
                    <?php if (empty($paginaCursos)): ?>
                        <tr><td colspan="8" class="muted" style="text-align:center;padding:24px;">Sin resultados con esos filtros.</td></tr>
                    <?php else: foreach ($paginaCursos as $cRow):
                        $fullnameCursos = $cRow['fullname'];
                        $fullnameCursosTrunc = mb_strlen($fullnameCursos) > 60 ? mb_substr($fullnameCursos, 0, 57) . '...' : $fullnameCursos;
                    ?>
                        <tr>
                            <td><input type="checkbox" name="course_ids[]" value="<?= (int)$cRow['id'] ?>" form="formCursosBulk" style="width:auto;"></td>
                            <td><?= (int)$cRow['id'] ?></td>
                            <td>
                                <span title="<?= htmlspecialchars($fullnameCursos) ?>"><strong><?= htmlspecialchars($fullnameCursosTrunc) ?></strong></span><?= $cRow['shortname'] !== '' ? '<br><span class="muted mono">' . htmlspecialchars($cRow['shortname']) . '</span>' : '' ?>
                            </td>
                            <td class="muted"><?= (int)$cRow['category'] ?></td>
                            <td><?= $cRow['tipo'] !== null
                                ? '<span class="badge ' . ($cursosTiposBadge[$cRow['tipo']] ?? 'badge-gray') . '">' . htmlspecialchars($cursosTiposLabels[$cRow['tipo']] ?? (string)$cRow['tipo']) . '</span>'
                                : '<span class="badge badge-gray">Sin clasificar</span>' ?></td>
                            <td><?= (isset($countsCursos[$cRow['id']]) && $countsCursos[$cRow['id']] !== null) ? number_format((int)$countsCursos[$cRow['id']]) : '&mdash;' ?></td>
                            <td><?= $cRow['cat_visible'] === null
                                ? '<span class="muted">&mdash;</span>'
                                : ((int)$cRow['cat_visible'] === 1 ? '<span class="badge badge-green">Sí</span>' : '<span class="badge badge-red">No</span>') ?></td>
                            <td>
                                <form method="POST" action="index.php?section=cursos" style="display:flex; gap:6px; align-items:center;">
                                    <?= admin_csrf_field() ?>
                                    <input type="hidden" name="course_id" value="<?= (int)$cRow['id'] ?>">
                                    <select name="course_type" style="padding:6px 8px; border:2px solid #e2e8f0; border-radius:8px; font-size:12px; width:auto;">
                                        <?php foreach ($cursosTiposLabels as $tipoOptK2 => $tipoOptL2): ?>
                                            <option value="<?= $tipoOptK2 ?>" <?= $cRow['tipo'] === $tipoOptK2 ? 'selected' : '' ?>><?= htmlspecialchars($tipoOptL2) ?></option>
                                        <?php endforeach; ?>
                                    </select>
                                    <label style="display:flex; align-items:center; gap:4px; font-size:11px; color:#555; white-space:nowrap;">
                                        <input type="checkbox" name="visible" style="width:auto;" <?= ($cRow['cat_visible'] === null || (int)$cRow['cat_visible'] === 1) ? 'checked' : '' ?>> App
                                    </label>
                                    <button type="submit" name="curso_clasif" value="1" class="btn btn-primary" style="padding:6px 10px; font-size:12px;">Guardar</button>
                                </form>
                            </td>
                        </tr>
                    <?php endforeach; endif; ?>
                    </tbody>
                </table>
            </div>

            <!-- Paginación simple (50 por página) -->
            <?php if ($totalPaginasCursos > 1): ?>
            <div class="section-card" style="padding:12px 20px; display:flex; gap:8px; align-items:center; flex-wrap:wrap;">
                <?php
                $urlPagCursos = 'index.php?section=cursos&q=' . urlencode($qCursos) . '&tipo=' . urlencode($tipoFiltro) . '&pag=';
                $pagIniCursos = max(1, $pagCursos - 2);
                $pagFinCursos = min($totalPaginasCursos, $pagIniCursos + 4);
                $pagIniCursos = max(1, $pagFinCursos - 4);
                ?>
                <?php if ($pagCursos > 1): ?>
                    <a class="btn" style="background:#e2e8f0; color:#334155; padding:6px 12px; font-size:12px;" href="<?= htmlspecialchars($urlPagCursos . ($pagCursos - 1)) ?>">&larr; Anterior</a>
                <?php endif; ?>
                <?php for ($pC = $pagIniCursos; $pC <= $pagFinCursos; $pC++): ?>
                    <a class="btn <?= $pC === $pagCursos ? 'btn-primary' : '' ?>" style="<?= $pC === $pagCursos ? '' : 'background:#e2e8f0; color:#334155;' ?> padding:6px 12px; font-size:12px;" href="<?= htmlspecialchars($urlPagCursos . $pC) ?>"><?= (int)$pC ?></a>
                <?php endfor; ?>
                <?php if ($pagCursos < $totalPaginasCursos): ?>
                    <a class="btn" style="background:#e2e8f0; color:#334155; padding:6px 12px; font-size:12px;" href="<?= htmlspecialchars($urlPagCursos . ($pagCursos + 1)) ?>">Siguiente &rarr;</a>
                <?php endif; ?>
                <span class="muted" style="margin-left:auto;">Página <?= (int)$pagCursos ?> de <?= (int)$totalPaginasCursos ?> · <?= number_format($totalFiltradoCursos) ?> cursos · 50 por página</span>
            </div>
            <?php endif; ?>
        <?php endif; ?>

        <?php endif; ?>

    <?php elseif ($section === 'ingresos'): ?>
        <!-- ✅ PT7: INGRESOS (Administration & Intelligence Center) -->
        <?php
        // Columnas reales verificadas en create_wompi_payment.php / wompi_webhook.php /
        // verify_play_purchase.php: payments(user_id=moodle_id, reference_code, amount,
        // currency, status minúsculas, gateway tras migración 004) + play_purchases (004).
        // Todo con degradación elegante al patrón $safeStat del propio archivo.
        $safeStat('ingresos_total', fn() =>
            round((float)$adminScalar("SELECT COALESCE(SUM(amount), 0) FROM payments WHERE LOWER(status) = 'approved'")));

        $safeStat('ingresos_mes', fn() =>
            round((float)$adminScalar("SELECT COALESCE(SUM(amount), 0) FROM payments WHERE LOWER(status) = 'approved' AND created_at >= DATE_FORMAT(NOW(), '%Y-%m-01')")));

        $safeStat('ingresos_aprobados', fn() =>
            (int)$adminScalar("SELECT COUNT(*) FROM payments WHERE LOWER(status) = 'approved'"));

        $safeStat('ingresos_pendientes', fn() =>
            (int)$adminScalar("SELECT COUNT(*) FROM payments WHERE LOWER(status) = 'pending'"));

        // Compras/suscripciones Google Play verificadas server-side (migración 004)
        $safeStat('ingresos_play', fn() =>
            (int)$adminScalar("SELECT COUNT(*) FROM play_purchases"));

        // Recaudo por gateway (requiere columna gateway — migración 004; degrada si falta)
        $ingresosPorGateway = null;
        try {
            $ingresosPorGateway = $adminFilas("
                SELECT gateway, COUNT(*) AS total, COALESCE(SUM(amount), 0) AS monto
                FROM payments
                WHERE LOWER(status) = 'approved'
                GROUP BY gateway ORDER BY monto DESC
            ");
        } catch (Throwable $exIng) {
            error_log('[ADMIN] ingresos por gateway: ' . $exIng->getMessage());
        }

        // Últimos 20 pagos: SELECT p.* tolera columnas opcionales ausentes (gateway/promo_id)
        $ingresosDisponibles = true;
        $ultimosPagos = [];
        try {
            $ultimosPagos = $adminFilas("
                SELECT p.*, u.email AS user_email, u.nombre AS user_nombre
                FROM payments p
                LEFT JOIN usuarios u ON p.user_id = u.moodle_id
                ORDER BY p.id DESC LIMIT 20
            ");
        } catch (Throwable $exIng2) {
            error_log('[ADMIN] últimos pagos: ' . $exIng2->getMessage());
            $ingresosDisponibles = false;
        }

        $etiquetasGateway = ['wompi' => 'Wompi (web)', 'play_billing' => 'Google Play'];
        $etiquetasEstado = ['approved' => ['badge-green', 'Aprobado'], 'pending' => ['badge-yellow', 'Pendiente'], 'declined' => ['badge-red', 'Rechazado']];
        ?>
        <?php if (!$ingresosDisponibles): ?>
            <div class="section-card">
                <h3 class="section-title">Ingresos no disponibles</h3>
                <p class="muted">No se pudo consultar la tabla <code>payments</code>. Revisa el log del servidor.</p>
            </div>
        <?php else: ?>
        <div class="section-card" style="padding:16px 20px; display:flex; justify-content:space-between; align-items:center; gap:12px; flex-wrap:wrap;">
            <p class="muted" style="margin:0;">
                Recaudo de pagos <strong>aprobados</strong>: Wompi (web) y Google Play Billing (Android).
                Los pagos de Play se registran en <code>payments</code> al verificarse contra la API de Google.
            </p>
            <!-- ✅ PT7: exportación CSV de pagos -->
            <a href="export_csv.php?type=pagos" class="btn btn-success">&#11015; Exportar CSV</a>
        </div>
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-icon" style="background: #D1FAE5;">&#128176;</div>
                <div class="stat-value">$<?= number_format((float)$stats['ingresos_total']) ?></div>
                <div class="stat-label">Total Recaudado (COP)</div>
                <div class="stat-change"><?= number_format($stats['ingresos_aprobados']) ?> pagos aprobados</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #DBEAFE;">&#128197;</div>
                <div class="stat-value">$<?= number_format((float)$stats['ingresos_mes']) ?></div>
                <div class="stat-label">Recaudado Este Mes</div>
                <div class="stat-change">Desde el 1 del mes en curso</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #FEF3C7;">&#9203;</div>
                <div class="stat-value"><?= number_format($stats['ingresos_pendientes']) ?></div>
                <div class="stat-label">Pagos Pendientes</div>
                <div class="stat-change">En proceso de confirmación</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="background: #E9D5FF;">&#127917;</div>
                <div class="stat-value"><?= number_format($stats['ingresos_play']) ?></div>
                <div class="stat-label">Compras Google Play</div>
                <div class="stat-change">Verificadas server-side (play_purchases)</div>
            </div>
        </div>

        <div class="grid-2">
            <div class="section-card">
                <h3 class="section-title">&#128202; Recaudo por pasarela</h3>
                <?php if ($ingresosPorGateway === null): ?>
                    <p class="muted">Columna <code>gateway</code> no disponible todavía — ejecuta la migración 004
                    (<code>backend/migrations/004_play_billing.sql</code>).</p>
                <?php elseif (!$ingresosPorGateway): ?>
                    <p class="muted">Sin pagos aprobados aún.</p>
                <?php else:
                    $maxMonto = max(1, (float)max(array_column($ingresosPorGateway, 'monto'))); ?>
                    <?php foreach ($ingresosPorGateway as $g):
                        $etiquetaGw = $etiquetasGateway[$g['gateway']] ?? $g['gateway']; ?>
                        <div class="bar-row">
                            <div class="bar-label" title="<?= htmlspecialchars((string)$g['gateway']) ?>"><?= htmlspecialchars($etiquetaGw) ?></div>
                            <div class="bar-track"><div class="bar-fill green" style="width: <?= round((float)$g['monto'] / $maxMonto * 100) ?>%"></div></div>
                            <div class="bar-value" style="width:auto; min-width:86px;">$<?= number_format((float)$g['monto']) ?></div>
                        </div>
                        <p class="muted" style="margin:0 0 6px 94px; font-size:11px;"><?= number_format((int)$g['total']) ?> pago(s) aprobado(s)</p>
                    <?php endforeach; ?>
                <?php endif; ?>
            </div>
            <div class="section-card">
                <h3 class="section-title">&#128179; Conversión Free → Premium</h3>
                <?php $totalBase = max(1, (int)$stats['total_users_all']); ?>
                <div class="bar-row">
                    <div class="bar-label">Premium</div>
                    <div class="bar-track"><div class="bar-fill" style="width: <?= min(100, round((int)$stats['premium_users'] * 100 / $totalBase)) ?>%"></div></div>
                    <div class="bar-value"><?= $stats['premium_users'] ?></div>
                </div>
                <div class="bar-row">
                    <div class="bar-label">Free</div>
                    <div class="bar-track"><div class="bar-fill green" style="width: <?= min(100, round((int)$stats['free_users'] * 100 / $totalBase)) ?>%"></div></div>
                    <div class="bar-value"><?= $stats['free_users'] ?></div>
                </div>
                <p class="muted" style="margin-top:12px;">Conversión global: <strong><?= number_format((float)($stats['conversion_premium'] ?? 0), 1) ?>%</strong> sobre <?= number_format($stats['total_users_all']) ?> usuarios registrados.</p>
            </div>
        </div>

        <div class="table-container">
            <table>
                <thead><tr><th>Fecha</th><th>Usuario</th><th>Monto</th><th>Pasarela</th><th>Estado</th><th>Referencia</th></tr></thead>
                <tbody>
                <?php if (!$ultimosPagos): ?>
                    <tr><td colspan="6" class="muted" style="text-align:center;padding:24px;">Aún no hay pagos registrados.</td></tr>
                <?php else: foreach ($ultimosPagos as $p):
                    $estadoK = strtolower((string)($p['status'] ?? ''));
                    [$badgeEst, $txtEst] = $etiquetasEstado[$estadoK] ?? ['badge-gray', ucfirst($estadoK)];
                    $gw = (string)($p['gateway'] ?? '');
                    $etiquetaGw = $etiquetasGateway[$gw] ?? ($gw !== '' ? $gw : '—');
                    $fechaPago = (string)($p['created_at'] ?? ($p['updated_at'] ?? '—'));
                ?>
                    <tr>
                        <td class="mono"><?= htmlspecialchars($fechaPago) ?></td>
                        <td><?php if (!empty($p['user_email'])): ?><strong><?= htmlspecialchars($p['user_nombre'] ?? '') ?></strong><br><span class="muted" style="font-size:12px;"><?= htmlspecialchars($p['user_email']) ?></span><?php else: ?><span class="muted">Usuario Moodle #<?= (int)($p['user_id'] ?? 0) ?></span><?php endif; ?></td>
                        <td><strong>$<?= number_format((float)($p['amount'] ?? 0)) ?></strong> <span class="muted" style="font-size:11px;"><?= htmlspecialchars((string)($p['currency'] ?? '')) ?></span></td>
                        <td><span class="badge badge-blue"><?= htmlspecialchars($etiquetaGw) ?></span></td>
                        <td><span class="badge <?= $badgeEst ?>"><?= htmlspecialchars($txtEst) ?></span></td>
                        <td class="mono" title="<?= htmlspecialchars((string)($p['reference_code'] ?? '')) ?>"><?= htmlspecialchars(mb_substr((string)($p['reference_code'] ?? ''), 0, 28)) ?><?= mb_strlen((string)($p['reference_code'] ?? '')) > 28 ? '...' : '' ?></td>
                    </tr>
                <?php endforeach; endif; ?>
                </tbody>
            </table>
        </div>
        <?php endif; ?>

    <?php elseif ($section === 'academica'): ?>
        <!-- ✅ PT7: ANALÍTICA EDUCATIVA (Administration & Intelligence Center) -->
        <?php
        // Degradación elegante: cada consulta en su try/catch (patrón $safeStat)
        $promAreas = null;
        try {
            $promAreas = $adminFilas("
                SELECT ROUND(AVG(lectura_puntaje),1)      AS lectura,
                       ROUND(AVG(matematicas_puntaje),1)  AS matematicas,
                       ROUND(AVG(sociales_puntaje),1)     AS sociales,
                       ROUND(AVG(naturales_puntaje),1)    AS naturales,
                       ROUND(AVG(ingles_puntaje),1)       AS ingles
                FROM simulacro_resultados
            ")[0] ?? null;
        } catch (Throwable $exA) {
            error_log('[ADMIN] academica promedios: ' . $exA->getMessage());
        }

        $distribucion = [];
        try {
            $distribucion = $adminFilas("
                SELECT LEAST(FLOOR(puntaje_global / 100), 4) AS rango, COUNT(*) AS c
                FROM simulacro_resultados
                WHERE puntaje_global IS NOT NULL
                GROUP BY rango ORDER BY rango ASC
            ");
        } catch (Throwable $exB) {
            error_log('[ADMIN] academica distribución: ' . $exB->getMessage());
        }

        // Top colegios por volumen (patrón de ranking_institucional.php /
        // director/export_csv.php: sr.usuario_id = u.moodle_id + TRIM del colegio)
        $topColegiosSim = [];
        try {
            $topColegiosSim = $adminFilas("
                SELECT TRIM(u.colegio) AS colegio,
                       COUNT(*) AS simulacros,
                       COUNT(DISTINCT sr.usuario_id) AS estudiantes,
                       ROUND(AVG(sr.puntaje_global), 1) AS promedio
                FROM simulacro_resultados sr
                INNER JOIN usuarios u ON sr.usuario_id = u.moodle_id
                WHERE u.colegio IS NOT NULL AND TRIM(u.colegio) <> ''
                GROUP BY TRIM(u.colegio)
                ORDER BY simulacros DESC LIMIT 10
            ");
        } catch (Throwable $exC) {
            error_log('[ADMIN] academica top colegios: ' . $exC->getMessage());
        }

        // Heatmap área × grado (promedio 0-100 por área, coloreado por intensidad)
        $heatmapGrados = [];
        try {
            $heatmapGrados = $adminFilas("
                SELECT u.grado, COUNT(*) AS total,
                       ROUND(AVG(sr.lectura_puntaje),1)      AS lectura,
                       ROUND(AVG(sr.matematicas_puntaje),1)  AS matematicas,
                       ROUND(AVG(sr.sociales_puntaje),1)     AS sociales,
                       ROUND(AVG(sr.naturales_puntaje),1)    AS naturales,
                       ROUND(AVG(sr.ingles_puntaje),1)       AS ingles
                FROM simulacro_resultados sr
                INNER JOIN usuarios u ON sr.usuario_id = u.moodle_id
                WHERE u.grado IS NOT NULL AND TRIM(u.grado) <> ''
                GROUP BY u.grado
                HAVING total >= 3
                ORDER BY LENGTH(TRIM(u.grado)), TRIM(u.grado)
                LIMIT 15
            ");
        } catch (Throwable $exD) {
            error_log('[ADMIN] academica heatmap: ' . $exD->getMessage());
        }

        $areasDef = [
            'Lectura Crítica' => ['lectura', '#1E4ED8'],
            'Matemáticas'     => ['matematicas', '#22C55E'],
            'Sociales'        => ['sociales', '#F59E0B'],
            'Naturales'       => ['naturales', '#8B5CF6'],
            'Inglés'          => ['ingles', '#EF4444'],
        ];
        $rangosLbl = ['0-100', '100-200', '200-300', '300-400', '400-500'];
        ?>
        <div class="section-card" style="padding:16px 20px; display:flex; justify-content:space-between; align-items:center; gap:12px; flex-wrap:wrap;">
            <p class="muted" style="margin:0;">
                Desempeño agregado de los simulacros ICFES: promedios por área (0-100), distribución del
                puntaje global (0-500), colegios más activos y mapa de calor área × grado.
            </p>
            <!-- ✅ PT7: exportación CSV de resultados -->
            <a href="export_csv.php?type=resultados" class="btn btn-success">&#11015; Exportar CSV</a>
        </div>

        <div class="section-card">
            <h3 class="section-title">&#127891; Promedio por área (todos los simulacros)</h3>
            <?php if ($promAreas === null): ?>
                <p class="muted">Sin datos todavía: no hay simulacros registrados o la tabla no está disponible.</p>
            <?php else: foreach ($areasDef as $nombreArea => [$claveArea, $colorArea]):
                $valorArea = (float)($promAreas[$claveArea] ?? 0); ?>
                <div class="bar-row">
                    <div class="bar-label"><?= htmlspecialchars($nombreArea) ?></div>
                    <div class="bar-track"><div class="bar-fill" style="width: <?= min(100, round($valorArea)) ?>%; background: <?= htmlspecialchars($colorArea) ?>;"></div></div>
                    <div class="bar-value"><?= number_format($valorArea, 1) ?></div>
                </div>
            <?php endforeach; endif; ?>
            <p class="muted" style="margin-top:12px;">Cada área se puntúa de 0 a 100 en la prueba Saber 11.</p>
        </div>

        <div class="grid-2">
            <div class="section-card">
                <h3 class="section-title">&#128202; Distribución de puntajes globales</h3>
                <?php if (!$distribucion): ?>
                    <p class="muted">Sin resultados aún.</p>
                <?php else:
                    $maxDist = max(1, (int)max(array_column($distribucion, 'c'))); ?>
                    <?php foreach ($distribucion as $d):
                        $etiqueta = $rangosLbl[(int)$d['rango']] ?? ((int)$d['rango'] * 100 . '+'); ?>
                        <div class="bar-row">
                            <div class="bar-label"><?= htmlspecialchars($etiqueta) ?></div>
                            <div class="bar-track"><div class="bar-fill" style="width: <?= round((int)$d['c'] / $maxDist * 100) ?>%"></div></div>
                            <div class="bar-value"><?= number_format((int)$d['c']) ?></div>
                        </div>
                    <?php endforeach; ?>
                <?php endif; ?>
                <p class="muted" style="margin-top:12px;">Rangos de puntaje global ICFES (0-500).</p>
            </div>
            <div class="section-card">
                <h3 class="section-title">&#127979; Top 10 colegios por volumen de simulacros</h3>
                <div class="table-container" style="box-shadow:none; margin-bottom:0;">
                    <table>
                        <thead><tr><th>#</th><th>Colegio</th><th>Simulacros</th><th>Estudiantes</th><th>Promedio</th></tr></thead>
                        <tbody>
                        <?php if (!$topColegiosSim): ?>
                            <tr><td colspan="5" class="muted" style="text-align:center;padding:24px;">Sin datos aún (requiere colegio informado por los estudiantes).</td></tr>
                        <?php else: foreach ($topColegiosSim as $i => $c): ?>
                            <tr>
                                <td><?= $i + 1 ?></td>
                                <td><?= htmlspecialchars($c['colegio']) ?></td>
                                <td><strong><?= number_format((int)$c['simulacros']) ?></strong></td>
                                <td><?= number_format((int)$c['estudiantes']) ?></td>
                                <td><?= htmlspecialchars((string)$c['promedio']) ?></td>
                            </tr>
                        <?php endforeach; endif; ?>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <?php if (!empty($heatmapGrados)): ?>
        <div class="section-card">
            <h3 class="section-title">&#128295; Mapa de calor: promedio por área × grado</h3>
            <p class="muted" style="margin-bottom:12px;">Intensidad del azul = desempeño del área (0-100). Grados con al menos 3 simulacros.</p>
            <div class="table-container" style="overflow-x:auto;">
                <table>
                    <thead><tr><th>Grado</th><th>Lectura</th><th>Matemáticas</th><th>Sociales</th><th>Naturales</th><th>Inglés</th><th>Simulacros</th></tr></thead>
                    <tbody>
                    <?php foreach ($heatmapGrados as $hg): ?>
                        <tr>
                            <td><strong><?= htmlspecialchars((string)$hg['grado']) ?></strong></td>
                            <?php foreach (['lectura', 'matematicas', 'sociales', 'naturales', 'ingles'] as $colHm):
                                $v = (float)($hg[$colHm] ?? 0);
                                $intensidad = max(0.05, min(1, $v / 100));
                                $colorTxt = $intensidad > 0.55 ? '#FFFFFF' : '#1E3A8A'; ?>
                                <td style="background: rgba(30, 78, 216, <?= round($intensidad, 2) ?>); color: <?= $colorTxt ?>; font-weight:700; text-align:center;"><?= number_format($v, 1) ?></td>
                            <?php endforeach; ?>
                            <td class="muted" style="text-align:center;"><?= number_format((int)$hg['total']) ?></td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <?php endif; ?>

    <?php elseif ($section === 'auditoria'): ?>
        <!-- ✅ PT7: AUDITORÍA DE ACCIONES ADMIN (migración 007) -->
        <?php
        $auditoriaDisponible = true;
        $auditoriaFilas = [];
        try {
            $stmtAud = $conexion->prepare("
                SELECT id, admin_user, action, entity, entity_id, details, ip, created_at
                FROM admin_audit_log
                ORDER BY id DESC LIMIT 50
            ");
            $stmtAud->execute();
            $auditoriaFilas = $stmtAud->fetchAll(PDO::FETCH_ASSOC);
        } catch (Throwable $exAud) {
            error_log('[ADMIN] auditoría: ' . $exAud->getMessage());
            $auditoriaDisponible = false;
        }
        ?>
        <?php if (!$auditoriaDisponible): ?>
            <div class="section-card">
                <h3 class="section-title">Migración pendiente</h3>
                <p class="muted">La tabla <code>admin_audit_log</code> no existe todavía.
                Ejecuta la migración: <code>mysql -u &lt;usuario&gt; -p &lt;basedatos&gt; &lt; backend/migrations/007_admin_intelligence.sql</code></p>
                <p class="muted">Mientras tanto, las acciones sensibles del panel funcionan con normalidad (la auditoría degrada a no-op silencioso).</p>
            </div>
        <?php else: ?>
        <div class="table-container">
            <table>
                <thead><tr><th>Fecha</th><th>Admin</th><th>Acción</th><th>Entidad</th><th>Detalles</th><th>IP</th></tr></thead>
                <tbody>
                <?php if (!$auditoriaFilas): ?>
                    <tr><td colspan="6" class="muted" style="text-align:center;padding:24px;">Sin registros aún. Las acciones sensibles del panel (directores, promociones, soporte, edición de usuarios, exportes) quedarán registradas aquí.</td></tr>
                <?php else: foreach ($auditoriaFilas as $au): ?>
                    <tr>
                        <td class="mono"><?= htmlspecialchars((string)$au['created_at']) ?></td>
                        <td><strong><?= htmlspecialchars($au['admin_user']) ?></strong></td>
                        <td><span class="badge badge-blue"><?= htmlspecialchars($au['action']) ?></span></td>
                        <td><?= htmlspecialchars($au['entity'] ?? '-') ?><?= $au['entity_id'] !== null ? ' #' . (int)$au['entity_id'] : '' ?></td>
                        <td class="mono" title="<?= htmlspecialchars((string)$au['details']) ?>"><?= htmlspecialchars(mb_substr((string)($au['details'] ?? ''), 0, 70)) ?><?= mb_strlen((string)($au['details'] ?? '')) > 70 ? '...' : '' ?></td>
                        <td class="mono"><?= htmlspecialchars((string)($au['ip'] ?? '-')) ?></td>
                    </tr>
                <?php endforeach; endif; ?>
                </tbody>
            </table>
        </div>
        <p class="muted">Se muestran las últimas 50 entradas. La auditoría nunca interrumpe la acción que la origina.</p>
        <?php endif; ?>

    <?php endif; ?>
</div>
</body>
</html>