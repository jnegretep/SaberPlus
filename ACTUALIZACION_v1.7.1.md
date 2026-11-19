# 🚀 Actualización v1.7.1 — Guía de Instalación y Pruebas

Saber+ (antes PrepSaber) — 8 de octubre de 2026

Esta versión corrige los problemas reportados de la v1.7.0 **sin romper
nada de lo que ya funciona**: render de cuestionarios (tablas, imágenes),
IA con failover automático, notificaciones FCM, sesión que expira,
navegación y visual web.

---

## 📋 Resumen de cambios

| # | Problema reportado | Solución |
|---|---|---|
| 1 | Tablas de preguntas no se ven | Nuevo motor de render `MoodleRichText` + `MoodleTable` (tablas nativas con bordes, encabezados y colspan) |
| 2 | Imágenes en opciones no se ven | Las opciones ahora renderizan sus imágenes inline (antes se eliminaban) |
| 3 | Imágenes amontonadas arriba del texto | Imágenes distribuidas EN ORDEN dentro del texto, táctiles → galería zoom |
| 4 | IA no responde ("tuve un problema para pensar") | **Causa raíz: el hosting bloquea la salida a api.deepseek.com**. Motor multi-proveedor con failover automático Gemini → DeepSeek |
| 5 | Notificaciones no llegan | Backend unificado + seguridad + limpieza automática de tokens muertos |
| 6 | Error de conexión tras inactividad | `refresh.php` regeneraba el JWT sin `moodle_userid` + el token rotado no se guardaba → ambos corregidos |
| 7 | Navegación confusa / iconos mal resaltados | Perfil y subpantallas marcan "Más" (antes "Retos"); tocar el tab actual lleva a la raíz de la sección; botón volver en Cursos |
| 8 | Tarjetas de retos sin función en dashboard | Reemplazadas por **vitrina de progreso premium** (nivel, racha, insignias, XP) + tarjeta "Reta a un amigo" |
| 9 | Visual web mejorable | Preguntas centradas con ancho legible, tarjetas y grid de cursos adaptativos en PC |

---

## 🔧 PASO 1 — Archivos del backend a subir al servidor

Sube estos archivos a `https://corpoinstel.edu.co/api/prepsaber/backend/`
(conserva la estructura de carpetas):

```
backend/api_saber_plus_ia.php          ← IA multi-proveedor (REESCRITO)
backend/refresh.php                    ← FIX sesión expirada (REESCRITO)
backend/register_fcm_token.php         ← FIX seguridad + token (REESCRITO)
backend/send_notification.php          ← notificación individual (REESCRITO)
backend/send_notification_all.php      ← notificación masiva (REESCRITO)
backend/smart_notifications.php        ← notificaciones inteligentes (FIX)
backend/includes/firebase_factory.php  ← NUEVO: Firebase unificado
backend/admin/check_ia.php             ← diagnóstico IA multi-proveedor
backend/admin/send_bulk.php            ← envío masivo del panel (FIX)
```

**Archivos a BORRAR del servidor** (riesgos de seguridad):

```
backend/api_ia.php          ← tenía la API key de DeepSeek expuesta y sin autenticación
backend/send_fcm_test.php   ← script de debug sin autenticación
```

⚠️ **IMPORTANTE**: la API key de DeepSeek (`sk-d8728...`) quedó expuesta en
git público y en ese archivo. Aunque la vas a seguir usando, **rótala** en
platform.deepseek.com → API Keys (es gratis y toma 1 minuto) y actualiza
`backend/.env`.

---

## 🤖 PASO 2 — Activar la IA (5 minutos, GRATIS)

**Diagnóstico real**: tu servidor NO puede conectarse a `api.deepseek.com`
(bloqueo de salida del hosting hacia la IP de AWS `3.173.21.63`; Google SÍ
es alcanzable — por eso Firebase funciona). **Por eso la IA nunca
respondía**, sin importar la key o el saldo.

La solución implementada: la IA ahora usa **Gemini de Google** como
proveedor principal (mismo formato, IPs de Google = alcanzables desde tu
servidor) con DeepSeek de respaldo.

1. Entra a **https://aistudio.google.com/apikey** con tu cuenta Google.
2. Clic en **"Create API key"** → copia la key (`AIza...`).
3. Edita `backend/.env` en el servidor y agrega:

