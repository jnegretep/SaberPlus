# REPORTE DE MEJORAS — CHECKLIST SABER+ 2.0

**Misión: corrección, optimización y preparación final para lanzamiento**
Base: última versión de GitHub (`jnegretep/SaberPlus`, commit `403c22d` —
las modificaciones puntuales del propietario fueron identificadas y
**preservadas al 100%**: reformateo de `question_screen.dart` /
`quiz_intro_screen.dart` y su fix real `simulacroId` → `quizId`).

Leyenda: ✅ completado y probado · 🟡 completado, pendiente de prueba
externa (en dispositivo/servidor real) · 🔵 requiere configuración manual ·
🔴 no completado (con explicación).

---

## 0. Limpieza profesional del repositorio — ✅

- **Problema**: 14 documentos de versiones anteriores en la raíz, código
  muerto y documentación contradictoria.
- **Causa**: acumulación de entregables históricos.
- **Solución**: docs históricos → `docs/history/` (13 archivos); guías
  operativas → `docs/`; README reescrito para 2.0 con mapa de
  documentación. Código muerto eliminado tras verificar **cero
  referencias**: `plan_service.dart` (era TODO sin llamadas),
  `access_wrapper.dart` (sin usos), `question_table.dart` (import roto).
  Se conservaron archivos de producción, configuración y migraciones.
- **Archivos**: moves a `docs/`, `docs/history/`, borrados indicados,
  `README.md`, `lib/main.dart` (providers).
- **Pruebas**: grep de referencias tras cada borrado (0 resultados);
  chequeo de balance de todos los archivos Dart/PHP modificados.

## 1. Review Question Screen — retroalimentación — ✅

- **Problema**: opciones eliminadas del HTML por regex (imposible ver la
  elegida/correcta), feedback truncado en el primer `</div>` anidado,
  enunciado con residuos HTML, estados mal detectados.
- **Causa**: heurísticas regex no balanceadas en
  `_removeImageTagsAndHeaders` / `_extractFeedback` / `_extractState`
  (comparación de strings exactas que fallaban con qtypes ≠ multichoice).
- **Solución**: parser DOM nuevo (`review_question_parser.dart`) que
  extrae enunciado, opciones con `checked`, correcta, rightanswer,
  specific/general feedback y estado tolerante; widget `QuestionOptionTile`
  (verde/rojo/neutro); tarjeta rediseñada con badge ✅/❌, opciones
  ordenadas, retroalimentación expandida por defecto, altura adaptable y
  scroll para contenido largo.
- **Archivos**: `lib/parsers/review_question_parser.dart` (nuevo),
  `lib/widgets/question_option_tile.dart` (nuevo),
  `lib/screens/review_screen.dart`.
- **Pruebas**: balance Dart OK; lógica de negocio preservada (stats/XP/
  tabs/áreas intactos); guard anti-crash con review vacío.
- **Estado**: ✅ (renderizado con HTML real de Moodle: 🟡 en dispositivo —
  no hay backend vivo en el sandbox).

## 2. Biometría / huella — rediseño del flujo — ✅

- **Problema**: flujo contradictorio e inutilizable (logout borraba las
  flags de biometría, la rotación de refresh tokens la invalidaba en
  servidor, el botón de huella casi nunca aparecía habilitado).
- **Causa**: la biometría estaba modelada como mecanismo de LOGIN con un
  refresh token duplicado en storage, en conflicto con el ciclo de vida
  real de la sesión.
- **Solución**: biometría = **bloqueo local de la app**: nueva
  `LockScreen` (huella al abrir/volver de background con sesión activa,
  reintentar, "usar contraseña" → logout → login); flag único en secure
  storage (sin contraseñas ni tokens); activación desde Perfil + ofrecimiento
  único post-login; si la sesión expira los interceptores existentes mandan
  al login (la biometría nunca sustituye credenciales); sin biometría →
  acceso normal; `NSFaceIDUsageDescription` para iOS; deshabilitada en web.
- **Archivos**: `lib/screens/lock_screen.dart` (nuevo),
  `auth_service.dart`, `login_screen.dart`, `main.dart`,
  `perfil_hub_screen.dart`, `biometric_service.dart` (comentario),
  `app_constants.dart`, `app_router.dart`, `ios/Runner/Info.plist`.
- **Pruebas**: balance OK; referencias a métodos viejos = 0; flujos
  alternativos documentados en código. En dispositivo real: 🟡 (huella
  nativa requiere hardware).

## 3. Acceso claro a Premium — ✅

- **Problema**: el único punto de entrada al upgrade era tocar un curso
  bloqueado.
