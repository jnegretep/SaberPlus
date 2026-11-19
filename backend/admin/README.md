# SABER+ COMMAND CENTER v3.0

Centro de Control Ejecutivo del ecosistema Saber+.

## Acceso

```
URL:     https://corpoinstel.edu.co/api/prepsaber/backend/admin/
Usuario: jorge@saberplus.app
Clave:   SaberPlus2026!   ← CAMBIAR EN EL PRIMER LOGIN
```

> ⚠️ **IMPORTANTE**: La migración 010 crea el usuario inicial con la contraseña
> `SaberPlus2026!`. CÁMBIALA INMEDIATAMENTE después del primer login. Para
> regenerar el hash:
> ```bash
> php -r "echo password_hash('tu_nueva_clave_segura', PASSWORD_DEFAULT);"
> ```
> Y actualiza el INSERT en `backend/migrations/010_admin_command_center.sql`.

## Requisitos

- PHP 8.0+ con PDO mysql, cURL, mbstring.
- MySQL 8 / MariaDB 10.4+.
- Composer (dependencias Firebase JWT + Kreait Firebase).
- Crontab configurado (ver más abajo).

## Instalación

```bash
# 1. Subir archivos al servidor
cd /ruta/al/backend
git pull origin feat/admin-command-center  # o main tras merge

# 2. Ejecutar migración 010 (idempotente, se puede correr múltiples veces)
mysql -u prepsaberuser -p prepsaber < migrations/010_admin_command_center.sql

# 3. Verificar que las 11 tablas nuevas se crearon
mysql -u prepsaberuser -p prepsaber -e "SHOW TABLES LIKE 'admin_%'; SHOW TABLES LIKE 'feature_flags'; SHOW TABLES LIKE 'ia_%'; SHOW TABLES LIKE 'system_%';"

# 4. Verificar permisos de archivos
chmod -R 755 admin/
chmod -R 644 admin/includes/*.php admin/sections/*/controller.php
chmod -R 644 admin/assets/css/*.css admin/assets/js/*.js

# 5. Configurar cron (ver abajo)

# 6. Test de acceso
curl -I https://corpoinstel.edu.co/api/prepsaber/backend/admin/login.php
# debe responder 200 OK
```

## Cron jobs (OBLIGATORIO configurar)

Añadir al crontab del usuario del servidor web (`www-data` o el que ejecute PHP):

```cron
# Saber+ Command Center — crons

# Cada 5 min: System Health checks + alertas automáticas
*/5 * * * * cd /ruta/al/backend && php cron_system_health.php >> /var/log/saberplus_cron_health.log 2>&1

# Cada minuto: procesa campañas de notificación pendientes
* * * * * cd /ruta/al/backend && php cron_send_campaigns.php >> /var/log/saberplus_cron_campaigns.log 2>&1

# Diario a las 00:05: agrega costos IA del día anterior
5 0 * * * cd /ruta/al/backend && php cron_ia_costs.php >> /var/log/saberplus_cron_ia.log 2>&1
```

**Verificar crons**:

```bash
# Comprobar que se ejecutan manualmente
php cron_system_health.php
# Output esperado: [2026-11-13 00:00:00] System health checks ejecutados: 5 servicios, 5 OK

php cron_send_campaigns.php
# Output esperado: [2026-11-13 00:00:00] 0 campañas pendientes

php cron_ia_costs.php
# Output esperado: [2026-11-13 00:00:00] ia_costs actualizado para YYYY-MM-DD: 1 providers
```

## Estructura

