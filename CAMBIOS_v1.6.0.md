# 📋 CAMBIOS v1.6.0 — Saber+

**Fecha:** 18 de septiembre de 2026
**Versión:** 1.6.0+16 (antes 1.5.0+15)
**Estado:** Listo para pruebas

Esta versión implementa **todas** las recomendaciones post-auditoría:
eliminación de cuenta, rankings institucionales, compartir en redes,
analítica y reporte de fallos, panel de administración ampliado y
**soporte completo para la aplicación web (Flutter Web)**.

---

## 🆕 Nuevas funcionalidades

### 1. Eliminación de cuenta (requisito Google Play / GDPR)
- **App:** botón "Eliminar mi cuenta" en Perfil → abajo de "Cerrar sesión".
  Requiere escribir `ELIMINAR` para confirmar; motivo opcional.
- **Backend:** `eliminar_cuenta.php` — transaccional y seguro (JWT):
  - Elimina: XP, insignias, rachas, resultados de simulacros, notificaciones,
    participación en retos, tokens de reset.
  - Anonimiza: la fila del usuario (sin PII) y referencias en eventos/errores.
  - Cancela retos pendientes donde participaba.
  - Revoca el JWT actual y registra auditoría en `account_deletions`
    (solo hash del email, sin datos personales).
  - Intenta eliminar el usuario en Moodle (best-effort, no bloqueante).

### 2. Rankings institucionales (colegios y departamentos)
- **App:** la pantalla "Ranking de XP" ahora tiene 3 pestañas:
  **Estudiantes / Colegios / Departamentos**, con los mismos períodos
  (histórico, mensual, semanal).
  - Podio olímpico institucional (oro/plata/bronce).
  - Cada institución muestra XP total, nº de estudiantes y ciudad.
  - Tu colegio/departamento queda **destacado** en la lista.
  - Tarjeta "Tu colegio" con su posición real aunque no esté en el top.
- **Backend:** `ranking_institucional.php` (JWT, whitelist de parámetros,
  índices nuevos en `usuarios.colegio` y `usuarios.departamento`).

### 3. Compartir resultados en redes sociales
- Nuevo botón de compartir en:
  - 🏆 Resultados de retos (con tu posición y jugadores).
  - 📊 Estadísticas de simulacro (puntaje global + área más fuerte).
  - 🥇 Pantalla de ranking (tu posición o la de tu institución).
  - 🎖️ Pantalla de logros (última insignia desbloqueada).
- Paquete `share_plus` — funciona en Android, iOS y Web.
- Cada acción registra el evento `share_clicked` en analítica
  (para medir crecimiento orgánico).

### 4. Analítica y reporte de fallos
- **Firebase Analytics** (nuevo paquete):
  - Eventos de negocio: login, sign_up, simulacro_started/completed,
    quiz_completed, challenge_completed, paywall_viewed,
    purchase_started, share_clicked, ai_chat, screen_view, etc.
  - `screen_view` automático vía observer del GoRouter.
  - Identificación de usuario por id (sin PII).
  - Deshabilitado en modo debug (no contamina métricas).
- **Firebase Crashlytics** (nuevo paquete, solo Android/iOS):
  - Errores fatales de Flutter + errores async no capturados.
- **Espejo propio en el backend** (independiente de Firebase):
  - `AnalyticsService` envía cada evento también a
    `registrar_evento.php` → tabla `app_events`.
  - Errores no fatales → evento `app_error` → tabla `error_logs`.
  - Si no hay sesión, el espejo se omite silenciosamente.

### 5. Panel de administración ampliado (`/admin`)
Se sumaron 4 secciones nuevas al menú lateral:
| Sección | Contenido |
|---|---|
| **📈 Analítica** | Eventos hoy/7d, usuarios activos (DAU/WAU aproximado), errores de app, top eventos con barras, distribución por plataforma (android/ios/web) |
| **⚠️ Errores** | Visor de `error_logs` (app + backend), filtros por severidad, marcar como resuelto, totales y fatales |
| **🔥 Actividad** | Últimos 100 eventos de la app con usuario, parámetros y versión |
| **🏆 Rankings Inst.** | Top 25 colegios y departamentos por XP |

### 6. Aplicación Web (Flutter Web) — soporte completo
- **Corrección de bloqueadores:**
  - `flutter_downloader` (sin soporte web) ya no se inicializa en web.
  - `dart:io` (rompía la compilación web) reemplazado por un shim
    condicional (`lib/core/io_shim/`) en 9 archivos.
  - PDFs en web: se abren en una pestaña nueva (visor del navegador).
  - Descargas offline (video/PDF) ocultas en web — streaming directo.
  - Biometría y FCM-background deshabilitados en web (no aplican).
  - Push web opcional vía VAPID key (`.env` → `FIREBASE_VAPID_KEY`).
  - Firebase Web init **no fatal**: sin configuración, la app funciona.
- **Diseño responsive:**
  - En pantallas anchas (desktop) la app se enmarca en una columna
    móvil centrada de 480px — el diseño se ve exactamente como en el
    teléfono, sin estiramientos ni desbordes.
- **Branding web:**
  - `web/index.html`: título, descripción SEO, theme-color, PWA manifest
    y **splash de carga** con logo Saber+ mientras carga Flutter.
  - `manifest.json`: nombre "Saber+", colores de marca, idioma es.

---

## 🔧 Backend — cambios técnicos

