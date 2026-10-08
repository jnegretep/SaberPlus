<?php
/**
 * export_csv.php — Exportación CSV del Panel del Director (Saber+)
 *
 * Repite el MISMO query de la página que lo invoca, siempre scoped al
 * colegio de la sesión + tipo_usuario='estudiante':
 *   tipo=estudiantes          → listado de estudiantes (filtros q/grado/estado)
 *   tipo=simulacros           → reporte agregado (filtros desde/hasta/grado)
 *   tipo=detalle&user_id=X    → simulacros de un estudiante del colegio
 *
 * Seguridad:
 * - BOM UTF-8 (\xEF\xBB\xBF) para que Excel respete acentos/ñ.
 * - Anti CSV-injection: toda celda que empiece por = + - @ se prefija con '.
 */

require_once __DIR__ . '/includes/auth.php';

$director = require_director($conexion);
$colegio  = $director['colegio'];

// ── Tipo de exportación (whitelist) ──
$tipo = (string)($_GET['tipo'] ?? '');
if (!in_array($tipo, ['estudiantes', 'simulacros', 'detalle'], true)) {
    http_response_code(400);
    exit('Tipo de exportación inválido.');
}

/** Prefija con ' las celdas peligrosas para fórmulas (CSV injection). */
function csv_celda($valor)
{
    $v = (string)$valor;
    if ($v !== '' && ($v[0] === '=' || $v[0] === '+' || $v[0] === '-' || $v[0] === '@')) {
        return "'" . $v;
    }
    return $v;
}

/** Escribe una fila aplicando la protección anti CSV-injection. */
function csv_fila($fh, array $fila)
{
    fputcsv($fh, array_map('csv_celda', $fila));
}

/** Slug del colegio para el nombre del archivo (sin acentos ni espacios). */
function colegio_slug($colegio)
{
    $ascii = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', (string)$colegio);
    if ($ascii === false || $ascii === '') {
        $ascii = (string)$colegio;
    }
    $slug = trim(preg_replace('/[^A-Za-z0-9]+/', '_', strtolower($ascii)), '_');
    return ($slug !== '') ? $slug : 'colegio';
}