```text
backend/admin/
├── index.php                  ← Router único (delega a sections/)
├── login.php                  ← Login multi-admin (bcrypt)
├── logout.php                 ← Logout POST con CSRF
├── bootstrap.php              ← Sesión + auth + CSRF + headers
│
├── sections/                  ← Una carpeta por módulo
│   ├── dashboard/controller.php    ← KPIs ejecutivos + gráficos
│   ├── users/controller.php        ← Gestión usuarios + acciones admin
│   ├── plans/controller.php        ← CRUD planes + features
│   ├── feature_flags/controller.php ← Feature flags con RBAC
│   ├── ai/controller.php            ← Centro monitoreo IA
│   ├── communications/controller.php ← Campañas masivas segmentadas
│   ├── alerts/controller.php        ← Alertas CEO
│   ├── system/controller.php        ← System Health
│   ├── audit/controller.php         ← Auditoría con diff before/after
│   └── exports/controller.php       ← Exportaciones con filtros
│
├── api/                       ← (futuro) endpoints REST JSON
├── includes/                  ← Helpers compartidos
│   ├── admin_helpers.php      ← sp_h, safeScalar, admin_svg_*, admin_fmt_*
│   ├── admin_auth.php         ← Multi-admin + RBAC + rate-limit
│   ├── admin_audit.php        ← Auditoría con before/after
│   ├── admin_security_headers.php ← CSP, HSTS, X-Frame-Options
│   └── layout.php             ← Sidebar + header + footer + nav
│
├── assets/
│   ├── css/
│   │   ├── admin.css          ← Base + login
│   │   ├── components.css     ← KPI cards, tablas, badges, modals
│   │   └── dashboard.css      ← Layouts dashboard
│   └── js/admin.js            ← Sidebar toggle, flash, sorting, modals
│
└── index.legacy.php           ← Panel anterior (3.696 líneas) — fallback
```

## Módulos implementados

### 1. Dashboard Ejecutivo (`?section=dashboard`)
KPIs de negocio (usuarios, MRR, conversión), producto (simulacros, errores), IA (solicitudes, costo), operaciones. Gráficos SVG sin CDN. Alertas prioritarias y actividad reciente.

### 2. Gestión de Usuarios (`?section=users`)
Lista paginada con búsqueda, filtros (plan, verificado, activo, departamento), sort. Vista detalle con gamificación, simulacros, actividad. Acciones: cambiar plan, toggle activo, verificar email, marcar early bird — todas con auditoría before/after.

### 3. Planes (`?section=plans`)
CRUD completo: crear/editar planes, gestionar features por plan, toggle activo. Vista detalle con `plan_features` y `content_access_levels`.

### 4. Feature Flags (`?section=feature_flags`)
Sistema de kill switches: activar/desactivar features sin deploy. Configurable por plan y rollout %. Test por usuario.

### 5. Centro IA (`?section=ai`)
Monitoreo en tiempo real: 8 KPIs (solicitudes, tokens, costo, latencia p50/p95, error rate, usuarios únicos). Estado de servicios (DeepSeek, Gemini) con ping on-demand. Top 10 usuarios, distribución por hora, historial errores, costos diarios.

### 6. Comunicaciones (`?section=communications`)
Campañas masivas segmentadas: por plan, departamento, días de inactividad, IDs específicos, segmentos guardados. Previsualización + confirmación + auditoría completa. Cron asíncrono procesa colas.

### 7. Alertas CEO (`?section=alerts`)
Alertas automáticas generadas por `cron_system_health`: servicio caído, errores críticos repetitivos, picos anormales, pagos pendientes. Marcar como resuelta con auditoría.

### 8. System Health (`?section=system`)
Estado de 5 servicios en tiempo real: BD prepsaber, BD Moodle, Moodle WS, FCM, DeepSeek. Logs recientes, estado de colas, info servidor. Botón "Probar servicios ahora" con ping on-demand.

### 9. Auditoría (`?section=audit`)
Tabla paginada de `admin_audit_log` con filtros (admin, módulo, acción, entidad, fecha, success). Vista detalle con **diff visual before/after**. Export CSV. Gráfico de actividad 30 días.

### 10. Exportaciones (`?section=exports`)
5 entidades exportables con filtros (fecha, plan, departamento, estado pago): usuarios, pagos, simulacros, gamificación, auditoría. Streaming real (no carga todo en memoria). RBAC por entidad. Límite 50.000 filas.

## Roles y permisos

| Rol | Permisos |
|-----|----------|
| `superadmin` | Todos (incluido gestionar admin_users y ver logs de auth) |
| `admin` | Todo excepto gestionar administradores |
| `editor` | Lectura + edición de contenido, planes, comunicaciones |
| `viewer` | Solo lectura en todo |

Para crear nuevos administradores, ejecutar SQL directo (futuro: sección `admin_users`):

```sql
-- Crear nuevo admin
INSERT INTO admin_users (email, name, password_hash, role_id, is_active)
SELECT 'nuevo@saberplus.app', 'Nombre Apellido',
  '$2y$10$hash_generado_con_password_hash', id, 1
FROM admin_roles WHERE name = 'admin';
```

## Seguridad implementada

