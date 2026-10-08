# Saber+ v1.6.1 — Corrección de compilación web

**Fecha:** 19 de septiembre de 2026
**Tipo:** Hotfix (no rompe nada de la versión móvil)
**Versión:** `1.6.1+17`

---

## 🔴 Problema corregido

Al ejecutar `flutter build web --release`, dart2js fallaba con **6 errores de tipos**:

```
Error: The argument type 'File/*1*/' can't be assigned to the parameter type 'File/*2*/'.
 - 'File/*1*/' is from 'package:saberplus_app/core/io_shim/io_web_stub.dart'
 - 'File/*2*/' is from 'dart:io'.
```

Aparecía en: `register_step1.dart`, `register_step2.dart`, `set_password_screen.dart`,
`edit_profile_complete_screen.dart`, `premium_video_player.dart`, `profile_avatar_widget.dart`.

### Causa raíz

Las APIs del framework de Flutter (`Image.file()`, `FileImage()`,
`VideoPlayerController.file()`) exigen el `File` **real de `dart:io`**, que no
existe en web. El shim creado en v1.6.0 permitía compilar las pantallas, pero al
pasar ese `File` del shim a esas APIs del framework, dart2js rechazaba la mezcla
de tipos.

*(Las advertencias de "Wasm dry run findings" del log son solo informativas para
builds WebAssembly — no bloquean la compilación JS y pueden ignorarse.)*

---

## ✅ Solución: puente multiplataforma (`platform_bridge`)

Se creó un puente con import condicional (mismo mecanismo que ya usaba el shim),
que expone **3 funciones con firma idéntica** que se resuelven en tiempo de
compilación:

| Función | Móvil (comportamiento original) | Web |
|---|---|---|
| `fileFromXFile(XFile)` | `File(path)` de dart:io | Stub `File` que conserva el XFile real |
| `fileImageProvider(File)` | `FileImage(file)` | `NetworkImage(blob:URL)` |
| `localVideoController(path)` | `VideoPlayerController.file(...)` | No soportado (las descargas ya están ocultas en web; degradación controlada con botón Reintentar) |

### Archivos nuevos

| Archivo | Propósito |
|---|---|
| `lib/core/io_shim/platform_bridge.dart` | Export condicional (io ↔ web) |
| `lib/core/io_shim/platform_bridge_io.dart` | Implementación móvil/escritorio (dart:io real — **idéntico al código anterior a v1.6.0**) |
| `lib/core/io_shim/platform_bridge_web.dart` | Implementación web |

### Archivos modificados

| Archivo | Cambio |
|---|---|
| `lib/core/io_shim/io_web_stub.dart` | El stub `File` ahora puede respaldarse en el `XFile` de image_picker: `readAsBytes()` lee los **bytes reales** del blob (antes devolvía vacío) → **subir avatar en web ahora funciona** |
| `lib/screens/register_step1.dart` | `fileFromXFile` + `Image(image: fileImageProvider(...))` + cámara oculta en web + try/catch del picker |
| `lib/screens/register_step2.dart` | Bridge de imagen + guard de tamaño de foto (> 4 MB avisa en vez de fallar en el servidor) |
| `lib/screens/set_password_screen.dart` | Bridge de imagen |
| `lib/screens/edit_profile_complete_screen.dart` | `fileFromXFile` + bridge de imagen + cámara oculta en web + try/catch + guard de tamaño |
| `lib/widgets/profile_avatar_widget.dart` | `FileImage` → `fileImageProvider` |
| `lib/widgets/video/premium_video_player.dart` | `VideoPlayerController.file` → `localVideoController` (bridge) |
| `pubspec.yaml` | `cross_file: ^0.3.3+2` como dependencia directa + versión `1.6.1+17` |

---

## 🧪 Cómo probar

### Móvil (no debe cambiar NADA)
```bash
flutter clean
flutter pub get
flutter run            # o flutter build apk --release
```
Verificar: registro con foto de galería/cámara, edición de perfil con foto,
reproducción de videos premium (streaming y descargados).

### Web
```bash
flutter clean
flutter pub get
flutter build web --release
```
El build debe completar sin errores de tipos. Las advertencias de Wasm del
principio son normales (solo aplican si algún día se compila a WebAssembly).

Verificar en web:
1. **Registro** → elegir foto de **Galería** (la opción Cámara está oculta en
   web a propósito — el navegador no la soporta con image_picker).
2. La foto se **muestra** en el círculo del avatar (blob URL).
3. Completar el registro → el avatar queda **guardado en el servidor** (base64,
   igual que en móvil). Fotos de más de 4 MB avisan y se omiten (el navegador
   no comprime como sí lo hace el móvil).
4. **Perfil → Editar** → cambiar foto → guardar.
5. **Cursos premium → video** → reproduce en streaming (el botón de descarga
   está oculto en web).
6. Avatares prediseñados funcionan igual que en móvil.

---

## 📌 Notas técnicas

- **Cero cambios de comportamiento en móvil/escritorio**: el bridge en móvil es
  literalmente el código original (`FileImage`, `VideoPlayerController.file`,
  `File(path)`), solo que encapsulado en funciones. Mismo render, misma caché.
- **CORS**: los videos y avatares remotos requieren que el backend sirva los
  headers CORS (ya configurado en `.htaccess` en v1.6.0). Si un video no carga
  en web pero sí en móvil, verificar que el `.htaccess` actualizado esté en el
  servidor.
- **Firebase en web**: seguir los pasos de `DESPLIEGUE_WEB.md`
  (`FIREBASE_APP_ID`, `MEASUREMENT_ID`, dominio autorizado).
