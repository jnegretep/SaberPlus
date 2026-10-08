# SaberPlus v1.7.0 — Cambios y Guía de Despliegue

**Versión:** 1.7.0+18 · **Fecha:** sep-2026
**Frente de trabajo:** Producto y negocio — pagos Play Billing, panel de colegios, promociones, soporte, branding y corrección IA.

---

## 1. Resumen ejecutivo

| # | Entregable | Estado |
|---|-----------|--------|
| 1 | **Google Play Billing** en Android (Wompi solo en web) | ✅ |
| 2 | **Web adaptativa** (nav lateral + contenido ancho en PC) | ✅ |
| 3 | **Panel del director de colegio** (B2B) + gestión desde admin | ✅ |
| 4 | **Promociones**: CRUD admin + banner/cuenta regresiva en app + códigos + descuento real en Wompi | ✅ |
| 5 | **Soporte in-app**: quejas/sugerencias con respuesta desde admin | ✅ |
| 6 | **Edición de usuarios** desde admin (búsqueda + perfil completo) | ✅ |
| 7 | **Branding SaberPlus** + políticas Google Play + redes sociales | ✅ |
| 8 | **Compartir mejorado** con logo adjunto y textos por rango de puntaje | ✅ |
| 9 | **Fix IA DeepSeek** (JWT ausente + robustez + diagnóstico) | ✅ |

---

## 2. Pagos: Google Play Billing (Android) + Wompi (web)

**Por qué:** Colombia NO participa en el programa de billing alternativo de Google Play. Toda compra de contenido digital DENTRO del APK debe ir por Play Billing (política de Google; el incumplimiento puede derivar en retiro de la app). Las "donaciones" o links externos a Wompi in-app también incumplen.

**Qué cambió:**
- `lib/services/billing_service.dart` (NUEVO): envoltorio de `in_app_purchase` con productos `saberplus_premium_monthly`, `saberplus_premium_annual` (suscripciones) y `saberplus_premium_lifetime` (único), compra, restauración y eventos tipados.
- `lib/screens/upgrade_screen.dart`: en **Android** compra por Play (muestra el precio REAL de Play Console, verifica server-side, diálogo de éxito, "Restaurar compras"); en **web** mantiene Wompi idéntico. Si Play no está configurado → tarjeta informativa **sin links de pago externos** (cumplimiento).
- `backend/verify_play_purchase.php` (NUEVO): valida cada compra contra la **Google Play Developer API** (service account, OAuth2 firmado con OpenSSL, token cacheado) ANTES de activar premium. Idempotente por `purchase_token`.
- `backend/play_rtdn.php` (NUEVO): webhook de renovaciones (Pub/Sub) con `X-Internal-Token`.
- `backend/migrations/004_play_billing.sql`: tabla `play_purchases` + columna `payments.gateway`.

**Para activarlo (guía completa en `docs/PLAY_BILLING_SETUP.md`):**
1. Play Console → crear los 3 productos con esos IDs exactos (precios sugeridos COP 25.000 / 199.000 / 399.000).
2. Google Cloud → habilitar *Google Play Android Developer API* → crear service account → JSON key → vincularla en Play Console con permiso de ver datos financieros.
3. `backend/.env`: `GOOGLE_PLAY_PACKAGE_NAME=com.saberplus.app` y `GOOGLE_PLAY_SA_JSON=<json en una línea>`.
4. Ejecutar `004_play_billing.sql` en MySQL.
5. Probar con license testers antes de producción.

> Mientras configuras Play Console, el app Android muestra "pago móvil próximamente" y **todo sigue funcionando**: la compra sigue disponible en la versión web con Wompi.

---

## 3. Web en escritorio (layout adaptativo)

- **> 1100px:** shell de escritorio real — barra de navegación lateral (logo + secciones) + contenido centrado de 880px sobre fondo degradado elegante con marca de agua del logo.
- **700–1100px:** marco centrado de 620px (antes 480px — la causa de la queja) con sombra y fondo mejorado.
- **≤ 700px:** sin cambios (móvil).
- Móvil: **cero cambios** (todo tras `kIsWeb`).
- Archivos: `lib/main.dart`, `lib/widgets/global_scaffold.dart`, `lib/widgets/web_desktop_shell.dart` (nuevo).

---

## 4. Panel del director de colegio (B2B) — `backend/director/`

Panel web independiente (login propio, no depende de Moodle) para vender a colegios:

- **Dashboard:** estudiantes, activos, promedio global del colegio, simulacros, mejor área, XP, tendencia mensual, distribución por grado, top 5.
- **Estudiantes:** búsqueda, filtros (grado/estado), simulacros/mejor/promedio, **activar/desactivar** (el estudiante desactivado no puede volver a entrar al app), detalle completo por estudiante con histórico de puntajes.
- **Simulacros:** reportes agregados por fecha con filtros + **exportación CSV** (Excel-friendly).
- **Aislamiento garantizado:** cada director SOLO ve los estudiantes de SU colegio (scoping por sesión en cada query).

**Operación:**
1. Ejecutar `backend/migrations/005_directores.sql` (crea tabla `directores` + columna `usuarios.activo`).
2. Panel admin → sección **🏫 Colegios** → crear director (nombre, email, contraseña, colegio).
3. Compartir credenciales: el director entra a `https://tu-dominio/api/prepsaber/backend/director/`.

---

## 5. Promociones (admin → app en tiempo real)

