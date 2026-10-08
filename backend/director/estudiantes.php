<?php
/**
 * estudiantes.php — Listado de estudiantes del colegio (Panel del Director)
 *
 * - Búsqueda por nombre/email (GET q), filtros por grado y estado.
 * - Paginación simple de 20 por página (LIMIT/OFFSET con (int)).
 * - Activar/desactivar estudiante: POST propio con CSRF. El UPDATE va
 *   SIEMPRE scoped por el colegio de la sesión, jamás del request.
 */

require_once __DIR__ . '/includes/auth.php';
require_once __DIR__ . '/includes/ui.php';

$director = require_director($conexion);
$colegio  = $director['colegio'];

$POR_PAGINA = 20;

// ── Acción POST: activar/desactivar estudiante ──
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['toggle_estado'])) {
    csrf_verify();
    $idUser     = (int)($_POST['user_id'] ?? 0);
    $nuevoEstado = (($_POST['nuevo_estado'] ?? '') === '1') ? 1 : 0;

    if ($idUser > 0) {
        try {
            // Scoped por colegio de sesión + tipo estudiante: un director
            // jamás puede tocar usuarios de otro colegio ni profesores/admins.
            $stmt = $conexion->prepare(
                "UPDATE usuarios
                 SET activo = :activo
                 WHERE id_usuario = :id AND colegio = :colegio AND tipo_usuario = 'estudiante'"
            );
            $stmt->execute([
                ':activo'  => $nuevoEstado,
                ':id'      => $idUser,
                ':colegio' => $colegio,
            ]);
        } catch (PDOException $ex) {
            error_log('[DIRECTOR] toggle_estado: ' . $ex->getMessage());
        }
    }

    // Redirige conservando los filtros que venían en el formulario
    $destino = 'estudiantes.php';
    $sep     = '?';
    foreach (['q' => 'f_q', 'grado' => 'f_grado', 'estado' => 'f_estado', 'page' => 'f_page'] as $getParam => $postParam) {
        $valor = trim((string)($_POST[$postParam] ?? ''));
        if ($getParam === 'page') {
            $valor = (string)max(1, (int)$valor);
            if ($valor === '1') {
                continue; // la página 1 es la default, no ensucia la URL
            }
        }
        if ($valor !== '') {
            $destino .= $sep . urlencode($getParam) . '=' . urlencode($valor);
            $sep = '&';
        }
    }
    header('Location: ' . $destino);
    exit;
}

// ── Filtros GET ──
$q      = trim((string)($_GET['q'] ?? ''));
$grado  = trim((string)($_GET['grado'] ?? ''));
$estado = (string)($_GET['estado'] ?? '');
if ($estado !== '1' && $estado !== '0') {
    $estado = ''; // '' = todos
}
$page = max(1, (int)($_GET['page'] ?? 1));

// Clausulas fijas (sin input del usuario) + parámetros bind
$where  = ['u.colegio = :colegio', "u.tipo_usuario = 'estudiante'"];
$params = [':colegio' => $colegio];

if ($q !== '') {
    $where[] = '(u.nombre LIKE :q_nombre OR u.email LIKE :q_email)';
    // Escapa comodines LIKE del usuario (% y _) para búsqueda literal
    $qEsc = str_replace(['\\', '%', '_'], ['\\\\', '\\%', '\\_'], $q);
    $like = '%' . $qEsc . '%';
    $params[':q_nombre'] = $like;
    $params[':q_email']  = $like;
}
if ($grado !== '') {
    $where[] = 'u.grado = :grado';
    $params[':grado'] = $grado;
}
if ($estado !== '') {
    $where[] = 'u.activo = :estado';
    $params[':estado'] = (int)$estado;
}
$whereSql = implode(' AND ', $where);

$estudiantes = [];
$total       = 0;
$grados      = [];
$errorDatos  = false;