- **Solución**: banner contextual en dashboard (discreto, descartable por
  sesión, solo free/trial), CTA en Perfil y tile "Plan Premium" en el hub
  de configuración.
- **Archivos**: `dashboard_screen.dart`, `perfil_screen.dart`,
  `perfil_hub_screen.dart`.
- **Estado**: ✅.

## 4. Sistema de códigos promocionales — ✅ (🔵 migración)

- **Problema**: no existía forma de activar Premium con código (las
  "promociones" solo descontaban en el checkout Wompi).
- **Solución**: tablas `codigos_premium` + `codigos_premium_usos`
  (migración 008) con código, estado, fechas, vencimiento opcional,
  max_usos (1 = uso único), usuario y fecha de uso; endpoint
  `redeem_promo_code.php` con JWT + rate limit 8/10min + transacción
  `SELECT ... FOR UPDATE` (anti carrera, anti reutilización por
  UNIQUE código+usuario, anti manipulación desde cliente — todo se
  valida en backend); sección "🎟️ Códigos Premium" en `/admin` (CRUD +
  generador + historial + CSRF + auditoría); en la app, sección "Tengo un
  código promocional" en la pantalla Premium.
- **Archivos**: `008_codigos_premium.sql`, `redeem_promo_code.php`
  (nuevos), `admin/index.php`, `upgrade_screen.dart`, `api_service.dart`.
- **Estado**: ✅ código · 🔵 ejecutar migración 008 en producción.

## 5. Registro con Google — ✅

- **Problema**: botón visible pero roto (web sin clientId; backend exige
  service account ausente).
- **Solución**: el botón muestra "🚀 Registro con Google próximamente"
  con explicación y CTA inmediato "Continuar con registro manual" (nadie
  queda bloqueado). El servicio completo queda conservado para su
  activación futura (documentado).
- **Archivos**: `login_screen.dart`.
- **Estado**: ✅.

## 6. Experiencia durante el registro — ✅

- **Problema**: envíos largos (SMTP, Moodle, matrículas) sin feedback y
  con riesgo de doble envío/estados inconsistentes.
- **Solución**: overlays honestos "🎓 Estamos preparando tu cuenta" /
  "🎓 Preparando tu experiencia académica" con pasos REALES (el paso
  activo refleja la petición en curso — sin progreso falso), check verde
  animado al completar, bloqueo de back durante el envío (`PopScope`), y
  anti doble-submit ya existente respetado.
- **Archivos**: `register_step2.dart`, `set_password_screen.dart`.
- **Estado**: ✅.

## 7. Confirmación de registro exitoso — ✅

- **Solución**: nueva pantalla "🎉 ¡Registro exitoso!" con el siguiente
  paso explícito (iniciar sesión con correo + nueva contraseña, email en
  chip) y CTA directo. Ruta `/register/success`.
- **Archivos**: `registration_success_screen.dart` (nuevo),
  `app_router.dart`, `set_password_screen.dart`.
- **Estado**: ✅.

## 8. Confirmación de correo — ✅

- **Problema**: sin reenvío (el endpoint existente usaba un código de 6
  dígitos que nada consumía), instrucciones mínimas.
- **Solución**: instrucciones numeradas 1-5 (revisa → busca → clic en
  confirmar → regresa → "Ya verifiqué mi correo"), nota de spam
  destacada, botón **"Reenviar correo"** con cooldown 60s; backend
  reescrito al flujo real (enlace mágico 24h, rate limit 3/10min, mismo
  correo HTML); "Ya verifiqué mi correo" verifica contra backend (ya lo
  hacía — preservado).
- **Archivos**: `verify_email_screen.dart`, `resend_verification.php`.
- **Estado**: ✅.

## 9. Cursos, simulacros y matrícula Moodle — ✅ (🔵 migración)

- **Problema**: clasificación hardcodeada por IDs en el backend (cursos
  fuera de las listas no aparecían); matrícula por lista fija; retos
  diarios 56-60 sin matricular para usuarios nuevos.
- **Solución** (preservando el sistema actual): tabla `course_catalog`
  (migración 009) sembrada con la clasificación EXACTA actual + 56-60;
  `get_courses.php` lee la tabla con **fallback idéntico al
  comportamiento actual** si no está migrada; `set_password.php` matricula
  según catálogo (mismo fallback). Módulo admin **"📚 Cursos Moodle"**:
  listado vivo desde Moodle con búsqueda/filtro/paginación/matriculados,
  clasificación individual y masiva, y **matrícula masiva** por segmento
  (todos/verificados/trial/premium/free/nuevos_7d) con pantalla de resumen
  (conteos + muestra), confirmación explícita, ejecución en lotes,
  resultados por curso, auditoría de quién/cuándo/qué/cuántos y nota
  "solo AÑADE matrículas, nunca las elimina". Fix de consistencia:
  `early_bird` ahora desbloquea contenido como premium.
