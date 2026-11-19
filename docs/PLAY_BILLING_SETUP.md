# Guía de configuración — Google Play Billing (Saber+)

> **Versión:** v1.7.0 · **Fecha:** 2026 · **Responsable:** Ingeniería de pagos
>
> **Por qué esta guía existe:** Colombia **NO participa** en el programa de
> billing alternativo de Google Play. Toda compra de productos digitales
> **dentro del APK Android** debe procesarse con **Google Play Billing**
> (política de Play Store; incumplir = retiro de la app). La **versión web**
> NO está sujeta a esas políticas y sigue usando **Wompi**.
>
> **Regla de oro:** dentro del app Android **NO hay links externos de pago**
> (ni botones a checkout.wompi.co, ni webviews de pago). Solo texto plano
> informativo tipo "saberplus.app", que sí está permitido.

---

## 0. Resumen de la arquitectura

```
┌──────────────┐   1. buyNonConsumable    ┌──────────────┐
│  App Android │ ───────────────────────► │  Google Play │
│ (in_app_     │ ◄─────────────────────── │   Billing    │
│  purchase)   │  2. purchaseToken        └──────────────┘
└──────┬───────┘
       │ 3. POST verify_play_purchase.php
       │    { product_id, purchase_token, order_id }  + JWT
       ▼
┌─────────────────────────────────────────────────────────────┐
│ backend/verify_play_purchase.php                            │
│  - valida JWT (moodle_id)                                   │
│  - OAuth2 service account → access_token (cache 50 min)     │
│  - GET Google Play Developer API v3 con el purchaseToken    │
│    · subscription → purchases/subscriptionsv2/tokens/{t}    │
│    · inapp         → purchases/products/{id}/tokens/{t}     │
│  - INSERT play_purchases + payments(gateway='play_billing') │
│  - UPDATE usuarios SET access_level='premium'               │
└─────────────────────────────────────────────────────────────┘
       ▲
       │ 4. (renovaciones) Pub/Sub RTDN → play_rtdn.php
       └── X-Internal-Token — misma verificación Google
```

Archivos clave:
- App: `lib/services/billing_service.dart`, `lib/screens/upgrade_screen.dart`,
  `lib/services/api_service.dart` (`verifyPlayPurchase`).
- Backend: `verify_play_purchase.php`, `play_rtdn.php`,
  `includes/google_play_verify.php` (helper compartido),
  `migrations/004_play_billing.sql`.

---

## 1. Crear los productos en Play Console

