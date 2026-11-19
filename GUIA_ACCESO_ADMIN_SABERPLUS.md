# Guía de acceso y administración — Panel Admin de Saber+

**Versión 2.0 · Noviembre 2026**

> ⚠️ Esta guía **no contiene contraseñas reales**. Los valores se configuran
> en el servidor por el propietario.

## 1. Ruta real del panel

El panel vive en el backend, junto al resto de la API:

```
https://corpoinstel.edu.co/api/prepsaber/backend/admin/index.php
```

(en general: `https://TU_SERVIDOR/api/prepsaber/backend/admin/index.php`)

Archivos del panel:

| Archivo | Función |
|---------|---------|
| `backend/admin/index.php` | Panel completo (todas las secciones) |
| `backend/admin/export_csv.php` | Exportación CSV (usuarios / resultados / pagos) |
| `backend/admin/send_bulk.php` | Envío masivo de notificaciones FCM |
| `backend/admin/check_ia.php` | Diagnóstico del tutor IA (DeepSeek/Gemini) |
| `backend/admin/includes/admin_audit.php` | Helper de auditoría |

## 2. Sistema de autenticación real

- **No hay tabla de administradores ni roles múltiples en BD.** Existe un
  único par usuario/contraseña definido en variables de entorno:
  `backend/.env` → claves `ADMIN_USER` y `ADMIN_PASS`.
- Si esas claves no están definidas, el panel responde **HTTP 503**
  (fail-closed: nunca deja entrar sin configuración).
- Al iniciar sesión se crea una **sesión PHP** con cookie `HttpOnly` y
  `SameSite=Lax`, y se regenera el ID de sesión (anti session-fixation).
- **Rate limit**: 5 intentos fallidos por IP+usuario en 10 minutos →
  bloqueo de 10 minutos.
- **CSRF**: todas las acciones POST verifican un token por sesión.
- **Auditoría**: cada acción sensible se registra en la tabla
  `admin_audit_log` (migración 007): quién, qué acción, entidad, detalles,
  IP y fecha. Sección "Auditoría" del panel para consultarla.

## 3. Cómo iniciar sesión

1. Abre la URL del panel (sección 1).
2. Introduce el usuario y la contraseña configurados en `backend/.env`.
3. Tras 5 fallos, espera 10 minutos (bloqueo automático).

## 4. Cómo crear un administrador / restablecer la contraseña

El modelo es **un solo administrador** definido por entorno:

1. Edita `backend/.env` en el servidor:
   ```ini
   ADMIN_USER=tu_usuario
   ADMIN_PASS=tu_contraseña_larga
   ```
2. Guarda. No requiere reiniciar PHP en la mayoría de hostings (el .env se
   lee en cada petición); si no refleja el cambio, reinicia PHP-FPM/Apache.
3. La contraseña se compara en texto plano contra el .env **sobre HTTPS**
   (asegura certificado válido en el dominio).

> Para múltiples administradores con roles diferenciados haría falta una
> tabla `admins` + roles — es una mejora futura; hoy el diseño es
> deliberadamente mínimo (menos superficie de ataque).

## 5. Roles y permisos

| Rol | Dónde se autentica | Qué ve |
|-----|--------------------|--------|
| **Admin** (único) | `/admin` con `ADMIN_USER`/`ADMIN_PASS` | Todo el panel |
| **Director** (B2B) | `backend/director/` con cuenta de la tabla `directores` | Solo los estudiantes de su colegio (panel separado) |
| **Usuario tipo "admin"** en la app | JWT normal con `tipo_usuario='admin'` | La app móvil, no el panel |

El panel **no** hereda permisos de la app ni viceversa.

## 6. Secciones del panel (v2.0)

| Sección | Qué hace |
|---------|----------|
| **Dashboard** | Métricas: usuarios, actividad, premium, XP, series de 30 días |
| **Usuarios** | Búsqueda, edición completa (incluye `access_level` free/trial/premium/early_bird), export CSV |
| **Colegios** | CRUD de directores B2B (crear, reset de contraseña mostrada 1 vez, activar/desactivar) |
| **📚 Cursos Moodle** ✨ | Catálogo dinámico: listar/buscar cursos de Moodle, clasificarlos (curso/simulacro/reto), ver matriculados y **matrícula masiva** por segmento (todos / verificados / trial / premium / free / nuevos 7 días) con resumen + confirmación. **Nunca desmatricula.** |
| **🎟️ Códigos Premium** ✨ | CRUD de códigos que **activan Premium** al canjearse en la app: estado, vencimiento, `max_usos` (1 = uso único), quién los usó y cuándo; historial de canjes |
| **Promociones** | Promos de **descuento** para el checkout Wompi (distintas de los códigos Premium) |
| **Notificaciones** | Envío masivo FCM + bandeja interna |
| **Anuncios / Planes / Ingresos** | Listados de ads, planes, pagos y conversión |
| **Académica / Reportes / Rankings** | Promedios por área, reportes, rankings institucionales |
| **Soporte** | Quejas y sugerencias con respuesta y estados |
| **Analítica / Errores / Actividad** | Eventos de la app, visor de errores, feed de actividad |
| **Auditoría** | Últimas 50 acciones admin con IP |

## 7. Seguridad — recomendaciones operativas

1. `ADMIN_PASS` debe ser larga (16+ chars) y única; rota si alguna vez se
   compartió por canales inseguros.
2. Sirve el panel **solo por HTTPS**.
3. Revisa la sección **Auditoría** periódicamente (acciones masivas de
   matrícula quedan registradas con conteos).
4. La tabla `admin_audit_log` crece con el uso: purga registros de más de
   6-12 meses si crece mucho.
5. Si sospechas compromiso: cambia `ADMIN_PASS` en el .env y revisa la
   sección Auditoría por IP desconocidas.

## 8. Problemas comunes

| Síntoma | Causa probable |
|---------|----------------|
| HTTP 503 al abrir | `ADMIN_USER`/`ADMIN_PASS` sin definir en `.env` |
| "Demasiados intentos" | Rate limit activo (espera 10 min) |
| Sección "Códigos Premium" pide migración | Ejecutar `backend/migrations/008_codigos_premium.sql` |
| Sección "Cursos Moodle" pide migración | Ejecutar `backend/migrations/009_course_catalog.sql` |
| Cursos Moodle no cargan | Moodle inalcanzable o token WS sin permisos (la sección sigue mostrando el catálogo local) |
