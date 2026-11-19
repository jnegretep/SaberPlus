# Saber+ 2.0.0 — Changelog

**Fecha: noviembre 2026 · versionCode 20**

Misión: corrección, optimización y preparación final para lanzamiento.
Base: v1.7.1 + transformación profunda previa (ya en GitHub). Se preservan
el 100% de las pequeñas modificaciones del propietario (incluido su fix
`quizId` en quiz_intro_screen y el reformateo de question_screen).

---

## 📝 1. Revisión de preguntas (ReviewScreen) — reescrita

- **Nuevo** `lib/parsers/review_question_parser.dart`: parser **DOM**
  (paquete `html`, cero regex frágiles) que extrae del HTML de revisión de
  Moodle: enunciado limpio, opciones con respuesta seleccionada (input
  `checked`) y correcta (clases/fallback por texto), estado real de la
  pregunta (tolerante a todos los qtypes), feedback específico + general +
  respuesta correcta + puntaje.
- **Nuevo** `lib/widgets/question_option_tile.dart`: tile de opción
  reutilizable (verde = correcta, rojo = elegida incorrecta, neutra).
- `review_screen.dart` rediseñado: opciones visibles con marca de
  correcta/incorrecta, badge ✅/❌ por pregunta, retroalimentación
  **expandida por defecto** con altura adaptable y scroll interno para
  contenido largo. Fix de crash con reviewData vacío, `_tabController`
  muerto y `@override` duplicado. Los conteos por área ahora usan el estado
  del parser (más robustos: truefalse/match ya no caen a "Sin responder").

## 🔒 2. Biometría rediseñada (bloqueo local de la app)

- Antes: flujo contradictorio (logout borraba las flags, la rotación de
  refresh tokens invalidaba el token biométrico en el servidor, el botón
  casi nunca aparecía). Ahora: **la biometría es SOLO un bloqueo local**.
- **Nueva** `lib/screens/lock_screen.dart`: prompt de huella al abrir la
  app o volver de segundo plano (con sesión activa + bloqueo activado),
  con reintentar y "Usar mi contraseña" (cierra sesión → login).
- `auth_service.dart`: `enableAppLock()/disableAppLock()/isAppLockEnabled()`
  — solo un flag en secure storage, **sin contraseñas ni tokens guardados**.
- Activación desde Perfil → "Bloqueo con huella" + ofrecimiento único
  post-login. iOS: `NSFaceIDUsageDescription` añadido. Web: deshabilitada
  (sin soporte de local_auth), acceso normal.

## 💎 3. Acceso claro a Premium

- Banner contextual en el **dashboard** (descartable por sesión, solo
  free/trial): "Desbloquea todo Saber+ · pago único".
- CTA "Pásate a Premium" en **Perfil** (tarjeta con "Ver planes").
- Tile **"Plan Premium"** en el hub de configuración (Más).

## 🎟️ 4. Sistema de códigos promocionales (activan Premium)

- **Nueva migración** `008_codigos_premium.sql`: tablas `codigos_premium`
  (código, estado, creado/vence, max_usos, duración) + `codigos_premium_usos`
  (quién, cuándo, UNIQUE por código+usuario).
- **Nuevo** `backend/redeem_promo_code.php`: canje con JWT + rate limit
  8/10min + transacción con `SELECT ... FOR UPDATE` (anti carrera) — la
  validación es 100% backend.
- Sección **"🎟️ Códigos Premium"** en `/admin` (CRUD, generador, estados
  calculados, historial de canjes, CSRF + auditoría).
- En la app: sección **"Tengo un código promocional"** en la pantalla
  Premium (todas las plataformas) con feedback de éxito/error inline.

## 📚 5. Cursos, simulacros y matrícula Moodle

- **Nueva migración** `009_course_catalog.sql`: tabla `course_catalog` con
  la clasificación actual sembrada **+ retos diarios 56-60** (hoy los
  usuarios nuevos no quedaban matriculados en ellos).
- `get_courses.php`: clasificación dinámica desde la tabla con **fallback
  exacto a las listas históricas** si no está migrada (cero regresión);
  `early_bird` ahora cuenta como premium para desbloqueos (fix de
  consistencia); eliminado residuo de debug.
- `set_password.php`: la matrícula de nuevos usuarios se rige por el
  catálogo (fallback a la lista histórica).
- **Nueva sección "📚 Cursos Moodle" en `/admin`**: listado en vivo desde
  Moodle (búsqueda, filtro por tipo, paginación, matriculados),
  clasificación individual y masiva, y **matrícula masiva** por segmento
  (todos/verificados/trial/premium/free/nuevos 7 días) con pantalla de
  resumen + confirmación + resultados por curso. **Nunca desmatricula.**
  Todo auditado.

## ⚡ 6. Performance y escalabilidad

- Dashboard: **una sola llamada** a `get_courses.php` (antes 3 idénticas
  → 3× `core_enrol_get_users_courses` por carga). Reparto local por
  categoría vía `ApiService.lastFetchedCategories`.

## 🖼️ 7. Avatar — fix integral

- **Causa raíz**: el `extra` del router `/register/step2` no transportaba
  la imagen/asset del paso 1 → `_encodeAvatar()` devolvía null →
  `avatar_path` NULL en BD. Corregido en `app_router.dart` +
  `register_step1.dart`.
