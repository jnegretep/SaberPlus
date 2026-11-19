# AUDITORÍA INICIAL — SABER+

**Fecha:** 5 de noviembre de 2026
**Versión auditada:** v1.7.1 (commit `ad0a870`, rama `main` de github.com/jnegretep/SaberPlus)
**Método:** Auditoría multi-agente (3 especialistas en paralelo: Flutter/Navegación, Backend/Seguridad, Producto/UX)
**Modo:** Solo lectura — no se modificó nada durante la auditoría

---

## 1. RESUMEN EJECUTIVO

Saber+ es una plataforma EdTech de preparación para las Pruebas Saber 11 (ICFES, Colombia) con un desarrollo considerable y funcional: **aplicación Flutter (móvil + web), backend PHP con ~107 endpoints, integración completa con Moodle como LMS y banco de preguntas, gamificación, notificaciones FCM, tutor con IA (Gemini→DeepSeek con failover), paneles B2B para directores de colegio y un panel administrativo de 13 secciones.**

**Veredicto general:** la base es sólida y sorprendentemente completa para su etapa, pero **no está lista para lanzamiento comercial** por tres razones:

1. **La navegación web está rota** (bug reportado por el propietario, causa raíz identificada al 100%): 37 pantallas se apilan con `Navigator.push` crudo por fuera de GoRouter, por lo que nunca generan entradas en el historial del navegador. El usuario queda "atrapado" en pantallas de simulacros.
2. **La seguridad tiene 7 familias de secretos commiteados en git** (secreto JWT, claves de producción de Wompi, contraseñas de aplicación SMTP, credenciales de BD) y **3 endpoints de lógica de negocio explotables** (auto-promoción a premium sin pagar, XP infinita desde el cliente, resultados de simulacro falsificables).
3. **El motor de gamificación está construido pero desconectado del flujo principal**: la XP solo se otorga en los retos diarios. Un estudiante que solo hace simulacros mantiene XP=0, nivel 1 y racha 0.

Ninguno de estos problemas requiere re-arquitectura: son **correcciones quirúrgicas** sobre archivos existentes.

---

## 2. ARQUITECTURA ENCONTRADA

### 2.1 Frontend (Flutter/Dart)

| Componente | Tecnología | Estado |
|---|---|---|
| Framework | Flutter, Material 3, GoRouter 14.8.1 | ✅ Moderno |
| Gestión de estado | Provider 6.1.5 (MultiProvider + ProxyProvider) | ✅ Adecuado |
| HTTP | **dio + http coexisten** (migración a medias) | ⚠️ Deuda |
| Autenticación | JWT + refresh token (DioClient con interceptores, cola de pendientes) | ✅ Bien hecho |
| Firebase | core 3.15 / messaging 15.1 / analytics 11.3 / crashlytics 4.1, init con `firebase_options.dart` | ✅ |
| Charts | **syncfusion_flutter_charts + fl_chart (dos librerías)** | ⚠️ Peso duplicado |
| HTML | flutter_html 3.0 + flutter_widget_from_html_core + html (tres parseadores) | ⚠️ |
| Tema | Light + dark completos, tipografía Inter, paleta Tailwind-like (`#1E4ED8` primario, `#FACC15` acento) | ✅ |

**Estructura:** `lib/` con 39 screens, 4 providers, servicios (auth, api, fcm, analytics, gamification, prediction, daily_challenge, plan, google_auth), `core/` (theme, services, utils), `config/` (router, navigation, env), controladores (quiz_controller), parsers, widgets ricos para contenido Moodle (moodle_rich_text, moodle_table, q_image — v1.7.1).

### 2.2 Backend (PHP)

- **~107 endpoints HTTP** en 129 archivos PHP (21 de soporte).
- Autenticación: **doble token** — JWT HS256 (24 h, revocación por lista negra `revoked_tokens`) + refresh opaco (30 días, rotación real en `refresh.php`). **Moodle actúa como IdP de los estudiantes** (login proxy vía `/login/token.php`, sincronización de usuario).
- FCM: **Kreait SDK + service account JSON = HTTP v1 API** ✅, limpieza de tokens inválidos en 3 niveles, crons inteligentes (racha en riesgo, inactividad, retos).
- IA: multi-proveedor Gemini→DeepSeek con failover, rate-limit 6 req/min, sanitización, prompt enriquecido con datos reales del estudiante.
- Pagos: Wompi (web, firma verificada con `hash_equals`) + Google Play Billing (verificación server-side contra Google, idempotencia).
- Paneles: admin (13 secciones, monolito de 1.744 líneas) y director B2B (el módulo mejor construido: CSRF, rate-limit, `session_regenerate_id`, scoping por colegio).
- Base de datos: MySQL con 6 migraciones versionadas (planes, gamificación con 5 tablas + funciones SQL, analytics, Play Billing, directores, promociones/quejas). **El schema base no está versionado** (inferido del código).

