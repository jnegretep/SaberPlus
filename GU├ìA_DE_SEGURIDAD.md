# 🔐 Guía de Seguridad — Cierre de Brechas y Rotación de Credenciales

> **Estado: ACCIÓN REQUERIDA INMEDIATA**
>
> Durante la auditoría de septiembre de 2026 se detectó que credenciales
> reales de producción estuvieron commiteadas en el repositorio **público**
> de GitHub. Aunque este commit las elimina del código, **permanecen en el
> historial de git** y deben considerarse COMPROMETIDAS.
>
> Este documento explica, paso a paso, qué rotar, dónde y en qué orden.

---

## ⏱️ Resumen de acciones (en orden de urgencia)

| # | Acción | Dónde | Urgencia |
|---|--------|-------|----------|
| 1 | Rotar llaves de Wompi (producción) | Panel Wompi | 🔴 HOY |
| 2 | Rotar secreto JWT | backend/.env | 🔴 HOY |
| 3 | Cambiar contraseña BD `jnegretep` | Servidor MySQL | 🔴 HOY |
| 4 | Revocar app passwords de Gmail | Cuenta Google | 🔴 HOY |
| 5 | Rotar API key de DeepSeek | platform.deepseek.com | 🔴 HOY |
| 6 | Cambiar token del Web Service de Moodle | Moodle (admin) | 🟠 Esta semana |
| 7 | Crear backend/.env con los NUEVOS valores | Servidor | 🟠 Junto con el deploy |
| 8 | Purgar el historial de git + hacer el repo privado | GitHub | 🟠 Esta semana |
| 9 | Verificar pagos y usuarios premium anómalos | BD | 🟡 Revisar |
| 10 | Endurecer Apache/.htaccess | Servidor | 🟡 Junto con el deploy |

---

## 1️⃣ Rotación de llaves Wompi (pasarela de pagos) — 🔴 CRÍTICO

**Qué estaba expuesto** (`backend/wompi_config.php`):
- `private_key` de producción
- `events_secret` (firma de webhooks)
- `integrity` (firma de checkouts)

**Riesgo**: con el `integrity` filtrado se podía alterar el monto de un
checkout; con `events_secret` se podían falsificar webhooks. El nuevo
código verifica monto+moneda en el webhook, pero las llaves filtradas
siguen siendo válidas hasta que las rotes.