- **Nuevo** `backend/includes/avatar_helper.php`: validación por magic
  bytes (jpg/png/webp), verificación real de escritura, extensión correcta.
  Usado por `register.php` y `update_profile.php` (antes `file_put_contents`
  sin check y MIME sin validar).
- `update_profile.php`: `avatar_url` construida con `getAvatarUrl()`
  (BACKEND_BASE_URL) — antes generaba URLs 404.
- `backend/uploads/avatars/.gitkeep` versionado (directorio garantizado).

## 🧑‍🎓 8. Registro y verificación de correo

- `register_step2.dart`: overlay honesto "🎓 Estamos preparando tu cuenta"
  (paso real = POST al backend; sin progreso falso), bloqueo de back
  durante el envío.
- `set_password_screen.dart`: overlay "Preparando tu experiencia académica"
  (describe el trabajo real del backend) → **nueva pantalla de éxito**
  `/register/success` ("🎉 ¡Registro exitoso!" con el siguiente paso
  explícito). El flujo de recuperación de contraseña queda intacto.
- `verify_email_screen.dart`: instrucciones numeradas 1-5, nota de spam
  destacada y **botón "Reenviar correo"** con cooldown de 60s.
- `backend/resend_verification.php` reescrito: enlace mágico 24h (antes un
  código de 6 dígitos que nada consumía), rate limit 3/10min, mismo correo
  HTML que el registro.
- **Login**: usuario con correo sin verificar → ahora va directo a la
  pantalla de verificación (antes veía "Credenciales inválidas").

## 🚀 9. Google Sign-In — "próximamente"

- El botón ya no intenta un flujo roto (web sin clientId, backend sin
  service account): muestra "🚀 Registro con Google próximamente" con CTA
  **"Continuar con registro manual"**. El servicio queda conservado para
  su activación futura.

## 🔔 10. Notificaciones FCM

- `send_to_many.php` + 3 crons: cabecera `X-Internal-Token` (antes 403
  garantizado) y URLs centralizadas.
- Android: `POST_NOTIFICATIONS`, canal por defecto en el manifest y
  **creación real del canal** `saberplus_notificaciones` en MainActivity.
- **Nuevo** `web/firebase-messaging-sw.js` (config real del proyecto) +
  `_initFCM()` habilitado en web si hay VAPID key.
- `admin/send_bulk.php`: `sendMulticast` por lotes de 500, columna
  `payload_json` con fallback, INSERT fuera del try.
- `smart_notifications.php`: `payload_json` con fallback.
- Guía completa: `GUIA_ACTIVACION_NOTIFICACIONES_SABERPLUS.md`.

## 💳 11. Plan Premium — copy claro

- Tarjeta destacada **"💳 PAGO ÚNICO"**: no es suscripción, sin cobros
  automáticos, acceso por 1 año (versión Play incluida).
- Comparativa actualizada: Trial (3 simulacros, 3 cursos de repaso, acceso
  limitado) vs Premium (simulacros ilimitados 1 año, todos los cursos).
- FAQ corregida (eliminada la mención a un "trial de 7 días" inexistente).

## 🌐 12. Redes sociales y versión

- URLs oficiales actualizadas (Instagram `@saberplus15`, TikTok `@saberplus5`,
  Facebook por profile id) en constantes + pantalla "Acerca de".
- **Versión 2.0.0** (versionCode 20): `pubspec.yaml`, `AppConstants`,
  `AnalyticsService` (reportaba 1.6.0), main.dart, "Acerca de".

## 🎯 13. Simulacro diagnóstico — decisión de producto

Decisión documentada: **fase útil (opción C)** — se mantiene como
simulacro normal y se añade valor pedagógico inmediato: sección
**"Recomendaciones para ti"** en las estadísticas (áreas más débiles
priorizadas con colores, área más fuerte destacada y acceso directo a los
cursos de repaso). No se toca Moodle ni la lógica de intentos.

## 🧹 14. Limpieza del repositorio

- Documentación histórica (v1.5–v1.7) movida a `docs/history/`; guías
  operativas a `docs/`. README reescrito para 2.0.
- Código muerto eliminado: `plan_service.dart` (fetchPlanStatus era TODO,
  sin llamadas), `access_wrapper.dart` (sin usos), `question_table.dart`
  (import roto, sin usos).
- **Fix crítico heredado**: `simulacro_stats_screen.dart` tenía un error de
  sintaxis real (`nombresejorKey]` → `nombres[mejorKey]`) que impedía
  compilar el proyecto tal como estaba en GitHub.

## 🔧 15. Otros fixes

- `google_login.php`: pendiente de service account (documentado; el botón
  de Google queda en modo "próximamente" mientras tanto).
- `.gitignore`: excepción para `backend/uploads/avatars/.gitkeep`.

---

## Migraciones a ejecutar en producción

```bash
mysql -u USER -p DB < backend/migrations/008_codigos_premium.sql
mysql -u USER -p DB < backend/migrations/009_course_catalog.sql
```

Ambas son aditivas y con fallback: **si no se ejecutan, todo sigue
funcionando como en v1.7.1** (sin códigos premium ni catálogo dinámico).
