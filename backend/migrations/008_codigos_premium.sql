-- ============================================================================
-- Migración 008 — Códigos Premium: canje desde la app → plan Premium (W1B)
-- ============================================================================
-- QUÉ HACE:
--   Crea las tablas `codigos_premium` y `codigos_premium_usos`:
--   - codigos_premium: códigos canjeables gestionados desde el panel admin
--     (sección "Códigos Premium"). Al canjearse desde la app (Perfil → Planes,
--     endpoint backend/redeem_promo_code.php), el usuario pasa a
--     access_level='premium' con unlocked_at=NOW() — la misma activación que
--     un pago Wompi aprobado (wompi_webhook.php), pero sin costo.
--   - codigos_premium_usos: un registro por canje (código × usuario).
--     La UNIQUE KEY (codigo_id, id_usuario) impide que un mismo usuario
--     canjee el mismo código dos veces; el conteo de usos contra max_usos
--     controla el cupo total (max_usos=1 → código individual de uso único).
--   - duracion_dias: dato informativo del código (default 365). Reservado
--     para una futura expiración programada del Premium; hoy el canje activa
--     premium de forma permanente, igual que el webhook de Wompi.
--
-- CÓMO EJECUTARLO (manual, por el propietario — este archivo NO se ejecuta
-- automáticamente y NO toca ninguna tabla existente):
--   mysql -u <usuario> -p <basedatos> < 008_codigos_premium.sql
--   (ej. mysql -u jnegretep -p prepsaber < 008_codigos_premium.sql)
--
-- ES SEGURO:
--   - Solo CREATE TABLE IF NOT EXISTS: puede ejecutarse varias veces.
--   - No modifica ni elimina tablas/columnas existentes.
--   - Si NO se ejecuta: el endpoint redeem_promo_code.php responde 503
--     (sistema_no_disponible) y la sección del panel muestra el aviso
--     "Ejecuta la migración 008_codigos_premium.sql".
-- ============================================================================

CREATE TABLE IF NOT EXISTS codigos_premium (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  codigo VARCHAR(40) NOT NULL UNIQUE,
  descripcion VARCHAR(255) NULL,
  estado ENUM('activo','deshabilitado') NOT NULL DEFAULT 'activo',
  creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  vence_en DATETIME NULL,
  max_usos INT UNSIGNED NOT NULL DEFAULT 1,
  duracion_dias INT UNSIGNED NOT NULL DEFAULT 365,
  notas VARCHAR(255) NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS codigos_premium_usos (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  codigo_id INT UNSIGNED NOT NULL,
  id_usuario INT UNSIGNED NOT NULL,
  usado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_codigo_usuario (codigo_id, id_usuario),
  INDEX idx_codigo_usos (codigo_id),
  CONSTRAINT fk_codigo_premium FOREIGN KEY (codigo_id) REFERENCES codigos_premium(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