En [Play Console](https://play.google.com/console) → **Monetizar → Productos →
Suscripciones** (y **Productos integrados** para el vitalicio), crea
**exactamente** estos IDs (el app los tiene hardcodeados en
`lib/services/billing_service.dart` → `BillingProductIds`):

| Product ID | Tipo | Base plan | Precio COP sugerido |
|---|---|---|---|
| `saberplus_premium_monthly` | Suscripción | 1 mes, renovación automática | $25.000 |
| `saberplus_premium_annual` | Suscripción | 1 año, renovación automática | $199.000 |
| `saberplus_premium_lifetime` | Producto único (no-consumible) | — | $399.000 |

Notas:
- En las suscripciones, crea el **base plan** correspondiente (1 mes / 1 año)
  sin ofertas ni pruebas gratis en v1.
- Activa cada producto (estado *Activo*) — un producto en borrador no aparece
  en `queryProductDetails` y el app mostrará la tarjeta "pago móvil
  próximamente".
- Los precios que ve el usuario Android salen de Play Console; mantenlos
  sincronizados con la tabla `plans` (web/Wompi).

## 2. Service account + Google Play Android Developer API

1. En [Google Cloud Console](https://console.cloud.google.com), abre el
   proyecto vinculado a tu app (mismo proyecto de Firebase).
2. **APIs y servicios → Biblioteca** → busca **"Google Play Android Developer
   API"** → **Habilitar**.
3. **APIs y servicios → Credenciales → Crear credenciales → Cuenta de
   servicio.** Nómbrala p. ej. `saberplus-play-billing`. No necesita roles de
   GCP.
4. Entra a la cuenta de servicio → **Claves → Agregar clave → Crear clave
   nueva → JSON**. Se descarga un archivo tipo
   `saberplus-XXXX-a1b2c3.json` con `client_email` y `private_key`.
   **Guárdalo en un lugar seguro: es una credencial.**
5. En **Play Console → Configuración → Usuarios y permisos → Invitar nuevos
   usuarios**, invita el **email de la service account**
   (`saberplus-play-billing@…iam.gserviceaccount.com`) con el permiso
   **"Ver información financiera"** (`View financial data`). Sin este permiso
   la API responde 401/403.
6. Espera ~15 min a que el permiso propague.

## 3. Configurar el backend (.env)

Añade a `backend/.env` (usa el mismo valor de `INTERNAL_TOKEN` que ya tienes
para los crons):

```dotenv
GOOGLE_PLAY_PACKAGE_NAME=com.saberplus.app
GOOGLE_PLAY_SA_JSON={"type":"service_account","project_id":"...","private_key_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----\n","client_email":"...@...iam.gserviceaccount.com","client_id":"...","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token",...}
```

⚠️ **`GOOGLE_PLAY_SA_JSON` debe ir en UNA SOLA LÍNEA** (sin saltos). El loader
`env.php` no soporta valores multilínea. Si copias el JSON del archivo
descargado, aplánalo en una línea (los `\n` de la private_key ya vienen
escapados dentro del JSON y NO hay que tocarlos):

```bash
# Helper: JSON de una línea listo para pegar tras GOOGLE_PLAY_SA_JSON=
python3 -c "import json,sys;print(json.dumps(json.load(open(sys.argv[1])),separators=(',',':')))" saberplus-XXXX.json
```

Si `GOOGLE_PLAY_SA_JSON` falta, `verify_play_purchase.php` responde
**503** con mensaje claro ("Pasarela de pagos móvil aún no configurada…") y el
app muestra la tarjeta informativa "pago móvil disponible próximamente"
(sin links de pago).

## 4. Ejecutar la migración 004

```bash
# Verificar si la columna gateway ya existe (create_wompi_payment.php ya la usa):
mysql -u <usuario> -p -e "SHOW COLUMNS FROM payments LIKE 'gateway';" prepsaber

# Si NO existe la columna:
mysql -u <usuario> -p prepsaber < backend/migrations/004_play_billing.sql

# Si YA existe, corre con --force (el ALTER dará error 1060 inofensivo):
mysql --force -u <usuario> -p prepsaber < backend/migrations/004_play_billing.sql
```

Crea la tabla `play_purchases` y la columna `gateway` en `payments`.

## 5. (Opcional, renovaciones) Pub/Sub RTDN

Sin esto las **renovaciones** no actualizan `expiry_time`/`payments`
automáticamente (el usuario mantiene premium por la compra original; el
acknowledge inicial lo hace el app).

1. Google Cloud Console → **Pub/Sub → Temas → Crear tema**
   `saberplus-play-rtdn`.
2. En Play Console → **Monetizar → Configuración → Notificaciones para
   desarrolladores en tiempo real (RTDN)** → selecciona el topic creado.
3. En el topic → **Suscripciones → Crear suscripción** tipo **Push**:
   - URL del endpoint: `https://<tu-dominio>/api/prepsaber/play_rtdn.php`
     (ajusta a la ruta pública real de tu backend).
   - Añade la cabecera de autenticación: `X-Internal-Token: <valor de
     INTERNAL_TOKEN de backend/.env>`.
4. Verifica el flujo con una compra de prueba y revisa el log del servidor:
   `[PLAY_RTDN] Notificación recibida`.

`play_rtdn.php` responde **siempre 200** a Pub/Sub (evita tormentas de
reintentos). La validación es por `X-Internal-Token` (403 si falla).

## 6. Testing

1. **Lista de testers de licencia:** Play Console → Configuración →
   *Detalles de la licencia* → añade los Gmail de los testers (las compras
   con tarjetas de prueba no cobran realmente).
2. **Track interno:** sube el APK con el código nuevo a
   *Pruebas → Pruebas internas* y añade los mismos testers. El billing solo
   funciona en builds firmados instalados desde Play (o con `flutter run`
   con `--flavor` + firma release si tienes todo configurado).
3. **Tarjetas de prueba:** en la ventana de pago de Play aparecen los
   instrumentos de prueba ("Tarjeta de crédito de prueba, aprobada
   automáticamente", "lenta", "rechazada"...).
4. **Flujo completo esperado:**
   1. El app muestra el **precio real de Play** (moneda local) en las cards.
   2. Botón *Suscribirme* → ventana de pago de Play → confirmar.
   3. El app llama a `verify_play_purchase.php` → backend consulta Google →
      activa premium → `fetchProfile()` refresca el usuario.
   4. Diálogo "¡Ahora eres Premium!" con check animado.
   5. **Acknowledge:** el app SIEMPRE llama `completePurchase` después de
      verificar (si no, Google **reembolsa a los 3 días**).
5. **Pago pendiente:** elige "método de pago lento" (efectivo) → el app
   muestra "pago pendiente"; al confirmarse Google llega el RTDN y la
   re-verificación.
6. **Restaurar compras:** desinstala/reinstala (o borra datos), entra a la
   pantalla premium → *Restaurar compras* → premium reactivado.
7. **Renovación/cancelación:** cancela la renovación desde Play Store →
   llega RTDN (eventType 3 CANCELED) → `play_purchases.state` se actualiza
   (v1 no degrada; ver §8).

## 7. Checklist de producción

- [ ] Productos `saberplus_premium_monthly` / `_annual` / `_lifetime`
      creados y **activos** en Play Console.
- [ ] Google Play Android Developer API **habilitada** en Cloud Console.
- [ ] Service account con clave JSON **creada y guardada en bóveda/1Password**
      (el JSON en `.env` es la copia operativa).
- [ ] Service account invitada en Play Console con **"Ver información
      financiera"**.
- [ ] `backend/.env`: `GOOGLE_PLAY_PACKAGE_NAME` + `GOOGLE_PLAY_SA_JSON`
      (una línea) verificados en el servidor de producción.
- [ ] Migración `004_play_billing.sql` ejecutada en producción
      (`SHOW COLUMNS FROM payments LIKE 'gateway';` para confirmar).
- [ ] `flutter pub get` + build release firmada; `flutter analyze` limpio.
- [ ] Compra de prueba end-to-end en track interno OK (compra → verificación
      → premium → acknowledge).
- [ ] Restaurar compras probado tras reinstalar.
- [ ] (Opcional) Pub/Sub RTDN configurado y logueando notificaciones.
- [ ] Política de datos/privacidad de Play Console actualizada (los pagos no
      añaden datos nuevos; verificar sección "Pagos" de la ficha de la app).
- [ ] **Cero links de pago externos dentro del APK** (grep de
      `checkout.wompi.co` debe salir limpio en Android; solo la web usa
      Wompi).
- [ ] Precios de Play Console sincronizados con la tabla `plans`.

## 8. Decisiones y limitaciones conocidas (v1)

- **Sin degradación automática en v1:** si una suscripción llega EXPIRED o
  CANCELED (y ya pasó su expiración), `play_rtdn.php` actualiza
  `play_purchases.state` pero **NO baja `access_level`**. Motivos: existen
  usuarios *lifetime* (inapp) que no expiran, la tolerancia de gracia evita
  cortar el acceso por un falso negativo transitorio de la API, y un webhook
  puede reordenarse. En **v2** un cron comparará `expiry_time` contra `NOW()`
  (solo suscripciones, nunca inapp) para degradar con margen.
- **Compras con la pantalla cerrada:** `BillingService` encola el evento y lo
  re-emite al reabrir la pantalla de upgrade; la re-verificación también
  puede dispararse con "Restaurar compras".
- **Precios:** el precio que muestra el app Android SIEMPRE es el de Play
  Console (`ProductDetails.price`, moneda local). El precio de la tabla
  `plans` solo es fallback/reportería (`payments.amount` se llena mapeando
  `product_id` → `plans.code` LIKE `%monthly%`/`%annual%`/`%lifetime%`).
- **Idempotencia:** `play_purchases.purchase_token` es UNIQUE y
  `payments.reference_code = 'play_' + sha1(token)[0..24]` es determinístico;
  reintentos del app o de Pub/Sub no duplican registros.
