# PLAN DE TRANSFORMACIÓN — SABER+

**Fecha:** 5 de noviembre de 2026
**Base:** v1.7.1 (`ad0a870`) · Rama de trabajo: `feature/transformacion-edtech`
**Deriva de:** AUDITORIA_INICIAL_SABERPLUS.md

---

## 1. ESTRATEGIA GENERAL

**Principio rector:** el producto ya funciona; la misión es llevarlo a nivel comercial **sin reconstruir lo que funciona** y **sin romper compatibilidad** con los servicios existentes (Moodle, FCM, Wompi, Play Billing, IA). Cada cambio debe aportar un beneficio comprobable.

**Lema de ejecución:** *cirugía, no trasplante.*

La transformación se organiza en 8 paquetes de trabajo (PT) con dependencias explícitas. Los PT 1–4 son críticos (bloquean lanzamiento); 5–8 son de alto valor.

---

## 2. MATRIZ DE PRIORIZACIÓN Y DEPENDENCIAS

| PT | Nombre | Origen auditoría | Severidad | Complejidad | Depende de |
|---|---|---|---|---|---|
| PT1 | Navegación web unificada (GoRouter) | C1, A2, A3, A4 | 🔴 Crítica | Media | — |
| PT2 | Experiencia de inicio de simulacro | C7, A1 | 🔴 Crítica | Media | PT1 (rutas) |
| PT3 | Seguridad crítica backend | C2, C3, C4, C5, C8, A6, A7, A8 | 🔴 Crítica | Media | — |
| PT4 | Identidad institucional de soporte | C9 | 🔴 Crítica | Baja | — |
| PT5 | Gamificación conectada | C6, A9 | 🔴 Crítica | Baja-Media | — |
| PT6 | Onboarding post-login | AUDIT-C §2 | 🟠 Alta | Media | PT1 |
| PT7 | Panel admin → Intelligence Center | AUDIT-B §3 | 🟠 Alta | Media | — |
| PT8 | UX/UI y pulido de pantallas | AUDIT-C §4 | 🟠 Alta | Baja-Media | PT1 |

