<?php
declare(strict_types=1);

/**
 * SPRINT 8 — Sección de exportaciones (refactor profesional).
 *
 * Reemplaza al export_csv.php legacy con:
 *  - 5 entidades (usuarios, pagos, simulacros, gamification, audit_logs)
 *  - Filtros por fecha, plan, departamento, estado de pago
 *  - Streaming real con fetch() iterativo (no fetchAll)
 *  - RBAC por entidad (exports.users / exports.payments / exports.analytics)
 *  - Auditoría con filtros aplicados
 *  - Límite configurable + set_time_limit dinámico
 */

require_once __DIR__ . '/../../bootstrap.php';
require_once __DIR__ . '/../../includes/layout.php';

require_permission('audit.read'); // cualquier admin puede ver la lista; el export real valida por entidad

$ENTIDADES = [
    'usuarios' => [
        'label' => 'Usuarios',
        'perm' => 'exports.users',
        'icon' => '👥',
        'columns' => ['ID', 'Nombre', 'Email', 'Teléfono', 'Departamento', 'Ciudad', 'Colegio', 'Grado',
                      'Access Level', 'Email Verificado', 'Activo', 'Registro', 'Último Login',
                      'Simulacros', 'Promedio ICFES'],
    ],
    'pagos' => [
        'label' => 'Pagos',
        'perm' => 'exports.payments',
        'icon' => '💳',
        'columns' => ['ID', 'Referencia', 'Usuario (moodle_id)', 'Email', 'Monto', 'Moneda',
                      'Estado', 'Gateway', 'Fecha Creación', 'Fecha Actualización'],
    ],
    'simulacros' => [
        'label' => 'Simulacros',
        'perm' => 'exports.analytics',
        'icon' => '📝',
        'columns' => ['Fecha', 'Usuario', 'Email', 'Colegio', 'Grado', 'Puntaje Global',
                      'Lectura', 'Matemáticas', 'Sociales', 'Naturales', 'Inglés', 'Tiempo (s)'],
    ],
    'gamification' => [
        'label' => 'Gamificación',
        'perm' => 'exports.analytics',
        'icon' => '🏆',
        'columns' => ['User ID', 'Email', 'XP Total', 'Nivel Actual', 'Racha (días)'],
    ],
    'audit_logs' => [
        'label' => 'Auditoría',
        'perm' => 'audit.read',
        'icon' => '📝',
        'columns' => ['ID', 'Admin', 'Módulo', 'Acción', 'Entidad', 'ID Entidad', 'Detalles',
                      'Success', 'IP', 'Fecha'],
    ],
];

// ── Procesar exportación ──
if (($_GET['action'] ?? '') === 'export') {
    $tipo = $_GET['tipo'] ?? '';
    if (!isset($ENTIDADES[$tipo])) {
        admin_json_error('Entidad inválida', 400);
    }
    require_permission($ENTIDADES[$tipo]['perm']);

    // Filtros comunes
    $from = $_GET['from'] ?? null;
    $to = $_GET['to'] ?? null;
    $plan = $_GET['plan'] ?? null;
    $departamento = $_GET['departamento'] ?? null;
    $estado = $_GET['estado'] ?? null;  // solo para pagos

    $filtros = [
        'from' => $from, 'to' => $to, 'plan' => $plan,
        'departamento' => $departamento, 'estado' => $estado,
    ];

    @set_time_limit(300);
    header('Content-Type: text/csv; charset=UTF-8');
    header('Content-Disposition: attachment; filename="' . $tipo . '_' . date('Y-m-d_His') . '.csv"');
    header('Cache-Control: no-store, no-cache, must-revalidate');
    $fh = fopen('php://output', 'w');
    // BOM UTF-8 para Excel
    fwrite($fh, "\xEF\xBB\xBF");
    // Header
    fputcsv($fh, $ENTIDADES[$tipo]['columns']);

    // Función de sanitización CSV
    $sanitize = function($val) {
        if (!is_string($val)) $val = (string)$val;
        if (preg_match('/^[=+\-@]/', $val)) return "'" . $val;
        return $val;
    };

    $total = 0;
    try {
        $stmt = build_export_query($conexion, $tipo, $filtros);
        $stmt->execute();
        // Streaming: una fila a la vez
        while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
            $csvRow = array_map($sanitize, array_values($row));
            fputcsv($fh, $csvRow);
            $total++;
            if ($total >= 50000) break; // límite duro
        }
    } catch (Throwable $e) {
        fwrite($fh, ["ERROR: " . $e->getMessage()]);
        error_log('[EXPORT] ' . $e->getMessage());
    }
    fclose($fh);

    // Auditar exportación
    admin_audit_log($conexion, 'export_csv', 'export', null,
        json_encode(['tipo' => $tipo, 'filas' => $total, 'filtros' => $filtros], JSON_UNESCAPED_UNICODE),
        'exports');

    exit;
}

// ── Render: lista de entidades ──
render_header('Exportaciones', ['section' => 'exports']);
?>