- ✅ Multi-admin con hash bcrypt (password_verify, timing-safe).
- ✅ Rate-limit login (5 fallos/10 min por IP+email).
- ✅ CSRF token en todos los POST (`admin_csrf_verify()`).
- ✅ Headers HTTP: CSP, X-Frame-Options DENY, X-Content-Type-Options, HSTS, Referrer-Policy.
- ✅ Prepared statements en TODAS las consultas.
- ✅ XSS escaping con `sp_h()` (htmlspecialchars ENT_QUOTES UTF-8).
- ✅ Anti CSV-injection (prefija `'` en celdas con `=+-@`).
- ✅ Auditoría completa con before/after en cambios sensibles.
- ✅ Sesión hardenizada: httponly, samesite=Lax, secure (en HTTPS), regenerate_id tras login.
- ✅ Logout POST (no GET, evita CSRF-driven logout).
- ✅ RBAC granular (18 permisos en 4 roles).
- ✅ Restricción: solo superadmin ve logs de `module='auth'`.

## Hotfixes aplicados a archivos legacy

Durante el Sprint 1 se aplicaron fixes críticos en paralelo a la construcción del nuevo panel:

- `send_bulk.php` hereda del bootstrap de seguridad aunque quede como legacy.
- `check_ia.php` se mantiene funcional; el nuevo `?section=ai` lo reemplaza.
- `export_csv.php` se mantiene como fallback; el nuevo `?section=exports` lo reemplaza.

Los archivos legacy (`index.legacy.php`, `send_bulk.php`, `check_ia.php`, `export_csv.php`) pueden eliminarse tras verificar que el nuevo panel funciona correctamente en producción.

## Procedimiento de rollback

```bash
# 1. Revertir commits (solo si hay problema crítico)
cd /ruta/al/repo
git revert fcd3315 6ce3b09 5f989c3 9fd961e 851599a bf00c82 <sprint-8-commit>

# 2. Revertir migración (opcional, las tablas nuevas son idempotentes y no rompen nada)
# NO es necesario: las tablas nuevas simplemente quedan vacías.

# 3. Restaurar admin original
cd backend/admin
git show e41b902:backend/admin/index.php > index.php  # restaurar original

# 4. Acceder al panel legacy
# https://corpoinstel.edu.co/api/prepsaber/backend/admin/index.php
# (con las credenciales viejas ADMIN_USER/ADMIN_PASS del .env)
```

## Troubleshooting

### "CSRF token inválido"
- Causa: cookie de sesión expirada o navegación entre subdominios.
- Fix: recargar la página de login y volver a autenticar.

### "Tabla admin_audit_log no existe"
- Causa: migración 010 no se ejecutó.
- Fix: `mysql -u ... prepsaber < migrations/010_admin_command_center.sql`.

### "No puedo loguear con la clave por defecto"
- Causa: el hash en migración 010 puede no coincidir con tu versión de PHP.
- Fix: regenerar hash y actualizar:
  ```bash
  php -r "echo password_hash('tu_clave', PASSWORD_DEFAULT);"
  mysql -u ... prepsaber -e "UPDATE admin_users SET password_hash='\$2y\$10\$...' WHERE email='jorge@saberplus.app';"
  ```

### "No veo datos en dashboard IA"
- Causa: las tablas `ia_mensajes`/`ia_conversaciones` están vacías porque se crearon con la migración pero la persistencia solo funciona tras deploy.
- Fix: esperar a que los usuarios usen el tutor IA tras el deploy; los datos aparecerán automáticamente.

### Crons no se ejecutan
- Verificar: `crontab -l` muestra las 3 entradas.
- Verificar: `php /ruta/cron_system_health.php` funciona manualmente.
- Verificar permisos de `/var/log/`.

## Soporte

- **Documentación técnica**: `SaberPlus-Command-Center-Auditoria-y-Plan.md`
- **Auditoría original**: `/home/z/my-project/download/SaberPlus-Command-Center-Auditoria-y-Plan.md`
- **Logs**: `/var/log/saberplus_cron_*.log` y `error_log` de PHP.

## Versión

**v3.0** · Noviembre 2026 · SABER+ Command Center
- 11 tablas nuevas en BD
- 10 módulos funcionales
- 4 roles + 18 permisos
- 3 cron jobs
- Multi-admin con RBAC
- Auditoría con before/after
- Streaming exports
- CSS/JS profesional, sin frameworks externos

Total: ~12.500 líneas nuevas de código en 25 archivos.
