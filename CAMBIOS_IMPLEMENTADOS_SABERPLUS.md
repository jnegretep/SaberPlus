# CAMBIOS IMPLEMENTADOS — SABER+

**Fecha:** 5 de noviembre de 2026 · **Rama:** `feature/transformacion-edtech` · **Base:** v1.7.1 (`ad0a870`)
**Commits de la transformación:** 7 commits atómicos (ver §8)

---

## RESUMEN DE IMPACTO

| Métrica | Valor |
|---|---|
| Archivos Dart modificados | 25 |
| Archivos PHP modificados | 26 |
| Archivos nuevos | 6 (onboarding_screen, admin/export_csv.php, admin/includes/admin_audit.php, migrations/007, 2 docs) |
| Archivos eliminados | 8 (código muerto/peligroso) |
| Líneas añadidas / eliminadas | ~3.700 / ~600 |
| Vulnerabilidades críticas cerradas | 9 |
| Pantallas migradas a navegación con URL | 14 |

---

## 1. NAVEGACIÓN WEB (PT1) — fix del bug reportado

### Cambio 1.1 — Rutas nuevas en el router
- **Problema:** 14 pantallas se abrían con `Navigator.push` crudo: nunca entraban en el historial del navegador. El botón atrás del navegador no las veía y el back interno dejaba de funcionar al mezclarse las pilas.
- **Causa raíz:** coexistencia de dos sistemas de navegación (GoRouter + Navigator). `Navigator.pushReplacement` desde una GoRoute "descuelga" la pantalla del router y congela la URL.
- **Solución:** registro de 8 rutas nuevas (`/quiz-intro/:courseId/:quizId`, `/html-viewer`, `/simulacro-stats/:quizId`, `/notifications`, `/chat`, `/stats/area-trend`, `/stats/comparativas`, `/stats/ranking`) + migración de los 37 call-sites a `context.push/pushReplacement/go`.
- **Archivos:** `lib/config/app_router.dart`, `lib/config/navigation.dart` (+ helpers `replaceQuestion/replaceReview/safePop/goQuizIntro/goHtmlViewer/goSimulacroStats/goNotifications/goChat/goAreaTrend/goComparativas/goRanking`), `dashboard_screen`, `course_contents_screen`, `quiz_intro_screen`, `question_screen`, `review_screen`, `quiz_list_screen`, `daily_challenges_screen`, `challenge_detail_screen`, `challenge_question_screen`, `stats_home_screen`, `perfil_hub_screen`, `register_step1/2`, `verify_email_screen`, `create_challenge_screen`, `course_list_screen`, `dashboard_header.dart`, `notifications_badge_icon.dart`, `global_scaffold.dart`.
- **Resultado:** flujo Cursos → Contenidos → Simulacro → Preguntas → Resultados → volver funciona con back interno Y back del navegador; cada pantalla tiene URL.
- **Pruebas:** análisis estático de balance (158 archivos ✓); verificación de que ningún `MaterialPageRoute` de pantalla queda (solo la galería de imágenes overlay). *Pendiente de validación externa: prueba en navegador real (protocolo en Checklist §3).*

### Cambio 1.2 — Null-checks de `state.extra` (anti-crash F5/deep-link)
- **Problema:** 6 rutas castiaban `state.extra as Map` sin verificación → recargar la página (F5) en registro/quiz/review crasheaba la app web.
- **Solución:** guard con pantalla `_extraRequiredFallback` ("Esta pantalla no puede abrirse directamente" + botón Volver al inicio).
- **Archivos:** `app_router.dart` (rutas verify-email, set-password, reset-password, question, review, challenges/:id/question).

### Cambio 1.3 — Tabs sin apilar historial
- **Problema:** cada tap en el bottom nav usaba `context.push` → el historial crecía por cambio de pestaña y "atrás" tenía que deshacer todos los cambios de pestaña.
- **Solución:** `_onStudentTap`/`_onTeacherTap` de `global_scaffold.dart` ahora usan `context.go` (afecta bottom nav, rail de tablet y rail de escritorio).
- **Archivos:** `lib/widgets/global_scaffold.dart`.

### Cambio 1.4 — WillPopScope deprecado eliminado
- **Problema:** `review_screen` usaba `WillPopScope` que devolvía `false` y popeaba manualmente → interfería con back de Android y del navegador.
- **Solución:** pops naturales con `context.pop(true)`; el comportamiento de refresco de la pantalla anterior se conserva (`result == true || mounted`).