| Archivo | Cambio |
|---|---|
| `.env` | **NUEVO** (local, gitignored): credenciales reales actuales — el sistema funciona sin exponer nada en git |
| `migrations/003_analytics_admin.sql` | **NUEVO**: tablas `app_events`, `error_logs`, `account_deletions` + índices para rankings |
| `includes/analytics.php` | **NUEVO**: helpers `saberplus_registrar_evento()` y `saberplus_log_error()` (best-effort) |
| `eliminar_cuenta.php` | **NUEVO**: eliminación GDPR completa |
| `ranking_institucional.php` | **NUEVO**: ranking colegios/departamentos |
| `registrar_evento.php` | **NUEVO**: eventos de analítica (JWT + whitelist) |
| `admin/index.php` | 4 secciones nuevas + acción "resolver error" |
| `.htaccess` | CORS global mejorado (X-Internal-Token, preflight OPTIONS→204, Max-Age) |

> **Sobre las contraseñas expuestas:** siguen siendo las actuales (decisión
> del administrador) pero ahora viven SOLO en `backend/.env`, que está en
> `.gitignore` — **nunca más entran al repositorio**. Cuando las rotes,
> actualiza el valor en `backend/.env` del servidor y nada más.

## 📱 Flutter — cambios técnicos

| Archivo | Cambio |
|---|---|
| `pubspec.yaml` | v1.6.0+16; añadidos `share_plus`, `firebase_analytics`, `firebase_crashlytics` |
| `lib/services/analytics_service.dart` | **NUEVO**: Analytics + Crashlytics + espejo backend |
| `lib/services/share_service.dart` | **NUEVO**: compartir resultados |
| `lib/core/io_shim/` | **NUEVO**: shim condicional de `dart:io` para web |
| `lib/main.dart` | Guards web, init analytics, marco responsive desktop, Firebase no fatal |
| `lib/screens/xp_ranking_screen.dart` | Pestañas Estudiantes/Colegios/Departamentos + compartir |
| `lib/screens/perfil_hub_screen.dart` | Botón + diálogo de eliminar cuenta |
| `lib/services/api_service.dart` | `deleteAccount()` + evento simulacro_completed |
| `lib/models/ranking_entry.dart` | Modelos de ranking institucional |
| `lib/services/gamification_service.dart` + provider | `getInstitutionRanking()` |
| `lib/config/app_router.dart` | Observer de screen_view |
| `lib/config/env.dart` | `firebaseVapidKey` opcional |
| `lib/services/fcm_service.dart` | Push web con VAPID opcional |
| `lib/services/biometric_service.dart` | Guard kIsWeb |
| `lib/widgets/pdf/premium_pdf_viewer.dart` | Visor web (abrir en pestaña) |
| `lib/widgets/video/premium_video_player.dart` | Descargas ocultas en web |
| 7 archivos más | Migración `dart:io` → shim (registro, perfil, avatar, caches) |
| `web/index.html` + `manifest.json` | Branding, SEO, splash, PWA |

---

## ✅ Qué debes hacer TÚ (administrador)

### Obligatorio antes de probar
1. **Ejecutar la migración en la BD** (una sola vez):
   ```bash
   mysql -u jnegretep -p prepsaber < backend/migrations/003_analytics_admin.sql
   ```
   (Es idempotente; crea las tablas de analítica/errores y los índices.)

2. **Subir el backend al servidor** y verificar que `backend/.env` esté
   presente en el servidor con los valores actuales (ya viene incluido
   en el proyecto entregado — NO lo subas a git, cópialo por SFTP).

3. **Flutter:** descargar dependencias nuevas:
   ```bash
   flutter pub get
   ```
   (Añade share_plus, firebase_analytics y firebase_crashlytics.)

### Para el build WEB (cuando lo vayas a montar)
Ver **DESPLIEGUE_WEB.md** — paso a paso completo. Resumen:
1. Completar `FIREBASE_APP_ID` y `FIREBASE_MEASUREMENT_ID` en `.env`
   (Firebase Console → Configuración → App Web).
2. `flutter build web --release`
3. Subir `build/web/` a tu hosting (misma infra del backend o Firebase Hosting).
4. Registrar el dominio web en Firebase Authentication (para Google Sign-In).

### Cuando rotes credenciales (pendiente de la auditoría)
Sigue **GUÍA_DE_SEGURIDAD.md** y actualiza los valores en `backend/.env`.

---

## 🧪 Plan de pruebas sugerido

1. **Eliminar cuenta:** crear una cuenta de prueba → Perfil → Eliminar mi
   cuenta → escribir ELIMINAR → verificar logout + login imposible.
2. **Rankings:** Ranking de XP → pestañas Colegios y Departamentos →
   cambiar períodos → verificar que tu institución aparece destacada.
3. **Compartir:** terminar un reto → botón compartir → elegir WhatsApp.
4. **Admin:** entrar a `/admin` → secciones Analítica, Errores, Actividad
   y Rankings — usar la app y ver los eventos llegar en tiempo real.
5. **Web:** `flutter run -d chrome` → probar login, cursos, simulacro,
   PDFs (abren en pestaña), responsive (redimensionar ventana).
6. **Crashlytics:** en Android, forzar un error en debug → verificar en
   Firebase Console → Crashlytics (tarda ~15 min en aparecer).

## ⚠️ Limitaciones conocidas de la web (v1)
- Avatar desde galería: en web usa los avatares predefinidos (la subida
  de imagen local queda para v1.7 con XFile).
- Notificaciones push web: requieren VAPID key (opcional).
- Crashlytics no existe en web (los errores web llegan al panel admin
  vía `app_error`).
- Google Sign-In en web requiere registrar el dominio en Firebase.
