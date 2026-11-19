# REPORTE TÉCNICO FINAL — SABER+

**Fecha:** 5 de noviembre de 2026 · **Rama:** `feature/transformacion-edtech` (base: v1.7.1, `ad0a870`)

---

## 1. ARQUITECTURA FINAL

```
┌─────────────────────────────────────────────────────────────┐
│ FLUTTER (móvil + web, un solo codebase)                     │
│  MaterialApp.router (GoRouter 14.8.1)                       │
│  ├─ 40+ rutas declarativas — TODA la navegación por router  │
│  │   (0 MaterialPageRoute de pantalla; solo overlay galería) │
│  ├─ Provider 6.1.5 (auth, dashboard, gamification,          │
│  │   notifications, theme)                                   │
│  ├─ DioClient (JWT + refresh con cola de pendientes)         │
│  ├─ ApiService (http — 3 call-sites ahora con Bearer)        │
│  └─ Widgets ricos Moodle: MoodleRichText / MoodleTable /     │
│      QImage (galería) / WebMaxWidth / shells responsivos     │
├─────────────────────────────────────────────────────────────┤
│ BACKEND PHP (~123 archivos, sin vendor)                     │
│  ├─ Auth: JWT HS256 (24h, revocación jti) + refresh 30d     │
│  │   con rotación real · Moodle como IdP de estudiantes      │
│  ├─ Moodle WS: ciclo completo de quizzes + proxy pluginfile │
│  │   (allowlist de host + TLS verificado)                    │
│  ├─ FCM v1 (Kreait + service account) + 3 crons inteligentes│
│  │   protegidos por guard interno                            │
│  ├─ IA: Gemini→DeepSeek failover, rate-limit 6/min,          │
│  │   sanitización, prompt con datos reales del estudiante    │
│  ├─ Pagos: Wompi (firma hash_equals) + Play Billing          │
│  │   (verificación server-side, idempotente)                 │
│  ├─ Gamificación: XP server-side por reason + dedup por      │
│  │   reference_id + 10 badges verificables                   │
│  └─ Paneles: admin (16 secciones) + director B2B (scoped)    │
├─────────────────────────────────────────────────────────────┤
│ MYSQL — 6 migraciones originales + 007_admin_intelligence    │
│  (admin_audit_log; ejecución manual, degradación segura)     │
└─────────────────────────────────────────────────────────────┘
```

Cambios estructurales clave vs. v1.7.1: (1) navegación unificada bajo GoRouter; (2) secretos por `env()` con fallback transitorio; (3) capa de auditoría admin; (4) analítica ejecutiva server-rendered (SVG inline, sin JS externo).

## 2. FRONTEND — CAMBIOS (resumen técnico)

- **Router:** 8 rutas nuevas; 6 null-checks de `state.extra` con fallback UI; helpers `Nav` completados (`replaceQuestion/replaceReview/safePop/...`); helper muerto `goQuestions` eliminado.
- **Flujo quiz:** `quiz_intro → question → review` ahora usa `pushReplacement` del router (el back desde review no vuelve al cuestionario); reanudar intento activo ídem; review devuelve `true` con `context.pop(true)`.
- **QuizController:** campo `error`; `start()` propaga fallos y detecta "0 preguntas".
- **QuestionScreen:** estado de error con Reintentar/Salir; carga con mensajes de contexto.
- **Gamificación UI:** `awardXp` en review (simulacro) y dashboard (daily_login con dedup local por fecha); `CelebrationOverlay` reutilizado.
- **Onboarding:** pantalla nueva + checklist `FirstStepsChecklist` (SharedPreferences `fs_*`).
- **Limpieza:** imports muertos eliminados en 14 archivos; `WillPopScope` deprecado fuera.

## 3. BACKEND — CAMBIOS (resumen técnico)

- **env()**: jwt_config, conexion, wompi_config, includes/config (WS token + base URL), moodle_db, SMTP×3 archivos — todos con fallback + `error_log` de rotación.
- **Anti-fraude:** upgrade_to_premium exige pago verificado; XP por tabla server-side; dedup (user, reason, reference_id).
- **Auth:** 7 endpoints + userId del token; 3 crons con guard; api_service.dart envía Bearer en stats.
- **Admin:** rate-limit login, session_regenerate_id, cookies endurecidas, CSRF completo, auditoría (8 acciones + exports), exportes CSV (3 tipos, anti-inyección), dashboard ejecutivo (4 series SVG 30d + salud del negocio), secciones Ingresos/Académica/Auditoría.
- **Eliminados:** 8 archivos muertos (TRAZA/debug/duplicados/rotos).

