# ENTREGA SABER+ 2.0 — Archivos modificados, nuevos y eliminados

Base: `origin/main` = commit `403c22d` (última versión de GitHub, con las
modificaciones del propietario preservadas). Rama de trabajo:
`feature/saberplus-2.0` (5 commits). Total: **71 archivos** (+7.242 / −2.501).

Como este entorno no tiene credenciales de GitHub, el push no fue posible.
Flujos para aplicar los cambios (cualquiera de los dos):

**Opción A — git bundle (recomendada)**:
```bash
cd SaberPlus
git fetch /ruta/a/saberplus-2.0.bundle feature/saberplus-2.0:tmp-2.0
git merge tmp-2.0        # o: git reset --hard tmp-2.0
git push origin main
```

**Opción B — parches**:
```bash
git am 00*.patch   # 5 parches en orden (incluidos en el ZIP de entrega)
```

---

## 🆕 ARCHIVOS NUEVOS (14)

| Ruta | Motivo | Cambio principal |
|------|--------|------------------|
| `backend/migrations/008_codigos_premium.sql` | #4 Códigos promocionales | Tablas `codigos_premium` + `codigos_premium_usos` (UNIQUE código+usuario) |
| `backend/redeem_promo_code.php` | #4 | Endpoint de canje: JWT + rate limit 8/10min + transacción FOR UPDATE |
| `backend/migrations/009_course_catalog.sql` | #9 Cursos | Tabla `course_catalog` sembrada con la clasificación actual + retos 56-60 |
| `backend/includes/avatar_helper.php` | #11 Avatar | Helper compartido: magic bytes jpg/png/webp + escritura verificada |
| `backend/uploads/avatars/.gitkeep` | #11 | Directorio de avatares garantizado en despliegues |
| `lib/parsers/review_question_parser.dart` | #1 Review | Parser DOM del HTML de revisión de Moodle (opciones/feedback/estado) |
| `lib/widgets/question_option_tile.dart` | #1 Review | Tile de opción reutilizable (correcta verde / elegida incorrecta roja) |
| `lib/screens/lock_screen.dart` | #2 Biometría | Pantalla de bloqueo local: huella, reintentar, usar contraseña |
| `lib/screens/registration_success_screen.dart` | #7 | "🎉 ¡Registro exitoso!" con siguiente paso explícito y CTA a login |
| `web/firebase-messaging-sw.js` | #16 FCM | Service worker web (config real saberplus-1ec41) para push en background |
| `CAMBIOS_v2.0.0.md` | Documentación | Changelog completo de la versión |
| `REPORTE_MEJORAS_CHECKLIST_SABERPLUS.md` | Reporte final | Estado por punto del checklist con pruebas |
| `GUIA_ACTIVACION_NOTIFICACIONES_SABERPLUS.md` | #16 FCM | Problema/causa/cambios/config pendiente/pasos/prueba final |
| `GUIA_ACCESO_ADMIN_SABERPLUS.md` | #17 Admin | Acceso, roles, seguridad del panel (sin contraseñas reales) |

## ✏️ ARCHIVOS MODIFICADOS (37)

### Flutter — Review (#1)

| Ruta | Motivo | Cambio principal |
|------|--------|------------------|
| `lib/screens/review_screen.dart` | #1 | Tarjetas con opciones marcadas, badge ✅/❌, feedback completo expandido; parser reemplaza regex; fixes de crash/NaN |

### Flutter — Biometría (#2), registro (#5-8), avatar (#11)

| Ruta | Motivo | Cambio principal |
|------|--------|------------------|
| `lib/services/auth_service.dart` | #2 | Biometría = bloqueo local (`enableAppLock`/`isAppLockEnabled`); login captura el 403 "unverified" |
| `lib/screens/login_screen.dart` | #2 #5 | Fuera botón-huella viejo; Google → "próximamente" + registro manual; unverified → pantalla de verificación; prompt post-login de bloqueo |
| `lib/main.dart` | #2 #16 | Observador de ciclo de vida → `/lock`; FCM habilitado en web con VAPID; provider PlanService fuera; comentario v2.0.0 |
| `lib/screens/perfil_hub_screen.dart` | #2 #3 | Toggle "Bloqueo con huella" al nuevo modelo; tile "Plan Premium" |
| `lib/config/app_router.dart` | #2 #7 #11 | Rutas `/lock` y `/register/success`; extra del step2 transporta el avatar (fix NULL) |
| `lib/core/constants/app_constants.dart` | #2 #13 #15 | Versión 2.0.0, redes oficiales, keys del bloqueo local |
| `lib/screens/register_step1.dart` | #11 | El avatar elegido viaja en el extra al paso 2 |
| `lib/screens/register_step2.dart` | #6 | Overlay honesto "Estamos preparando tu cuenta" + PopScope anti-abandono |
| `lib/screens/set_password_screen.dart` | #6 #7 | Overlay "Preparando tu experiencia académica" → pantalla de éxito (modo recuperación intacto) |
| `lib/screens/verify_email_screen.dart` | #8 | Instrucciones 1-5, spam destacado, botón reenvío con cooldown 60s |
| `lib/services/biometric_service.dart` | #2 | Comentario actualizado al nuevo modelo |

