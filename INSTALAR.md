# 📦 SaberPlus v1.5.1 — Guía rápida de instalación

Esta carpeta contiene los 18 archivos modificados/nuevos para corregir los
errores reportados y agregar Google Sign-In + Login por huella.

---

## 📋 Lista de archivos (reemplazar en tu proyecto)

### Archivos MODIFICADOS (reemplazar los existentes)

| # | Ruta en tu proyecto SaberPlus/ | Descripción |
|---|-------------------------------|-------------|
| 1 | `lib/main.dart` | Fix #1+#3: GoRouter estable |
| 2 | `lib/config/app_router.dart` | Fix #1: refreshListenable + redirect /welcome |
| 3 | `lib/screens/login_screen.dart` | Fix #4+#5: Botones Google + Huella |
| 4 | `lib/screens/perfil_hub_screen.dart` | Fix #5: Toggle biometría en Ajustes |
| 5 | `lib/services/auth_service.dart` | Métodos loginWithGoogle + biometric |
| 6 | `lib/core/constants/app_constants.dart` | Nuevas keys biometric_* |
| 7 | `lib/widgets/dashboard/preview_card.dart` | Fix #2: altura 152 + FittedBox |
| 8 | `lib/widgets/dashboard/horizontal_preview_list.dart` | Fix #2: altura 164 |
| 9 | `pubspec.yaml` | Agregado google_sign_in + local_auth |
| 10 | `android/app/src/main/AndroidManifest.xml` | Permisos USE_BIOMETRIC |
| 11 | `android/app/src/main/kotlin/com/saberplus/app/MainActivity.kt` | FlutterFragmentActivity |

### Archivos NUEVOS (copiar a tu proyecto)

| # | Ruta en tu proyecto SaberPlus/ | Descripción |
|---|-------------------------------|-------------|
| 12 | `lib/services/google_auth_service.dart` | Servicio Google Sign-In (Flutter) |
| 13 | `lib/services/biometric_service.dart` | Wrapper local_auth (Flutter) |
| 14 | `backend/google_login.php` | Endpoint validación Google (PHP) |
| 15 | `backend/config/firebase-service-account.json` | Credenciales Firebase Admin |
| 16 | `backend/config/README.txt` | Instrucciones del archivo |
| 17 | `backend/.gitignore` | Excluye credenciales de git |
| 18 | `CAMBIOS_v1.5.1.md` | Documentación completa paso a paso |

---

## 🚀 Pasos para instalar

### Paso 1: Copiar archivos
Copia cada archivo desde esta carpeta a la misma ruta relativa en tu
proyecto local `SaberPlus/`. Por ejemplo:

```bash
# Desde la raíz de tu proyecto SaberPlus
cp /ruta/descarga/SaberPlus-v1.5.1/lib/main.dart lib/main.dart
cp /ruta/descarga/SaberPlus-v1.5.1/lib/services/google_auth_service.dart lib/services/
# ... etc para cada archivo
```

O más fácil: extrae el ZIP `SaberPlus-v1.5.1.zip` directamente sobre
la raíz de tu proyecto (sobreescribirá los archivos modificados y
creará los nuevos).

### Paso 2: Configurar Firebase Console (IMPORTANTE)

1. Ve a https://console.firebase.google.com → proyecto `saberplus-1ec41`
2. **Authentication** → **Sign-in method**
3. Habilita **Google** como proveedor
4. Ve a **Project Settings** → sección "Your apps" → Android app
5. Click **Add fingerprint** y agrega el SHA-1 de tu keystore
   (ejecuta `cd android && ./gradlew signingReport` para obtenerlo)
6. Descarga el `google-services.json` actualizado y reemplázalo en
   `android/app/google-services.json`

### Paso 3: Subir backend al servidor

1. Sube estos archivos a tu servidor PHP (mismo directorio que `login.php`):
   - `backend/google_login.php`
   - `backend/config/firebase-service-account.json`
   - `backend/.gitignore`

2. Ejecuta en el servidor:
   ```bash
   cd /ruta/al/backend
   composer install
   ```
   (instalará `kreait/firebase-php` que ya está en composer.json)

3. Verifica permisos del archivo de credenciales:
   ```bash
   chmod 600 config/firebase-service-account.json
   chown www-data:www-data config/firebase-service-account.json
   ```

### Paso 4: Instalar dependencias Flutter

```bash
cd /ruta/a/tu/SaberPlus
flutter clean
flutter pub get
```

### Paso 5: Probar

```bash
flutter run
```

---

## ✅ Cómo verificar cada fix

### Fix #1+#3: Login correcto
- Cierra sesión.
- Inicia sesión con email y contraseña.
- **ANTES:** Volvía a Welcome → "Siguiente, Siguiente, Comenzar" → dashboard.
- **AHORA:** Debe ir directo al dashboard (o teacher dashboard si eres profesor).

