-- ============================================================================
-- Migración 005 — Saber+ B2B: Panel del Director de Colegio
-- ============================================================================
-- Ejecutar en MySQL/MariaDB sobre la BD `prepsaber`:
--   mysql -u jnegretep -p prepsaber < 005_directores.sql
--
-- Contenido:
--   1) Tabla `directores`: cuentas de los directores de colegio (B2B).
--      Las cuentas las crea el dueño/admin desde Panel Admin → Colegios.
--      Cada director SOLO ve los estudiantes cuyo `usuarios.colegio`
--      coincida exactamente con `directores.colegio`.
--   2) Columna `usuarios.activo`: permite al director activar/desactivar
--      estudiantes de SU colegio. backend/login.php rechaza con 403 a los
--      usuarios con activo = 0 ("Tu cuenta fue desactivada por tu colegio").
--
-- Idempotencia:
--   * CREATE TABLE IF NOT EXISTS → puede reejecutarse sin problema.
--   * El ALTER TABLE falla INOFENSIVAMENTE con error 1060
--     ("Duplicate column name 'activo'") si la columna ya existe.
--     MySQL/MariaDB no soporta "ADD COLUMN IF NOT EXISTS", así que ese
--     error puede ignorarse con seguridad (o comentar la línea si la
--     migración ya se aplicó antes).
-- ============================================================================

CREATE TABLE IF NOT EXISTS directores (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(120) NOT NULL,
  email VARCHAR(190) NOT NULL UNIQUE,
  contrasena_hash VARCHAR(255) NOT NULL,
  colegio VARCHAR(190) NOT NULL,
  telefono VARCHAR(30) NULL,
  activo TINYINT(1) NOT NULL DEFAULT 1,
  ultimo_login DATETIME NULL,
  creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ⚠️ Falla inofensivamente (error 1060 "Duplicate column name") si la
--    columna ya existe: en ese caso ignorar el error o comentar la línea.
ALTER TABLE usuarios ADD COLUMN activo TINYINT(1) NOT NULL DEFAULT 1;
