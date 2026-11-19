# Saber+ 🎓

**Preparación para las Pruebas Saber 11 (ICFES) — Colombia**

App **multiplataforma** (Android + iOS + **Web**) que prepara a estudiantes
de grado 11° para el examen Saber 11 del ICFES: cursos, simulacros, retos
en tiempo real, gamificación (XP, rachas, medallas, rankings por colegio y
departamento), tutor con IA, estadísticas por área y predicción de puntaje.

**Versión actual: 2.0.0** — ver **[CAMBIOS_v2.0.0.md](CAMBIOS_v2.0.0.md)**

## ✨ Novedades v2.0

- 📝 **Revisión de simulacros renovada**: enunciado limpio, opciones con
  correcta/incorrecta marcadas, feedback completo de Moodle sin cortes
  (parser DOM nuevo — `lib/parsers/review_question_parser.dart`)
- 🔒 **Biometría rediseñada**: bloqueo local de la app (huella/Face ID) al
  abrirla o volver de segundo plano — sin contraseñas ni tokens guardados
- 🎟️ **Códigos promocionales** que **activan Premium** al canjearse
  (gestión en `/admin` → Códigos Premium; validación 100% backend)
- 📚 **Gestión de cursos Moodle en `/admin`**: catálogo dinámico,
  clasificación curso/simulacro/reto y **matrícula masiva** con resumen y
  confirmación (nunca desmatricula)
- 🧑‍🎓 **Registro guiado**: progreso real durante el alta, pantalla de éxito,
  reenvío de correo de verificación y manejo claro del correo no verificado
- 🖼️ **Avatar arreglado** de punta a punta (el bug que dejaba `avatar_path`
  en NULL)
- 🔔 **Notificaciones FCM reparadas** (403 interno, canal Android, permisos
  Android 13+, push web con service worker) — ver
  **[GUIA_ACTIVACION_NOTIFICACIONES_SABERPLUS.md](GUIA_ACTIVACION_NOTIFICACIONES_SABERPLUS.md)**
- 💳 **Copy de Premium claro**: pago único, 1 año de acceso, sin cobros
  automáticos
- ⚡ Dashboard 3× más rápido en carga (una sola llamada de cursos)

## 🧱 Arquitectura general

| Capa | Tecnología | Ubicación |
|------|-----------|-----------|
| App móvil | Flutter 3.x + Provider + GoRouter | `lib/` |
| Backend / API | PHP 8 + PDO (MySQL) | `backend/` |
| LMS y banco de preguntas | Moodle (Web Services) | instancia externa |
| Pagos | Wompi (checkout web + webhook) | `backend/*wompi*.php` |
| Notificaciones push | Firebase Cloud Messaging | `lib/services/fcm_service.dart` |
| Tutor IA | DeepSeek (chat con contexto del estudiante) | `backend/api_saber_plus_ia.php` |

## 🚀 Puesta en marcha (desarrollo)

### 1. App Flutter

```bash
flutter pub get

# Opción A (recomendada): configuración en compilación, sin .env en el APK
flutter run \
  --dart-define=API_BASE_URL=https://corpoinstel.edu.co/api/prepsaber/backend \
  --dart-define=AVATAR_BASE_URL=https://corpoinstel.edu.co/api/prepsaber/backend/uploads/avatars/ \
  --dart-define=DEFAULT_AVATAR_URL=https://corpoinstel.edu.co/api/prepsaber/backend/uploads/avatars/default_avatar.png \
  --dart-define=AI_API_URL=https://corpoinstel.edu.co/api/prepsaber/backend/api_saber_plus_ia.php

# Opción B (legacy): copiar .env y ejecutar normal
cp .env.example .env   # y rellenar valores
flutter run
```

> El build necesita `lib/firebase_options.dart` (gitignored): se genera con
> `flutterfire configure` usando el proyecto Firebase `saberplus-1ec41`.

### 2. Backend PHP

```bash
cd backend
composer install
cp .env.example .env   # ⚠️ OBLIGATORIO: rellenar TODOS los valores
```

> **⚠️ Regla de oro del backend:** NINGÚN secreto vive en el código.
> Base de datos, JWT, Wompi, SMTP, DeepSeek, admin y tokens internos se
> configuran en `backend/.env` (gitignored). Ver `backend/.env.example`.

**Migraciones SQL** (en orden, con `mysql -u USER -p DB < archivo.sql`):

```bash
backend/migrations/001_add_plan_system.sql        # planes y acceso
backend/migrations/002_add_gamification.sql       # XP y gamificación
backend/migrations/003_analytics_admin.sql        # analítica propia
backend/migrations/004_play_billing.sql           # Google Play Billing
backend/migrations/005_directores.sql             # panel B2B directores
backend/migrations/006_promociones_quejas.sql     # promos Wompi y soporte
backend/migrations/007_admin_intelligence.sql     # auditoría admin
backend/migrations/008_codigos_premium.sql        # ✅ v2.0 códigos → Premium
backend/migrations/009_course_catalog.sql         # ✅ v2.0 catálogo de cursos
```

