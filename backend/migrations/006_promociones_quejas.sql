-- ═══════════════════════════════════════════════════════════════════
-- Migración 006 — Sistema de promociones + quejas/sugerencias (v1.7.0)
-- SaberPlus
--
-- Ejecutar:  mysql -u <usuario> -p <basedatos> < 006_promociones_quejas.sql
-- Nota: los ALTER pueden fallar con error 1060/1061 si la columna/índice
--       ya existe — es inofensivo, verifica con SHOW COLUMNS.
-- ═══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- PROMOCIONES
-- Gestionadas 100% desde el panel admin (/admin sección Promociones).
-- Se sincronizan con la app en tiempo real vía get_active_promos.php:
-- el banner y el precio con descuento aparecen en la app al instante
-- (el app consulta el endpoint cada vez que abre la pantalla Premium).
--
-- tipo:
--   'banner' → tarjeta promocional en la pantalla Premium del app.
--              Si descuento_valor > 0, el descuento se aplica
--              AUTOMÁTICAMENTE en el checkout web (Wompi).
--   'codigo' → código canjeable que el usuario escribe en la web.
--              El descuento se aplica al validar el código.
-- descuento_tipo: 'porcentaje' (0-100) | 'monto' (COP fijos)
-- plan_id: NULL = aplica a todos los planes
-- max_usos: NULL = ilimitado
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS promociones (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  titulo VARCHAR(120) NOT NULL,
  descripcion VARCHAR(255) NULL,
  tipo ENUM('banner','codigo') NOT NULL DEFAULT 'banner',
  codigo VARCHAR(40) NULL,
  descuento_tipo ENUM('porcentaje','monto') NOT NULL DEFAULT 'porcentaje',
  descuento_valor DECIMAL(10,2) NOT NULL DEFAULT 0,
  plan_id INT UNSIGNED NULL,
  fecha_inicio DATETIME NOT NULL,
  fecha_fin DATETIME NOT NULL,
  max_usos INT UNSIGNED NULL,
  usos INT UNSIGNED NOT NULL DEFAULT 0,
  activo TINYINT(1) NOT NULL DEFAULT 1,
  creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_promo_codigo (codigo),
  INDEX idx_promo_activa (activo, fecha_inicio, fecha_fin),
  INDEX idx_promo_plan (plan_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─────────────────────────────────────────────────────────────
-- QUEJAS Y SUGERENCIAS (soporte in-app)
-- Enviadas desde la app (crear_queja.php / mis_quejas.php) y
-- gestionadas desde el panel admin (sección Soporte).
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS quejas_sugerencias (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  tipo ENUM('queja','sugerencia','bug','otro') NOT NULL DEFAULT 'sugerencia',
  asunto VARCHAR(150) NULL,
  mensaje TEXT NOT NULL,
  estado ENUM('nuevo','en_proceso','resuelto','descartado') NOT NULL DEFAULT 'nuevo',
  respuesta_admin TEXT NULL,
  creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  actualizado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_qs_user (user_id),
  INDEX idx_qs_estado (estado),
  INDEX idx_qs_fecha (creado_en)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─────────────────────────────────────────────────────────────
-- Auditoría de promoción aplicada en cada pago web (Wompi)
-- (error 1060 si ya existe → inofensivo)
-- ─────────────────────────────────────────────────────────────
ALTER TABLE payments ADD COLUMN promo_id INT UNSIGNED NULL;

-- Ejemplo de promoción de lanzamiento (banner 20% en todos los planes,
-- vigente 90 días desde la instalación). Edítala/desactívala desde /admin.
-- INSERT INTO promociones
--   (titulo, descripcion, tipo, descuento_tipo, descuento_valor,
--    fecha_inicio, fecha_fin, activo)
-- VALUES
--   ('Lanzamiento SaberPlus', '20% de descuento en cualquier plan por tiempo limitado',
--    'banner', 'porcentaje', 20,
--    NOW(), DATE_ADD(NOW(), INTERVAL 90 DAY), 1);
