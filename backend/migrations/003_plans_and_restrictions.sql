-- ============================================================
-- Saber+ Migración Fase 3: Planes, precios y restricciones
-- ============================================================

-- 1. Actualizar precio del plan premium a $25.000 COP
UPDATE plans SET price = 25000 WHERE code = 'premium';

-- 2. Asegurar que el plan free tenga precio 0
UPDATE plans SET price = 0 WHERE code = 'free';

-- 3. Reducir simulacros gratuitos de 3 a 2
-- Actualmente: simulacro 1 (diagnostico) = free, simulacro 2 = free, simulacro 3+ = premium
-- Cambio: simulacro 1 (diagnostico) = free, simulacro 2 = free, simulacro 3+ = premium (sin cambios)
-- Los simulacros gratuitos ya son 2 (diagnostico + simulacro 1), solo verificamos:
-- Si hay un simulacro 3 marcado como free, cambiarlo a premium
UPDATE content_access_levels SET min_plan = 'premium' 
WHERE content_type = 'simulacro' AND min_plan = 'free' AND content_id NOT IN (1, 2);

-- 4. Agregar restricción de retos a compañero para usuarios no premium
-- Insertar restricciones de retos (feature-level, no por content_id específico)
INSERT IGNORE INTO content_access_levels (content_type, content_id, min_plan, order_index, is_active)
VALUES ('feature', NULL, 'premium', 100, 1);

-- 5. Asegurar que los docentes no tengan restricciones premium
-- Esto se maneja en el backend verificando tipo_usuario = 'profesor'
-- No necesita cambios en BD, solo en el código del backend

-- 6. Actualizar capabilities del plan premium
UPDATE plans SET capabilities = '["simulacros_ilimitados","retos_diarios","prediccion_icfes","analisis_errores","gamificacion_completa","sin_anuncios","soporte_prioritario","retos_companero"]' 
WHERE code = 'premium';

UPDATE plans SET capabilities = '["simulacro_diagnostico","simulacro_1","cursos_basicos","gamificacion_basica"]' 
WHERE code = 'free';

-- 7. Verificar
SELECT id, code, name, price, capabilities FROM plans ORDER BY sort_order;
SELECT content_type, content_id, min_plan FROM content_access_levels WHERE content_type = 'simulacro' ORDER BY order_index;