### 2.3 Flujos críticos verificados

- **Simulacro completo:** `get_quizzes` → `quiz_attempts_list` → `start_attempt` (idempotente, reanuda `inprogress`) → `get_attempt_data` (polling 30 s) → `submit_attempt` (debounce 700 ms) → `finish_attempt` → `review_attempt` → `save_result` (solo cursos 2,3,18,24–31).
- **Puntaje ICFES:** ponderación Saber 11 real `(LC·3 + Mat·3 + Soc·3 + CN·3 + Ing·1)/13 · 5` → escala 0–500.
- **Áreas (5):** Lectura crítica, Matemáticas, Ciencias sociales, Ciencias naturales, Inglés — asignadas **por posición de página** de Moodle (frágil).

---

## 3. PROBLEMAS DETECTADOS

### 3.1 🔴 CRÍTICOS

| # | Problema | Ubicación | Impacto |
|---|---|---|---|
| C1 | **Navegación web rota**: 37 usos de `Navigator.push/pushReplacement` fuera de GoRouter; pantallas de simulacro sin entrada en historial del navegador; back interno deja de funcionar; `QuestionScreen` en carga no tiene botón de salida (atrapado si falla) | `dashboard_screen:276,317,338,402,539` · `course_contents:435,453` · `quiz_intro:344,1107,1153` · `question_screen:127,200,250,318,867` · `quiz_list:53-84` · `challenge_detail:328,383,622` · `stats_home:600,686,705` · `dashboard_header:98` · `perfil_hub:376,598` · `daily_challenges:147` | Bug #1 reportado por el propietario; web inutilizable en flujos largos |
| C2 | **Secreto JWT hardcodeado en git** (`jwt_config.php:4`) | backend | Cualquiera con acceso al repo puede forjar tokens de cualquier usuario (incluye `moodle_token` embebido) = takeover total |
| C3 | **7 familias de secretos en git**: claves de PRODUCCIÓN Wompi (`wompi_config.php:5-8`), 2 app-passwords SMTP de Gmail (`register.php:155-156,254-255`, `forgot_password.php:117-118`, `resend_verification.php:73-74`), credenciales BD (`includes/conexion.php:3-6`, `includes/moodle_db.php:7-10`), token WS Moodle (`includes/config.php:35`) | backend | Compromiso total de pagos, correo y bases de datos |
| C4 | **`upgrade_to_premium.php` sin verificación de pago**: cualquier usuario autenticado se auto-promueve a premium | `upgrade_to_premium.php:46-54` | Pérdida directa de ingresos |
| C5 | **XP desde el cliente sin tope**: `xp_amount` llega del body; XP infinita y rankings falsos | `gamification_award_xp.php:73,96` | Integridad de gamificación destruida |
| C6 | **Motor de gamificación desconectado**: `awardXp()` solo se llama desde retos diarios; simulacros, cursos, `daily_login` y `streak_bonus` nunca otorgan XP ni actualizan racha | `review_screen.dart:382` (guarda resultado sin XP) | Retención nula: el estudiante no percibe progreso |
| C7 | **Spinner infinito sin escape** en QuestionScreen si `QuizController.start()` falla (error tragado en `quiz_controller:321`) | `question_screen.dart:867-889` | Usuario atrapado; única salida es cerrar la pestaña |
| C8 | **Endpoints sin autenticación**: `stats/summary, rank, context, area_trend` (rendimiento académico de cualquier estudiante), `get_notifications.php`, `mark_notification_read.php`, 3 crons disparables por HTTP | backend/stats/, crons | Fuga de datos personales (IDOR) y spam masivo FCM |
| C9 | **Datos personales de soporte expuestos**: "Jose Negrete" en pantalla Acerca de, teléfono personal +57 315 279 1015, correo personal `jnegretep24@gmail.com` con contraseñas SMTP en el código | `app_constants.dart:16-18` · `acerca_screen.dart:300,436` · register/forgot/resend | Requisito del propietario: identidad institucional |

### 3.2 🟠 ALTOS