### Flutter — Premium (#3 #4 #14), diagnóstico (#12), performance (#10), redes (#15), versión (#13)

| Ruta | Motivo | Cambio principal |
|------|--------|------------------|
| `lib/screens/upgrade_screen.dart` | #4 #14 | Sección "Tengo un código promocional" con canje; tarjeta 💳 PAGO ÚNICO; comparativa/FAQ corregidas |
| `lib/services/api_service.dart` | #4 #10 | `redeemPromoCode()`; `lastFetchedCategories` (1 llamada en vez de 3) |
| `lib/screens/dashboard_screen.dart` | #3 | Banner de Premium descartable (solo free/trial) |
| `lib/screens/perfil_screen.dart` | #3 | CTA "Pásate a Premium" bajo el nivel de acceso |
| `lib/screens/simulacro_stats_screen.dart` | #12 | Recomendaciones por área (3 más débiles + fuerte + cursos); **fix de sintaxis crítico heredado** |
| `lib/screens/acerca_screen.dart` | #15 | Handles oficiales de redes |
| `lib/services/analytics_service.dart` | #13 | appVersion 2.0.0 (reportaba 1.6.0) |
| `lib/providers/dashboard_provider.dart` | #10 | Carga de cursos en 1 llamada |
| `pubspec.yaml` | #13 | `version: 2.0.0+20` |

### Nativo / Web (#2 #16)

| Ruta | Motivo | Cambio principal |
|------|--------|------------------|
| `ios/Runner/Info.plist` | #2 | `NSFaceIDUsageDescription` (Face ID) |
| `android/app/src/main/AndroidManifest.xml` | #16 | `POST_NOTIFICATIONS` + meta-data canal por defecto |
| `android/app/src/main/kotlin/com/saberplus/app/MainActivity.kt` | #16 | Creación real del canal `saberplus_notificaciones` (Android 8+) |

### Backend (#4 #9 #11 #16)

| Ruta | Motivo | Cambio principal |
|------|--------|------------------|
| `backend/admin/index.php` | #4 #9 #17 | Secciones "🎟️ Códigos Premium" y "📚 Cursos Moodle" (clasificación + matrícula masiva con resumen/confirmación/auditoría) |
| `backend/moodle/get_courses.php` | #9 | Clasificación dinámica por catálogo con fallback exacto; early_bird desbloquea; sin residuo de debug |
| `backend/set_password.php` | #9 | Matrícula según catálogo (fallback histórico) |
| `backend/register.php` | #11 | Avatar con helper validado; sin archivos huérfanos en el 409 |
| `backend/update_profile.php` | #11 | Avatar con helper; `avatar_url` con `getAvatarUrl()` (antes 404) |
| `backend/resend_verification.php` | #8 | Reescrito: enlace mágico 24h + rate limit + mismo correo HTML |
| `backend/send_to_many.php` | #16 | Header `X-Internal-Token` (antes 403) |
| `backend/cron_retos.php` | #16 | Idem + URL centralizada |
| `backend/cron_simulacros.php` | #16 | Idem |
| `backend/cron_inactividad.php` | #16 | Idem |
| `backend/admin/send_bulk.php` | #16 | sendMulticast por lotes de 500, `payload_json` con fallback, INSERT fuera del try |
| `backend/smart_notifications.php` | #16 | Bandeja en `payload_json` con fallback |

### Proyecto

| Ruta | Motivo | Cambio principal |
|------|--------|------------------|
| `.gitignore` | #11 | Excepción para `uploads/avatars/.gitkeep` |
| `README.md` | #0 | Reescrito para 2.0: novedades, migraciones 001-009, mapa de docs |

## 🗑️ ARCHIVOS ELIMINADOS (4)

| Ruta | Motivo (verificado) |
|------|---------------------|
| `lib/services/plan_service.dart` | Código muerto: `fetchPlanStatus` era TODO sin llamadas, `updatePremiumStatus` sin usos |
| `lib/widgets/access_wrapper.dart` | Sin usos (el paywall real vive en course_list + upgrade) |
| `lib/widgets/question_table.dart` | Import roto (`models/question.dart` inexistente) y sin usos |
| `backend/CAMBIOS_v1.5.1.md` | Duplicado histórico (conservado en `docs/history/`) |

## 📦 ARCHIVOS MOVIDOS (15)

14 documentos históricos (v1.5–v1.7) → `docs/history/`;
`INSTALAR.md` y `DESPLIEGUE_WEB.md` → `docs/`. Contenido intacto (R100).

---

## Pasos posteriores recomendados

1. Aplicar los cambios (bundle o parches) y hacer push.
2. Ejecutar en producción: `migrations/008_codigos_premium.sql` y
   `migrations/009_course_catalog.sql` (con fallback seguro si se retrasan).
3. Completar la configuración manual de FCM
   (`GUIA_ACTIVACION_NOTIFICACIONES_SABERPLUS.md` §4).
4. `flutter analyze` + build en el entorno del propietario (aquí no hay SDK
   de Flutter/PHP; la validación fue estructural y de integración).
5. Pruebas externas del checklist (§ Pruebas del reporte).
