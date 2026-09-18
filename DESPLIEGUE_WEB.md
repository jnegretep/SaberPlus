# 🌐 DESPLIEGUE WEB — Saber+ (Flutter Web)

Guía completa para compilar y montar la aplicación web de Saber+
(v1.6.0+). La app ya es 100% compatible con web: los bloqueadores
(`dart:io`, plugins sin soporte web) fueron corregidos.

---

## 0. Prerrequisitos

- Flutter SDK 3.x con soporte web activado:
  ```bash
  flutter config --enable-web
  flutter doctor
  ```
- El backend ya actualizado a v1.6.0 (con `.env` en el servidor y la
  migración 003 aplicada).
- Acceso a Firebase Console (proyecto `saberplus-1ec41`).

---

## 1. Completar la configuración Firebase Web

El archivo `.env` de la raíz del proyecto Flutter ya viene con casi todo.
Faltan 2 valores que SOLO existen en Firebase Console:

1. Entra a **https://console.firebase.google.com** → proyecto
   **saberplus-1ec41**.
2. **⚙️ Configuración del proyecto → General → "Tus apps"**.
3. Si no existe una app **Web `</>`**, créala:
   - Nombre: `Saber+ Web` → Registrar app.
4. En la tarjeta de la app web, busca **"Configuración del SDK"** y copia:
   - `appId` → pégalo en `.env` como `FIREBASE_APP_ID`
     (formato `1:341784491066:web:xxxxxxx`)
   - `measurementId` → pégalo como `FIREBASE_MEASUREMENT_ID`
     (formato `G-XXXXXXX`) — **es el que activa Google Analytics en web**.

> Sin estos valores la app web **funciona igual** (login, cursos,
> simulacros), pero sin analítica ni push. Los errores quedan en el
> log del navegador.

### (Opcional) Notificaciones push en web
1. Firebase Console → **Cloud Messaging → Web Push certificates** →
   "Crear certificado VAPID".
2. Copia la clave pública en `.env` como `FIREBASE_VAPID_KEY`.

### (Necesario para Google Sign-In en web)
1. Firebase Console → **Authentication → Sign-in method → Google**.
2. **Configuración → Dominios autorizados** → agrega tu dominio web
   (ej. `saberplus.app` o el subdominio que uses).
3. Además, en **Google Cloud Console → Credenciales** (OAuth 2.0),
   el cliente "Web client" debe incluir tu dominio en
   *Orígenes JavaScript autorizados*.

---

## 2. Compilar

```bash
cd SaberPlus
flutter pub get

# Opción A — servir en la RAÍZ de un dominio (recomendado):
flutter build web --release

# Opción B — servir en una SUBCARPETA (ej. midominio.com/app):
flutter build web --release --base-href /app/
```

El resultado queda en **`build/web/`** (archivos estáticos:
`index.html`, `main.dart.js`, assets, etc.).

> 🧪 Prueba local antes de subir:
> ```bash
> flutter run -d chrome
> ```

---

## 3. Montar en el servidor

### Opción A — Tu hosting actual (corpoinstel.edu.co)
1. Sube el contenido de `build/web/` a una carpeta pública del servidor,
   por ejemplo: `/var/www/html/app/`.
2. La app queda en `https://corpoinstel.edu.co/app/`.
3. Recuerda compilar con `--base-href /app/` en ese caso.

### Opción B — Firebase Hosting (gratis hasta 10 GB/mes)
```bash
npm install -g firebase-tools
firebase login
firebase init hosting
  # ¿Qué carpeta? build/web
  # ¿Single-page app (rewrite a index.html)? Sí
  # ¿Sobrescribir index.html? NO
firebase deploy
```
Obtendrás `https://saberplus-1ec41.web.app` + dominio propio opcional.

---

## 4. CORS — ya está resuelto ✅

El backend ya envía cabeceras CORS en cada endpoint (y `.htaccess`
añade una capa global con preflight `OPTIONS → 204`). La app web puede
llamar a la API desde cualquier dominio sin configuración adicional.

> Si en el futuro restringes orígenes, edita `backend/.htaccess`
> (sección "CORS headers para Flutter Web").

---

## 5. Verificación post-despliegue (checklist)

- [ ] La app carga con el splash de Saber+ y llega al login.
- [ ] Login con contraseña funciona.
- [ ] El dashboard se ve bien en ventana ancha (columna centrada).
- [ ] Un curso carga y el video se reproduce (streaming).
- [ ] Un PDF muestra el botón "Abrir documento" y abre en pestaña nueva.
- [ ] Ranking → pestañas Colegios / Departamentos cargan datos.
- [ ] "Eliminar mi cuenta" aparece en Perfil.
- [ ] (Si configuraste Firebase) Eventos aparecen en
      Firebase Analytics → DebugView.
- [ ] (Si subiste a corpoinstel.edu.co) Google Sign-In funciona —
      si falla, revisa dominios autorizados (paso 1).

---

## 6. Limitaciones conocidas (web v1.6.0)

| Función | Estado en web |
|---|---|
| Descargar videos/PDFs offline | Oculto (streaming/pestaña nueva) |
| Avatar desde galería | Usar avatares predefinidos |
| Biometría (huella) | No aplica en web |
| Crashlytics | No existe en web — errores visibles en Admin → Errores |
| Notificaciones push | Solo con VAPID key configurada |
| Pago Wompi | Abre la pasarela en pestaña/emergente — igual que en móvil |

---

## 7. Actualizaciones futuras

Cada vez que cambies código:
```bash
flutter build web --release
# y sube de nuevo build/web/ (o firebase deploy)
```
La app web y la móvil usan el mismo backend — no hay que tocar nada
del lado PHP para nuevos builds web.
