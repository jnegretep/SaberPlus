# INFORME EJECUTIVO — CEO — SABER+

**Para:** Propietario / Dirección de Saber+
**De:** Equipo de transformación (CEO-Producto, CTO-Arquitectura, Seguridad, Flutter, UX, Gamificación, Académico, Admin)
**Fecha:** 5 de noviembre de 2026 · **Versión transformada sobre:** v1.7.1

---

## 1. ¿EN QUÉ ESTADO ESTABA SABER+?

Saber+ llegó a esta misión como un producto **funcional y sorprendentemente completo para su etapa** — app móvil y web en Flutter, ~107 endpoints PHP, integración total con Moodle como banco de preguntas, tutor IA con failover Gemini→DeepSeek, pagos Wompi y Google Play, panel B2B para directores de colegio y gamificación con 5 tablas en BD.

Pero tenía **tres problemas que bloqueaban cualquier lanzamiento comercial**:

1. **La web estaba rota donde más importa.** El flujo Cursos → Simulacro → Resultados se ejecutaba fuera del historial del navegador: el botón atrás dejaba de funcionar y el usuario quedaba atrapado en pantallas sin salida. Un estudiante nuevo que probara la web en ese estado no volvería.
2. **La seguridad no era desplegable.** 7 familias de credenciales en el repositorio público (incluyendo el secreto JWT y claves de producción de pagos), un endpoint que regalaba premium sin pagar, XP manipulable desde el cliente y datos académicos de cualquier estudiante accesibles sin login.
3. **El motor de retención estaba apagado.** La gamificación existía en la base de datos, pero la XP solo se otorgaba en retos diarios: un estudiante que preparaba simulacros completos seguía en nivel 1, con 0 XP y sin racha. Nadie vuelve a una app donde su esfuerzo no cuenta.

Además: soporte con datos personales del fundador (nombre, teléfono y contraseñas de Gmail en el código), sin onboarding post-registro, y un panel admin operativo pero sin visión de negocio.

## 2. ¿EN QUÉ ESTADO QUEDA?

| Frente | Antes | Ahora |
|---|---|---|
| Navegación web | Rota (atrapados, back muerto) | **14 pantallas con URL propia**, back/adelante/F5 funcionales, deep-links seguros |
| Inicio de simulacro | Spinner mudo o pantalla sin salida | **Overlay de preparación con estados** + error con Reintentar + 0 dobles llamadas |
| Secretos | 7 familias en git | En `.env` con advertencia de rotación (rotación pendiente: §7) |
| Fraude | Premium gratis, XP infinita, resultados falsificables | **Cerrado** (verificación de pago, XP server-side, deduplicación) |
| Datos de estudiantes | Accesibles sin token | JWT obligatorio, id del token |
| Gamificación | Desconectada (XP=0 haciendo simulacros) | **100 XP por simulacro, 10 XP por login diario, racha viva, 4 badges nuevos** |
| Onboarding | Solo carrusel pre-login | **Tour post-login de 5 pasos + checklist de activación** |
| Soporte | Datos personales expuestos | **Equipo de soporte Saber+ · +57 350 2114292 · Saberplus2026@gmail.com** en toda la app |
| Panel admin | 13 secciones operativas | **+ Dashboard ejecutivo con series de 30 días, ingresos, analítica educativa, auditoría de acciones, exportes CSV** |

## 3. MEJORAS DE MAYOR IMPACTO (ranking del equipo)

1. **Fix de navegación web** — era el asesino silencioso de conversión; sin él, todo el gasto de adquisición se perdía en el primer simulacro.
2. **Gamificación conectada** — el hábito diario (XP + racha + celebraciones) es lo que hace que un estudiante de 16 años vuelva mañana. Costó 3 archivos; cambia el producto.
3. **Cierre de fraude** — premium gratis y XP infinita eran pérdidas de ingresos directas y de confianza en los rankings.
4. **Experiencia de simulacro** — la pantalla de preparación elimina el momento de máxima incertidumbre ("¿se colgó?") justo antes del compromiso más valioso.
5. **Panel con visión de negocio** — ingresos, retención aproximada y rendimiento académico agregado por primera vez en un solo lugar.

## 4. VENTAJAS COMPETITIVAS REALES

- **Banco de preguntas ICFES vía Moodle** con explicaciones por pregunta: la mayoría de apps de prepago colombianas no explican el error.
- **Predicción de puntaje ICFES + análisis de errores por tipo** (conceptual/cálculo/comprensión/tiempo): diferenciador académico genuino.
- **Modelo B2B de colegios** (panel de director con métricas de su colegio): canal de venta institucional que casi nadie tiene en este segmento.
- **Tutor IA multi-proveedor con failover** y costo controlado (DeepSeek), ya con rate-limit y datos reales del estudiante en el prompt.
- **Puntaje ponderado Saber 11 real** (0–500 con pesos 3-3-3-3-1), no un simple porcentaje.