Las 008/009 son de la v2.0: sin ejecutarlas, el sistema funciona igual que
antes (fallbacks seguros); al ejecutarlas se habilitan los códigos Premium
y la clasificación dinámica de cursos.

Los cron jobs se ejecutan por CLI o por HTTP con token:

```bash
# CLI (recomendado, en el crontab del servidor)
0 7 * * * php /var/www/html/api/prepsaber/backend/smart_notifications.php

# HTTP (exige cabecera X-Internal-Token con el valor de INTERNAL_TOKEN del .env)
curl -X POST https://TU_SERVIDOR/api/prepsaber/backend/smart_notifications.php \
     -H "X-Internal-Token: VALOR_DE_INTERNAL_TOKEN"
```

### 3. Firma de release (Android)

El build de release **falla intencionalmente** si no existe
`android/key.properties` (nunca se firma con clave debug):

```properties
# android/key.properties  (gitignored)
storeFile=ruta/al/keystore.jks
storePassword=********
keyAlias=upload
keyPassword=********
```

```bash
flutter build appbundle --release
```

### 4. Build web

```bash
# Completar antes FIREBASE_APP_ID, FIREBASE_MEASUREMENT_ID y FIREBASE_VAPID_KEY en .env
flutter build web --release          # raíz de dominio
flutter build web --release --base-href /app/   # subcarpeta
```

Guía completa: **[docs/DESPLIEGUE_WEB.md](docs/DESPLIEGUE_WEB.md)** (Firebase Web,
CORS ya resuelto, hosting, checklist de verificación).

## 🔒 Seguridad

- Rotar TODAS las credenciales que pasaron por git (SMTP, tokens WS,
  claves de API) antes de lanzar a producción; el `.env` nunca se sube.
- El panel admin y su modelo de acceso se documentan en
  **[GUIA_ACCESO_ADMIN_SABERPLUS.md](GUIA_ACCESO_ADMIN_SABERPLUS.md)**
  (sin contraseñas reales).

## 📁 Estructura del proyecto

```
lib/
├── config/          # Env, router (GoRouter + observer analytics), navegación
├── core/            # Tema, widgets base, servicios cache/dio, utils, io_shim (web)
├── controllers/     # Controladores (quiz)
├── models/          # Modelos JSON tipados (incl. rankings institucionales)
├── providers/       # ChangeNotifier providers (auth, gamification, etc.)
├── screens/         # Pantallas (auth, dashboard, quiz, retos, stats, teacher)
├── services/        # API services (auth, FCM, analytics, share, IA...)
├── parsers/         # Parsers (quiz_question_parser, review_question_parser)
└── widgets/         # Widgets compartidos (charts, gamification, dashboard)

backend/
├── env.php          # Cargador de configuración (.env) — NUNCA editar secretos en PHP
├── .env.example     # Plantilla de configuración
├── includes/        # Conexión BD, config Moodle, cliente Moodle, JWT, analytics
├── challenges/      # Retos 1v1 (crear, responder, resultados)
├── simulacros/      # Resultados, rankings, stats de simulacros
├── stats/           # Estadísticas por área
├── moodle/          # Proxy de Web Services de Moodle
├── admin/           # Panel de administración (usuarios, colegios, cursos Moodle,
│                    #   códigos premium, promociones, analítica, auditoría...)
└── migrations/      # Esquemas SQL (001–009)
```

## 📚 Documentación

| Documento | Contenido |
|-----------|-----------|
| [CAMBIOS_v2.0.0.md](CAMBIOS_v2.0.0.md) | Changelog completo de la v2.0 |
| [REPORTE_MEJORAS_CHECKLIST_SABERPLUS.md](REPORTE_MEJORAS_CHECKLIST_SABERPLUS.md) | Reporte de la misión 2.0 (por punto) |
| [GUIA_ACTIVACION_NOTIFICACIONES_SABERPLUS.md](GUIA_ACTIVACION_NOTIFICACIONES_SABERPLUS.md) | Activación paso a paso de FCM |
| [GUIA_ACCESO_ADMIN_SABERPLUS.md](GUIA_ACCESO_ADMIN_SABERPLUS.md) | Acceso y operación del panel admin |
| [docs/INSTALAR.md](docs/INSTALAR.md) | Instalación del proyecto |
| [docs/DESPLIEGUE_WEB.md](docs/DESPLIEGUE_WEB.md) | Despliegue de la versión web |
| [docs/PLAY_BILLING_SETUP.md](docs/PLAY_BILLING_SETUP.md) | Configuración de Google Play Billing |
| [docs/history/](docs/history/) | Histórico de versiones 1.5–1.7 |

## 🧪 Testing

```bash
flutter analyze
flutter test
```

## 📄 Licencia

Propiedad del autor del repositorio. Todos los derechos reservados.