- Panel admin → **🎁 Promociones**: crear/editar/activar/eliminar promos con título, descripción, tipo (**banner** visible en el app / **código** canjeable), descuento (% o COP fijo), plan específico o todos, **fechas de vigencia**, cupo máximo de usos y contador de usos.
- La app consulta `get_active_promos.php` al abrir la pantalla Premium → **los cambios del admin se ven al instante** (banner morado con cuenta regresiva en vivo; sin actualizar la app).
- En la **web** el descuento es real: los banners con descuento se aplican automáticamente al pagar y el usuario puede escribir códigos promocionales (el backend valida vigencia/cupo y aplica el precio final; el webhook de Wompi sigue cuadrando porque `payments.amount` guarda el precio con descuento).
- En **Android** los precios los fija Play Console (restricción de Google) → para equivalentes usa los códigos promociales de Play; el banner igual funciona como urgencia/comunicación.
- Migración: `backend/migrations/006_promociones_quejas.sql`.

---

## 6. Soporte in-app (quejas y sugerencias)

- App: **Perfil → Información y soporte → "Ayuda y Soporte"** (nueva pantalla `soporte_screen.dart`): enviar sugerencia/queja/bug/otro + historial "Mis envíos" con estado y **respuesta del equipo**.
- Admin: sección **💬 Soporte** — bandeja con contadores por estado, filtros, detalle del ticket y respuesta que llega al app al instante. Anti-spam: 1 envío cada 5 min por usuario.

---

## 7. Administración de usuarios mejorada

- Sección **Usuarios** del admin: **buscador** (nombre/email/ID) + botón **Editar** por usuario.
- Edición completa: nombre, email, teléfono, departamento, ciudad, colegio, grado, tipo (estudiante/profesor/admin), plan (free/premium/early_bird), email verificado y cuenta activa.

---

## 8. Branding, redes y políticas

- "PrepSaber" → **SaberPlus** en Quiénes somos y todos los footers visibles; versión 1.7.0 dinámica; © 2026.
- Nueva sección **"Síguenos"** en Quiénes somos (Instagram, TikTok, Facebook, WhatsApp) — ⚠️ **ajusta los handles reales** en `lib/core/constants/app_constants.dart` cuando crees las cuentas.
- **Política de privacidad reescrita** alineada con Google Play Data Safety (datos recopilados, terceros Firebase/DeepSeek/Wompi/Play, menores 13+, Ley 1581/2012, eliminación de cuenta in-app).
- **Compartir en redes mejorado:** textos con gancho por rango de puntaje (en camino / nivel pro / modo leyenda), **logo adjunto** en el mensaje (móvil), y nuevo share de puntaje estimado por la IA. `share_plus` subido a `^10.0.0` (la API que ya usaba el código).

---

## 9. Fix del tutor IA (DeepSeek)

**Causa raíz (dos frentes):**
1. Las 3 pantallas de IA (chat, estadísticas, análisis por área) **no enviaban el header `Authorization: Bearer`** que el backend exige desde el blindaje de seguridad → la IA nunca recibía la pregunta.
2. El backend llamaba a DeepSeek sin timeouts y con errores opacos (el clásico **HTTP 402 sin saldo** era indistinguible).

**Solución:**
- Las 3 pantallas envían JWT + timeouts de 60s + mensajes de error accionables + **reintentar con un tap** (burbuja tap-to-retry en el chat).
- Backend: timeouts, códigos de error (`SIN_SALDO`, `KEY_INVALIDA`, `RATE_LIMIT`, `TIMEOUT`), log completo del body de DeepSeek, rate-limit por usuario, validación de respuesta.
- `backend/admin/check_ia.php`: botón "Probar IA" que diagnostica el estado real (si falta saldo lo dice en texto claro).

> **Acción requerida si la IA sigue sin responder:** abre `admin/check_ia.php`. Lo más probable es que la cuenta de DeepSeek esté **sin saldo** → recarga en platform.deepseek.com (los mensajes de error del app ahora lo indican sin exponer detalles técnicos).

---

## 10. Checklist de despliegue

**Backend (subir archivos y ejecutar migraciones):**
```
mysql -u <user> -p <db> < backend/migrations/004_play_billing.sql
mysql -u <user> -p <db> < backend/migrations/005_directores.sql
mysql -u <user> -p <db> < backend/migrations/006_promociones_quejas.sql
```
- Subir TODOS los archivos nuevos/modificados del backend (lista en el ZIP).
- `backend/.env`: agregar `GOOGLE_PLAY_PACKAGE_NAME` y `GOOGLE_PLAY_SA_JSON` (cuando tengas la service account).
- Verificar permisos de `backend/director/` (igual que `/admin`).

**App:**
```
flutter clean
flutter pub get        # actualiza share_plus 10.x e in_app_purchase 3.x
flutter build apk --release --dart-define=API_BASE_URL=... (tus dart-define habituales)
flutter build web --release (si publicas la web)
```

**Post-despliegue:**
1. Probar el chat de la IA (debe responder; si no, `admin/check_ia.php`).
2. Crear la primera promoción de lanzamiento en admin → verificar banner en el app.
3. Crear un director de prueba y validar el panel.
4. Enviar una sugerencia desde el app y responderla desde admin.
5. Subir a Play Store (los productos de billing pueden configurarse después; el app degrada elegantemente).

---

## 11. Verificación automática ejecutada

| Script | Resultado |
|--------|-----------|
| `scripts/verify_billing_files.py` | PASS |
| `scripts/verify_web_layout.py` (50 checks) | PASS |
| `scripts/verify_director_panel.py` | PASS |
| `scripts/verify_branding.py` | PASS |
| `scripts/verify_ia_fix.py` (27 checks) | PASS |
| `scripts/verify_v170_final.py` (55 checks, integración global) | PASS |

> Nota: el entorno de desarrollo no tiene Flutter/PHP instalados; la verificación es estática (balance, imports, consistencia). Ejecuta `flutter analyze` en tu máquina antes del release final.