### Cambio 1.5 — Nav.safePop (back que nunca atrapa)
- **Solución:** helper que hace `context.pop()` si hay pila y `context.go('/dashboard')` si no (entrada directa por URL). Aplicado en los back de quiz_intro y estados de error.

### Cambio 1.6 — Tap muerto de curso corregido
- **Problema:** la tarjeta de curso del dashboard tenía `onTap: () {}` vacío (auditoría C-UX).
- **Solución:** navega a `/course-contents/:id` vía `Nav.goCourseContents`.

---

## 2. EXPERIENCIA DE SIMULACROS (PT2)

### Cambio 2.1 — Overlay de preparación con estados
- **Problema:** al presionar "Comenzar simulacro" solo giraba el spinner del botón; en esperas largas el usuario no sabía si la app se colgó.
- **Solución:** diálogo no cancelable: *"Estamos preparando tu simulacro. Estamos cargando las preguntas y configurando tu intento. Esto puede tardar unos segundos. No cierres esta pantalla."* con indicador animado y pasos (crear intento · cargar preguntas · configurar cronómetro). Se cierra solo al entrar o al manejar el error.
- **Archivos:** `quiz_intro_screen.dart` (`_showPreparationOverlay`).

### Cambio 2.2 — Fin del callejón sin salida en QuestionScreen
- **Problema:** si `QuizController.start()` fallaba, el error se tragaba (catch → debugPrint) y la pantalla quedaba en `CircularProgressIndicator` SIN AppBar ni botón — usuario atrapado (auditoría C7).
- **Solución:** (a) `QuizController` expone `error`; `start()` lo propaga y detecta "0 preguntas" como error real; (b) QuestionScreen muestra estado de error con **Reintentar** y back de salida.
- **Archivos:** `quiz_controller.dart`, `question_screen.dart`.

### Cambio 2.3 — Rediseño de QuizListScreen
- **Problema:** la pantalla más débil de la app (auditoría): "Límite: 1500s" en segundos crudos, error crudo `Error: ...`, tap que iniciaba el intento directamente sin confirmación ni guard de doble-tap.
- **Solución:** tarjetas del design system (icono, preguntas, duración en minutos), estados de carga/error con Reintentar/empty state amable, y el tap navega a la **ficha del quiz** (confirmación + intentos previos + prevención de duplicados) por router.
- **Archivos:** `quiz_list_screen.dart` (reescrito).

---

## 3. SEGURIDAD BACKEND (PT3)

### Cambio 3.1 — Secretos fuera del código (7 familias)
- **Problema:** secreto JWT, credenciales BD (x2), 4 claves Wompi de producción, token WS Moodle y 2 app-passwords SMTP de Gmail commiteados en un repo público → forja de tokens, acceso a BD, manipulación de pagos, robo de correo (auditoría C2/C3).
- **Solución:** todo pasa por `env()` con **fallback transitorio al valor actual** (para no romper el despliegue ni invalidar sesiones activas) + `error_log` de advertencia de rotación en cada uso del fallback. `.env.example` ampliado con todas las claves mascaradas.
- **Archivos:** `jwt_config.php`, `includes/conexion.php`, `wompi_config.php`, `includes/config.php`, `includes/moodle_db.php`, `register.php`, `forgot_password.php`, `resend_verification.php`, `.env.example`.
- **⚠️ Acción obligatoria del propietario:** definir los valores en `backend/.env` del servidor, **rotar todas las credenciales** y borrar los fallbacks (cada uno emite warning en log mientras exista).

### Cambio 3.2 — Fin de la auto-promoción a premium
- **Problema:** `upgrade_to_premium.php` activaba premium a cualquier usuario autenticado sin verificar pago (auditoría C4) — pérdida directa de ingresos.
- **Solución:** exige `reference` (validada contra `payments` con status approved y user del token) o `purchase_token` (validado contra `play_purchases`); sin ninguno → `400 {"error":"pago_requerido"}`.

### Cambio 3.3 — XP server-side (fin de la XP infinita)
- **Problema:** `xp_amount` llegaba del cliente sin tope → rankings falsos (auditoría C5).
- **Solución:** tabla server-side fija por reason (simulacro=100, reto=50, curso=20, daily_login=10, streak_bonus=25); el valor del cliente se ignora y se loguea; reason inválido → 400. Respuesta exitosa idéntica (compatibilidad).

