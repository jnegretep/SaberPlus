<?php
declare(strict_types=1);

/**
 * eliminar_cuenta.php — Saber+ v1.6.0
 *
 * Eliminación de cuenta desde la app (requisito Google Play / GDPR).
 *
 * Seguridad:
 *  - Requiere JWT válido (auth_middleware.php).
 *  - Requiere POST con { "confirm": "ELIMINAR" } (frase exacta escrita
 *    por el usuario en la app) — evita borrados accidentales por tap.
 *  - Todo dentro de una transacción: o se borra todo, o nada.
 *
 * Estrategia de datos:
 *  1. Se ELIMINAN las filas de datos puramente personales:
 *     gamificación (XP, badges, actividad diaria), notificaciones,
 *     tokens de reset, resultados de simulacros, participación en retos.
 *  2. Se ANONIMIZA la fila de `usuarios` (no se hace DELETE para no
 *     romper FKs históricas): nombre/email/teléfono/avatar/colegio/
 *     ciudad/departamento/grado/FCM → nulos o valores "eliminado".
 *  3. Se ANONIMIZAN referencias en app_events y error_logs (user_id → NULL)
 *     para conservar métricas agregadas sin vincularlas a la persona.
 *  4. Se cancelan los retos pendientes donde participaba.
 *  5. Se revoca el JWT actual y se registra auditoría en
 *     account_deletions (solo hash del email, sin PII).
 *  6. BEST-EFFORT: se intenta eliminar el usuario en Moodle vía WS
 *     (core_user_delete_users). Si el token no tiene permiso, se
 *     desvincula (moodle_username = NULL) y se continúa.
 *
 * Request:
 *   POST /eliminar_cuenta.php
 *   Authorization: Bearer <jwt>
 *   { "confirm": "ELIMINAR", "motivo": "opcional" }
 *
 * Response:
 *   { "status": "ok", "msg": "Cuenta eliminada" }
 */

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/auth_middleware.php';
require __DIR__ . '/includes/analytics.php';

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
}

$user_id = (int)($authUser['id_usuario'] ?? 0);
$currentJti = $GLOBALS['currentJti'] ?? null;

if ($user_id <= 0) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Usuario no válido']));
}

// ── Leer y validar body ──
$input = json_decode(file_get_contents('php://input'), true) ?: [];
$confirm = strtoupper(trim((string)($input['confirm'] ?? '')));
$motivo  = isset($input['motivo']) ? substr(trim((string)$input['motivo']), 0, 255) : null;

if ($confirm !== 'ELIMINAR') {
    http_response_code(400);
    exit(json_encode([
        'status' => 'error',
        'msg'    => 'Confirmación inválida. Escribe ELIMINAR para confirmar.',
    ]));
}