try {
    // Grados disponibles (para el filtro)
    $stmt = $conexion->prepare(
        "SELECT DISTINCT grado
         FROM usuarios
         WHERE colegio = :colegio AND tipo_usuario = 'estudiante'
           AND grado IS NOT NULL AND TRIM(grado) <> ''
         ORDER BY grado"
    );
    $stmt->execute([':colegio' => $colegio]);
    $grados = $stmt->fetchAll(PDO::FETCH_COLUMN);

    // Total de resultados (para paginación)
    $stmt = $conexion->prepare("SELECT COUNT(*) FROM usuarios u WHERE " . $whereSql);
    foreach ($params as $k => $v) {
        $stmt->bindValue($k, $v);
    }
    $stmt->execute();
    $total = (int)$stmt->fetchColumn();

    $totalPaginas = max(1, (int)ceil($total / $POR_PAGINA));
    $page = max(1, min($page, $totalPaginas));
    $offset = ($page - 1) * $POR_PAGINA;

    // Listado paginado con métricas de simulacros por estudiante
    $stmt = $conexion->prepare(
        "SELECT u.id_usuario, u.nombre, u.email, u.grado, u.activo, u.ultimo_login,
                COUNT(sr.id) AS num_simulacros,
                MAX(sr.puntaje_global) AS mejor_puntaje,
                ROUND(AVG(sr.puntaje_global), 1) AS promedio,
                MAX(sr.fecha_realizacion) AS ultimo_simulacro
         FROM usuarios u
         LEFT JOIN simulacro_resultados sr ON sr.usuario_id = u.moodle_id
         WHERE " . $whereSql . "
         GROUP BY u.id_usuario, u.nombre, u.email, u.grado, u.activo, u.ultimo_login
         ORDER BY u.nombre ASC
         LIMIT :limite OFFSET :offset"
    );
    foreach ($params as $k => $v) {
        $stmt->bindValue($k, $v);
    }
    $stmt->bindValue(':limite', $POR_PAGINA, PDO::PARAM_INT);
    $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
    $stmt->execute();
    $estudiantes = $stmt->fetchAll(PDO::FETCH_ASSOC);
} catch (PDOException $ex) {
    error_log('[DIRECTOR] estudiantes: ' . $ex->getMessage());
    $errorDatos = true;
    $totalPaginas = 1;
    $offset = 0;
}

// Querystring base para preservar filtros en enlaces
$baseParams = [];
if ($q !== '')      { $baseParams['q'] = $q; }
if ($grado !== '')  { $baseParams['grado'] = $grado; }
if ($estado !== '') { $baseParams['estado'] = $estado; }
// URLs ya codificadas (se escapan al imprimirlas en el HTML)
$urlPagina = 'estudiantes.php' . ($baseParams ? http_build_query($baseParams) . '&' : '');
$urlExport = 'export_csv.php?' . http_build_query(array_merge(['tipo' => 'estudiantes'], $baseParams));

panel_head('Estudiantes', 'estudiantes', $director);
?>

<?php if ($errorDatos): ?>
    <div class="flash-err">No se pudo cargar el listado en este momento. Intenta de nuevo más tarde.</div>
<?php endif; ?>

<!-- Barra de filtros -->
<form method="GET" action="estudiantes.php" class="filters-bar">
    <div class="form-group">
        <label for="q">Buscar</label>
        <input type="text" id="q" name="q" value="<?= e($q) ?>" placeholder="Nombre o email...">
    </div>
    <div class="form-group">
        <label for="f_grado">Grado</label>
        <select id="f_grado" name="grado">
            <option value="">Todos</option>
            <?php foreach ($grados as $g): ?>
                <option value="<?= e($g) ?>"<?= $g === $grado ? ' selected' : '' ?>><?= e($g) ?></option>
            <?php endforeach; ?>
        </select>
    </div>
    <div class="form-group">
        <label for="f_estado">Estado</label>
        <select id="f_estado" name="estado">
            <option value="">Todos</option>
            <option value="1"<?= $estado === '1' ? ' selected' : '' ?>>Activos</option>
            <option value="0"<?= $estado === '0' ? ' selected' : '' ?>>Inactivos</option>
        </select>
    </div>
    <button type="submit" class="btn btn-primary">Filtrar</button>
    <a href="estudiantes.php" class="btn btn-outline">Limpiar</a>
    <a href="<?= e($urlExport) ?>" class="btn btn-success">&#11015; Exportar CSV</a>
</form>