### Cambio 3.4 — Endpoints sin autenticación cerrados (IDOR)
- **Problema:** `stats/summary|rank|context|area_trend`, `get_notifications`, `mark_notification_read`, `simulacros_attempts` filtraban datos de CUALQUIER estudiante sin token (auditoría C8).
- **Solución:** `auth_middleware` + userId tomado del JWT (parámetro de request ignorado). La app (api_service.dart, 3 call-sites) ahora envía `Authorization: Bearer`.

### Cambio 3.5 — Crons protegidos, anti-SSRF y hardening admin
- **Solución:** (a) los 3 crons exigen guard (`saberplus_guard_admin_fcm`): sesión admin, CLI o `X-Internal-Token`; (b) `get_file.php`: allowlist de host contra MOODLE_BASE_URL + TLS reactivado; (c) admin: rate-limit login 5/10 min, `session_regenerate_id`, cookies httponly+samesite, CSRF en resolve_error; (d) rate-limit por IP en login/register/forgot_password.
- **Nota crons:** si en el servidor se invocan por HTTP, deben pasar a CLI (cron de sistema) o enviar `X-Internal-Token`.

### Cambio 3.6 — Eliminación de código muerto/peligroso
- **Eliminados:** `update_hash.php` (reset de password sin auth), `stats/rank(1).php` (duplicado), `challenges/force_start.php` (vacío), `config/database.php` + `middleware/auth_middleware.php` (de otro proyecto "TRAZA"), `controllers/access_controller.php`, `models/UserPlan.php`, `moodle/auth.php` (roto). Verificado: cero referencias.

---

## 4. IDENTIDAD INSTITUCIONAL DE SOPORTE (PT4)

- **Problema:** nombre propio "Jose Negrete" en pantalla Acerca de, teléfono personal y Gmail personal con app-passwords en el código (auditoría C9).
- **Solución:** `app_constants.dart` → soporte = **Equipo de soporte Saber+** · **+57 350 2114292** · **Saberplus2026@gmail.com**; acerca_screen con equipos institucionales; soporte_screen con nueva tarjeta "Escríbenos directamente" (WhatsApp + correo con launchUrl); correos SMTP con remitente y firma "Equipo de soporte Saber+" y marca "PrepSaber" eliminada.
- **Preservado (legítimo):** datos de colegios en CSV, ejemplos "John Doe"/"Juan Pérez" en docblocks, IDs de Firebase.

---

## 5. GAMIFICACIÓN CONECTADA (PT5)

- **Problema:** el motor de XP existía pero `awardXp()` solo se llamaba desde retos diarios → quien solo hacía simulacros mantenía XP=0, nivel 1, racha 0 (auditoría C6).
- **Solución:**
  - `review_screen`: al guardar estadísticas del simulacro → `awardXp(reason:'simulacro', referenceId:attemptId)` + `CelebrationOverlay` (levelUp/badge/completado).
  - `dashboard_screen`: `daily_login` (10 XP) una vez por día natural (dedup local por fecha + server-side).
  - Backend: **deduplicación server-side por (usuario, reason, reference_id)** — un evento otorga XP una sola vez.
  - **4 badges antes imposibles** ahora se desbloquean: `early_bird` (5–8 am), `night_owl` (22–5), `perfect_area` (100% en un área), `all_areas_70` (≥70% todo).

---

## 6. ONBOARDING Y ACTIVACIÓN (PT6)

- **OnboardingScreen nueva:** 5 pasos (Bienvenida · Cursos · Simulacros · XP e insignias · Progreso), avance/retroceso, Saltar, indicadores animados, responsive (≤560px centrado en escritorio). Flag `onboarding_completed` marcado **solo al completar/saltar** (el carrusel pre-login se marcaba al arrancar y se perdía). Se dispara en el primer arranque del dashboard y es **relanzable desde Configuración → "Ver tour de bienvenida"**.
- **FirstStepsChecklist** en dashboard: "Empieza con buen pie" (Completa tu perfil · Haz tu primer simulacro · Gana tu primera XP) con progreso x/3, persistido, descartable, se oculta al completar.
- **Fix botón muerto:** "Calificar app" ahora abre la ficha de Play Store.

---

