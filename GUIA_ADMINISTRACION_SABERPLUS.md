# GUÍA DE ADMINISTRACIÓN — SABER+

**Para:** Equipo administrativo y operativo de Saber+
**Panel:** `https://tu-dominio/api/admin/` · **Versión:** Administration & Intelligence Center (transformación 2026-11)

---

## 1. ACCESO Y SEGURIDAD DEL PANEL

- Usuario y contraseña se definen en `backend/.env` (`ADMIN_USER` / `ADMIN_PASS`).
- **Tras 5 intentos fallidos** la cuenta queda bloqueada 10 minutos (por combinación IP+usuario).
- Todas las acciones sensibles quedan registradas en **Auditoría** (sección 2.10) con usuario, acción, entidad, IP y fecha.
- Para cambiar la contraseña: editar `.env` en el servidor y reiniciar PHP/Apache.

> 🔐 Recomendación operativa: usar una contraseña larga (≥16 caracteres) exclusiva del panel y no compartir la cuenta. El sistema de roles diferenciados (soporte/analista/coordinador) está en la hoja de ruta; hoy existe un solo administrador.

## 2. SECCIONES DEL PANEL

### 2.1 Dashboard (centro de control operativo)
KPIs del día: usuarios verificados, activos hoy/7 días, simulacros totales, promedio global, premium vs free, retos finalizados, XP total, notificaciones enviadas, nuevos registros.

**Nuevo — Dashboard ejecutivo:**
- **4 series de 30 días** (gráficos): nuevos registros/día, simulacros realizados/día, XP otorgada/día y usuarios activos únicos por día (DAU aproximado).
- **Salud del negocio:** conversión a premium (%), promedio global ICFES y tiempo medio por simulacro.

*Cómo usarlo:* revisa el embudo diario — si "registros" sube pero "simulacros/día" no, el problema es activación (onboarding/first simulacro). Si DAU cae en fin de semana, es candidato a reforzar notificaciones de racha.

### 2.2 Usuarios
Búsqueda y edición completa de cualquier cuenta: tipo (estudiante/profesor), nivel de acceso (free/premium/early_bird), verificación de email y estado activo. **Exportar CSV** para listados externos.

*Operativa:* un usuario reporta no ver contenido premium → verifica aquí su `access_level` y `email_verificado`.

### 2.3 Colegios (B2B) — directores
- **Crear director:** nombre, email, colegio, departamento y contraseña inicial (el panel sugiere una segura). El director la cambia al entrar.
- **Activar/desactivar director:** desactivar corta su sesión al instante.
- **Restablecer contraseña:** genera una nueva temporal y la muestra una sola vez — entrégala por un canal seguro.

### 2.4 Anuncios / 2.5 Planes
Vistas de solo lectura (los anuncios y planes se gestionan directamente en BD por ahora — hoja de ruta: gestión completa desde el panel).

### 2.6 Promociones
CRUD completo de promociones (banner/código), vigencias, cupos y plan asociado. *Operativa de campaña:* crea la promo con fecha de fin, asóciala al plan objetivo y desactívala manualmente si la campaña termina antes.

### 2.7 Notificaciones
Envío masivo de notificaciones push (FCM) a segmentos (todos / premium / free). Historial de envíos. El sistema limpia automáticamente tokens inválidos.

### 2.8 Soporte (quejas y sugerencias)
Bandeja de tickets con estados (pendiente / en proceso / resuelto / descartado), respuesta al usuario y vista de detalle. Los estudiantes ven la respuesta en su pantalla de Soporte.

### 2.9 Analítica (eventos de app)
Gráficos de eventos `app_events` por tipo y plataforma (los que la app reporta vía `registrar_evento`).

### 2.10 Auditoría (nuevo)
Últimas 50 acciones administrativas: quién, qué, sobre qué entidad, detalles y IP. Requiere la **migración 007** (§5). Si no está ejecutada, la sección lo indica y el registro queda deshabilitado sin afectar nada más.

### 2.11 Errores / 2.12 Actividad
- **Errores:** registros de `error_logs` con opción de marcar resueltos.
- **Actividad:** feed reciente de eventos de la plataforma.

### 2.13 Rankings institucionales / 2.14 Reportes
Top colegios y departamentos por XP; usuarios por ciudad/grado/departamento.

### 2.15 Ingresos (nuevo)
- Total recaudado (pagos aprobados), del mes, pendientes y compras Google Play.
- Reparto por pasarela (Wompi vs Play Billing) y conversión Free→Premium.
- Últimos 20 pagos con usuario, monto, estado y referencia. **Exportar CSV**.

