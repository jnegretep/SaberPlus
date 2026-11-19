<?php
declare(strict_types=1);

/**
 * Helper de auditoría extendido para SABER+ Command Center.
 *
 * Extiende el helper original con:
 *  - admin_user_id (FK real, no string)
 *  - module
 *  - before_value / after_value (JSON)
 *  - success flag
 *  - user_agent, session_id
 *
 * Sigue siendo fail-open silencioso (no rompe el flujo principal si la tabla
 * no existe o hay error).
 */

function admin_audit_log(
    PDO $conexion,
    string $action,
    ?string $entity = null,
    ?int $entityId = null,
    ?string $details = null,
    ?string $module = null,
    ?array $beforeValue = null,
    ?array $afterValue = null,
    bool $success = true
): void {
    static $tableExists = null;
    if ($tableExists === null) {
        try {
            $stmt = $conexion->query("SHOW TABLES LIKE 'admin_audit_log'");
            $tableExists = $stmt && $stmt->fetch() !== false;
        } catch (Throwable $e) {
            $tableExists = false;
        }
    }
    if (!$tableExists) {
        static $warned = false;
        if (!$warned) {
            error_log('[AUDIT] Tabla admin_audit_log no existe — audit skipped');
            $warned = true;
        }
        return;
    }

    $adminId   = $_SESSION['admin_user_id'] ?? null;
    $adminEmail = $_SESSION['admin_email'] ?? 'unknown';

    try {
        $stmt = $conexion->prepare(
            "INSERT INTO admin_audit_log
             (admin_user, admin_user_id, module, action, entity, entity_id, details,
              before_value, after_value, success, ip, user_agent, session_id)
             VALUES
             (:admin_user, :admin_user_id, :module, :action, :entity, :entity_id,
              :details, :before_value, :after_value, :success, :ip, :user_agent, :session_id)"
        );
        $stmt->execute([
            ':admin_user'    => mb_substr($adminEmail, 0, 100),
            ':admin_user_id' => $adminId,
            ':module'        => $module ? mb_substr($module, 0, 50) : null,
            ':action'        => mb_substr($action, 0, 100),
            ':entity'        => $entity ? mb_substr($entity, 0, 100) : null,
            ':entity_id'     => $entityId,
            ':details'        => $details ? mb_substr($details, 0, 4000) : null,
            ':before_value' => $beforeValue ? json_encode($beforeValue, JSON_UNESCAPED_UNICODE) : null,
            ':after_value'  => $afterValue ? json_encode($afterValue, JSON_UNESCAPED_UNICODE) : null,
            ':success'       => $success ? 1 : 0,
            ':ip'            => admin_client_ip(),
            ':user_agent'    => mb_substr($_SERVER['HTTP_USER_AGENT'] ?? '', 0, 255),
            ':session_id'    => session_id() ?: null,
        ]);
    } catch (Throwable $e) {
        error_log('[AUDIT] Error insertando: ' . $e->getMessage());
    }
}

/**
 * Conveniencia para auditar un cambio en un registro.
 * Captura before/after de forma automática comparando arrays.
 */
function admin_audit_change(
    PDO $conexion,
    string $module,
    string $action,
    string $entity,
    int $entityId,
    ?array $before,
    array $after,
    bool $success = true
): void {
    $changed = [];
    if ($before !== null) {
        foreach ($after as $k => $v) {
            $old = $before[$k] ?? null;
            if ((string)$old !== (string)$v) {
                $changed[$k] = ['from' => $old, 'to' => $v];
            }
        }
    } else {
        $changed = $after;
    }

    admin_audit_log(
        $conexion,
        $action,
        $entity,
        $entityId,
        json_encode(['changed' => $changed], JSON_UNESCAPED_UNICODE),
        $module,
        $before,
        $after,
        $success
    );
}