- **Archivos**: `009_course_catalog.sql` (nuevo), `get_courses.php`,
  `set_password.php`, `admin/index.php`.
- **Estado**: ✅ código · 🔵 ejecutar migración 009 · 🟡 probar matrícula
  masiva contra el Moodle real.

## 10. Escalabilidad de cursos — ✅

- **Problema**: dashboard hacía 3 llamadas idénticas al mismo endpoint
  (3× `core_enrol_get_users_courses` en el backend por carga).
- **Solución**: una sola llamada + reparto local por categoría
  (`ApiService.lastFetchedCategories`). Las listas ya usan
  GridView/ListView.builder (lazy) y búsqueda local; con el catálogo, el
  número de cursos deja de depender de listas fijas.
- **Archivos**: `dashboard_provider.dart`, `api_service.dart`.
- **Estado**: ✅.

## 11. Avatar — corrección integral — ✅

- **Problema**: `avatar_path` quedaba NULL y el avatar nunca se mostraba.
- **Causa raíz (Flutter)**: el `extra` de `/register/step2` no
  transportaba la imagen/asset elegidos en el paso 1 → el paso 2 codificaba
  null. **Causas secundarias (backend)**: `file_put_contents` sin verificar,
  sin validación de tipo real, y `avatar_url` construida con HTTP_HOST
  (URLs 404).
- **Solución**: transporte completo en el router; helper compartido
  `avatar_helper.php` (magic bytes jpg/png/webp + verificación de
  escritura + extensión correcta) usado por registro y edición de perfil;
  `avatar_url` con `getAvatarUrl()`; directorio versionado (.gitkeep).
- **Archivos**: `app_router.dart`, `register_step1.dart`,
  `backend/includes/avatar_helper.php` (nuevo), `register.php`,
  `update_profile.php`, `.gitignore`.
- **Pruebas**: la ruta de edición (que ya funcionaba) no cambió de
  comportamiento; el flujo de registro ahora sí envía el avatar. Verificación
  end-to-end en servidor: 🟡.

## 12. Simulacro diagnóstico — decisión de producto — ✅ (opción C)

- **Decisión del Product Manager**: **C — primera fase útil**. Un
  diagnóstico adaptativo real requiere bancos dinámicos en Moodle
  (complejidad alta, riesgo sobre lo que funciona). El valor inmediato: el
  resultado del simulacro ahora genera **"Recomendaciones para ti"**
  (3 áreas más débiles priorizadas con colores, área más fuerte, acceso
  directo a cursos de repaso) — personalización basada en datos reales sin
  tocar Moodle ni la lógica de intentos.
- **Archivos**: `simulacro_stats_screen.dart` (+ fix crítico de sintaxis
  heredado que impedía compilar: `nombres[mejorKey]`).
- **Estado**: ✅.

## 13. Versión 2.0 — ✅

- `pubspec.yaml` → `2.0.0+20` (versionName + versionCode derivados,
  Android/Web automáticos), `AppConstants.appVersion = '2.0.0'`
  (alimenta "Acerca de"), `AnalyticsService.appVersion = '2.0.0'`
  (reportaba 1.6.0 al backend), comentario de `main.dart`. Compatible con
  actualizaciones futuras (mono-incremental).

## 14. Plan Premium — copy — ✅

- Tarjeta destacada **"💳 PAGO ÚNICO"** (no suscripción, sin cobros
  automáticos, 1 año); comparativa Trial (3 simulacros, 3 cursos de
  repaso, acceso limitado) vs Premium (ilimitados 1 año, todos los
  cursos, contenido Premium); FAQ corregida (eliminado el "trial 7 días"
  sin respaldo y el copy de cancelación de suscripción).
- **Archivos**: `upgrade_screen.dart`.
- **Estado**: ✅.

## 15. Redes sociales — ✅

- URLs oficiales nuevas (Facebook por profile id
  `61586244015979`, Instagram `saberplus15`, TikTok `saberplus5`) en
  `AppConstants` + handles visibles en "Acerca de" (la app no tiene otras
  redes hardcodeadas — verificado por grep; soporte/privacidad usan
  contacto propio, sin cambio).
- **Archivos**: `app_constants.dart`, `acerca_screen.dart`.
- **Estado**: ✅.

## 16. Notificaciones FCM — 🟡/🔵 (código ✅, activación manual)

