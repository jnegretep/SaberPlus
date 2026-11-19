-- ============================================================
-- Saber+ — Migración de Gamificación v1.0
-- Crea las tablas necesarias para XP, niveles, rachas y badges
-- ============================================================

-- 1. Tabla principal de estado de gamificación por usuario
--    Se inicializa automáticamente con un trigger cuando un usuario se registra
CREATE TABLE IF NOT EXISTS user_gamification (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL UNIQUE,
    total_xp INT NOT NULL DEFAULT 0,
    current_level INT NOT NULL DEFAULT 1,
    current_streak INT NOT NULL DEFAULT 0,          -- días consecutivos
    max_streak INT NOT NULL DEFAULT 0,              -- racha máxima alcanzada
    last_activity_date DATE NULL,                    -- última fecha de actividad (para calcular racha)
    streak_freeze_count INT NOT NULL DEFAULT 0,     -- congeladores de racha disponibles (tipo Duolingo)
    badges_count INT NOT NULL DEFAULT 0,            -- contador desnormalizado para queries rápidos
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_total_xp (total_xp DESC),             -- para ranking global
    INDEX idx_current_streak (current_streak DESC),  -- para ranking de rachas
    INDEX idx_last_activity (last_activity_date),

    FOREIGN KEY (user_id) REFERENCES usuarios(id_usuario) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Historial de transacciones de XP (audit log)
--    Cada vez que el usuario gana XP, se registra aquí
CREATE TABLE IF NOT EXISTS xp_transactions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    xp_amount INT NOT NULL,                          -- positivo (ganado) o negativo (ajuste)
    reason VARCHAR(50) NOT NULL,                     -- 'simulacro', 'reto', 'curso', 'daily_login', 'badge_unlock', 'streak_bonus'
    reference_id INT NULL,                           -- ID del simulacro/reto/curso/badge (si aplica)
    description VARCHAR(255) NULL,                   -- texto legible: "Completaste Simulacro 1"
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_user_created (user_id, created_at DESC),
    INDEX idx_reason (reason),

    FOREIGN KEY (user_id) REFERENCES usuarios(id_usuario) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Catálogo de badges/logros desbloqueables
CREATE TABLE IF NOT EXISTS badges (
    id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE,                -- 'first_simulacro', 'streak_7', 'top_10_nacional', etc.
    name VARCHAR(100) NOT NULL,                      -- "Primer Simulacro"
    description TEXT NOT NULL,                       -- "Completa tu primer simulacro"
    icon VARCHAR(100) NOT NULL,                      -- nombre del icono Material: 'assignment_turned_in'
    color VARCHAR(20) NOT NULL DEFAULT '#1E4ED8',    -- color del badge en hex
    xp_reward INT NOT NULL DEFAULT 0,                -- XP bonus al desbloquear
    category VARCHAR(30) NOT NULL DEFAULT 'general', -- 'simulacros', 'rachas', 'social', 'especial'
    requirement_type VARCHAR(30) NOT NULL,           -- 'simulacros_count', 'streak_days', 'xp_total', 'rank_position'
    requirement_value INT NOT NULL,                  -- valor numérico del requisito
    is_hidden TINYINT(1) NOT NULL DEFAULT 0,         -- badge secreto (no mostrar hasta desbloquear)
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. Badges desbloqueados por usuario (muchos a muchos)
CREATE TABLE IF NOT EXISTS user_badges (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    badge_id INT NOT NULL,
    unlocked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    UNIQUE KEY uniq_user_badge (user_id, badge_id),

    FOREIGN KEY (user_id) REFERENCES usuarios(id_usuario) ON DELETE CASCADE,
    FOREIGN KEY (badge_id) REFERENCES badges(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. Registro diario de actividad (para calcular rachas y stats)
CREATE TABLE IF NOT EXISTS user_daily_activity (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    activity_date DATE NOT NULL,
    simulacros_completed INT NOT NULL DEFAULT 0,
    retos_completed INT NOT NULL DEFAULT 0,
    cursos_accessed INT NOT NULL DEFAULT 0,
    questions_answered INT NOT NULL DEFAULT 0,
    xp_earned INT NOT NULL DEFAULT 0,

    UNIQUE KEY uniq_user_date (user_id, activity_date),

    FOREIGN KEY (user_id) REFERENCES usuarios(id_usuario) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- INSERTAR CATÁLOGO INICIAL DE BADGES
-- ============================================================

INSERT INTO badges (code, name, description, icon, color, xp_reward, category, requirement_type, requirement_value, sort_order) VALUES
-- Simulacros
('first_simulacro', 'Primer Simulacro', 'Completa tu primer simulacro ICFES', 'assignment_turned_in', '#22C55E', 50, 'simulacros', 'simulacros_count', 1, 1),
('simulacros_5', 'Estudiante Constante', 'Completa 5 simulacros', 'school', '#3B82F6', 100, 'simulacros', 'simulacros_count', 5, 2),
('simulacros_10', 'Maestro del Simulacro', 'Completa 10 simulacros', 'workspace_premium', '#F59E0B', 200, 'simulacros', 'simulacros_count', 10, 3),
('simulacros_25', 'Leyenda ICFES', 'Completa 25 simulacros', 'military_tech', '#8B5CF6', 500, 'simulacros', 'simulacros_count', 25, 4),

-- Rachas
('streak_3', 'En Marcha', 'Mantén una racha de 3 días', 'local_fire_department', '#F59E0B', 30, 'rachas', 'streak_days', 3, 10),
('streak_7', 'Una Semana Completa', 'Mantén una racha de 7 días', 'whatshot', '#EF4444', 100, 'rachas', 'streak_days', 7, 11),
('streak_30', 'Imparable', 'Mantén una racha de 30 días', 'bolt', '#DC2626', 500, 'rachas', 'streak_days', 30, 12),
('streak_100', 'Centenario', 'Mantén una racha de 100 días', 'auto_awesome', '#7C3AED', 2000, 'rachas', 'streak_days', 100, 13),

-- Puntajes
('score_300', 'En Camino', 'Obtén 300+ puntos en un simulacro', 'trending_up', '#3B82F6', 50, 'simulacros', 'max_score', 300, 20),
('score_400', 'Buen Desempeño', 'Obtén 400+ puntos en un simulacro', 'trending_up', '#10B981', 100, 'simulacros', 'max_score', 400, 21),
('score_500', 'Excelente', 'Obtén 500+ puntos en un simulacro', 'star', '#F59E0B', 200, 'simulacros', 'max_score', 500, 22),

-- Ranking
('top_10_global', 'Top 10 Global', 'Alcanza el top 10 del ranking global', 'emoji_events', '#FACC15', 300, 'social', 'rank_position', 10, 30),
('top_1_global', 'Número 1', 'Alcanza el #1 del ranking global', 'emoji_events', '#F59E0B', 1000, 'social', 'rank_position', 1, 31),

-- Especiales (algunos ocultos)
('early_bird', 'Amanecer Productivo', 'Estudia antes de las 7 AM', 'wb_sunny', '#F59E0B', 50, 'especial', 'time_early_morning', 7, 40),
('night_owl', 'Búho Nocturno', 'Estudia después de las 11 PM', 'nightlight', '#6366F1', 50, 'especial', 'time_late_night', 23, 41),
('perfect_area', 'Perfeccionista', 'Obtén 100% en un área', 'check_circle', '#22C55E', 150, 'simulacros', 'perfect_area', 1, 50),
('all_areas_70', 'Equilibrado', 'Supera 70% en todas las áreas', 'balance', '#8B5CF6', 300, 'simulacros', 'all_areas_70', 1, 51)

ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    description = VALUES(description);

-- ============================================================
-- TRIGGER: inicializar gamification cuando se crea un usuario
-- ============================================================
DELIMITER //
CREATE TRIGGER IF NOT EXISTS trg_user_created_gamification
AFTER INSERT ON usuarios
FOR EACH ROW
BEGIN
    INSERT IGNORE INTO user_gamification (user_id, total_xp, current_level, current_streak)
    VALUES (NEW.id_usuario, 0, 1, 0);
END//
DELIMITER ;

-- ============================================================
-- Inicializar gamification para usuarios existentes
-- ============================================================
INSERT IGNORE INTO user_gamification (user_id, total_xp, current_level, current_streak, max_streak)
SELECT id_usuario, 0, 1, 0, 0 FROM usuarios;

-- ============================================================
-- FUNCIÓN: Calcular nivel basado en XP
-- Fórmula: nivel = floor(sqrt(xp / 100)) + 1
-- Ejemplos:
--   0 XP → nivel 1
--   100 XP → nivel 2 (sqrt(1) + 1)
--   400 XP → nivel 3 (sqrt(4) + 1)
--   900 XP → nivel 4 (sqrt(9) + 1)
--   1600 XP → nivel 5 (sqrt(16) + 1)
--   2500 XP → nivel 6 (sqrt(25) + 1)
-- ============================================================
DELIMITER //
CREATE FUNCTION IF NOT EXISTS fn_level_from_xp(xp INT) RETURNS INT
DETERMINISTIC
BEGIN
    IF xp < 0 THEN RETURN 1; END IF;
    RETURN FLOOR(SQRT(xp / 100.0)) + 1;
END//
DELIMITER ;

-- ============================================================
-- FUNCIÓN: XP necesaria para alcanzar un nivel
-- Inversa de fn_level_from_xp: xp = (nivel - 1)^2 * 100
-- ============================================================
DELIMITER //
CREATE FUNCTION IF NOT EXISTS fn_xp_for_level(level INT) RETURNS INT
DETERMINISTIC
BEGIN
    IF level < 1 THEN RETURN 0; END IF;
    RETURN POW(level - 1, 2) * 100;
END//
DELIMITER ;
