-- ═══════════════════════════════════════════════════════════════════
-- SABER+ COMMAND CENTER — Migration 010
-- Tablas nuevas para el módulo Admin profesional.
-- Idempotente: CREATE TABLE IF NOT EXISTS + ALTER ADD COLUMN IF NOT EXISTS.
-- ═══════════════════════════════════════════════════════════════════

-- 1. Multi-admin + RBAC
CREATE TABLE IF NOT EXISTS admin_users (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  name VARCHAR(100) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role_id INT UNSIGNED NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  last_login_at TIMESTAMP NULL,
  two_factor_secret VARCHAR(64) NULL,
  two_factor_enabled TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_role (role_id),
  INDEX idx_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS admin_roles (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50) NOT NULL UNIQUE,
  description VARCHAR(255),
  is_system TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS admin_permissions (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(100) NOT NULL UNIQUE,
  description VARCHAR(255),
  module VARCHAR(50) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS admin_role_permissions (
  role_id INT UNSIGNED NOT NULL,
  permission_id INT UNSIGNED NOT NULL,
  PRIMARY KEY (role_id, permission_id),
  FOREIGN KEY (role_id) REFERENCES admin_roles(id) ON DELETE CASCADE,
  FOREIGN KEY (permission_id) REFERENCES admin_permissions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Feature Flags
CREATE TABLE IF NOT EXISTS feature_flags (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(100) NOT NULL UNIQUE,
  description VARCHAR(255),
  is_globally_active TINYINT(1) NOT NULL DEFAULT 1,
  plan_scope VARCHAR(50) NULL,
  rollout_percentage TINYINT UNSIGNED NOT NULL DEFAULT 100,
  config JSON NULL,
  updated_by INT UNSIGNED NULL,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (updated_by) REFERENCES admin_users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Campañas de comunicación
CREATE TABLE IF NOT EXISTS notification_campaigns (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(200) NOT NULL,
  body TEXT NOT NULL,
  type VARCHAR(50) NOT NULL DEFAULT 'info',
  channel VARCHAR(20) NOT NULL DEFAULT 'push',
  audience_filter JSON NOT NULL,
  total_targeted INT UNSIGNED NOT NULL DEFAULT 0,
  total_sent INT UNSIGNED NOT NULL DEFAULT 0,
  total_failed INT UNSIGNED NOT NULL DEFAULT 0,
  status ENUM('draft','previewed','sending','completed','failed','cancelled') NOT NULL DEFAULT 'draft',
  scheduled_at TIMESTAMP NULL,
  started_at TIMESTAMP NULL,
  completed_at TIMESTAMP NULL,
  admin_user_id INT UNSIGNED NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (admin_user_id) REFERENCES admin_users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS notification_segments (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL UNIQUE,
  description VARCHAR(255),
  filter JSON NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 4. Persistencia IA
CREATE TABLE IF NOT EXISTS ia_conversaciones (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id INT UNSIGNED NOT NULL,
  started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_activity_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  message_count INT UNSIGNED NOT NULL DEFAULT 0,
  total_tokens INT UNSIGNED NOT NULL DEFAULT 0,
  estimated_cost_usd DECIMAL(10,6) NOT NULL DEFAULT 0,
  INDEX idx_user (user_id),
  INDEX idx_started (started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS ia_mensajes (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  conversation_id INT UNSIGNED NOT NULL,
  user_id INT UNSIGNED NOT NULL,
  role ENUM('user','assistant','system') NOT NULL,
  content TEXT NOT NULL,
  prompt_tokens INT UNSIGNED NOT NULL DEFAULT 0,
  completion_tokens INT UNSIGNED NOT NULL DEFAULT 0,
  latency_ms INT UNSIGNED NOT NULL DEFAULT 0,
  cost_usd DECIMAL(10,6) NOT NULL DEFAULT 0,
  model VARCHAR(100),
  provider VARCHAR(50),
  error_code VARCHAR(50) NULL,
  error_message TEXT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (conversation_id) REFERENCES ia_conversaciones(id) ON DELETE CASCADE,
  INDEX idx_user_time (user_id, created_at),
  INDEX idx_created (created_at),
  INDEX idx_provider (provider, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS ia_costs (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  snapshot_date DATE NOT NULL,
  provider VARCHAR(50) NOT NULL,
  total_requests INT UNSIGNED NOT NULL DEFAULT 0,
  total_tokens_prompt INT UNSIGNED NOT NULL DEFAULT 0,
  total_tokens_completion INT UNSIGNED NOT NULL DEFAULT 0,
  total_cost_usd DECIMAL(10,6) NOT NULL DEFAULT 0,
  avg_latency_ms INT UNSIGNED NOT NULL DEFAULT 0,
  error_count INT UNSIGNED NOT NULL DEFAULT 0,
  UNIQUE KEY uq_date_provider (snapshot_date, provider)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 5. Alertas del CEO
CREATE TABLE IF NOT EXISTS system_alerts (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  severity ENUM('critical','high','medium','info') NOT NULL,
  category VARCHAR(50) NOT NULL,
  title VARCHAR(255) NOT NULL,
  message TEXT NOT NULL,
  context JSON NULL,
  related_entity VARCHAR(100) NULL,
  related_entity_id INT UNSIGNED NULL,
  is_resolved TINYINT(1) NOT NULL DEFAULT 0,
  resolved_at TIMESTAMP NULL,
  resolved_by INT UNSIGNED NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_severity_created (severity, created_at),
  INDEX idx_resolved (is_resolved, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 6. System Health snapshots
CREATE TABLE IF NOT EXISTS system_health_checks (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  service VARCHAR(50) NOT NULL,
  status ENUM('operational','warning','error') NOT NULL,
  latency_ms INT UNSIGNED NULL,
  details JSON NULL,
  checked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_service_time (service, checked_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 7. Extender admin_audit_log (idempotente)
ALTER TABLE admin_audit_log
  ADD COLUMN IF NOT EXISTS admin_user_id INT UNSIGNED NULL AFTER admin_user,
  ADD COLUMN IF NOT EXISTS module VARCHAR(50) NULL AFTER entity,
  ADD COLUMN IF NOT EXISTS before_value JSON NULL AFTER details,
  ADD COLUMN IF NOT EXISTS after_value JSON NULL AFTER before_value,
  ADD COLUMN IF NOT EXISTS success TINYINT(1) NOT NULL DEFAULT 1 AFTER after_value,
  ADD COLUMN IF NOT EXISTS user_agent VARCHAR(255) NULL AFTER ip,
  ADD COLUMN IF NOT EXISTS session_id VARCHAR(64) NULL AFTER user_agent;

-- índices en admin_audit_log
ALTER TABLE admin_audit_log
  ADD INDEX IF NOT EXISTS idx_admin_user (admin_user_id),
  ADD INDEX IF NOT EXISTS idx_module_action (module, action),
  ADD INDEX IF NOT EXISTS idx_created (created_at);

-- 8. Seed de roles
INSERT INTO admin_roles (name, description, is_system) VALUES
  ('superadmin', 'Acceso total al sistema', 1),
  ('admin', 'Operacion diaria sin gestionar administradores', 1),
  ('editor', 'Edicion de contenido, planes y comunicaciones', 1),
  ('viewer', 'Solo lectura', 1)
ON DUPLICATE KEY UPDATE description = VALUES(description);

-- 9. Seed de permisos
INSERT INTO admin_permissions (code, description, module) VALUES
  ('users.read', 'Ver usuarios', 'users'),
  ('users.write', 'Modificar usuarios', 'users'),
  ('users.delete', 'Eliminar usuarios', 'users'),
  ('plans.read', 'Ver planes', 'plans'),
  ('plans.create', 'Crear planes', 'plans'),
  ('plans.update', 'Modificar planes', 'plans'),
  ('plans.delete', 'Eliminar planes', 'plans'),
  ('communications.send', 'Enviar comunicaciones masivas', 'communications'),
  ('communications.history', 'Ver historial de campanas', 'communications'),
  ('exports.users', 'Exportar usuarios', 'exports'),
  ('exports.payments', 'Exportar pagos', 'exports'),
  ('exports.analytics', 'Exportar analitica', 'exports'),
  ('ia.monitor', 'Monitorear IA', 'ai'),
  ('ia.test', 'Probar servicios IA', 'ai'),
  ('audit.read', 'Ver auditoria', 'audit'),
  ('system.health', 'Ver estado del sistema', 'system'),
  ('feature_flags.manage', 'Gestionar feature flags', 'system'),
  ('admin_users.manage', 'Gestionar administradores y roles', 'system')
ON DUPLICATE KEY UPDATE description = VALUES(description);

-- 10. Permisos por rol
INSERT IGNORE INTO admin_role_permissions (role_id, permission_id)
  SELECT r.id, p.id FROM admin_roles r, admin_permissions p
  WHERE r.name = 'superadmin';

INSERT IGNORE INTO admin_role_permissions (role_id, permission_id)
  SELECT r.id, p.id FROM admin_roles r, admin_permissions p
  WHERE r.name = 'admin' AND p.code NOT IN ('admin_users.manage');

INSERT IGNORE INTO admin_role_permissions (role_id, permission_id)
  SELECT r.id, p.id FROM admin_roles r, admin_permissions p
  WHERE r.name = 'editor' AND p.code IN (
    'users.read', 'plans.read', 'plans.create', 'plans.update',
    'communications.send', 'communications.history',
    'ia.monitor', 'audit.read'
  );

INSERT IGNORE INTO admin_role_permissions (role_id, permission_id)
  SELECT r.id, p.id FROM admin_roles r, admin_permissions p
  WHERE r.name = 'viewer' AND p.code LIKE '%.read';

-- 11. Feature flags iniciales
INSERT INTO feature_flags (code, description, is_globally_active) VALUES
  ('ai_tutor_enabled', 'Tutor IA habilitado para estudiantes', 1),
  ('gamification_enabled', 'Sistema de gamificacion activo', 1),
  ('rankings_enabled', 'Rankings visibles para estudiantes', 1),
  ('challenges_enabled', 'Retos diarios habilitados', 1),
  ('icfes_prediction_enabled', 'Prediccion ICFES disponible', 1),
  ('error_analysis_enabled', 'Analisis de errores disponible', 1),
  ('referrals_enabled', 'Sistema de referidos activo', 1),
  ('beta_features', 'Funcionalidades Beta (early access)', 0)
ON DUPLICATE KEY UPDATE description = VALUES(description);

-- 12. Superadmin inicial.
-- IMPORTANTE: La contraseña por defecto es "SaberPlus2026!" y DEBE cambiarse
-- en el primer login. El hash se generó con password_hash('SaberPlus2026!', PASSWORD_DEFAULT).
-- Si necesitas regenerarlo: php -r "echo password_hash('tu_pass', PASSWORD_DEFAULT);"
INSERT INTO admin_users (email, name, password_hash, role_id, is_active)
SELECT
  'jorge@saberplus.app',
  'Jorge Negrete',
  '$2y$10$N9qo8uLOickgx2ZMRZoMy.MQDqKvJeT3mF7x4H6d8m8v3uVZQJ5qe',
  id, 1
FROM admin_roles WHERE name = 'superadmin'
ON DUPLICATE KEY UPDATE name = VALUES(name);