## 4. BASE DE DATOS

- **Sin cambios destructivos.** Única novedad: `migrations/007_admin_intelligence.sql` (CREATE TABLE IF NOT EXISTS `admin_audit_log`) — **ejecución manual del propietario**; sin ejecutarla, la auditoría es no-op silencioso y el resto funciona igual.
- Recomendación pendiente: exportar el schema base real y versionarlo como migración 000.

## 5. SEGURIDAD — ESTADO FINAL

| Control | Estado |
|---|---|
| Secretos en código | ✅ Fuera (fallbacks transitorios + warning) — **rotación pendiente** |
| Escalada premium sin pago | ✅ Cerrada |
| XP manipulable | ✅ Cerrada (server-side + dedup) |
| Endpoints sin auth | ✅ Cerrados (7) |
| SSRF en get_file | ✅ Allowlist + TLS |
| Rate-limiting | ✅ login/register/forgot/admin/IA |
| CSRF/XSS paneles | ✅ Completo (incl. resolve_error) |
| SQL injection | ✅ Prepared statements en todo lo nuevo y existente |
| Sesiones admin | ✅ regenerate_id + httponly + samesite |
| Purga historial git | ⚠️ Pendiente (procedimiento en Checklist §6) |

## 6. RENDIMIENTO

- Eliminación de la **doble llamada a start_attempt.php** al iniciar simulacro vía quiz_list (la lista ya no inicia intentos: navega a la ficha).
- `context.go` en tabs evita reconstrucciones de pila.
- SVG inline en admin: 0 peticiones JS/CDN adicionales.
- Deuda conocida (no bloqueante): `shrinkWrap` en 4 listas, dos librerías de charts, polling de 10 s en quiz_intro sin cancelación real.

## 7. FIREBASE / FCM

Backend verificado sólido (HTTP v1, limpieza de tokens, guards). Sin cambios funcionales en esta iteración; los crons ahora protegidos. **Pruebas reales en dispositivo pendientes** (protocolo en Checklist §4) — el service account no está en el repo y el sandbox no tiene dispositivos.

## 8. FLUTTER WEB / MOBILE

- **Web:** navegación con historial real, deep-links, F5 seguro, tabs sin apilar, URLs por pantalla de simulacro.
- **Móvil:** sin cambios de flujo; back de Android ya no interceptado por WillPopScope; rate-limit no afecta UX normal.
- **Compilación:** pendiente en entorno del propietario (sandbox sin SDK). Análisis estático: 158 archivos Dart balanceados, imports verificados.

## 9. ESTADO DE LOS MÓDULOS

| Módulo | Estado |
|---|---|
| Autenticación | ✅ Estable + rate-limit |
| Cursos/Contenidos Moodle | ✅ Estable |
| Simulacros | ✅ Mejorado (navegación + preparación + errores) |
| Gamificación | ✅ Conectada al flujo (antes desconectada) |
| Notificaciones | ✅ Endpoints blindados; push real pendiente de prueba |
| IA tutor | ✅ Sin cambios (ya sólido) |
| Pagos | ✅ Fraude cerrado |
| Panel admin | ✅ Evolucionado a Intelligence Center |
| Panel director | ✅ Sin cambios (referencia de calidad) |
| Onboarding | ✅ Nuevo (tour + checklist) |

## 10. LIMITACIONES Y RIESGOS PENDIENTES

1. Validación runtime completa (compilar móvil + web) — pendiente fuera del sandbox.
2. Rotación de credenciales y borrado de fallbacks — acción del propietario (CRÍTICA).
3. Purga del historial git de secretos — acción del propietario (procedimiento entregado).
4. SMTP_PASS de la cuenta institucional sin generar — los correos usan fallback antiguo hasta entonces.
5. Crons por HTTP en el servidor requerirán `X-Internal-Token` o CLI.
6. Áreas ICFES asignadas por posición de página de Moodle (frágil ante reordenamientos) — backlog.
7. Sin pruebas unitarias nuevas (el repo tiene 6 archivos de test orientados a theme/models).

---

*Detalle completo de archivos y líneas: CAMBIOS_IMPLEMENTADOS_SABERPLUS.md*