<div class="section-header">
    <div>
        <div class="section-header__title">📤 Exportaciones</div>
        <div class="section-header__subtitle">Descarga datos en CSV con filtros y auditoría</div>
    </div>
</div>

<div class="grid-3" style="margin-bottom: 24px;">
    <?php foreach ($ENTIDADES as $key => $info): ?>
        <div class="card">
            <div class="card__header">
                <div class="card__title"><?= $info['icon'] ?> <?= sp_h($info['label']) ?></div>
                <?php if (!admin_has_permission($info['perm'])): ?>
                    <span class="badge badge--gray">Sin permiso</span>
                <?php endif; ?>
            </div>
            <form method="get" action="index.php" class="filters-bar" style="border:none;padding:0;flex-direction:column;align-items:stretch;">
                <input type="hidden" name="section" value="exports">
                <input type="hidden" name="action" value="export">
                <input type="hidden" name="tipo" value="<?= sp_h($key) ?>">

                <div class="filters-bar__field">
                    <label class="filters-bar__label">Desde</label>
                    <input type="date" name="from" value="<?= sp_h($_GET['from'] ?? '') ?>">
                </div>
                <div class="filters-bar__field">
                    <label class="filters-bar__label">Hasta</label>
                    <input type="date" name="to" value="<?= sp_h($_GET['to'] ?? '') ?>">
                </div>

                <?php if (in_array($key, ['usuarios', 'simulacros', 'gamification'])): ?>
                    <div class="filters-bar__field">
                        <label class="filters-bar__label">Plan</label>
                        <select name="plan">
                            <option value="">Todos</option>
                            <option value="free">Free</option>
                            <option value="premium">Premium</option>
                            <option value="trial">Trial</option>
                            <option value="early_bird">Early Bird</option>
                        </select>
                    </div>
                    <div class="filters-bar__field">
                        <label class="filters-bar__label">Departamento</label>
                        <input type="text" name="departamento" placeholder="Ej: Cundinamarca">
                    </div>
                <?php endif; ?>

                <?php if ($key === 'pagos'): ?>
                    <div class="filters-bar__field">
                        <label class="filters-bar__label">Estado</label>
                        <select name="estado">
                            <option value="">Todos</option>
                            <option value="approved">Aprobado</option>
                            <option value="pending">Pendiente</option>
                            <option value="declined">Rechazado</option>
                            <option value="failed">Fallido</option>
                        </select>
                    </div>
                <?php endif; ?>

                <button type="submit"
                        class="btn btn--primary btn--sm"
                        <?= admin_has_permission($info['perm']) ? '' : 'disabled' ?>>
                    ⬇️ Exportar CSV
                </button>
            </form>
            <p style="margin-top:12px;font-size:11px;color:#94A3B8;">
                Columnas: <?= count($info['columns']) ?> · Límite: 50.000 filas
            </p>
        </div>
    <?php endforeach; ?>
</div>