```env
GEMINI_API_KEY=AIzaXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

(Ya quedaron listas en el .env: `GEMINI_MODEL=gemini-2.0-flash` y
`IA_PROVEEDORES=gemini,deepseek`)

4. Verifica en el panel admin: **`/admin/check_ia.php`** → botón
   "Probar todos los proveedores". Deberías ver:
   - Gemini: ✅ TODO BIEN
   - DeepSeek: ⛔ BLOQUEO DE RED (normal, hasta que el hosting lo abra)

5. Prueba en la app: chat "Saber+ IA" → escribe "hola".

**Nota sobre DeepSeek**: si quieres usarlo en el futuro, pide a tu hosting
(corpoinstel) que habilite la salida HTTPS hacia `api.deepseek.com`
(IP `3.173.21.63`). En cuanto lo abran, DeepSeek funcionará como respaldo
automático sin tocar nada más — está configurado como segundo proveedor.

---

## 🔔 PASO 3 — Notificaciones push

**Qué se arregló:**
- Los scripts de envío usaban el service account de Firebase en 2 rutas
  distintas (unas funcionaban, otras no) → ahora hay un loader unificado
  que busca en ambas.
- La BD tenía tokens viejos de instalaciones desinstaladas/reinstaladas
  (tras el cambio de nombre PrepSaber → Saber+ los tokens quedaron
  huérfanos y Firebase los rechaza) → ahora se limpian automáticamente al
  enviar.
- `register_fcm_token.php` estaba roto (pedía `id_usuario` en el body pero
  la app no lo envía → "Datos incompletos" → el token nunca se guardaba) →
  corregido y blindado (el id sale del JWT).
- Se añadió prioridad alta a los envíos (mejor entrega con app cerrada).

**Qué hacer:**
1. Sube los archivos del PASO 1.
2. Coloca el service account de Firebase en
   `backend/config/firebase-service-account.json` (si ya existe el archivo
   `saberplus-1ec41-firebase-adminsdk-*.json` en la raíz del backend, el
   loader lo encuentra solo — no hay que hacer nada).
3. Instala la app v1.7.1 en un dispositivo, inicia sesión y espera ~30
   segundos (el token se registra solo).
4. Desde el panel admin → Notificaciones → enviar una de prueba.
5. Los usuarios con la app vieja deben actualizar: sus tokens viejos se
   limpiarán solos en el primer envío masivo.

**Para notificaciones en la VERSIÓN WEB** (opcional): falta completar en
`.env` los valores `FIREBASE_APP_ID`, `FIREBASE_MEASUREMENT_ID` y
`FIREBASE_VAPID_KEY` desde Firebase Console → Configuración del proyecto →
Tus apps → Web (ver DESPLIEGUE_WEB.md). Sin ellos, la web funciona
perfecto pero sin push.

---

## 🔐 PASO 4 — Sesión que expiraba (sin acción adicional)

Todo es código: al volver tras inactividad la app renueva el JWT en
silencio (con los datos completos de Moodle) y lo persiste. El usuario ya
no ve "error de conexión" ni es obligado a re-iniciar sesión.

**Prueba**: inicia sesión, cierra la app, espera >24h (o cambia la fecha
del dispositivo +1 día), abre la app → debe entrar directo al dashboard.

---

## 📱 PASO 5 — Compilar la app

```bash
flutter pub get
flutter build apk --release \
  --dart-define=API_BASE_URL=https://corpoinstel.edu.co/api/prepsaber/backend \
  --dart-define=AVATAR_BASE_URL=https://corpoinstel.edu.co/api/prepsaber/backend/uploads/avatars/ \
  --dart-define=DEFAULT_AVATAR_URL=https://corpoinstel.edu.co/api/prepsaber/backend/uploads/avatars/default_avatar.png \
  --dart-define=AI_API_URL=https://corpoinstel.edu.co/api/prepsaber/backend/api_saber_plus_ia.php
```

(Los mismos dart-define que ya usas; el .env empaquetado sigue de respaldo.)

---

## ✅ CHECKLIST DE PRUEBAS (15 min)

**Cuestionarios:**
- [ ] Abrir un simulacro con tablas → las tablas se ven con bordes y contenido
- [ ] Pregunta con imagen → la imagen aparece donde corresponde en el texto
- [ ] Pregunta con 2-3 imágenes → cada una en su sitio (no amontonadas arriba)
- [ ] Opciones con imágenes → se ven dentro de la opción
- [ ] Tocar cualquier imagen → galería zoom a pantalla completa

**IA:**
- [ ] Chat Saber+ IA responde (tras configurar GEMINI_API_KEY)
- [ ] Análisis global en Stats responde
- [ ] Análisis por área responde

**Notificaciones:**
- [ ] App instalada nueva → token registrado (ver log del servidor)
- [ ] Panel admin → enviar notificación → llega al dispositivo
- [ ] Con la app cerrada → la notificación aparece en la barra de Android

**Sesión:**
- [ ] Cerrar y reabrir la app → entra sin pedir login

**Navegación:**
- [ ] Inicio → Cursos → tocar "Inicio" en el pie → vuelve al dashboard
- [ ] Perfil → el icono resaltado del pie es "Más" (no "Retos")
- [ ] Cursos tiene botón ← arriba a la izquierda

**Dashboard:**
- [ ] La sección de tarjetas de retos fue reemplazada por el panel de
      progreso (nivel con anillo, racha, insignias, XP)
- [ ] "Reta a un amigo" lleva a la sección de retos

**Web (PC):**
- [ ] Preguntas centradas con ancho legible (no estiradas)
- [ ] Tarjetas de cursos/simulacros más grandes y legibles
- [ ] Grid de cursos con 3-4 columnas en pantalla grande
- [ ] Rail lateral de navegación funcional

---

## 🗂️ Archivos nuevos de la app (referencia)

```
lib/widgets/rich/moodle_rich_text.dart   ← motor de render enriquecido
lib/widgets/rich/moodle_table.dart       ← tablas HTML nativas
lib/widgets/rich/q_image.dart            ← imágenes inline + galería
lib/widgets/dashboard/progress_showcase.dart ← vitrina de progreso
lib/widgets/web_max_width.dart           ← ancho legible en PC
```