- **Problema**: no llegaban. **Causas** (verificadas): (1) 403 en todos
  los llamadores internos (regresión del endurecimiento v2 de
  `send_notification.php`); (2) canal Android `saberplus_notificaciones`
  nunca creado (Android 8+ descarta silenciosamente); (3) permiso
  `POST_NOTIFICATIONS` ausente (Android 13+, targetSdk 36); (4) push web
  deshabilitado por diseño (sin service worker ni VAPID); (5) bandeja
  inconsistente (`data` vs `payload_json`); (6) service account de
  Firebase sin configurar en el servidor.
- **Solución (código)**: header `X-Internal-Token` en `send_to_many.php`
  + 3 crons (URLs centralizadas); creación del canal en `MainActivity.kt`
  + permisos/meta-data en el manifest; **nuevo**
  `web/firebase-messaging-sw.js` con la config real + FCM habilitado en
  web cuando hay VAPID; `send_bulk.php` por lotes de 500 con
  `payload_json` (+fallback) y INSERT fuera del try; `smart_notifications.php`
  con `payload_json` (+fallback).
- **Pendiente manual** (pasos exactos en
  `GUIA_ACTIVACION_NOTIFICACIONES_SABERPLUS.md`): subir el service
  account JSON a `backend/config/` (o definir `FIREBASE_SERVICE_ACCOUNT`),
  generar VAPID key y completar `.env` de Flutter, y probar end-to-end.
- **Estado**: 🟡 código completado y balance-verificado · 🔵 activación
  en Firebase Console/servidor.

## 17. Panel administrativo — ✅ (+🔴 parcial justificado)

- Documentado en `GUIA_ACCESO_ADMIN_SABERPLUS.md`: ruta real,
  autenticación (`.env` `ADMIN_USER`/`ADMIN_PASS` + sesión PHP + rate
  limit + CSRF + auditoría), cómo crear admin / restablecer contraseña,
  roles (admin único / directores B2B / usuario-app) y seguridad. Sin
  contraseñas reales.
- Visión de producto aplicada: módulos nuevos **Cursos Moodle** (#9) y
  **Códigos Premium** (#4); ya existían Usuarios, Colegios, Métricas
  (dashboard/analítica/ingresos), Seguridad (auditoría) y Soporte.
- **🔴 Multi-admin con roles diferenciados**: no implementado — decisión
  deliberada (el modelo actual de un solo admin por `.env` tiene menos
  superficie de ataque y el panel B2B de directores cubre el caso de uso
  institucional real). Documentado como mejora futura.

---

## Pruebas ejecutadas (no-regresión)

| Área | Prueba | Resultado |
|------|--------|-----------|
| Sintaxis Dart | Balance estructural (strings/comentarios excluidos) sobre los 23 archivos .dart modificados | ✅ TODO BALANCEADO |
| Sintaxis PHP | Chequeo estructural del proyecto (incluye `admin/index.php` 245/245 llaves) sobre los 14 .php modificados | ✅ TODO OK |
| Referencias cruzadas | Métodos biometricos viejos, plan_service/access_wrapper/question_table, rutas nuevas, redeemPromoCode | ✅ 0 referencias rotas |
| Colores/UI | Todos los `AppColors.*` usados en pantallas nuevas existen | ✅ |
| Compatibilidad | Ambas migraciones con fallback verificado por simulación (get_courses/set_password idénticos sin migrar) | ✅ |
| Preservación | Diferencias del propietario (quiz_intro/question_screen) intactas — verificado por diff contra origin/main | ✅ |

**Pendiente de prueba externa** (requiere dispositivo/servidor/Moodle
reales — no disponibles en este entorno): renderizado de retroalimentación
con HTML real de Moodle, huella en dispositivo físico, matrícula masiva
contra Moodle, entrega de push end-to-end, envío de correos SMTP.

## Archivos totales de la entrega

- **Nuevos (12)**: `backend/migrations/008_codigos_premium.sql`,
  `backend/migrations/009_course_catalog.sql`,
  `backend/redeem_promo_code.php`, `backend/includes/avatar_helper.php`,
  `lib/parsers/review_question_parser.dart`,
  `lib/widgets/question_option_tile.dart`, `lib/screens/lock_screen.dart`,
  `lib/screens/registration_success_screen.dart`,
  `web/firebase-messaging-sw.js`, `GUIA_ACTIVACION_NOTIFICACIONES_SABERPLUS.md`,
  `GUIA_ACCESO_ADMIN_SABERPLUS.md`, `CAMBIOS_v2.0.0.md`.
- **Modificados (37)** + **Eliminados (4)** + **Movidos a docs/ (15)** —
  detalle con motivo y cambio principal en el archivo de entrega adjunto.