<div class="card">
    <div class="card__header">
        <div class="card__title">📋 Exportaciones recientes</div>
    </div>
    <?php
    $recentExports = safeRows($conexion,
        "SELECT admin_user, details, created_at FROM admin_audit_log
         WHERE action='export_csv' ORDER BY id DESC LIMIT 10");
    if (empty($recentExports)):
        echo '<div class="empty-state">
                <div class="empty-state__icon">📭</div>
                <div class="empty-state__title">Sin exportaciones aún</div>
                <div class="empty-state__message">Cuando realices tu primera exportación, aparecerá aquí.</div>
              </div>';
    else: ?>
        <table class="data-table table-compact">
            <thead>
                <tr>
                    <th>Admin</th>
                    <th>Detalles</th>
                    <th>Fecha</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($recentExports as $r):
                    $det = json_decode($r['details'] ?? '{}', true);
                ?>
                    <tr>
                        <td><?= sp_h($r['admin_user']) ?></td>
                        <td>
                            <strong><?= sp_h($det['tipo'] ?? '?') ?></strong> ·
                            <?= (int)($det['filas'] ?? 0) ?> filas
                            <?php if (!empty($det['filtros']['from'])): ?>· desde <?= sp_h($det['filtros']['from']) ?><?php endif; ?>
                            <?php if (!empty($det['filtros']['to'])): ?>· hasta <?= sp_h($det['filtros']['to']) ?><?php endif; ?>
                        </td>
                        <td><?= sp_h(admin_fmt_tiempo_relativo($r['created_at'])) ?></td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    <?php endif; ?>
</div>

<?php
render_footer();

// ── Builder de queries (con filtros y streaming) ──

function build_export_query(PDO $db, string $tipo, array $filtros): PDOStatement {
    $where = [];
    $params = [];

    if (!empty($filtros['from'])) {
        $where[] = 'created_at >= ?';
        $params[] = $filtros['from'] . ' 00:00:00';
    }
    if (!empty($filtros['to'])) {
        $where[] = 'created_at <= ?';
        $params[] = $filtros['to'] . ' 23:59:59';
    }

    $whereSql = $where ? ('WHERE ' . implode(' AND ', $where)) : '';

    switch ($tipo) {
        case 'usuarios':
            $sql = "SELECT u.id_usuario, u.nombre, u.email, u.telefono, u.departamento, u.ciudad,
                           u.colegio, u.grado, u.access_level, u.email_verificado,
                           COALESCE(u.activo, 1) AS activo, u.registration_date, u.ultimo_login,
                           COUNT(sr.id) AS num_simulacros, COALESCE(ROUND(AVG(sr.puntaje_global),1),0) AS promedio
                    FROM usuarios u
                    LEFT JOIN simulacro_resultados sr ON sr.usuario_id = u.moodle_id";
            if (!empty($filtros['plan'])) {
                $sql .= " WHERE u.access_level = ?";
                $params[] = $filtros['plan'];
            } else {
                $sql .= " WHERE 1=1";
            }
            if (!empty($filtros['departamento'])) {
                $sql .= " AND u.departamento = ?";
                $params[] = $filtros['departamento'];
            }
            $sql .= " GROUP BY u.id_usuario ORDER BY u.id_usuario DESC LIMIT 50000";
            break;

        case 'pagos':
            $sql = "SELECT p.id, p.reference_code, p.user_id, u.email, p.amount, p.currency,
                           p.status, p.gateway, p.created_at, p.updated_at
                    FROM payments p
                    LEFT JOIN usuarios u ON u.moodle_id = p.user_id";
            $where2 = [];
            if (!empty($filtros['estado'])) {
                $where2[] = 'LOWER(p.status) = ?';
                $params[] = strtolower($filtros['estado']);
            }
            if (!empty($filtros['from'])) {
                $where2[] = 'p.created_at >= ?';
                $params[] = $filtros['from'] . ' 00:00:00';
            }
            if (!empty($filtros['to'])) {
                $where2[] = 'p.created_at <= ?';
                $params[] = $filtros['to'] . ' 23:59:59';
            }
            $sql .= $where2 ? (' WHERE ' . implode(' AND ', $where2)) : '';
            $sql .= " ORDER BY p.id DESC LIMIT 50000";
            break;

        case 'simulacros':
            $sql = "SELECT sr.fecha_realizacion, u.nombre, u.email, u.colegio, u.grado,
                           sr.puntaje_global, sr.lectura_puntaje, sr.matematicas_puntaje,
                           sr.sociales_puntaje, sr.naturales_puntaje, sr.ingles_puntaje, sr.tiempo_empleado
                    FROM simulacro_resultados sr
                    LEFT JOIN usuarios u ON u.moodle_id = sr.usuario_id";
            $where2 = [];
            if (!empty($filtros['plan'])) {
                $where2[] = 'u.access_level = ?';
                $params[] = $filtros['plan'];
            }
            if (!empty($filtros['departamento'])) {
                $where2[] = 'u.departamento = ?';
                $params[] = $filtros['departamento'];
            }
            if (!empty($filtros['from'])) {
                $where2[] = 'sr.fecha_realizacion >= ?';
                $params[] = $filtros['from'] . ' 00:00:00';
            }
            if (!empty($filtros['to'])) {
                $where2[] = 'sr.fecha_realizacion <= ?';
                $params[] = $filtros['to'] . ' 23:59:59';
            }
            $sql .= $where2 ? (' WHERE ' . implode(' AND ', $where2)) : '';
            $sql .= " ORDER BY sr.fecha_realizacion DESC, sr.id DESC LIMIT 50000";
            break;

        case 'gamification':
            $sql = "SELECT ug.user_id, u.email, ug.total_xp, ug.current_level,
                           COALESCE(ug.current_streak, 0) AS current_streak
                    FROM user_gamification ug
                    LEFT JOIN usuarios u ON u.id_usuario = ug.user_id";
            if (!empty($filtros['plan'])) {
                $sql .= " WHERE u.access_level = ?";
                $params[] = $filtros['plan'];
            }
            $sql .= " ORDER BY ug.total_xp DESC LIMIT 50000";
            break;

        case 'audit_logs':
            $sql = "SELECT id, admin_user, module, action, entity, entity_id,
                           LEFT(details, 200) AS details, success, ip, created_at
                    FROM admin_audit_log";
            $where2 = [];
            if (!empty($filtros['from'])) {
                $where2[] = 'created_at >= ?';
                $params[] = $filtros['from'] . ' 00:00:00';
            }
            if (!empty($filtros['to'])) {
                $where2[] = 'created_at <= ?';
                $params[] = $filtros['to'] . ' 23:59:59';
            }
            // Solo superadmin ve auth logs
            if (!admin_has_permission('admin_users.manage')) {
                $where2[] = "(module IS NULL OR module != 'auth')";
            }
            $sql .= $where2 ? (' WHERE ' . implode(' AND ', $where2)) : '';
            $sql .= " ORDER BY id DESC LIMIT 50000";
            break;

        default:
            throw new InvalidArgumentException("Tipo inválido: $tipo");
    }

    $stmt = $db->prepare($sql);
    foreach ($params as $i => $v) {
        $stmt->bindValue($i + 1, $v);
    }
    return $stmt;
}
