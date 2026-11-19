-- Migración para usuarios existentes
-- Marcar primeros 1000 usuarios como early bird

SET @early_limit = 1000;

UPDATE usuarios 
SET access_level = 'early_bird',
    is_early_user = 1,
    trial_ends_at = DATE_ADD(NOW(), INTERVAL 180 DAY)
WHERE id IN (
  SELECT id FROM (
    SELECT id 
    FROM usuarios 
    WHERE access_level = 'free'
    ORDER BY registration_date ASC 
    LIMIT @early_limit
  ) AS temp
);

-- Insertar configuración de acceso para contenido existente
INSERT INTO content_access_levels (content_type, content_id, min_plan, order_index) VALUES
-- Simulacros
('simulacro', 1, 'free', 1),  -- Diagnóstico
('simulacro', 2, 'free', 2),  -- Simulacro 1
('simulacro', 3, 'premium', 3),
('simulacro', 4, 'premium', 4),
('simulacro', 5, 'premium', 5),
('simulacro', 6, 'premium', 6),
('simulacro', 7, 'premium', 7),
('simulacro', 8, 'premium', 8),
('simulacro', 9, 'premium', 9),
('simulacro', 10, 'premium', 10),

-- Cursos básicos (free)
('course', 1, 'free', 1),  -- Matemáticas básicas
('course', 2, 'free', 2),  -- Lenguaje básico
('course', 3, 'free', 3),  -- Ciencias básicas

-- Cursos avanzados (premium)
('course', 4, 'premium', 4),
('course', 5, 'premium', 5),
('course', 6, 'premium', 6),
-- ... más cursos
;

-- Actualizar unlocked_modules para usuarios early bird
UPDATE usuarios u
JOIN user_access_plans uap ON u.id = uap.user_id
SET uap.unlocked_modules = '["all"]'
WHERE u.access_level = 'early_bird';