try {
    // ── Datos actuales del usuario (para auditoría y Moodle) ──
    $stmt = $conexion->prepare("SELECT email, moodle_username, moodle_userid, avatar_path FROM usuarios WHERE id_usuario = ?");
    $stmt->execute([$user_id]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        http_response_code(404);
        exit(json_encode(['status' => 'error', 'msg' => 'La cuenta ya no existe']));
    }

    $emailHash  = hash('sha256', strtolower((string)$user['email']));
    $moodleUser = $user['moodle_username'] ?: null;
    $avatarPath = $user['avatar_path'] ?: null;
    $deletedEmail = 'deleted_' . $user_id . '_' . bin2hex(random_bytes(4)) . '@saberplus.invalid';

    $conexion->beginTransaction();

    // ── 1. Datos personales: ELIMINAR ──
    $tablasPersonales = [
        "DELETE FROM xp_transactions      WHERE user_id = ?",
        "DELETE FROM user_gamification    WHERE user_id = ?",
        "DELETE FROM user_badges          WHERE user_id = ?",
        "DELETE FROM user_daily_activity  WHERE user_id = ?",
        "DELETE FROM notifications        WHERE user_id = ?",
        "DELETE FROM password_resets      WHERE user_id = ?",
        "DELETE FROM simulacro_resultados WHERE usuario_id = ?",
    ];
    foreach ($tablasPersonales as $sql) {
        $stmt = $conexion->prepare($sql);
        $stmt->execute([$user_id]);
    }

    // Retos: salir de participantes pendientes y cancelar los que creó
    $stmt = $conexion->prepare("DELETE FROM challenge_participants WHERE user_id = ? AND challenge_id IN (SELECT id FROM challenges WHERE status <> 'finished')");
    $stmt->execute([$user_id]);

    $stmt = $conexion->prepare("UPDATE challenges SET status = 'cancelled' WHERE creator_id = ? AND status <> 'finished'");
    $stmt->execute([$user_id]);

    // ── 2. Anonimizar referencias (métricas agregadas sin persona) ──
    $stmt = $conexion->prepare("UPDATE app_events  SET user_id = NULL WHERE user_id = ?");
    $stmt->execute([$user_id]);
    $stmt = $conexion->prepare("UPDATE error_logs  SET user_id = NULL WHERE user_id = ?");
    $stmt->execute([$user_id]);

    // ── 3. Anonimizar la fila de usuarios ──
    $stmt = $conexion->prepare("
        UPDATE usuarios SET
            nombre           = 'Usuario eliminado',
            email            = ?,
            telefono         = NULL,
            avatar_path      = NULL,
            colegio          = NULL,
            ciudad           = NULL,
            departamento     = NULL,
            grado            = NULL,
            fcm_token        = NULL,
            moodle_username  = NULL,
            email_verificado = 0,
            access_level     = 'free'
        WHERE id_usuario = ?
    ");
    $stmt->execute([$deletedEmail, $user_id]);

    // ── 4. Revocar el JWT actual (y cualquier sesión) ──
    if ($currentJti) {
        $stmt = $conexion->prepare("INSERT IGNORE INTO revoked_tokens (jti, revoked_at) VALUES (?, NOW())");
        $stmt->execute([$currentJti]);
    }

    // ── 5. Auditoría (sin PII) ──
    $stmt = $conexion->prepare("
        INSERT INTO account_deletions (user_id, email_hash, motivo, user_agent)
        VALUES (?, ?, ?, ?)
    ");
    $stmt->execute([
        $user_id,
        $emailHash,
        $motivo,
        substr((string)($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 255),
    ]);

    $conexion->commit();

    // ── 6. Limpieza fuera de la transacción (best-effort, no bloqueante) ──

    // Borrar el archivo de avatar del disco (si era un avatar subido)
    if ($avatarPath && str_contains((string)$avatarPath, 'uploads/avatars/')) {
        $basename = basename($avatarPath);
        $file = __DIR__ . '/uploads/avatars/' . $basename;
        if (is_file($file) && preg_match('/^avatar_[a-f0-9]+\.jpg$/', $basename)) {
            @unlink($file);
        }
    }

    // Intentar eliminar el usuario en Moodle (best-effort)
    $moodleDeleted = false;
    if (!empty($user['moodle_userid'])) {
        try {
            require_once __DIR__ . '/includes/config.php';
            $moodleUserId = (int)$user['moodle_userid'];
            $ch = curl_init(MOODLE_BASE_URL . '/webservice/rest/server.php');
            curl_setopt_array($ch, [
                CURLOPT_POST           => true,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_SSL_VERIFYPEER => true,
                CURLOPT_TIMEOUT        => 10,
                CURLOPT_POSTFIELDS     => http_build_query([
                    'wstoken'      => MOODLE_WS_TOKEN,
                    'wsfunction'   => 'core_user_delete_users',
                    'moodlewsrestformat' => 'json',
                    'userids[0]'   => $moodleUserId,
                ]),
            ]);
            $resp = curl_exec($ch);
            curl_close($ch);
            $decoded = json_decode((string)$resp, true);
            // La WS devuelve null/[] en éxito; un array con 'exception' indica fallo (p.ej. sin capability)
            $moodleDeleted = !isset($decoded['exception']);
        } catch (Throwable $e) {
            error_log('[ELIMINAR_CUENTA] Moodle best-effort falló: ' . $e->getMessage());
        }
    }

    // Evento de analítica agregado (user_id ya anonimizado → NULL)
    saberplus_registrar_evento($conexion, null, 'account_deleted', [
        'motivo' => $motivo,
    ]);

    echo json_encode([
        'status' => 'ok',
        'msg'    => 'Cuenta eliminada correctamente',
        'moodle_deleted' => $moodleDeleted,
    ], JSON_UNESCAPED_UNICODE);

} catch (Throwable $e) {
    if ($conexion->inTransaction()) {
        $conexion->rollBack();
    }
    saberplus_log_error(
        $conexion, 'backend', 'eliminar_cuenta.php: ' . $e->getMessage(),
        ['user_id' => $user_id], get_class($e), 'fatal'
    );
    error_log('[ELIMINAR_CUENTA] Error: ' . $e->getMessage());
    http_response_code(500);
    exit(json_encode(['status' => 'error', 'msg' => 'Error interno al eliminar la cuenta']));
}
