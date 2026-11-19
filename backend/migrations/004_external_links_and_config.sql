-- ============================================================
-- Saber+ Migración Fase 5: Enlaces externos y configuración
-- ============================================================

-- Insertar enlaces externos por defecto en app_config
INSERT INTO app_config (clave, valor, grupo, descripcion) VALUES
('link_google_play', 'https://play.google.com/store/apps/details?id=com.saberplus.app', 'enlaces', 'URL de Google Play Store'),
('link_app_store', '', 'enlaces', 'URL de App Store (vacío hasta publicar en iOS)'),
('link_facebook', 'https://facebook.com/saberplus', 'enlaces', 'URL de Facebook'),
('link_instagram', 'https://instagram.com/saberplus', 'enlaces', 'URL de Instagram'),
('link_tiktok', 'https://tiktok.com/@saberplus', 'enlaces', 'URL de TikTok'),
('link_youtube', 'https://youtube.com/@saberplus', 'enlaces', 'URL de YouTube'),
('link_web', 'https://corpoinstel.edu.co', 'enlaces', 'URL del sitio web oficial'),
('link_whatsapp', '', 'enlaces', 'URL de WhatsApp (vacío hasta configurar)'),
('link_privacy_policy', 'https://corpoinstel.edu.co/privacidad', 'legal', 'URL de política de privacidad'),
('link_terms', 'https://corpoinstel.edu.co/terminos', 'legal', 'URL de términos y condiciones')
ON DUPLICATE KEY UPDATE valor = VALUES(valor);

-- Configuración de invitación a calificar
INSERT INTO app_config (clave, valor, grupo, descripcion) VALUES
('rate_app_enabled', '1', 'rating', 'Activar/desactivar invitación a calificar'),
('rate_app_min_simulacros', '3', 'rating', 'Mínimo de simulacros antes de pedir calificación'),
('rate_app_min_days', '7', 'rating', 'Mínimo de días de uso antes de pedir calificación'),
('rate_app_cooldown_days', '30', 'rating', 'Días entre recordatorios si el usuario pospone')
ON DUPLICATE KEY UPDATE valor = VALUES(valor);

-- Configuración de simulacros gratuitos
INSERT INTO app_config (clave, valor, grupo, descripcion) VALUES
('free_simulacros_count', '2', 'planes', 'Cantidad de simulacros gratuitos disponibles')
ON DUPLICATE KEY UPDATE valor = VALUES(valor);

-- Configuración de referidos
INSERT INTO app_config (clave, valor, grupo, descripcion) VALUES
('referral_required_friends', '5', 'referidos', 'Cantidad de amigos necesarios para recompensa'),
('referral_max_rewards', '2', 'referidos', 'Máximo de recompensas por referidos')
ON DUPLICATE KEY UPDATE valor = VALUES(valor);

-- Verificar
SELECT * FROM app_config WHERE grupo = 'enlaces';
SELECT * FROM app_config WHERE grupo = 'rating';