try {
    if ($tipo === 'estudiantes') {
        // ── Mismo query+filtros que estudiantes.php ──
        $q      = trim((string)($_GET['q'] ?? ''));
        $grado  = trim((string)($_GET['grado'] ?? ''));
        $estado = (string)($_GET['estado'] ?? '');
        if ($estado !== '1' && $estado !== '0') {
            $estado = '';
        }

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

        $stmt = $conexion->prepare(
            "SELECT u.id_usuario, u.nombre, u.email, u.grado, u.activo, u.ultimo_login,
                    COUNT(sr.id) AS num_simulacros,
                    MAX(sr.puntaje_global) AS mejor_puntaje,
                    ROUND(AVG(sr.puntaje_global), 1) AS promedio,
                    MAX(sr.fecha_realizacion) AS ultimo_simulacro
             FROM usuarios u
             LEFT JOIN simulacro_resultados sr ON sr.usuario_id = u.moodle_id
             WHERE " . implode(' AND ', $where) . "
             GROUP BY u.id_usuario, u.nombre, u.email, u.grado, u.activo, u.ultimo_login
             ORDER BY u.nombre ASC"
        );
        foreach ($params as $k => $v) {
            $stmt->bindValue($k, $v);
        }
        $stmt->execute();
        $filas = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $nombreArchivo = 'saberplus_' . colegio_slug($colegio) . '_estudiantes_' . date('Ymd') . '.csv';
        header('Content-Type: text/csv; charset=UTF-8');
        header('Content-Disposition: attachment; filename="' . $nombreArchivo . '"');
        header('Pragma: public');
        header('Expires: 0');

        $fh = fopen('php://output', 'w');
        echo "\xEF\xBB\xBF"; // BOM UTF-8 para Excel
        csv_fila($fh, ['ID', 'Nombre', 'Email', 'Grado', 'Simulacros', 'Mejor puntaje',
                       'Promedio', 'Ultimo simulacro', 'Ultimo login', 'Estado']);
        foreach ($filas as $f) {
            csv_fila($fh, [
                $f['id_usuario'],
                $f['nombre'],
                $f['email'],
                $f['grado'],
                (int)$f['num_simulacros'],
                $f['mejor_puntaje'],
                $f['promedio'],
                $f['ultimo_simulacro'],
                $f['ultimo_login'],
                ((int)$f['activo'] === 1) ? 'Activo' : 'Inactivo',
            ]);
        }
        fclose($fh);
        exit;

    } elseif ($tipo === 'simulacros') {
        // ── Mismo query+filtros que simulacros.php ──
        $desde = (string)($_GET['desde'] ?? '');
        $hasta = (string)($_GET['hasta'] ?? '');
        $grado = trim((string)($_GET['grado'] ?? ''));
        if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $desde)) {
            $desde = '';
        }
        if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $hasta)) {
            $hasta = '';
        }

        $where  = ['u.colegio = :colegio', "u.tipo_usuario = 'estudiante'"];
        $params = [':colegio' => $colegio];
        if ($desde !== '') {
            $where[] = 'sr.fecha_realizacion >= :desde';
            $params[':desde'] = $desde . ' 00:00:00';
        }
        if ($hasta !== '') {
            $where[] = 'sr.fecha_realizacion <= :hasta';
            $params[':hasta'] = $hasta . ' 23:59:59';
        }
        if ($grado !== '') {
            $where[] = 'u.grado = :grado';
            $params[':grado'] = $grado;
        }

        $stmt = $conexion->prepare(
            "SELECT DATE(sr.fecha_realizacion) AS fecha,
                    COUNT(*) AS total,
                    COUNT(DISTINCT sr.usuario_id) AS participantes,
                    ROUND(AVG(sr.puntaje_global), 1) AS promedio,
                    MIN(sr.puntaje_global) AS minimo,
                    MAX(sr.puntaje_global) AS maximo,
                    ROUND(AVG(sr.lectura_puntaje), 1)    AS lectura,
                    ROUND(AVG(sr.matematicas_puntaje), 1) AS matematicas,
                    ROUND(AVG(sr.sociales_puntaje), 1)    AS sociales,
                    ROUND(AVG(sr.naturales_puntaje), 1)   AS naturales,
                    ROUND(AVG(sr.ingles_puntaje), 1)      AS ingles
             FROM simulacro_resultados sr
             INNER JOIN usuarios u ON sr.usuario_id = u.moodle_id
             WHERE " . implode(' AND ', $where) . "
             GROUP BY DATE(sr.fecha_realizacion)
             ORDER BY fecha DESC"
        );
        foreach ($params as $k => $v) {
            $stmt->bindValue($k, $v);
        }
        $stmt->execute();
        $filas = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $nombreArchivo = 'saberplus_' . colegio_slug($colegio) . '_simulacros_' . date('Ymd') . '.csv';
        header('Content-Type: text/csv; charset=UTF-8');
        header('Content-Disposition: attachment; filename="' . $nombreArchivo . '"');
        header('Pragma: public');
        header('Expires: 0');

        $fh = fopen('php://output', 'w');
        echo "\xEF\xBB\xBF"; // BOM UTF-8 para Excel
        csv_fila($fh, ['Fecha', 'Participantes', 'Simulacros', 'Promedio global', 'Lectura',
                       'Matematicas', 'Sociales', 'Naturales', 'Ingles', 'Minimo', 'Maximo']);
        foreach ($filas as $f) {
            csv_fila($fh, [
                $f['fecha'],
                (int)$f['participantes'],
                (int)$f['total'],
                $f['promedio'],
                $f['lectura'],
                $f['matematicas'],
                $f['sociales'],
                $f['naturales'],
                $f['ingles'],
                $f['minimo'],
                $f['maximo'],
            ]);
        }
        fclose($fh);
        exit;

    } else {
        // ── tipo=detalle: simulacros de UN estudiante del colegio ──
        $idUser = (int)($_GET['user_id'] ?? 0);
        if ($idUser <= 0) {
            http_response_code(400);
            exit('Estudiante inválido.');
        }

        // 🔒 Valida que el estudiante pertenezca al colegio de la sesión
        $stmt = $conexion->prepare(
            "SELECT id_usuario, moodle_id, nombre, email, grado
             FROM usuarios
             WHERE id_usuario = :id AND colegio = :colegio AND tipo_usuario = 'estudiante'
             LIMIT 1"
        );
        $stmt->execute([':id' => $idUser, ':colegio' => $colegio]);
        $est = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$est) {
            http_response_code(403);
            exit('Acceso denegado: este estudiante no pertenece a tu colegio.');
        }

        $stmt = $conexion->prepare(
            "SELECT sr.puntaje_global, sr.lectura_puntaje, sr.matematicas_puntaje,
                    sr.sociales_puntaje, sr.naturales_puntaje, sr.ingles_puntaje, sr.fecha_realizacion
             FROM simulacro_resultados sr
             WHERE sr.usuario_id = :moodle_id
             ORDER BY sr.fecha_realizacion ASC, sr.id ASC"
        );
        $stmt->execute([':moodle_id' => (int)$est['moodle_id']]);
        $simulacros = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $nombreArchivo = 'saberplus_' . colegio_slug($colegio) . '_detalle_' . date('Ymd') . '.csv';
        header('Content-Type: text/csv; charset=UTF-8');
        header('Content-Disposition: attachment; filename="' . $nombreArchivo . '"');
        header('Pragma: public');
        header('Expires: 0');

        $fh = fopen('php://output', 'w');
        echo "\xEF\xBB\xBF"; // BOM UTF-8 para Excel
        csv_fila($fh, ['Estudiante', 'Email', 'Grado']);
        csv_fila($fh, [$est['nombre'], $est['email'], $est['grado']]);
        csv_fila($fh, []); // línea en blanco de separación
        csv_fila($fh, ['Fecha', 'Puntaje global', 'Lectura', 'Matematicas', 'Sociales', 'Naturales', 'Ingles']);
        foreach ($simulacros as $s) {
            csv_fila($fh, [
                $s['fecha_realizacion'],
                $s['puntaje_global'],
                $s['lectura_puntaje'],
                $s['matematicas_puntaje'],
                $s['sociales_puntaje'],
                $s['naturales_puntaje'],
                $s['ingles_puntaje'],
            ]);
        }
        fclose($fh);
        exit;
    }
} catch (PDOException $ex) {
    error_log('[DIRECTOR] export_csv (' . $tipo . '): ' . $ex->getMessage());
    http_response_code(500);
    exit('Error generando el archivo CSV. Intenta más tarde.');
}