### Fix #2: Sin overflow
- Entra al dashboard.
- Mira las tarjetas de Simulacros, Cursos y Retos.
- **ANTES:** "Bottom overflowed by 2.0 pixels" en consola.
- **AHORA:** Sin errores. Las tarjetas se ven completas.

### Fix #3: Pantalla "Más" se queda
- Toca el botón "Más" (bottom nav, ícono ajustes).
- **ANTES:** Cargaba y volvía al dashboard.
- **AHORA:** Permanece abierta, muestra perfil + ajustes + toggle biometría.

### Fix #4: Google Sign-In
- En el login, toca "Continuar con Google".
- Selecciona tu cuenta de Google.
- **Usuario existente:** entra directo al dashboard.
- **Usuario nuevo:** te lleva al step2 del registro con email y nombre ya cargados.

### Fix #5: Login por huella
- En el login verás "Configurar huella" (si tu dispositivo soporta biometría).
- Pulsa el botón → te explica que primero debes iniciar sesión normal.
- Inicia sesión → ve a "Más" → activa el toggle "Login por huella".
- Confirma con tu huella.
- Cierra sesión.
- **Ahora** el botón dirá "Ingresar con huella" → al pulsarlo, pide huella y entra directo.

---

## 🚨 Solución de problemas comunes

### "Token de Google inválido o expirado" (HTTP 401 del backend)
- Verifica que `backend/config/firebase-service-account.json` esté subido
- Verifica que Google Sign-In esté habilitado en Firebase Console
- Ejecuta `composer install` en el backend

### El botón de huella no aparece
- Verifica que tu teléfono tenga huella configurada (Ajustes → Seguridad)
- Verifica permisos `USE_BIOMETRIC` en AndroidManifest.xml
- Verifica que `MainActivity.kt` use `FlutterFragmentActivity`

### El prompt de huella aparece pero falla silenciosamente
- Verifica que `MainActivity` sea `FlutterFragmentActivity` (no `FlutterActivity`)
- En emulador: configura una huella en Ajustes → Security → Fingerprint

### Tras login sigue volviendo a Welcome
- Ejecuta `flutter clean && flutter pub get` y vuelve a probar
- Verifica que `lib/main.dart` use `late final GoRouter _router`
- Si el problema persiste, revisa que `app_router.dart` tenga `refreshListenable: auth`

### Error de compilación: "google_sign_in not found"
- Ejecuta `flutter pub get` (debe instalar las nuevas dependencias)
- Si persiste, ejecuta `flutter clean && flutter pub get`

---

## 📦 Archivos en este paquete

```
SaberPlus-v1.5.1/
├── CAMBIOS_v1.5.1.md                          ← Documentación completa
├── INSTALAR.md                                ← Este archivo
├── pubspec.yaml                               ← Dependencias actualizadas
│
├── lib/
│   ├── main.dart                              ← MODIFICADO
│   ├── config/
│   │   └── app_router.dart                    ← MODIFICADO
│   ├── core/constants/
│   │   └── app_constants.dart                 ← MODIFICADO
│   ├── screens/
│   │   ├── login_screen.dart                  ← MODIFICADO
│   │   └── perfil_hub_screen.dart             ← MODIFICADO
│   ├── services/
│   │   ├── auth_service.dart                  ← MODIFICADO
│   │   ├── google_auth_service.dart           ← NUEVO
│   │   └── biometric_service.dart             ← NUEVO
│   └── widgets/dashboard/
│       ├── preview_card.dart                  ← MODIFICADO
│       └── horizontal_preview_list.dart       ← MODIFICADO
│
├── backend/
│   ├── .gitignore                             ← NUEVO
│   ├── google_login.php                       ← NUEVO (endpoint)
│   └── config/
│       ├── README.txt                         ← NUEVO
│       └── firebase-service-account.json      ← NUEVO (credenciales)
│
└── android/app/src/main/
    ├── AndroidManifest.xml                    ← MODIFICADO
    └── kotlin/com/saberplus/app/
        └── MainActivity.kt                    ← MODIFICADO
```

**Total:** 18 archivos + 2 documentos = 20 archivos

---

## ⚠️ IMPORTANTE — Seguridad

- **NUNCA subas** `backend/config/firebase-service-account.json` a GitHub.
  Ya está excluido en `backend/.gitignore`.
- El `google-services.json` en `android/app/` sí se sube (no contiene
  secretos privados, solo IDs públicos de cliente).
- Antes de hacer `git push`, verifica:
  ```bash
  git status | grep firebase-service-account
  # NO debe aparecer nada
  ```

---

¡Listo! Sigue los pasos y prueba. Si algo no funciona, revisa
`CAMBIOS_v1.5.1.md` para más detalles o la sección de solución de
problemas arriba.