**Paralelizables:** PT1+PT3+PT4+PT5 pueden ejecutarse en paralelo (archivos disjuntos: lib/config+lib/screens vs backend/*).
**Secuencia obligatoria:** PT2 después de PT1 (usa las nuevas rutas); PT6 después de PT5 (celebra la primera XP).

---

## 3. DISEÑO DE CADA PAQUETE

### PT1 — Navegación web unificada (el fix del bug reportado)

**Objetivo:** cada pantalla visible = una entrada de historial del navegador. Back/adelante/recarga/F5/deep-link funcionan.

1. **Registrar rutas faltantes** en `app_router.dart`:
   - `/quiz-intro/:courseId/:quizId` (extra: quiz data)
   - `/question` (ya existe; se le da uso real + null-check)
   - `/review` (ídem)
   - `/notifications`, `/chat`, `/html-viewer`, `/simulacro-stats/:quizId`
   - `/stats/area-trend`, `/stats/comparativas`, `/stats/ranking`
2. **Null-checks de `state.extra`** en las 6 rutas que castean sin guard → redirect seguro a `/dashboard` (evita crash en F5).
3. **Migrar los 37 `Navigator.push/pushReplacement`** a `context.push/pushReplacement/go` vía helpers `Nav.*` completados.
4. **Modernizar bloqueos:** `WillPopScope` → `PopScope` (review_screen); salida explícita de review a `/quizzes/:courseId`.
5. **Tabs sin apilar historial:** bottom nav/rail pasa a `context.go` (misma página del router).
6. **Pantalla de carga con escape** (se completa en PT2): botón cancelar/reintentar.
7. Limpieza de helpers muertos (`goQuestions` → ruta inexistente).

**Criterio de aceptación:** flujo Cursos→Contenidos→Simulacro→Preguntas→Resultados→volver funciona con back interno Y back del navegador; F5 en /question con estado pierde la sesión del quiz pero no crashea (redirige con mensaje).

### PT2 — Experiencia de inicio de simulacro

**Objetivo:** cero incertidumbre, cero dobles llamadas, cero pantallas atrapadas.

1. Eliminar la **doble llamada** a `start_attempt.php` (quiz_intro la hace; quiz_controller la repite) → una sola, con el controlador recibiendo el intento ya creado.
2. `QuizController.start()` **deja de tragar errores**: propaga excepción.
3. **Pantalla de preparación** con estados explícitos: `preparando → cargando_preguntas → listo | error_conexión (reintentar/salir) | reintentando`. Mensaje: *"Estamos preparando tu simulacro… Esto puede tardar unos segundos. No cierres esta pantalla."*
4. **Timeouts** en todo el flujo (15 s por llamada, reintento 1 vez con backoff).
5. Guard de doble-tap ya existente se conserva; se añade en quiz_list.
6. Al finalizar: transición a review vía router (PT1).

### PT3 — Seguridad crítica backend

**Regla:** todas las correcciones mantienen compatibilidad de contrato con la app (ningún endpoint cambia su respuesta exitosa).

1. **Secretos fuera del código → `.env`** (el mecanismo `env()` ya existe):
   - `jwt_config.php`: `JWT_SECRET` obligatorio (fallback al valor actual SOLO para no romper sesión activa durante la transición, con warning en log; documentado para rotar).
   - `includes/conexion.php`, `includes/moodle_db.php`, `includes/config.php`: credenciales a `env()`.
   - SMTP en `register.php`, `forgot_password.php`, `resend_verification.php`: `SMTP_USER/SMTP_PASS/SMTP_FROM/SMTP_FROM_NAME` (ya existen en .env.example) + unificar marca a "Saber+".
   - `wompi_config.php`: claves a `env()`.
2. **`upgrade_to_premium.php`**: exige verificación de pago (referencia Wompi válida o purchase token Play verificado) o se desactiva tras aviso (decisión documentada; la app usa los flujos verificados).
3. **XP server-side**: `gamification_award_xp.php` calcula el monto según `reason` con tabla de valores del servidor; ignora `xp_amount` del cliente (retro-compatible: la respuesta no cambia).
4. **Auth en endpoints huérfanos**: `stats/*` (summary, rank, context, area_trend), `get_notifications`, `mark_notification_read`, `simulacros_attempts` → `auth_middleware` + userId del token.
5. **Crons protegidos** con el guard existente `saberplus_guard_admin_fcm()`.
6. **`get_file.php`**: allowlist de host (solo `MOODLE_BASE_URL`) + reactivar verificación SSL.
7. **Admin hardening**: rate-limit login (5 fallos/10 min, patrón director), `session_regenerate_id(true)`, CSRF en `resolve_error`, cookies `httponly+samesite`.
8. **Limpieza de código muerto/peligroso**: eliminar `update_hash.php`, `stats/rank(1).php`, `challenges/force_start.php` (vacío), `config/database.php`, `middleware/auth_middleware.php` (TRAZA), `controllers/`, `models/UserPlan.php`, `moodle/auth.php` (roto), fix `moodle/get_questions.php` (argumentos invertidos).
9. **Rate-limit** en login/register/forgot (patrón /tmp+flock del endpoint IA).
10. `.env` como asset Flutter: se retira del bundle web (build remplaza en runtime ya documentado).

### PT4 — Identidad institucional de soporte

1. `app_constants.dart`: `supportEmail = 'Saberplus2026@gmail.com'`, `supportPhone = '+57 350 2114292'`, `whatsappUrl = 'https://wa.me/573502114292'`.
2. `acerca_screen.dart`: eliminar "Jose Negrete" → "Equipo de soporte Saber+"; teléfono hardcodeado → `AppConstants.supportPhone`.
3. `soporte_screen.dart`: tarjeta de contacto directo (WhatsApp + email) encima del formulario.
4. Correos transaccionales: remitente y firma "Equipo de soporte Saber+" (se solapa con PT3-SMTP).
5. Se PRESERVAN nombres legítimos: "John Doe"/"Juan Pérez" (docblocks), datos de colegios (CSV), IDs Firebase.

### PT5 — Gamificación conectada al flujo real

1. **XP por simulacro:** tras `save_result` exitoso en review_screen → `awardXp(reason:'simulacro')` (100 XP). Solo si el intento no premió ya XP (deduplicación por `reference` = attempt_id, verificada server-side).
2. **XP por curso:** al completar visita de lección/módulo → `awardXp(reason:'curso', 20 XP)` con deduplicación por contenido.
3. **`daily_login` (10 XP):** al abrir sesión el primer arranque del día (client dispara, server valida fecha contra `user_daily_activity`).
4. **Racha:** `awardXp` ya actualiza streak via `_updateStreak` — al conectar los reasons, la racha vive.
5. **Badges especiales** (`early_bird`, `night_owl`, `perfect_area`, `all_areas_70`): implementar sus `requirement_type` en el switch server-side.
6. **Metas diarias:** infra `user_daily_activity` existe → tarjeta "Meta diaria" (anillo de progreso XP del día, meta 100 XP) en dashboard.
7. Celebración: reutilizar `CelebrationOverlay` para level-up/badge tras simulacro.

### PT6 — Onboarding post-login

1. Pantalla de bienvenida de 4–6 pasos (Descubre cursos · Simulacros · Gana XP e insignias · Tu progreso · Comienza), con skip, avance/retroceso, adaptable móvil/web.
2. Flag `onboarding_completed` en SharedPreferences marcado SOLO al completar (o al skip).
3. Checklist "Primeros pasos" en dashboard para usuarios nuevos: [ ] Completa tu perfil · [ ] Haz tu simulacro diagnóstico · [ ] Gana tu primera XP (checklist desaparece al completar).
4. Re-lanzable desde Configuración ("Ver tour de bienvenida").

### PT7 — Panel admin → Administration & Intelligence Center

Evolutivo (sin reescribir el monolito de golpe — se añaden módulos):

1. **Dashboard ejecutivo:** series temporales reales (registros por día 30d, simulacros por día 30d, DAU aproximado por `user_daily_activity`, XP otorgada por día) con mini-gráficos SVG/CSS sin dependencias JS externas.
2. **Exportes CSV:** usuarios, simulacros/resultados, pagos (patrón anti-CSV-injection del panel director).
3. **Módulo de ingresos:** tabla `payments` + `play_purchases` → total, por gateway, por mes, conversión free→premium.
4. **Analítica educativa agregada:** promedio por área (de `simulacro_resultados`/`respuestas_detalle`), heatmap área×grado, top colegios por mejora.
5. **Auditoría de acciones admin:** tabla `admin_audit_log` (migración 007) — quién/qué/cuándo en acciones sensibles.
6. **Hardening** (PT3-7) aplicado primero.
7. Declarado fuera de alcance de esta iteración: roles múltiples de admin, asistente IA ejecutivo (documentados como roadmap).

### PT8 — UX/UI y pulido

1. **Rediseño `quiz_list_screen`:** tarjetas del design system, duración en minutos, intentos previos/estado, empty y error states amables, guard de doble-tap + navegación a quiz-intro (no directo a preguntas).
2. **Taps muertos:** tarjeta de curso del dashboard navega; "Calificar app" abre store URL real (Android) / oculta (web); tap en simulacro específico → su intro.
3. Estados de carga/error consistentes (snippet reutilizable).
4. Limpieza: colores inline → tokens del tema.

---

## 4. CRONOLOGÍA DE EJECUCIÓN (esta iteración)

| Sprint | Paquetes | Entregable |
|---|---|---|
| S1 | PT1 + PT2 | Web navegable + simulacro sin incertidumbre |
| S2 | PT3 + PT4 | Seguridad cerrada + identidad institucional |
| S3 | PT5 + PT6 | Gamificación viva + onboarding |
| S4 | PT7 + PT8 | Admin Center + pulido UX |
| S5 | Verificación + docs | 7 documentos + checklist + entrega |

---

## 5. QUÉ NO SE HARÁ EN ESTA ITERACIÓN (y por qué)

- **No** se reemplaza Provider por Riverpod/Bloc: el estado actual es adecuado al tamaño; migrar es riesgo sin beneficio medible.
- **No** se eliminan las dos librerías de charts todavía: syncfusion se usa en estadísticas complejas; retirarla exige reescribir 4 pantallas (backlog).
- **No** se implementan tipos de pregunta cloze/drag-drop: depende del banco Moodle real (backlog con el propietario).
- **No** se despliega en producción ni se toca la BD real sin autorización (regla de la misión). Las migraciones nuevas (007) se entregan documentadas para ejecución manual.
- **No** se purga el historial git de secretos desde aquí (requiere `git filter-repo` + force push: se documenta el procedimiento exacto para que lo ejecute el propietario, junto con la rotación obligatoria de credenciales).

---

## 6. CRITERIOS DE ÉXITO POR PAQUETE

| PT | Criterio verificable |
|---|---|
| PT1 | Flujo completo cursos→simulacro→resultados→volver funciona con back del navegador; F5 no crashea |
| PT2 | Al iniciar simulacro se ve estado de preparación; error de red muestra reintentar; no hay doble start_attempt |
| PT3 | `grep` de secretos en código = 0; upgrade_to_premium rechaza sin pago; XP desde cliente ignorada; stats/* exige token |
| PT4 | Ningún nombre propio ni dato personal de soporte en la app; contacto = Equipo Saber+ / +57 350 2114292 / Saberplus2026@gmail.com |
| PT5 | Simulacro terminado otorga XP+racha (verificable en UI); daily_login otorga 10 XP una vez/día |
| PT6 | Usuario nuevo ve tour una vez, puede saltarlo, puede relanzarlo desde configuración |
| PT7 | Dashboard admin muestra series reales de 30 días + exportes CSV funcionales |
| PT8 | quiz_list con design system; cero botones muertos |

---

*Siguiente documento: CAMBIOS_IMPLEMENTADOS_SABERPLUS.md (se genera al cierre de la implementación).*