*Operativa de conciliación:* cruza el total del mes con el extracto de Wompi; cualquier pago "pending" antiguo revísalo aquí antes de reclamar.

### 2.16 Académica (nuevo)
- **Promedio por área** de todos los simulacros (barras): detecta dónde pierde la base de estudiantes.
- **Distribución de puntajes globales** por rangos (0-100 … 400-500).
- **Top 10 colegios** por volumen de simulacros.
- **Heatmap área×grado:** rendimiento cruzado — ideal para reuniones con rectores (argumento de venta B2B).
- **Exportar CSV** de resultados.

*Cómo usarlo en una venta B2B:* abre el heatmap, filtra mentalmente el colegio del prospecto y muestra "sus estudiantes de grado 11 pierden en Matemáticas" → el panel de director del colegio le dará seguimiento nominal.

## 3. OPERACIONES DIARIAS RECOMENDADAS

| Frecuencia | Acción | Dónde |
|---|---|---|
| Diaria | Revisar series del dashboard (registros, simulacros, DAU) | Dashboard |
| Diaria | Bandeja de soporte (SLA sugerido: <24 h) | Soporte |
| Diaria | Error log (marcar resueltos) | Errores |
| Semanal | Envío de notificación de retención (racha/retos ya son automáticas) | Notificaciones |
| Semanal | Conciliación de ingresos | Ingresos |
| Mensual | Exportar usuarios/resultados para backup frío | Exportes CSV |
| Mensual | Revisar auditoría de acciones admin | Auditoría |

## 4. NOTIFICACIONES AUTOMÁTICAS (crons)

Tres procesos corren en el servidor (configúralos como cron del sistema, p. ej. cada 5–15 min):

| Cron | Función |
|---|---|
| `cron_retos.php` | Avisos de retos 1v1 por empezar (10 y 5 min antes) |
| `cron_simulacros.php` | Cierre/purga de simulacros |
| `cron_inactividad.php` + `smart_notifications.php` | "Tu racha está en riesgo" (≥3 días + 1 día sin actividad), recordatorios de inactividad y nuevo reto diario — máx. 1/día por usuario |

> Tras la transformación, estos scripts **rechazan invocaciones anónimas por HTTP**: ejecútalos por CLI (`php /ruta/cron.php`) o envía la cabecera `X-Internal-Token` definida en `.env`.

## 5. MIGRACIÓN 007 (necesaria para Auditoría)

```bash
mysql -u <usuario> -p <basedatos> < backend/migrations/007_admin_intelligence.sql
```
Crea `admin_audit_log`. Sin ejecutarla: la sección Auditoría muestra un aviso y el registro de acciones queda deshabilitado — **nada más se ve afectado**.

## 6. SOLUCIÓN DE PROBLEMAS FRECUENTES

| Síntoma | Causa probable | Solución |
|---|---|---|
| "Panel de administración no configurado" | Faltan ADMIN_USER/ADMIN_PASS en `.env` | Definirlos y reiniciar PHP |
| Login admin bloqueado siempre | 5 fallos recientes | Esperar 10 min (o limpiar `/tmp/saberplus_admin_rl_*`) |
| Serie del dashboard vacía | Tabla origen sin datos o columna distinta en tu versión | La tarjeta se degrada; revisa `error_log` |
| Notificación masiva llega a pocos | Tokens muertos | Es automático: se limpian en cada envío |
| Auditoría vacía tras migrar 007 | Tabla creada pero sin acciones aún | Realiza cualquier acción admin y refresca |
| Correos no salen | SMTP_PASS sin configurar en `.env` (cuenta institucional) | Generar app-password de Gmail y definirla |
| Series "este mes" de Ingresos en 0 | `payments.created_at` inexistente en tu esquema | Degradación prevista; revisa `error_log` |

## 7. BUENAS PRÁCTICAS

1. **Nunca** compartas la contraseña del panel por chat sin cifrar.
2. Revisa **Auditoría** si sospechas acceso no autorizado.
3. Antes de desactivar un usuario, revisa su historial en Soporte (puede tener caso abierto).
4. Usa **Exportar CSV** antes de operaciones masivas manuales sobre la BD.
5. Los respaldos de BD son tu única reversa: verifica que el backup automático exista y restaúralo en un entorno de prueba al menos una vez al trimestre.