<!-- Tabla de estudiantes -->
<div class="table-container">
    <table>
        <thead>
            <tr>
                <th>#</th>
                <th>Estudiante</th>
                <th>Email</th>
                <th>Grado</th>
                <th>Simulacros</th>
                <th>Mejor puntaje</th>
                <th>Promedio</th>
                <th>Último simulacro</th>
                <th>Último login</th>
                <th>Estado</th>
                <th>Acciones</th>
            </tr>
        </thead>
        <tbody>
        <?php if (!$estudiantes): ?>
            <tr><td colspan="11" class="empty-state">No se encontraron estudiantes con esos criterios.</td></tr>
        <?php else: foreach ($estudiantes as $i => $est): ?>
            <tr>
                <td><?= $offset + $i + 1 ?></td>
                <td>
                    <a href="estudiante_detalle.php?id=<?= (int)$est['id_usuario'] ?>" style="text-decoration:none;color:#1a1a2e;">
                        <span class="user-cell"><?= avatar_inicial($est['nombre']) ?><strong><?= e($est['nombre']) ?></strong></span>
                    </a>
                </td>
                <td><?= e($est['email']) ?></td>
                <td><?= e($est['grado'] !== '' && $est['grado'] !== null ? $est['grado'] : '—') ?></td>
                <td><?= (int)$est['num_simulacros'] ?></td>
                <td><strong><?= $est['mejor_puntaje'] !== null ? number_format((float)$est['mejor_puntaje'], 0, ',', '.') : '—' ?></strong></td>
                <td><?= $est['promedio'] !== null ? number_format((float)$est['promedio'], 1, ',', '.') : '—' ?></td>
                <td><?= fecha_corta($est['ultimo_simulacro']) ?></td>
                <td><?= fecha_hora_corta($est['ultimo_login']) ?></td>
                <td><?= badge_estado($est['activo']) ?></td>
                <td style="white-space:nowrap;">
                    <a href="estudiante_detalle.php?id=<?= (int)$est['id_usuario'] ?>" class="btn btn-primary btn-sm">Ver detalle</a>
                    <form method="POST" action="estudiantes.php" style="display:inline;"
                          onsubmit="return confirm('<?= ((int)$est['activo'] === 1) ? '¿Desactivar a este estudiante? No podrá iniciar sesión en la app.' : '¿Activar a este estudiante? Podrá volver a iniciar sesión en la app.' ?>');">
                        <?= csrf_field() ?>
                        <input type="hidden" name="toggle_estado" value="1">
                        <input type="hidden" name="user_id" value="<?= (int)$est['id_usuario'] ?>">
                        <input type="hidden" name="nuevo_estado" value="<?= ((int)$est['activo'] === 1) ? '0' : '1' ?>">
                        <input type="hidden" name="f_q" value="<?= e($q) ?>">
                        <input type="hidden" name="f_grado" value="<?= e($grado) ?>">
                        <input type="hidden" name="f_estado" value="<?= e($estado) ?>">
                        <input type="hidden" name="f_page" value="<?= $page ?>">
                        <button type="submit" class="btn <?= ((int)$est['activo'] === 1) ? 'btn-danger' : 'btn-success' ?> btn-sm">
                            <?= ((int)$est['activo'] === 1) ? 'Desactivar' : 'Activar' ?>
                        </button>
                    </form>
                </td>
            </tr>
        <?php endforeach; endif; ?>
        </tbody>
    </table>
</div>

<!-- Paginación -->
<?php if ($totalPaginas > 1): ?>
    <div class="pagination">
        <?php if ($page > 1): ?>
            <a href="<?= e($urlPagina . 'page=' . ($page - 1)) ?>">&laquo; Anterior</a>
        <?php endif; ?>
        <?php for ($n = 1; $n <= $totalPaginas; $n++): ?>
            <?php if ($n === $page): ?>
                <span class="current"><?= $n ?></span>
            <?php else: ?>
                <a href="<?= e($urlPagina . 'page=' . $n) ?>"><?= $n ?></a>
            <?php endif; ?>
        <?php endfor; ?>
        <?php if ($page < $totalPaginas): ?>
            <a href="<?= e($urlPagina . 'page=' . ($page + 1)) ?>">Siguiente &raquo;</a>
        <?php endif; ?>
        <span style="box-shadow:none;background:transparent;color:#94A3B8;font-size:12px;"><?= number_format($total, 0, ',', '.') ?> estudiantes</span>
    </div>
<?php endif; ?>

<?php panel_footer(); ?>
