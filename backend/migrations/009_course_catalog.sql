-- ============================================================================
-- Migración 009 — Catálogo de cursos Moodle: clasificación dinámica (W2E)
-- ============================================================================
-- QUÉ HACE:
--   Crea la tabla `course_catalog`: la clasificación de cada curso de Moodle
--   (por id) en 'curso' | 'simulacro' | 'reto' | 'otro', con flag `visible`
--   (si se sirve a la app) y `sort_order` (orden de despliegue dentro del
--   tipo). Se gestiona desde el panel admin (sección "Cursos Moodle").
--
--   La siembra (INSERT IGNORE) replica EXACTAMENTE la clasificación que hoy
--   vive hardcodeada en backend/moodle/get_courses.php (listas de las líneas
--   110-112):
--     cursos:     4, 5, 6, 7, 8, 52, 53, 54, 55
--     simulacros: 2, 3, 18, 24, 25, 26, 27, 28, 29, 30, 31
--     retos:      19, 20, 21, 22, 23, 32..51
--   y AÑADE los retos diarios 56-60 (Matemáticas, Sociales, Inglés,
--   Naturales, Lectura — usados por backend/daily_challenges.php) como
--   'reto'. Hoy esos ids NO están en la lista de matrícula de
--   set_password.php → los usuarios nuevos quedan SIN retos diarios.
--
-- POR QUÉ:
--   - get_courses.php pasa de listas hardcodeadas a esta tabla: clasificar un
--     curso nuevo (o quitarlo de la app) será un cambio en el panel admin,
--     sin tocar código ni redesplegar. Si la tabla NO existe o está vacía,
--     el endpoint hace fallback a las listas históricas → cero regresión.
--   - set_password.php rige la matrícula de usuarios nuevos por esta tabla
--     (todos los course_id con visible = 1), cubriendo así los retos 56-60.
--
-- CÓMO EJECUTARLO (manual, por el propietario — este archivo NO se ejecuta
-- automáticamente y NO toca ninguna tabla existente):
--   mysql -u <usuario> -p <basedatos> < 009_course_catalog.sql
--   (ej. mysql -u jnegretep -p prepsaber < 009_course_catalog.sql)
--
-- ES REVERSIBLE / SEGURO:
--   - Solo CREATE TABLE IF NOT EXISTS + INSERT IGNORE (course_id es PRIMARY
--     KEY): puede ejecutarse varias veces sin duplicar nada.
--   - No modifica ni elimina tablas/columnas existentes.
--   - Rollback: DROP TABLE course_catalog; → get_courses.php y
--     set_password.php vuelven automáticamente al comportamiento
--     hardcodeado histórico (todo funciona igual que antes de migrar).
-- ============================================================================

CREATE TABLE IF NOT EXISTS course_catalog (
  course_id INT UNSIGNED PRIMARY KEY,          -- id del curso Moodle
  course_type ENUM('curso','simulacro','reto','otro') NOT NULL DEFAULT 'otro',
  visible TINYINT(1) NOT NULL DEFAULT 1,
  sort_order INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─────────────────────────────────────────────────────────────
-- Siembra: clasificación histórica EXACTA (compatibilidad 100%)
-- + retos diarios 56-60 como 'reto' (fix de matrícula).
-- INSERT IGNORE → re-ejecutar es seguro y nunca pisa cambios
-- hechos después desde el panel admin.
-- ─────────────────────────────────────────────────────────────

-- CURSOS (get_courses.php: [4,5,6,7,8,52,53,54,55])
INSERT IGNORE INTO course_catalog (course_id, course_type, visible, sort_order) VALUES
  (4,  'curso', 1, 1),
  (5,  'curso', 1, 2),
  (6,  'curso', 1, 3),
  (7,  'curso', 1, 4),
  (8,  'curso', 1, 5),
  (52, 'curso', 1, 6),
  (53, 'curso', 1, 7),
  (54, 'curso', 1, 8),
  (55, 'curso', 1, 9);

-- SIMULACROS (get_courses.php: [2,3,18,24,25,26,27,28,29,30,31])
INSERT IGNORE INTO course_catalog (course_id, course_type, visible, sort_order) VALUES
  (2,  'simulacro', 1, 1),
  (3,  'simulacro', 1, 2),
  (18, 'simulacro', 1, 3),
  (24, 'simulacro', 1, 4),
  (25, 'simulacro', 1, 5),
  (26, 'simulacro', 1, 6),
  (27, 'simulacro', 1, 7),
  (28, 'simulacro', 1, 8),
  (29, 'simulacro', 1, 9),
  (30, 'simulacro', 1, 10),
  (31, 'simulacro', 1, 11);

-- RETOS (get_courses.php: [19,20,21,22,23,32..51])
INSERT IGNORE INTO course_catalog (course_id, course_type, visible, sort_order) VALUES
  (19, 'reto', 1, 1),
  (20, 'reto', 1, 2),
  (21, 'reto', 1, 3),
  (22, 'reto', 1, 4),
  (23, 'reto', 1, 5),
  (32, 'reto', 1, 6),
  (33, 'reto', 1, 7),
  (34, 'reto', 1, 8),
  (35, 'reto', 1, 9),
  (36, 'reto', 1, 10),
  (37, 'reto', 1, 11),
  (38, 'reto', 1, 12),
  (39, 'reto', 1, 13),
  (40, 'reto', 1, 14),
  (41, 'reto', 1, 15),
  (42, 'reto', 1, 16),
  (43, 'reto', 1, 17),
  (44, 'reto', 1, 18),
  (45, 'reto', 1, 19),
  (46, 'reto', 1, 20),
  (47, 'reto', 1, 21),
  (48, 'reto', 1, 22),
  (49, 'reto', 1, 23),
  (50, 'reto', 1, 24),
  (51, 'reto', 1, 25);

-- RETOS DIARIOS (daily_challenges.php: [56,57,58,59,60]) — CRÍTICO:
-- hoy faltan en la lista de matrícula de set_password.php; con esta fila
-- los usuarios nuevos quedan matriculados y los retos diarios funcionan.
INSERT IGNORE INTO course_catalog (course_id, course_type, visible, sort_order) VALUES
  (56, 'reto', 1, 26),
  (57, 'reto', 1, 27),
  (58, 'reto', 1, 28),
  (59, 'reto', 1, 29),
  (60, 'reto', 1, 30);
