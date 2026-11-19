-- ============================================================================
-- Migración 003 — Saber+ v1.6.0
-- Analytics propio + logs de errores + rankings institucionales + auditoría
-- ============================================================================
-- Ejecutar en MySQL/MariaDB sobre la BD `prepsaber`:
--   mysql -u jnegretep -p prepsaber < 003_analytics_admin.sql
--
-- Es idempotente: puede ejecutarse varias veces sin romper nada.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────
-- 1) Eventos de analítica enviados por la app (Firebase Analytics
--    queda como fuente principal; esto es el espejo propio para el
--    panel de administración, sin depender de terceros).
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app_events (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id       INT             NULL,
    event_name    VARCHAR(64)     NOT NULL,
    platform      VARCHAR(16)     NOT NULL DEFAULT 'android',  -- android | ios | web
    app_version   VARCHAR(24)     NULL,
    params        JSON            NULL,                        -- payload acotado (máx 2 KB)
    created_at    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_event_created (event_name, created_at DESC),
    INDEX idx_user_created (user_id, created_at DESC),
    INDEX idx_created (created_at DESC),
    INDEX idx_platform (platform),
    CONSTRAINT fk_app_events_user FOREIGN KEY (user_id)
        REFERENCES usuarios (id_usuario) ON DELETE SET NULL
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- ─────────────────────────────────────────────────────────────
-- 2) Log de errores: (a) errores no fatales reportados por la app
--    (evento app_error) y (b) errores del propio backend.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS error_logs (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id       INT             NULL,
    source        VARCHAR(16)     NOT NULL DEFAULT 'app',      -- app | backend
    severity      ENUM('info','warning','error','fatal') NOT NULL DEFAULT 'error',
    error_code    VARCHAR(48)     NULL,                        -- ej. DioException, PlatformException
    message       TEXT            NOT NULL,
    stack_trace   TEXT            NULL,
    context       JSON            NULL,                        -- pantalla, dispositivo, etc.
    platform      VARCHAR(16)     NULL,
    app_version   VARCHAR(24)     NULL,
    resolved      TINYINT(1)      NOT NULL DEFAULT 0,
    created_at    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_source_created (source, created_at DESC),
    INDEX idx_severity_created (severity, created_at DESC),
    INDEX idx_user (user_id),
    INDEX idx_resolved (resolved, created_at DESC),
    CONSTRAINT fk_error_logs_user FOREIGN KEY (user_id)
        REFERENCES usuarios (id_usuario) ON DELETE SET NULL
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- ─────────────────────────────────────────────────────────────
-- 3) Auditoría de eliminación de cuentas (requisito Play/GDPR).
--    No guarda PII: solo hash del email para deduplicar y motivo.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS account_deletions (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id       INT             NOT NULL,             -- id de la fila anonimizada
    email_hash    CHAR(64)        NOT NULL,             -- SHA-256 del email original
    motivo        VARCHAR(255)    NULL,
    user_agent    VARCHAR(255)    NULL,
    created_at    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_created (created_at DESC),
    INDEX idx_email_hash (email_hash)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

-- ─────────────────────────────────────────────────────────────
-- 4) Índices para los rankings institucionales (colegio/departamento).
--    usuarios.colegio y usuarios.departamento son VARCHAR de texto
--    libre elegidos de listas (data/colegios.csv, departamentos.php).
-- ─────────────────────────────────────────────────────────────
CREATE INDEX idx_usuarios_colegio       ON usuarios (colegio);
CREATE INDEX idx_usuarios_departamento  ON usuarios (departamento);