**Pasos:**
1. Entra al panel de Wompi (https://dashboard.wompi.co).
2. En Configuración → API Keys, genera un nuevo par de llaves
   públicas/privadas de producción.
3. Regenera el `events_secret` (Configuración → Webhooks).
4. Copia el nuevo `integrity` secreto.
5. Pon los 4 valores nuevos en `backend/.env` (ver sección 7).
6. Prueba el flujo completo: comprar un plan de prueba con tarjeta PSE
   y verificar que el webhook active premium.

## 2️⃣ Rotación del secreto JWT — 🔴 CRÍTICO

**Qué estaba expuesto** (`backend/jwt_config.php`): el secreto HS256.

**Riesgo**: cualquiera podía falsificar tokens de CUALQUIER usuario.

**Pasos:**
1. Genera un secreto nuevo:
   ```bash
   openssl rand -hex 32
   ```
2. Ponlo como `JWT_SECRET` en `backend/.env`.
3. Deploy. **Efecto colateral esperado**: todas las sesiones activas se
   invalidan (los usuarios deben volver a iniciar sesión). Es el
   comportamiento correcto tras una rotación.

## 3️⃣ Contraseña de la base de datos — 🔴 CRÍTICO

**Qué estaba expuesto** (`backend/includes/conexion.php`):
usuario `jnegretep` y su contraseña.

**Pasos:**
```sql
-- En MySQL, como root:
ALTER USER 'jnegretep'@'localhost' IDENTIFIED BY 'NuevaClaveMuyLargaYAleatoria!';
FLUSH PRIVILEGES;
```
Además (recomendado): crea un usuario dedicado con permisos SOLO sobre
la base `prepsaber`, en vez de usar una cuenta personal:
```sql
CREATE USER 'saberplus_app'@'localhost' IDENTIFIED BY '...';
GRANT SELECT, INSERT, UPDATE, DELETE ON prepsaber.* TO 'saberplus_app'@'localhost';
```
Actualiza `DB_USER`/`DB_PASS` en `backend/.env`.

## 4️⃣ App passwords de Gmail — 🔴 CRÍTICO

**Qué estaba expuesto**: DOS app passwords distintas (en `register.php`
y `forgot_password.php`).

**Pasos:**
1. Ve a https://myaccount.google.com/security
2. "Contraseñas de aplicaciones" (o "Verificación en 2 pasos" →
   Contraseñas de aplicaciones).
3. **Revoca ambas** app passwords filtradas.
4. Genera una nueva y ponla como `SMTP_PASSWORD` en `backend/.env`.
5. Prueba el registro de un usuario nuevo (debe llegar el correo).

> 💡 Recomendación a futuro: migra el envío de correos a un servicio
> transaccional (Brevo, Resend, Amazon SES) — Gmail tiene límites de
> envío y no está pensado para producción.

## 5️⃣ API key de DeepSeek — 🔴 CRÍTICO

**Qué estaba expuesto**: la API key completa (en `api_ia.php` — ya
eliminado — y `api_saber_plus_ia.php`).

**Pasos:**
1. Entra a https://platform.deepseek.com → API Keys.
2. **Elimina** la clave filtrada.
3. Crea una clave nueva y ponla como `DEEPSEEK_API_KEY` en `backend/.env`.
4. Revisa el historial de consumo: si ves uso anómalo (miles de llamadas
   que no corresponden a tus usuarios), repórtalo a soporte DeepSeek.

## 6️⃣ Token del Web Service de Moodle — 🟠 ALTO

**Qué estaba expuesto** (`backend/includes/config.php`): token con
permisos de lectura/escritura.

**Pasos:**
1. Entra a Moodle como administrador del sitio.
2. Administración del sitio → Plugins → Servicios web → Tokens.
3. **Elimina** el token filtrado.
4. Crea uno nuevo (mismo servicio, permisos mínimos necesarios).
5. Ponlo como `MOODLE_WS_TOKEN` en `backend/.env`.
6. Verifica en los logs del servidor que no hubo uso anómalo del token
   (búsqueda de `wstoken` en access logs).

## 7️⃣ Crear backend/.env en el servidor

Después de rotar TODO lo anterior:

```bash
cd /var/www/html/api/prepsaber/backend   # o tu ruta de deploy
cp .env.example .env
nano .env    # rellena TODOS los valores con los NUEVOS
chmod 640 .env
chown www-data:www-data .env   # que Apache pueda leerlo, nadie más
```

⚠️ **El backend no funcionará hasta que exista .env** — es un fallo
intencional (fail-closed) para que ninguna credencial vuelva al código.

## 8️⃣ Purgar el historial de git y privatizar el repo

Las credenciales siguen visibles en commits antiguos aunque el código
actual esté limpio. Dos opciones:

**Opción A (recomendada, más segura): hacer el repo privado**
- GitHub → Settings → General → Danger Zone → Change visibility → Private.
- Esto elimina el acceso público inmediato (clones existentes no se
  borran, pero con las credenciales rotadas ya no sirven de nada).

**Opción B: reescribir el historial** (si el repo debe seguir público)
```bash
# Con git-filter-repo (más rápido y moderno que BFG):
pip install git-filter-repo
cd SaberPlus
git filter-repo --replace-text <(echo '37663518c05c753401b5fa535ceb7316==>REMOVED')
# (repetir una línea por cada secreto filtrado, con las llaves Wompi,
#  el secreto JWT, la contraseña BD, los app passwords de Gmail,
#  la API key de DeepSeek y las credenciales admin)
git push --force --all
```
⚠️ Reescribir el historial requiere coordinación si hay más clones.

**Además, en cualquier caso:**
- GitHub → Settings → Developer settings → Personal access tokens:
  revoca los que no reconozcas.
- Revisa Settings → Deploy keys y colaboradores del repo.

## 9️⃣ Verificar daños en la base de datos

Con las brechas anteriores, ejecuta estas verificaciones:

```sql
-- ¿Cuentas premium sin pago aprobado? (bypass del endpoint viejo)
SELECT u.id_usuario, u.nombre, u.email, u.unlocked_at
FROM usuarios u
LEFT JOIN payments p ON p.user_id = u.moodle_id AND p.status = 'approved'
WHERE u.access_level = 'premium' AND p.id IS NULL;

-- ¿Pagos aprobados con montos que no coinciden con ningún plan?
SELECT reference_code, amount, currency, status
FROM payments WHERE status = 'approved'
AND amount NOT IN (SELECT price FROM plans WHERE is_active = 1);

-- ¿Cambios de contraseña recientes sospechosos? (tomar nota de unlocked_at/updated_at)
SELECT id_usuario, email, moodle_username FROM usuarios
ORDER BY id_usuario DESC LIMIT 50;
```

Si la primera consulta devuelve filas, revísalas manualmente: o son
cuentas de prueba, o son usos del bypass (que ya está cerrado).

## 🔟 Endurecimiento del servidor (Apache)

Crea/edita `backend/.htaccess` (o la configuración del VirtualHost):

```apache
# Bloquear acceso directo a archivos sensibles
<FilesMatch "\.(env|log|sql|json|md)$">
    Require all denied
</FilesMatch>
<FilesMatch "^(env\.php|jwt_config\.php|wompi_config\.php)$">
    # env.php solo si nadie lo llama por HTTP (es incluido, no endpoint)
    Require all denied
</FilesMatch>

# Forzar HTTPS
RewriteEngine On
RewriteCond %{HTTPS} off
RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
```

En `php.ini` del servidor:
```ini
display_errors = Off
log_errors = On
```

Y verifica que la cuenta del servicio `saberplus-1ec41-firebase-adminsdk-*.json`
(clave de servicio FCM, también en el repo) tenga permisos restringidos
en la consola de Firebase — idealmente regenerarla también.

---

## ✅ Checklist final antes de lanzar

- [ ] Las 5 rotaciones críticas completadas (Wompi, JWT, BD, Gmail, DeepSeek)
- [ ] Token Moodle rotado
- [ ] `backend/.env` creado en el servidor con los valores NUEVOS
- [ ] Flujo de registro + verificación de correo probado
- [ ] Flujo de compra premium probado de punta a punta (webhook OK)
- [ ] Cambio de contraseña probado (ahora exige la contraseña actual)
- [ ] Notificaciones push llegan (FCM)
- [ ] Cron jobs actualizados (CLI o con cabecera X-Internal-Token)
- [ ] Repo privado (o historial purgado) + 2FA en GitHub
- [ ] Consultas de verificación de BD sin resultados anómalos

## 🗺️ Mejoras de seguridad recomendadas (fase 2, post-lanzamiento)

1. **Rate limiting** en login / forgot_password / verify_reset_code
   (tabla de intentos fallidos + bloqueo temporal, o fail2ban).
2. **Unificar el middleware de auth** (existe `auth_middleware.php` y
   `middleware/auth_middleware.php` + código muerto de otro proyecto en
   `config/`, `controllers/` — eliminar).
3. **Tomar el user_id del JWT en TODOS los endpoints** que hoy lo aceptan
   del body (stats/*, get_notifications, mark_notification_read,
   simulacros/save_result).
4. **Validación real de avatares** (finfo MIME + tamaño máximo 2 MB +
   re-encode con GD; hoy acepta cualquier base64).
5. **XP y puntajes calculados en el servidor** (hoy el cliente reporta
   su propia XP y sus puntajes de simulacro).
6. **Play Billing para productos digitales en Android** (la política de
   Google exige Google Play Billing para contenido digital consumido en
   la app; Wompi puede seguir para web/B2B).
