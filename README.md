# Saber+ 🎓

**Preparación para las Pruebas Saber 11 (ICFES) — Colombia**

App **multiplataforma** (Android + iOS + **Web**) que prepara a estudiantes
de grado 11° para el examen Saber 11 del ICFES: cursos, simulacros, retos
en tiempo real, gamificación (XP, rachas, medallas, rankings por colegio y
departamento), tutor con IA, estadísticas por área y predicción de puntaje.

## ✨ Novedades v1.6.0

- 🗑️ **Eliminación de cuenta** in-app (requisito Google Play / GDPR)
- 🏫 **Rankings institucionales**: colegios y departamentos con podio olímpico
- 📲 **Compartir resultados** en redes sociales (retos, simulacros, insignias, posición)
- 📊 **Firebase Analytics + Crashlytics** integrados + espejo propio en el backend
- 🛠️ **Panel admin ampliado**: Analítica, Errores, Actividad, Rankings institucionales
- 🌐 **Soporte Flutter Web** completo: responsive de escritorio, splash, PWA —
  ver **[DESPLIEGUE_WEB.md](DESPLIEGUE_WEB.md)**

Detalles completos: **[CAMBIOS_v1.6.0.md](CAMBIOS_v1.6.0.md)**

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
  --dart-define=API_BASE_URL=https://TU_SERVIDOR/api/prepsaber/backend \
  --dart-define=AVATAR_BASE_URL=https://TU_SERVIDOR/api/prepsaber/backend/uploads/avatars/ \
  --dart-define=DEFAULT_AVATAR_URL=https://TU_SERVIDOR/api/prepsaber/backend/uploads/avatars/default_avatar.png \
  --dart-define=AI_API_URL=https://TU_SERVIDOR/api/prepsaber/backend/api_saber_plus_ia.php

# Opción B (legacy): copiar .env y ejecutar normal
cp .env.example .env   # y rellenar valores
flutter run
```

### 2. Backend PHP

```bash
cd backend
composer install
cp .env.example .env   # ⚠️ OBLIGATORIO: rellenar TODOS los valores
```

> **⚠️ Regla de oro del backend:** NINGÚN secreto vive en el código.
> Base de datos, JWT, Wompi, SMTP, DeepSeek, admin y tokens internos se
> configuran en `backend/.env` (gitignored). Ver `backend/.env.example`.

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

### 4. Build web (v1.6.0+)

```bash
# Completar antes FIREBASE_APP_ID y FIREBASE_MEASUREMENT_ID en .env
flutter build web --release          # raíz de dominio
flutter build web --release --base-href /app/   # subcarpeta
```

Guía completa: **[DESPLIEGUE_WEB.md](DESPLIEGUE_WEB.md)** (Firebase Web,
CORS ya resuelto, hosting, checklist de verificación).

## 🔒 Seguridad

- Ver **[GUÍA_DE_SEGURIDAD.md](GUÍA_DE_SEGURIDAD.md)** para la rotación de
  credenciales y el endurecimiento del servidor (obligatorio antes de lanzar).
- Historial: las credenciales que llegaron a estar expuestas en el
  repositorio DEBEN rotarse; el archivo .env nunca se sube a git.

## 📁 Estructura del proyecto

```
lib/
├── config/          # Env, router (GoRouter + observer analytics), navegación
├── core/            # Tema, widgets base, servicios cache/dio, utils, io_shim (web)
├── controllers/     # Controladores (quiz)
├── models/          # Modelos JSON tipados (incl. rankings institucionales)
├── providers/       # ChangeNotifier providers (auth, gamification, etc.)
├── screens/         # Pantallas (auth, dashboard, quiz, retos, stats, teacher)
├── services/        # API services (auth, gamification, plan, FCM, analytics,
│                    #   share, IA...)
├── parsers/         # Parsers (quiz_question_parser)
└── widgets/         # Widgets compartidos (charts, gamification, dashboard)

backend/
├── env.php          # Cargador de configuración (.env) — NUNCA editar secretos en PHP
├── .env.example     # Plantilla de configuración
├── includes/        # Conexión BD, config Moodle, cliente Moodle, JWT, analytics
├── challenges/      # Retos 1v1 (crear, responder, resultados)
├── simulacros/      # Resultados, rankings, stats de simulacros
├── stats/           # Estadísticas por área
├── moodle/          # Proxy de Web Services de Moodle
├── admin/           # Panel de administración (dashboard, analítica, errores,
│                    #   actividad, rankings, usuarios, planes, notificaciones)
└── migrations/      # Esquemas SQL (001 planes, 002 gamificación, 003 analytics)
```

## 🧪 Testing

```bash
flutter analyze
flutter test
```

## 📄 Licencia

Propiedad del autor del repositorio. Todos los derechos reservados.
