<?php
/**
 * ✅ PT7: export_csv.php — Exportación CSV del Panel Admin (Saber+)
 * Administration & Intelligence Center.
 *
 *   type=usuarios   → listado de usuarios (perfil + estadísticas de simulacros)
 *   type=resultados → resultados de simulacros (con usuario identificado)
 *   type=pagos      → pagos registrados (Wompi + Google Play Billing)
 *
 * Seguridad (patrón del panel director /export_csv.php):
 * - Requiere sesión admin activa (mismo esquema que admin/index.php).
 * - BOM UTF-8 (\xEF\xBB\xBF) para que Excel respete acentos/ñ.
 * - Anti CSV-injection: toda celda que empiece por = + - @ se prefija con '.
 * - Límite de 5000 filas por exportación.
 * - Auditoría de la exportación en admin_audit_log (migración 007).
 */

// ✅ PT3: cookie de sesión endurecida — mismo esquema que admin/index.php.
session_set_cookie_params([
    'httponly' => true,
    'samesite' => 'Lax',
]);
session_start();

require_once __DIR__ . '/../includes/conexion.php';
require_once __DIR__ . '/../includes/config.php';
require_once __DIR__ . '/../env.php';
require_once __DIR__ . '/includes/admin_audit.php';

// ── Auth: sesión admin activa (patrón de admin/index.php) ──
if (!isset($_SESSION['admin_logged_in']) || $_SESSION['admin_logged_in'] !== true) {
    http_response_code(403);
    exit('Acceso denegado: se requiere sesión de administrador.');
}

// ── Tipo de exportación (whitelist) ──
$tipo = (string)($_GET['type'] ?? '');
if (!in_array($tipo, ['usuarios', 'resultados', 'pagos'], true)) {
    http_response_code(400);
    exit('Tipo de exportación inválido.');
}

// ✅ PT7: límite duro de filas por exportación
$LIMITE_EXPORT = 5000;

/** ✅ PT7: prefija con ' las celdas peligrosas para fórmulas (CSV injection). */
function admin_csv_celda($valor)
{
    $v = (string)$valor;
    if ($v !== '' && ($v[0] === '=' || $v[0] === '+' || $v[0] === '-' || $v[0] === '@')) {
        return "'" . $v;
    }
    return $v;
}

/** ✅ PT7: escribe una fila aplicando la protección anti CSV-injection. */
function admin_csv_fila($fh, array $fila)
{
    fputcsv($fh, array_map('admin_csv_celda', $fila));
}

/** ✅ PT7: cabeceras + apertura del stream de salida con BOM UTF-8. */
function admin_csv_inicio(string $tipo): void
{
    $nombreArchivo = 'saberplus_admin_' . $tipo . '_' . date('Ymd') . '.csv';
    header('Content-Type: text/csv; charset=UTF-8');
    header('Content-Disposition: attachment; filename="' . $nombreArchivo . '"');
    header('Pragma: public');
    header('Expires: 0');
    echo "\xEF\xBB\xBF"; // BOM UTF-8 para Excel
}

