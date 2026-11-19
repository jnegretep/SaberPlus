# CHECKLIST DE LANZAMIENTO — SABER+

**Fecha:** 5 de noviembre de 2026 · **Versión candidata:** transformación sobre v1.7.1 (rama `feature/transformacion-edtech`)

Cómo usar: marca ✅ solo cuando la verificación real esté hecha (no "debería funcionar"). Los bloques A–C son bloqueantes; D–E son post-lanzamiento.

---

## A. SEGURIDAD (BLOQUEANTE — antes de cualquier despliegue público)

- [ ] **A1.** Generar NUEVO secreto JWT (≥32 chars): `openssl rand -hex 32` → definir `JWT_SECRET` en `backend/.env` del servidor.
- [ ] **A2.** Rotar contraseña de la BD MySQL y definir `DB_HOST/DB_NAME/DB_USER/DB_PASS` en `.env`.
- [ ] **A3.** Rotar las 4 claves en el panel de Wompi → `WOMPI_PUBLIC_KEY / WOMPI_PRIVATE_KEY / WOMPI_EVENTS_SECRET / WOMPI_INTEGRITY_SECRET` en `.env`.
- [ ] **A4.** Rotar el token de servicios web de Moodle → `MOODLE_WS_TOKEN` en `.env`.
- [ ] **A5.** Credenciales BD de Moodle → `MOODLE_DB_*` en `.env`.
- [ ] **A6.** Generar app-password de Gmail para **Saberplus2026@gmail.com** → `SMTP_USER / SMTP_PASS / SMTP_FROM / SMTP_FROM_NAME` en `.env`.
- [ ] **A7.** Probar un registro y una recuperación de contraseña (llegan los correos).
- [ ] **A8.** Borrar los **fallbacks** de: `jwt_config.php`, `includes/conexion.php`, `wompi_config.php`, `includes/config.php`, `includes/moodle_db.php`, `register.php`, `forgot_password.php`, `resend_verification.php` (cada uno marca con "ROTAR"/"fallback" en comentarios). Con `.env` completo, si algo falla aparecerá en `error_log`.
- [ ] **A9.** Purgar el historial git de secretos (ver §6 al final).
- [ ] **A10.** Verificar en el servidor que `backend/.env` NO es descargable por web: `curl -s https://tu-dominio/api/.env` debe dar 403/404. Si lo sirve: añadir a la config de Apache `<FilesMatch "\.(env|sql|log)$"> Require all denied </FilesMatch>`.
- [ ] **A11.** Confirmar que los crons del servidor corren por **CLI** (`php /ruta/cron_retos.php`) o, si son HTTP, definir `INTERNAL_TOKEN` en `.env` y añadir la cabecera `X-Internal-Token` a la invocación.
- [ ] **A12.** Probar el fraude cerrado: `POST /api/upgrade_to_premium.php` con JWT válido y sin reference → debe responder `400 {"error":"pago_requerido"}`.

## B. COMPILACIÓN Y PRUEBAS DE REGRESIÓN (BLOQUEANTE)

- [ ] **B1.** `flutter pub get` sin errores.
- [ ] **B2.** `flutter analyze` — 0 errores (warnings de estilo aceptables).
- [ ] **B3.** `flutter build web --release` exitoso.
- [ ] **B4.** `flutter build apk --release` exitoso (Gradle 8.14.3 ya migrado por el propietario).
- [ ] **B5.** Login con usuario de prueba (estudiante) en móvil.
- [ ] **B6.** Login en web.
- [ ] **B7.** Registro completo de un usuario nuevo (2 pasos → verificación email → contraseña) — llega el correo institucional.
- [ ] **B8.** Onboarding: el usuario nuevo ve el tour una vez; "Saltar" funciona; Configuración → "Ver tour de bienvenida" lo relanza.
- [ ] **B9.** Checklist "Empieza con buen pie" visible en dashboard del usuario nuevo y se oculta al completar.

## C. PRUEBAS DE NAVEGACIÓN WEB (BLOQUEANTE — protocolo del fix)

Ejecutar en Chrome/Edge/Firefox en la build web:

