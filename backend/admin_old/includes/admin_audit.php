<?php
/**
 * ✅ PT7: includes/admin_audit.php — Auditoría de acciones del panel admin.
 *
 * Registra en `admin_audit_log` (migración 007) quién hizo qué y desde qué IP.
 * Reglas de diseño:
 *   - La auditoría JAMÁS rompe la acción que la invoca (try/catch silencioso).
 *   - Si la tabla no existe (migración 007 sin ejecutar), es un no-op y se
 *     deja UNA sola línea de error_log por request para no llenar el log.
 *   - Solo INSERT con prepared statements.
 *
 * Uso:
 *   require_once __DIR__ . '/includes/admin_audit.php';
 *   admin_audit_log($conexion, 'promo_save', 'promociones', $id,
 *                   json_encode(['titulo' => $titulo], JSON_UNESCAPED_UNICODE));
 */

/**
 * ✅ PT7: inserta una entrada de auditoría admin. void — nunca lanza.
 */
function admin_audit_log(PDO $conexion, string $action, ?string $entity = null, ?int $entityId = null, ?string $details = null): void
{
    // Degradación: si ya se detectó que la tabla no existe en este request, no-op.
    static $tablaExiste = null;
    static $yaLogeado = false;

    try {
        if ($tablaExiste === null) {
            // ✅ PT7: comprobación barata y cachada — SHOW TABLES una sola vez por request.
            $stmt = $conexion->query("SHOW TABLES LIKE 'admin_audit_log'");
            $tablaExiste = ($stmt !== false && $stmt->fetchColumn() !== false);
            if (!$tablaExiste && !$yaLogeado) {
                $yaLogeado = true;
                error_log('[ADMIN-AUDIT] Tabla admin_audit_log no existe — ejecuta backend/migrations/007_admin_intelligence.sql (auditoría en no-op).');
            }
        }
        if (!$tablaExiste) {
            return;
        }

        // ✅ PT7: admin de la sesión (se guarda en el login del panel); IP del cliente.
        $adminUser = (string)($_SESSION['admin_user'] ?? 'admin');
        if ($adminUser === '') {
            $adminUser = 'admin';
        }
        $ip = $_SERVER['REMOTE_ADDR'] ?? null;

        $stmt = $conexion->prepare("
            INSERT INTO admin_audit_log (admin_user, action, entity, entity_id, details, ip)
            VALUES (:au, :ac, :en, :ei, :de, :ip)
        ");
        $stmt->execute([
            ':au' => mb_substr($adminUser, 0, 100),
            ':ac' => mb_substr($action, 0, 100),
            ':en' => ($entity !== null ? mb_substr($entity, 0, 100) : null),
            ':ei' => $entityId,
            ':de' => ($details !== null ? mb_substr($details, 0, 4000) : null),
            ':ip' => $ip,
        ]);
    } catch (Throwable $e) {
        // ✅ PT7: silencioso por diseño — auditar nunca rompe la acción principal.
        // Se registra una sola vez por request para no inundar el log.
        if (!$yaLogeado) {
            $yaLogeado = true;
            error_log('[ADMIN-AUDIT] ' . $e->getMessage());
        }
    }
}