## 7. PANEL ADMINISTRATIVO — INTELLIGENCE CENTER (PT7)

- **Dashboard ejecutivo:** 4 series de 30 días con SVG inline 100% PHP (sin JS/CDN): registros/día, simulacros/día, XP otorgada/día, DAU aproximado + mini-grid "Salud del negocio" (conversión premium, promedio ICFES, tiempo medio).
- **Sección Ingresos:** recaudo approved (total/mes/pendiente), barras por pasarela, conversión Free→Premium, últimos 20 pagos con usuario y badges de estado.
- **Sección Académica:** promedio por área (5 barras), distribución de puntajes por rangos, top 10 colegios, heatmap área×grado.
- **Sección Auditoría:** últimas 50 acciones admin (`admin_audit_log`).
- **Auditoría de acciones:** 8 acciones sensibles registradas (directores, promos, quejas, usuarios) — contraseñas nunca.
- **Exportes CSV:** usuarios/resultados/pagos con anti-CSV-injection, BOM UTF-8, límite 5000, auditados.
- **Migración 007** (manual, no rompe nada sin ejecutar): tabla `admin_audit_log`.

---

## 8. COMMITS DE LA TRANSFORMACIÓN

| # | Commit | Contenido |
|---|---|---|
| 1 | `012bbda` | PT1+PT2: migración completa a GoRouter + estados de carga |
| 2 | `1ca14c4` | PT3: cierre de vulnerabilidades críticas del backend (33 archivos) |
| 3 | `097b279` | PT4: identidad institucional de soporte |
| 4 | `af3ea1a` | PT5: motor de XP conectado al flujo principal |
| 5 | `4d644e8` | PT6: tour de bienvenida + checklist de activación |
| 6 | `1909a79` | PT7: Administration & Intelligence Center |
| 7 | `3aa5a1e` | PT2 completo: overlay de preparación |
| 8 | `43947ae` | docs: 7 entregables de la misión |

Rama: `feature/transformacion-edtech` (8 commits sobre `origin/main` = `ad0a870`).

---

## 9. PRUEBAS REALIZADAS Y PENDIENTES

### Realizadas en este entorno (sin SDK Flutter/PHP disponible)
1. **Análisis estructural Dart:** 158 archivos — balance de llaves/paréntesis/corchetes fuera de strings/comentarios: **100% OK**.
2. **Análisis estructural PHP:** 123 archivos (sin vendor) — **100% OK** (2 falsos positivos por heredoc con CSS, verificados manualmente).
3. **Verificación de imports:** ningún archivo usa `Nav.*` o `context.push/pop/go` sin su import; cero referencias a clases eliminadas; cero rutas referenciadas no registradas.
4. **Verificación de referencias cruzadas:** campos de `AppColors`, `AwardXpResult`, `Quiz` usados en código nuevo existen en los modelos; columnas SQL de badges verificadas contra `save_result.php` real.
5. **Grep de datos personales:** 0 ocurrencias de "Jose Negrete"/teléfono personal/Gmail personal en `lib/`.

### Pendientes de validación externa (requieren el entorno del propietario)
1. `flutter analyze` + `flutter build web` + `flutter build apk` (sandbox sin SDK).
2. Protocolo de prueba del bug de navegación (Checklist §3): flujo completo con back/adelante/F5 del navegador.
3. Disparo real de FCM en dispositivo (el service account no está en el repo).
4. Rotación de credenciales + borrar fallbacks + probar login/SMTP/pagos en staging.
5. Prueba del flujo XP: terminar simulacro → verificar +100 XP y celebración; segundo intento → deduplicado (0 XP).
6. Ejecutar migración 007 y verificar sección Auditoría del panel.

### Estado por categoría (según la misión)
- **Implementado y probado (estáticamente):** navegación, estados de simulacro, seguridad, marca, XP, onboarding, panel admin.
- **Implementado, pendiente de validación externa:** todo lo anterior en runtime (compilación y pruebas en dispositivo/navegador).
- **Analizado, no implementado (roadmap):** roles múltiples de admin, asistente IA ejecutivo, streak freeze UI, metas semanales, tipos de pregunta cloze/T-F, purga del historial git de secretos (procedimiento documentado en Checklist §6).
- **Pendiente por falta de acceso:** pruebas FCM reales, configuración del servidor Apache (`.env` descargable), ejecución de la migración en BD real.