- [ ] **C1.** Dashboard → "Ver todo" de Simulacros → la URL cambia a `/courses?...` y el back del navegador regresa al dashboard.
- [ ] **C2.** Cursos → abrir un curso → URL `/course-contents/...` → navegar contenidos → back del navegador funciona en cada paso.
- [ ] **C3.** Entrar a un quiz: URL `/quiz-intro/...` → "Comenzar simulacro" → overlay "Estamos preparando tu simulacro" → cuestionario con URL `/question`.
- [ ] **C4.** Finalizar el simulacro → revisión con URL `/review` → **back del navegador** NO vuelve al cuestionario (regresa a la ficha/contenidos).
- [ ] **C5.** Al terminar: aparece celebración y la XP subió +100 (ver en header de gamificación). Repetir revisión → NO otorga otra vez (dedup).
- [ ] **C6.** F5 (recarga) estando en `/question` → pantalla "Esta pantalla no puede abrirse directamente" con botón Volver al inicio (sin crash).
- [ ] **C7.** Campanita de notificaciones → URL `/notifications` → back funciona.
- [ ] **C8.** FAB "Saber+ IA" → URL `/chat`.
- [ ] **C9.** Estadísticas → Comparativas/Ranking/Tendencia → cada una con URL → back funciona.
- [ ] **C10.** Cambiar entre tabs del menú inferior varias veces → el back del navegador NO deshace los cambios de pestaña (sale o vuelve a la página previa).
- [ ] **C11.** Sesión expirada (borrar tokens en devtools y navegar) → redirige a login sin crash.
- [ ] **C12.** Cerrar sesión → login → volver a entrar → flujo normal.
- [ ] **C13.** Móvil Android: back físico en el cuestionario y en la revisión se comporta (no interfiere).

## D. FCM / NOTIFICACIONES (antes del lanzamiento comercial)

- [ ] **D1.** Con el service account en `config/firebase-service-account.json`, enviar prueba desde el panel admin → Notificaciones → envío masivo a 1 usuario.
- [ ] **D2.** Móvil: notificación recibida en primer y segundo plano; tap abre la app.
- [ ] **D3.** Web (Chrome): permiso solicitado tras login; token registrado (ver `register_fcm_token` en logs); notificación visible con la pestaña abierta.
- [ ] **D4.** Los 3 crons corren (`php cron_retos.php` manual con usuario en reto activo) → llega el aviso 10/5 min.

## E. PANEL ADMINISTRATIVO

- [ ] **E1.** Login admin sobrevive 6 intentos fallidos (lock 10 min).
- [ ] **E2.** Migración 007 ejecutada: `mysql -u root -p prepsaber < backend/migrations/007_admin_intelligence.sql`.
- [ ] **E3.** Sección Auditoría registra acciones (crear director, guardar promo).
- [ ] **E4.** Dashboard ejecutivo muestra las 4 series con datos.
- [ ] **E5.** Exportes CSV de usuarios/resultados/pagos descargan y abren bien en Excel.
- [ ] **E6.** Sección Ingresos cuadra con los pagos reales de prueba.

## F. POST-LANZAMIENTO (primera semana)

- [ ] **F1.** Revisar `error_log` diario (búsquedas de "ADVERTENCIA" = fallbacks aún activos).
- [ ] **F2.** Monitorear la serie "Nuevos registros/día" y "Simulacros/día" del panel.
- [ ] **F3.** Verificar rate-limit de login no bloquea colegios (comparten IP) — ajustar constante si hay quejas.
- [ ] **F4.** Backup BD programado (verificar el existente).

---

## 6. PROCEDIMIENTO: PURGAR SECRETOS DEL HISTORIAL GIT

> ⚠️ Reescribe el historial: coordina con cualquier colaborador antes. Haz backup del repo primero.

```bash
# 1. Backup
cp -r SaberPlus SaberPlus_backup_$(date +%F)

# 2. Instalar la herramienta (requiere git >= 2.22)
pip3 install git-filter-repo

# 3. Lista de archivos con secretos a purgar (valores antiguos)
cd SaberPlus
cat > /tmp/archivos_secretos.txt <<'EOF'
backend/jwt_config.php
backend/includes/conexion.php
backend/wompi_config.php
backend/includes/config.php
backend/includes/moodle_db.php
backend/register.php
backend/forgot_password.php
backend/resend_verification.php
backend/update_hash.php
EOF

# 4. Reescribir el historial (conserva los archivos, borra su contenido antiguo
#    de todos los commits) — SOLO después de rotar TODAS las credenciales:
git filter-repo --paths-from-file /tmp/archivos_secretos --invert-paths --force

# 5. Re-publicar
git remote add origin https://github.com/jnegretep/SaberPlus.git
git push origin --force --all
git push origin --force --tags
```

Los valores rotados en A1–A6 quedan inútiles, por lo que la purga es segura incluso si alguien clonó el historial antiguo. El orden correcto es: **rotar primero, purgar después**.

## 7. LANZAMIENTO — CRITERIO FINAL

**NO lanzar** si queda pendiente cualquier ítem de las secciones A, B o C. El producto transformado queda en estado "listo para lanzamiento" únicamente cuando este checklist esté completo en el entorno real del propietario.
