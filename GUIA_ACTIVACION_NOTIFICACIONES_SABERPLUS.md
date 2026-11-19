# Guía de activación de notificaciones — Saber+

**Versión 2.0 · Noviembre 2026**

Esta guía explica qué estaba roto en las notificaciones push (FCM), qué se
corrigió en el código, qué queda pendiente de configuración manual (con
acceso a Firebase Console / servidor) y cómo verificar el funcionamiento
final.

---

## 1. Problema encontrado

Las notificaciones push no llegaban a los usuarios. Síntomas reportados:
retos sin aviso, recordatorios de simulacros ausentes, envíos masivos del
panel admin sin efecto visible.

## 2. Causas encontradas (en orden de impacto)

| # | Causa | Dónde |
|---|-------|-------|
| 1 | **403 en todos los envíos internos**: el endurecimiento v2 de `send_notification.php` exige autenticación (sesión admin, `X-Internal-Token` o JWT propio), pero `send_to_many.php` (retos) y los 3 crons llamaban **sin ninguna credencial** → HTTP 403 silencioso | `backend/send_to_many.php`, `backend/cron_retos.php`, `cron_simulacros.php`, `cron_inactividad.php` |
| 2 | **Canal de Android inexistente**: el backend envía `channel_id: 'saberplus_notificaciones'`, pero la app nunca creaba ese canal ni declaraba el canal por defecto → en Android 8+ las notificaciones se **descartan silenciosamente** con la app cerrada | `android/app/src/main/AndroidManifest.xml`, `MainActivity.kt` |
| 3 | **Permiso `POST_NOTIFICATIONS` no declarado** (obligatorio en Android 13+ con targetSdk 36) → el sistema puede auto-denegar | `AndroidManifest.xml` |
| 4 | **Push web completamente deshabilitado por diseño**: `_initFCM()` retornaba inmediatamente en web; no existía el service worker `firebase-messaging-sw.js`; `FIREBASE_VAPID_KEY`/`FIREBASE_APP_ID` vacíos en `.env` | `lib/main.dart`, `web/` |
| 5 | **Bandeja interna inconsistente**: `admin/send_bulk.php` y `smart_notifications.php` insertaban en la columna `data` mientras el resto (y `get_notifications.php`) usan `payload_json` → en `send_bulk` cada INSERT fallido dentro del try contaba el envío como fallido | backend |
| 6 | **Service account de Firebase ausente en el repo** (correcto que no esté) pero sin alternativa configurada → `saberplus_fcm_messaging()` lanza excepción y todo envío muere | `backend/includes/firebase_factory.php` |
| 7 | `send_bulk.php` enviaba 1 notificación por usuario con `usleep(50ms)` → riesgo de timeout PHP con bases grandes | `backend/admin/send_bulk.php` |

## 3. Cambios realizados (ya incluidos en el código)

1. `send_to_many.php` + los 3 crons ahora envían la cabecera
   `X-Internal-Token: <INTERNAL_TOKEN>` (leída de `backend/.env`) y usan
   `getBackendFileUrl()` en vez de URLs `localhost` hardcodeadas.
2. `MainActivity.kt` crea el canal `saberplus_notificaciones`
   (IMPORTANCE_HIGH) al arrancar; `AndroidManifest.xml` declara
   `POST_NOTIFICATIONS` y el meta-data
   `com.google.firebase.messaging.default_notification_channel_id`.
3. **Nuevo** `web/firebase-messaging-sw.js` (service worker con la
   configuración real del proyecto `saberplus-1ec41`): muestra la
   notificación en background y enruta el click a la app.
4. `main.dart`: `_initFCM()` ya no se salta en web — ahora se ejecuta si
   `FIREBASE_VAPID_KEY` está definida (si falta, registra un aviso y sigue
   sin romper).
5. `admin/send_bulk.php` reescrito: `sendMulticast` por lotes de 500,
   columna `payload_json` (con fallback a `data` si el esquema es viejo),
   INSERT de bandeja fuera del try del envío, limpieza de tokens muertos.
6. `smart_notifications.php`: inserta en `payload_json` con fallback.
7. `ios/Runner/Info.plist`: añadido `NSFaceIDUsageDescription` (Face ID
   para el bloqueo biométrico — relacionado con permisos del dispositivo).

## 4. Configuración pendiente (requiere acceso que solo tiene el propietario)

### 4.1 Service account de Firebase (IMPRESCINDIBLE — sin esto NO envía nada)

1. Firebase Console → **Project settings → Service accounts** (proyecto
   `saberplus-1ec41`).
2. **Generate new private key** → descarga el JSON.
3. Súbelo al servidor como
   `backend/config/firebase-service-account.json`
   (o cualquier ruta y defínela en `backend/.env`:
   `FIREBASE_SERVICE_ACCOUNT=/ruta/absoluta/al/archivo.json`).
4. Verifica permisos de lectura solo para el usuario de PHP (`chmod 600`).

> El archivo NO se sube a git (está ignorado). `includes/firebase_factory.php`
> lo busca en las rutas anteriores automáticamente.

### 4.2 VAPID key para push web

1. Firebase Console → **Project settings → Cloud Messaging → Web Push
   certificates**.
2. **Generate key pair** → copia el valor de la llave pública.
3. En el `.env` de Flutter (raíz del proyecto), define:
   ```
   FIREBASE_VAPID_KEY=BJxxxx...  (el valor completo)
   FIREBASE_APP_ID=1:341784491066:web:26ca4e954d757889447103
   FIREBASE_MEASUREMENT_ID=G-CLQPZCG2F6
   ```
4. Reconstruye la web (`flutter build web --release`).

### 4.3 Verificar `INTERNAL_TOKEN` en el servidor

`backend/.env` debe tener definido (ya lo tiene por defecto):
```
INTERNAL_TOKEN=<valor largo y aleatorio>
```
Todos los crons lo usan ahora; si cambia el valor, no hay que tocar código.

### 4.4 Cron jobs (si no estaban activos)

```cron
# Recordatorios de retos (cada 5 min)
*/5 * * * * php /ruta/al/backend/cron_retos.php
# Recordatorios de simulacros (cada 5 min)
*/5 * * * * php /ruta/al/backend/cron_simulacros.php
# Inactividad (diario 9am)
0 9 * * * php /ruta/al/backend/cron_inactividad.php
# Notificaciones inteligentes (diario 7am)
0 7 * * * php /ruta/al/backend/smart_notifications.php
```

## 5. Prueba final (checklist)

1. **Token**: abre la app (Android), inicia sesión, ve a Perfil → el token
   FCM se sincroniza automáticamente (ver log `FcmService: token
   sincronizado` o el registro en la BD, columna `usuarios.fcm_token`).
2. **Envío individual**: panel admin → Notificaciones → envía una prueba
   a tu usuario → debe llegar con la app en segundo plano **y** cerrada.
3. **Bandeja interna**: campana de notificaciones dentro de la app muestra
   el registro con título/cuerpo correctos.
4. **Web**: con la VAPID configurada, abre la web, acepta permisos, envía
   otra prueba → llega con la pestaña en background (service worker).
5. **Crons**: ejecuta manualmente `php cron_retos.php` y revisa el log —
   debe mostrar HTTP 200 (antes 403).

Si algo falla: revisar `error_log` de PHP buscando `[SEND` / `[CRON` /
`[FCM]`; el token de FCM más común es `messaging/registration-token-not-registered`
(limpieza automática ya implementada).
