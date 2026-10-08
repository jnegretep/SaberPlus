-- ============================================================================
-- Migración 004 — Google Play Billing (Saber+ v1.7.0)
-- Task 3-a: migración de pagos móviles Android a Google Play Billing.
--
-- Nueva tabla play_purchases: registro server-side de cada compra/suscripción
-- verificada contra la Google Play Developer API (verify_play_purchase.php y
-- play_rtdn.php). Permite idempotencia, renovaciones (RTDN) y auditoría.
--
-- ALTER payments: la columna gateway ya la usa create_wompi_payment.php en
-- producción; si la columna NO existe aún, este ALTER la crea. Si YA existe,
-- MySQL responde con error 1060 "Duplicate column name 'gateway'" y el resto
-- del script no se ejecuta si corres el archivo de una sola vez.
--
-- ⚠️ CÓMO EJECUTAR (a prueba de idempotencia):
--   1) Verificar primero si la columna ya existe:
--        SHOW COLUMNS FROM payments LIKE 'gateway';
--   2a) Si NO devuelve filas → ejecutar TODO este archivo:
--        mysql -u <usuario> -p prepsaber < 004_play_billing.sql
--   2b) Si YA devuelve una fila → ejecutar SOLO el CREATE TABLE de arriba
--       (o correr el archivo con --force para que ignore el error del ALTER):
--        mysql --force -u <usuario> -p prepsaber < 004_play_billing.sql
--      El error 1060 es inofensivo: la columna ya está con el mismo tipo.
-- ============================================================================

CREATE TABLE IF NOT EXISTS play_purchases (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  product_id VARCHAR(100) NOT NULL,
  purchase_token VARCHAR(512) NOT NULL UNIQUE,
  order_id VARCHAR(190) NULL,
  purchase_type ENUM('subscription','inapp') NOT NULL DEFAULT 'subscription',
  state VARCHAR(40) NOT NULL DEFAULT 'PURCHASED',
  expiry_time DATETIME NULL,
  raw_response MEDIUMTEXT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_pp_user (user_id),
  INDEX idx_pp_product (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Verificar antes: SHOW COLUMNS FROM payments LIKE 'gateway';
-- Falla inofensivamente (error 1060) si la columna ya existe.
ALTER TABLE payments ADD COLUMN gateway VARCHAR(30) NOT NULL DEFAULT 'wompi';
