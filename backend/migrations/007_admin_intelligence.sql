-- ============================================================================
-- Migración 007 — Saber+ Administration & Intelligence Center (PT7, ADMIN-PT7)
-- ============================================================================
-- QUÉ HACE:
--   Crea la tabla `admin_audit_log`: registro de las acciones sensibles que
--   ejecuta el administrador desde el panel (crear/activar directores, reset
--   de contraseñas, promociones, respuestas de soporte, edición de usuarios,
--   exportes CSV). Guarda quién, qué, sobre qué entidad, detalles compactos
--   (JSON), IP y fecha — suficiente para trazabilidad sin guardar PII más
--   allá del usuario administrador.
--
-- CÓMO EJECUTARLO (manual, por el propietario — este archivo NO se ejecuta
-- automáticamente y NO toca ninguna tabla existente):
--   mysql -u <usuario> -p <basedatos> < 007_admin_intelligence.sql
--   (ej. mysql -u jnegretep -p prepsaber < 007_admin_intelligence.sql)
--
-- ES SEGURO:
--   - Solo usa CREATE TABLE IF NOT EXISTS: puede ejecutarse varias veces.
--   - No modifica ni elimina tablas/columnas existentes.
--   - Si NO se ejecuta, el panel sigue funcionando: el helper
--     backend/admin/includes/admin_audit.php detecta la ausencia de la tabla
--     y convierte cada llamada en un no-op silencioso (un solo error_log).
-- ============================================================================

CREATE TABLE IF NOT EXISTS admin_audit_log (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    admin_user  VARCHAR(100) NOT NULL,               -- usuario de la sesión admin
    action      VARCHAR(100) NOT NULL,               -- crear_director, promo_save, export_csv, ...
    entity      VARCHAR(100) NULL,                   -- directores, promociones, usuarios, payments, ...
    entity_id   INT NULL,                            -- id de la fila afectada (si aplica)
    details     TEXT NULL,                           -- JSON compacto de parámetros clave
    ip          VARCHAR(45) NULL,                    -- soporta IPv4 e IPv6
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_admin (admin_user),
    INDEX idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