## 5. OPORTUNIDADES COMERCIALES

1. **Venta institucional (B2B)**: con el heatmap área×grado del panel admin, una reunión con un rector puede mostrarse con datos: "sus estudiantes pierden en razonamiento cuantitativo". Precio por colegio, no por estudiante.
2. **Freemium con paywall de simulacros avanzados**: el embudo ya existe (planes, promociones, Wompi + Play Billing verificados).
3. **Alianzas con preparadores independientes**: el ecosistema Moodle permite cargar contenido de terceros y compartir ingresos.
4. **Reporte para padres**: el mismo dato académico ya calculado, empaquetado como email semanal — los padres pagan por visibilidad.

## 6. QUÉ FALTA PARA COMPETIR (hoja de ruta priorizada)

| Prioridad | Funcionalidad | Esfuerzo | Impacto |
|---|---|---|---|
| P0 | Rotar credenciales + borrar fallbacks + purgar historial git | 2–4 h (procedimiento entregado) | Seguridad real |
| P0 | Compilar y probar móvil + web en dispositivo real | 1 día | Cierre del ciclo |
| P1 | Pruebas FCM en dispositivo real (protocolo listo) | medio día | Retención push |
| P1 | Metas semanales + streak freeze (columna ya existe en BD) | 2–3 días | Hábito |
| P1 | Normalizar competencias ICFES (mapear tags Moodle al marco oficial) | 1–2 semanas | Diferenciador académico, reporte B2B |
| P2 | Tipos de pregunta adicionales (T/F, multi-select, cloze) | 1–2 semanas | Profundidad del banco |
| P2 | Roles del panel admin (soporte, coordinador, analista) | 1 semana | Operación con equipo |
| P2 | Asistente IA ejecutivo del panel (preguntas en lenguaje natural sobre métricas reales) | 2–3 semanas | El "wow" comercial |
| P3 | Aprendizaje adaptativo (recomendar áreas débiles) | 1–2 meses | Retención a largo plazo |

## 7. RIESGOS QUE DEBEN ATENDERSE

1. **CRÍTICO — credenciales expuestas:** los valores antiguos siguen como *fallbacks transitorios* en el código (decisión para no romper el despliegue durante la transición). Mientras no se roten y se borren, la ventana sigue abierta. Procedimiento: Checklist §6.
2. **SMTP:** el correo transaccional ahora sale de `Saberplus2026@gmail.com`, pero la app-password de esa cuenta debe generarse y configurarse en `.env` (SMTP_PASS); mientras tanto el fallback usa la cuenta antigua y emitirá advertencias.
3. **Crons:** si se invocan por HTTP en el servidor, dejarán de correr (403) — pasar a CLI o configurar `X-Internal-Token`.
4. **Validación en runtime pendiente:** toda la transformación está verificada estáticamente (sintaxis, referencias, esquemas), pero NO se compiló ni ejecutó en este entorno. Antes de producción: `flutter analyze`, build móvil/web y el protocolo de navegación del Checklist §3.
5. **Single point of failure en Moodle:** si el WS de Moodle cae, no hay simulacros. Considerar caché de preguntas (backlog).

## 8. RECOMENDACIÓN DEL CEO PARA LOS PRÓXIMOS 6 MESES

**Mes 1 — Cierre y estabilización.** Rotar credenciales, compilar, ejecutar el protocolo de pruebas completo, lanzar a un grupo cerrado (1–2 colegios aliados) con el B2B. Medir: tasa de finalización del primer simulacro (objetivo >60%) y D7 de usuarios nuevos.

**Meses 2–3 — Activación.** Metas semanales, streak freeze y notificaciones inteligentes ya construidas (crons) afinadas con los datos reales del panel. Lanzamiento público con el modelo freemium. Empezar el mapeo de competencias ICFES.

**Meses 4–5 — Institucional.** Reportes para padres/directores exportables, roles del panel admin, primeras 5–10 ventas B2B con el heatmap como argumento comercial.

**Mes 6 — Inteligencia.** Asistente IA ejecutivo del panel + recomendador de estudio adaptativo (MVP sobre icfes_prediction + error_analysis que ya existen). Aquí Saber+ deja de competir por precio y compite por dato.

**La pregunta de fondo que guía todo:** *¿qué hace que un estudiante de bachillerato colombiano abra Saber+ mañana sin que se lo pidan?* Esta transformación instaló la infraestructura de respuesta (racha, XP, celebración, progreso visible, preparación sin fricción). Los próximos 6 meses deben convertirla en hábito medible.

---

*Documentos complementarios: AUDITORIA_INICIAL · PLAN_TRANSFORMACION · CAMBIOS_IMPLEMENTADOS · REPORTE_TECNICO_FINAL · CHECKLIST_LANZAMIENTO · GUIA_ADMINISTRACION*