try {
    if ($tipo === 'usuarios') {
        // ── Usuarios: perfil + estadísticas agregadas (JOIN del panel director) ──
        $stmt = $conexion->prepare("
            SELECT u.id_usuario, u.nombre, u.email, u.tipo_usuario, u.access_level,
                   u.email_verificado, u.departamento, u.ciudad, u.colegio, u.grado,
                   u.registration_date, u.ultimo_login,
                   COUNT(sr.id) AS num_simulacros,
                   ROUND(AVG(sr.puntaje_global), 1) AS promedio
            FROM usuarios u
            LEFT JOIN simulacro_resultados sr ON sr.usuario_id = u.moodle_id
            GROUP BY u.id_usuario, u.nombre, u.email, u.tipo_usuario, u.access_level,
                     u.email_verificado, u.departamento, u.ciudad, u.colegio, u.grado,
                     u.registration_date, u.ultimo_login
            ORDER BY u.id_usuario DESC
            LIMIT " . (int)$LIMITE_EXPORT
        );
        $stmt->execute();
        $filas = $stmt->fetchAll(PDO::FETCH_ASSOC);

        admin_csv_inicio($tipo);
        $fh = fopen('php://output', 'w');
        admin_csv_fila($fh, ['ID', 'Nombre', 'Email', 'Tipo', 'Plan', 'Email verificado',
                             'Departamento', 'Ciudad', 'Colegio', 'Grado',
                             'Registro', 'Ultimo login', 'Simulacros', 'Promedio']);
        foreach ($filas as $f) {
            admin_csv_fila($fh, [
                $f['id_usuario'],
                $f['nombre'],
                $f['email'],
                $f['tipo_usuario'],
                $f['access_level'],
                ((int)$f['email_verificado'] === 1) ? 'Si' : 'No',
                $f['departamento'],
                $f['ciudad'],
                $f['colegio'],
                $f['grado'],
                $f['registration_date'],
                $f['ultimo_login'],
                (int)$f['num_simulacros'],
                $f['promedio'],
            ]);
        }
        fclose($fh);

    } elseif ($tipo === 'resultados') {
        // ── Resultados de simulacros (usuario identificado vía moodle_id) ──
        $stmt = $conexion->prepare("
            SELECT sr.fecha_realizacion, u.nombre AS user_nombre, u.email AS user_email,
                   u.colegio, u.grado, sr.puntaje_global,
                   sr.lectura_puntaje, sr.matematicas_puntaje, sr.sociales_puntaje,
                   sr.naturales_puntaje, sr.ingles_puntaje, sr.tiempo_empleado
            FROM simulacro_resultados sr
            LEFT JOIN usuarios u ON sr.usuario_id = u.moodle_id
            ORDER BY sr.fecha_realizacion DESC, sr.id DESC
            LIMIT " . (int)$LIMITE_EXPORT
        );
        $stmt->execute();
        $filas = $stmt->fetchAll(PDO::FETCH_ASSOC);

        admin_csv_inicio($tipo);
        $fh = fopen('php://output', 'w');
        admin_csv_fila($fh, ['Fecha', 'Estudiante', 'Email', 'Colegio', 'Grado',
                             'Puntaje global', 'Lectura', 'Matematicas', 'Sociales',
                             'Naturales', 'Ingles', 'Tiempo (segundos)']);
        foreach ($filas as $f) {
            admin_csv_fila($fh, [
                $f['fecha_realizacion'],
                $f['user_nombre'],
                $f['user_email'],
                $f['colegio'],
                $f['grado'],
                $f['puntaje_global'],
                $f['lectura_puntaje'],
                $f['matematicas_puntaje'],
                $f['sociales_puntaje'],
                $f['naturales_puntaje'],
                $f['ingles_puntaje'],
                $f['tiempo_empleado'],
            ]);
        }
        fclose($fh);

    } else {
        // ── Pagos: SELECT p.* tolera columnas opcionales ausentes (gateway 004,
        //    promo_id 006, created_at) — las celdas faltantes salen vacías ──
        $stmt = $conexion->prepare("
            SELECT p.*, u.email AS user_email, u.nombre AS user_nombre
            FROM payments p
            LEFT JOIN usuarios u ON p.user_id = u.moodle_id
            ORDER BY p.id DESC
            LIMIT " . (int)$LIMITE_EXPORT
        );
        $stmt->execute();
        $filas = $stmt->fetchAll(PDO::FETCH_ASSOC);

        admin_csv_inicio($tipo);
        $fh = fopen('php://output', 'w');
        admin_csv_fila($fh, ['Fecha', 'Usuario', 'Email', 'Monto', 'Moneda',
                             'Pasarela', 'Estado', 'Referencia']);
        foreach ($filas as $f) {
            admin_csv_fila($fh, [
                $f['created_at'] ?? ($f['updated_at'] ?? ''),
                $f['user_nombre'] ?? ('Usuario Moodle #' . ($f['user_id'] ?? '')),
                $f['user_email'] ?? '',
                $f['amount'] ?? 0,
                $f['currency'] ?? '',
                $f['gateway'] ?? '',
                $f['status'] ?? '',
                $f['reference_code'] ?? '',
            ]);
        }
        fclose($fh);
    }

    // ✅ PT7: auditoría del export (no-op silencioso si la tabla aún no existe)
    admin_audit_log($conexion, 'export_csv', 'export', null,
        json_encode(['tipo' => $tipo, 'filas' => count($filas)], JSON_UNESCAPED_UNICODE));
    exit;

} catch (PDOException $ex) {
    error_log('[ADMIN] export_csv (' . $tipo . '): ' . $ex->getMessage());
    http_response_code(500);
    exit('Error generando el archivo CSV. Intenta más tarde.');
}