| # | Problema | Ubicación |
|---|---|---|
| A1 | Doble llamada a `start_attempt.php` al iniciar simulacro (quiz_intro + quiz_controller) → latencia duplicada | `quiz_intro:327` + `quiz_controller:291` |
| A2 | `state.extra as Map` sin null-check en 6 rutas → crash en F5/deep-link web | `app_router.dart:137,149,174,234,244,327` |
| A3 | `WillPopScope` que devuelve false y popea manualmente (deprecado + interfiere back Android) | `review_screen.dart:809-813` |
| A4 | Tabs del bottom nav con `context.push` → cada tap apila historial | `global_scaffold.dart:295-312` |
| A5 | `ApiService` (http crudo) sin timeouts ni manejo de 401 → solo Dio refresca sesión | `api_service.dart` |
| A6 | Resultados de simulacro enviados por el cliente sin validar contra Moodle | `simulacros/save_result.php:66-80` |
| A7 | SSRF + fuga de token WS Moodle en proxy de archivos (host arbitrario, SSL sin verificar) | `get_file.php:36-90` |
| A8 | Login admin sin rate-limit, sin `session_regenerate_id`, contraseña en claro en .env; acción `resolve_error` sin CSRF | `admin/index.php:13-34,99-109` |
| A9 | 4 insignias imposibles de desbloquear (`early_bird`, `night_owl`, `perfect_area`, `all_areas_70`) — sus `requirement_type` no están implementados | `gamification_award_xp.php:467` |
| A10 | Sin rate-limit en login/register/forgot (fuerza bruta, spam de correos) | backend |
| A11 | Tabla `notifications` con inserciones en columnas distintas según endpoint (`data` vs `payload_json`) → fallos silenciosos | `send_bulk.php:45` vs `send_notification.php:158` |
| A12 | `.env` empaquetado como asset Flutter (pubspec.yaml:100) | flutter |

### 3.3 🟡 MEDIOS

- `quiz_list_screen` es la pantalla más débil: error crudo, "Límite: 1500s" en segundos, sin intentos previos, fuera del design system.
- Tap muerto en tarjeta de curso del dashboard (`dashboard_screen:365-367`) y en "Calificar app" (`perfil_hub:869-873`).
- Polling con `Future.delayed` recursivo sin cancelación real (`quiz_intro:83-102`).
- IDs de cursos simulacro hardcodeados `[2,3,18,24..31]` (`quiz_intro:41`).
- `NotificationProvider` recreado en cada rebuild de auth (`main.dart:400-412`).
- Onboarding inexistente post-login (solo carrusel pre-login de 2 páginas; flag `first_time` se marca al arrancar, no al completar).
- Sin soporte de tipos de pregunta más allá de opción múltiple única (parser solo lee `input[type=radio]`).
- `display_errors=1` en 2 endpoints teacher; `json_encode($e->getMessage())` en 17 archivos.
- CORS `*` en 80 endpoints.
- Código muerto de otro proyecto ("TRAZA"): `config/database.php`, `middleware/auth_middleware.php`, `controllers/access_controller.php`, `models/UserPlan.php`, `moodle/auth.php` (roto), `moodle/get_questions.php` (argumentos invertidos), `update_hash.php` (script de debug), `stats/rank(1).php` (duplicado), `challenges/force_start.php` (vacío).
- Inconsistencia de marca: correos transaccionales firmados "PrepSaber" vs "Saber+".

---

## 4. RIESGOS

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| Explotación de secretos publicados (repo público confirmado) | Alta si el repo tiene tráfico | Crítico | Rotación inmediata de TODAS las credenciales + purga del historial git |
| Usuario atrapado en simulacro web → abandono | Alta (reproducible) | Alto | Fix C1 (migración completa a GoRouter) |
| Auto-promoción premium masiva | Media | Alto (ingresos) | Fix C4 |
| Manipulación de rankings (XP cliente) | Media | Alto (confianza) | Fix C5 |
| Crash web en F5 durante registro/quiz | Media | Medio | Fix A2 |
| Spam FCM por crons expuestos | Media | Medio | Fix C8 |

---

## 5. DEUDA TÉCNICA

1. **Doble stack HTTP** (dio + http): solo dio tiene interceptores de refresh/401.
2. **Dos librerías de charts** y **tres parseadores HTML** (peso de app duplicado).
3. **Panel admin monolítico** (1.744 líneas) sin separación de vistas/lógica.
4. **Validación JWT duplicada** (copy-paste del mismo bloque en ~15 archivos) en vez de un solo middleware.
5. **Schema base de BD no versionado** (no hay migración 000).
6. Validación manual `AppColors` + ternarios `isDark` en pantallas en vez de consumir `ThemeData`.
7. Helpers de navegación muertos (`Nav.goCourses/goQuestion/goReview/goProfile/goQuestions`).

---

## 6. FUNCIONALIDADES EXISTENTES (inventario)

