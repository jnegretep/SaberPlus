# Saber+ — Guía de actualización v1.5.1

Esta guía documenta los cambios realizados para corregir los errores reportados
y agregar las nuevas funcionalidades de Google Sign-In y login por huella.

---

## 📋 Resumen de cambios

| # | Problema | Estado |
|---|----------|--------|
| 1 | Tras login, volvía a la pantalla Welcome | ✅ Corregido |
| 2 | "Bottom overflowed by 2.0 pixels" en tarjetas del dashboard | ✅ Corregido |
| 3 | Pantalla "Más" se cerraba inesperadamente | ✅ Corregido (mismo fix que #1) |
| 4 | Integrar Google Sign-In | ✅ Implementado |
| 5 | Login por huella (biometric) | ✅ Implementado |

---

## 📁 Archivos modificados / creados

### Modificados

**Flutter (lib/):**
- `lib/main.dart` — Router creado una sola vez (no se recrea en cada rebuild)
- `lib/config/app_router.dart` — `refreshListenable` + redirect incluye `/welcome`
- `lib/screens/login_screen.dart` — Botones Google + Huella funcionales
- `lib/screens/perfil_hub_screen.dart` — Toggle de biometría en Ajustes
- `lib/services/auth_service.dart` — Métodos `loginWithGoogle()`, `enableBiometricLogin()`, `loginWithBiometric()`
- `lib/core/constants/app_constants.dart` — Nuevas keys para biometría
- `lib/widgets/dashboard/preview_card.dart` — Altura 138→152, FittedBox en textos
- `lib/widgets/dashboard/horizontal_preview_list.dart` — Altura 150→164
- `pubspec.yaml` — Agregado `google_sign_in: ^6.2.1` y `local_auth: ^2.2.0`

**Android:**
- `android/app/src/main/AndroidManifest.xml` — Permisos `USE_BIOMETRIC` y `USE_FINGERPRINT`
- `android/app/src/main/kotlin/com/saberplus/app/MainActivity.kt` — Cambiado a `FlutterFragmentActivity` (requerido por local_auth)

### Creados

**Flutter:**
- `lib/services/google_auth_service.dart` — Servicio de Google Sign-In
- `lib/services/biometric_service.dart` — Wrapper sobre local_auth

**Backend PHP:**
- `backend/google_login.php` — Endpoint para validar id_token de Google
- `backend/config/firebase-service-account.json` — Credenciales Firebase Admin (NO subir a git)
- `backend/.gitignore` — Excluye credenciales y vendor/

### Eliminados (archivos basura en la raíz)
- `QuestionScreen(controller`, `Container(`, `Padding(`, `Scaffold(`
- `ChallengeResultsScreen(`, `_loading`, `_sectionCard(_sections[i])`
- `a`, `const`, `null`, `')` — Todos eran archivos vacíos accidentales

---

## 🔧 Configuración requerida (IMPORTANTE)

### Paso 1: Habilitar Google Sign-In en Firebase Console

El backend ya tiene las credenciales del service account, pero falta habilitar
Google como proveedor de autenticación en Firebase:

1. Ve a https://console.firebase.google.com → proyecto `saberplus-1ec41`
2. **Authentication** → **Sign-in method**
3. Click en **Google** → **Habilitar** → Guardar
4. Esto creará automáticamente un Web Client ID

### Paso 2: Configurar OAuth Consent Screen en Google Cloud

1. Ve a https://console.cloud.google.com → proyecto `saberplus-1ec41`
2. **APIs & Services** → **OAuth consent screen**
3. Completa al menos: App name (Saber+), support email, developer email
4. Agrega el scope `userinfo.email` y `userinfo.profile`

### Paso 3: Agregar SHA-1 del keystore a Firebase

Para que Google Sign-In funcione en Android, Firebase necesita conocer el
SHA-1 de tu keystore:

```bash
# Keystore de debug (para desarrollo)
cd android
./gradlew signingReport
```

Copia el SHA-1 del keystore `debug` y agrégalo en:
- Firebase Console → Project Settings → sección "Your apps" → Android app
- Click "Add fingerprint" → pega el SHA-1
- Descarga el `google-services.json` actualizado y reemplázalo en `android/app/`

### Paso 4: Subir el backend

1. Sube `backend/google_login.php` a tu servidor (mismo directorio que `login.php`)
2. Sube `backend/config/firebase-service-account.json` (¡NO a git!)
3. Verifica que el archivo composer.json tiene `kreait/firebase-php` (ya lo tiene)
4. Ejecuta en el servidor:
   ```bash
   cd backend
   composer install
   ```
5. Verifica permisos:
   ```bash
   chmod 600 config/firebase-service-account.json
   chown www-data:www-data config/firebase-service-account.json
   ```

### Paso 5: Instalar dependencias Flutter

```bash
flutter pub get
```

### Paso 6: Probar

```bash
flutter run
```

---

## 🧪 Cómo verificar cada fix

### Fix #1+#3: Login correcto
1. Cierra sesión si la tienes abierta.
2. Inicia sesión con email y contraseña.
3. **Antes:** Volvía a Welcome → había que presionar "Siguiente, Siguiente, Comenzar".
4. **Ahora:** Debe ir directamente al dashboard (o teacher dashboard si eres profesor).

### Fix #2: Sin overflow
1. Entra al dashboard.
2. Mira las tarjetas de Simulacros, Cursos y Retos.
3. **Antes:** Aparecía "Bottom overflowed by 2.0 pixels" en consola.
4. **Ahora:** No debe aparecer ningún error de overflow.

### Fix #3: Pantalla "Más" se queda abierta
1. Toca el botón "Más" en el bottom nav.
2. **Antes:** Cargaba y volvía al dashboard.
3. **Ahora:** Debe quedar abierta y mostrar el perfil + settings.

### Fix #4: Google Sign-In
1. En la pantalla de login, toca "Continuar con Google".
2. Selecciona tu cuenta de Google.
3. **Si ya existe el usuario:** entra directo al dashboard.
4. **Si es nuevo:** te lleva al step2 del registro con email y nombre precargados.

### Fix #5: Login por huella
1. Si el dispositivo soporta biometría, verás el botón "Configurar huella" en login.
2. Inicia sesión normalmente primero.
3. Ve a "Más" → activa el toggle "Login por huella" (te pedirá la huella para confirmar).
4. Cierra sesión.
5. **Ahora** en el login aparecerá "Ingresar con huella" → al pulsarlo, pide huella y entra directo.

---

## 🚨 Solución de problemas

### "El token de Google inválido o expirado" (400 del backend)
- Verifica que el archivo `firebase-service-account.json` esté en `backend/config/`
- Verifica que el service account tenga permisos de Firebase Admin
- Verifica que Google Sign-In esté habilitado en Firebase Console

### El botón de huella no aparece
- Verifica que el dispositivo tenga huella configurada (Ajustes → Seguridad)
- Verifica permisos `USE_BIOMETRIC` en AndroidManifest
- Verifica que `MainActivity.kt` use `FlutterFragmentActivity`

### El prompt de huella aparece pero falla
- Verifica que `MainActivity` sea `FlutterFragmentActivity` (no `FlutterActivity`)
- En emulador: configura una huella en Ajustes → Security → Fingerprint

### Tras login sigue volviendo a Welcome
- Asegúrate de haber ejecutado `flutter clean && flutter pub get`
- Si el problema persiste, ejecuta `flutter run` con `--verbose` para ver los logs
- Verifica que `main.dart` use `late final GoRouter _router` (no recrear en build)

---

## 📦 Para subir a GitHub

```bash
cd SaberPlus
git add .
git status  # verifica qué se va a commitear
git commit -m "feat: fixes #1-3 (router, overflow, perfil hub) + #4 Google Sign-In + #5 biometric login

- Fix #1+#3: GoRouter estable, redirect incluye /welcome
- Fix #2: preview_card altura 152 + FittedBox en textos
- Fix #4: google_auth_service + endpoint google_login.php
- Fix #5: biometric_service + toggle en perfil hub
- Limpieza: eliminados 11 archivos vacíos accidentales en raíz
- Android: USE_BIOMETRIC permission + FlutterFragmentActivity
- Backend: firebase-service-account.json en .gitignore"
git push
```

**IMPORTANTE:** Verifica antes del commit que `backend/config/firebase-service-account.json`
NO esté en staging (debe estar en `.gitignore`).

```bash
git status | grep firebase-service-account
# NO debe aparecer nada
```