**✅ Completas y funcionando:** auth (login/registro 2 pasos/verificación email/recuperación/Google/cambio y reset de contraseña/eliminación GDPR), cursos y contenidos Moodle, simulacros completos con review y explicaciones, retos 1v1, retos diarios, XP/niveles/rachas/insignias/ranking, predicción ICFES, análisis de errores, tendencias por área, comparativas, tutor IA multi-proveedor, notificaciones FCM + bandeja interna, gamificación header, dashboard con showcase de progreso, perfiles y configuración (tema, privacidad), soporte con tickets, paneles admin y director, pagos Wompi + Play Billing, promociones, analytics propio + Firebase, panel web adaptativo (rail >1100px, marco móvil ≤1100px).

**⚠️ Incompletas:** gamificación desconectada del flujo principal (C6), 4 badges sin desbloqueo (A9), streak freeze (columna existe, sin endpoint ni UI), "Calificar app" (botón muerto), tour de bienvenida (solo pre-login, sin skip, no recuperable), metas diarias/semanales (no existen), exportes CSV en admin (solo el panel director los tiene), analítica educativa agregada (los datos existen pero no se visualizan), tipos de pregunta adicionales (cloze, T/F, multi-select).

---

## 7. OPORTUNIDADES DE MEJORA (matriz)

| Oportunidad | Beneficio | Complejidad | Prioridad |
|---|---|---|---|
| Migración completa a GoRouter (fix C1) | Web realmente navegable | Media | 🔴 Crítica |
| Pantalla de preparación de simulacro + estados | Elimina incertidumbre y atrapados | Media | 🔴 Crítica |
| Conectar XP/racha al flujo principal | Retención inmediata | Baja | 🔴 Crítica |
| Soporte institucional + SMTP a .env | Seguridad + marca | Baja | 🔴 Crítica |
| Cierre de vulnerabilidades (C2–C5, C8) | Integridad del negocio | Media | 🔴 Crítica |
| Onboarding post-login con checklist | Activación de nuevos usuarios | Media | 🟠 Alta |
| Rediseño quiz_list_screen | Coherencia visual | Baja | 🟠 Alta |
| Badges especiales + metas diarias | Motivación | Baja-Media | 🟠 Alta |
| Dashboard ejecutivo admin (series, retención, ingresos) | Control del negocio | Media | 🟠 Alta |
| Exportes CSV en admin | Operación | Baja | 🟠 Alta |
| Mejor UX de error/carga general | Confianza | Baja | 🟡 Media |
| Mapeo formal de competencias ICFES | Diferenciador académico | Alta | 🟡 Media |

---

## 8. PLAN DE TRABAJO (resumen)

**Fase 3 — Implementación (orden):**
1. Navegación web completa a GoRouter + null-checks + PopScope modernos.
2. Flujo de inicio de simulacro con estados (preparando/cargando/listo/error/reintentando) y eliminación de la doble llamada.
3. Seguridad crítica: JWT/SMTP a env, cierre de `upgrade_to_premium`, XP server-side, auth en stats/crons, limpieza de código muerto.
4. Soporte institucional (Equipo de soporte Saber+ · +57 350 2114292 · Saberplus2026@gmail.com) en toda la app.
5. Gamificación conectada: XP por simulacro/curso/login + racha + badges especiales.
6. Onboarding post-login.
7. Panel admin: dashboard ejecutivo con series reales + exportes CSV.
8. UX/UI: quiz_list, taps muertos, estados vacíos.

**Fase 4-5:** integración, análisis estático (dart analyzer / php -l donde el sandbox lo permita), verificación de flujos.

**Fase 6-7:** checklist de lanzamiento, documentación (7 entregables), entrega.

---

## 9. LIMITACIONES DE LA AUDITORÍA (declaradas)

- No se pudo ejecutar la app ni el SDK de Flutter/PHP en el sandbox de auditoría: las líneas de código citadas están verificadas al 100% en fuente, pero el comportamiento runtime se describe según la semántica documentada de GoRouter/Navigator.
- El schema base de la BD no está en el repo: tablas base inferidas del código.
- No se verificó la configuración real de Apache/PHP del servidor de producción ni si `.env` es descargable por web (hallazgo A-18 a comprobar en servidor).
- El service account de Firebase no está en el repo (correcto): no se pudo validar la vigencia de credenciales FCM.
- Firebase/FCM requiere pruebas reales en dispositivo/navegador que solo el propietario puede ejecutar; se entregará un protocolo de verificación.

---

*Documento generado por el equipo de auditoría multi-agente (AUDIT-A: Flutter/Navegación · AUDIT-B: Backend/Seguridad · AUDIT-C: Producto/UX). Próximo documento: PLAN_TRANSFORMACION_SABERPLUS.md*
