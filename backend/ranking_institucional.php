<?php
declare(strict_types=1);

/**
 * ranking_institucional.php — Saber+ v1.6.0
 *
 * Rankings agregados por institución:
 *   - tipo=colegios       → ranking de colegios por XP total de sus estudiantes
 *   - tipo=departamentos  → ranking de departamentos
 *
 * Períodos (como gamification_ranking.php):
 *   - all_time : XP total acumulada
 *   - weekly   : XP ganada en los últimos 7 días
 *   - monthly  : XP ganada en los últimos 30 días
 *
 * Request:
 *   GET  /ranking_institucional.php?tipo=colegios&period=all_time&limit=50
 *   POST { "tipo": "colegios", "period": "weekly", "limit": 50 }
 *
 * Response:
 * {
 *   "status": "ok",
 *   "data": {
 *     "tipo": "colegios",
 *     "period": "all_time",
 *     "total_instituciones": 87,
 *     "mi_institucion": { "nombre": "...", "posicion": 12, "total_xp": 5400, "usuarios": 8 } | null,
 *     "ranking": [
 *       { "posicion": 1, "nombre": "Colegio X", "departamento": "Antioquia",
 *         "ciudad": "Medellín", "total_xp": 45000, "usuarios": 32, "nivel_promedio": 4.2 }
 *     ]
 *   }
 * }
 */

require __DIR__ . '/vendor/autoload.php';
require __DIR__ . '/includes/conexion.php';
require __DIR__ . '/auth_middleware.php';
require __DIR__ . '/includes/analytics.php';

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if (!in_array($_SERVER['REQUEST_METHOD'], ['POST', 'GET'], true)) {
    http_response_code(405);
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
}

$user_id = (int)($authUser['id_usuario'] ?? 0);
if ($user_id <= 0) {
    http_response_code(401);
    exit(json_encode(['status' => 'error', 'msg' => 'Usuario no válido']));
}

// ── Parámetros ──
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $tipo   = $_GET['tipo'] ?? 'colegios';
    $period = $_GET['period'] ?? 'all_time';
    $limit  = (int)($_GET['limit'] ?? 50);
} else {
    $input  = json_decode(file_get_contents('php://input'), true) ?: [];
    $tipo   = $input['tipo'] ?? 'colegios';
    $period = $input['period'] ?? 'all_time';
    $limit  = (int)($input['limit'] ?? 50);
}

// Whitelist estricta — el campo se usa como nombre de columna
$campoTipo = $tipo === 'departamentos' ? 'departamento' : ($tipo === 'colegios' ? 'colegio' : null);
if ($campoTipo === null) {
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'tipo no válido (usar: colegios, departamentos)']));
}

$valid_periods = ['all_time', 'weekly', 'monthly'];
if (!in_array($period, $valid_periods, true)) {
    http_response_code(400);
    exit(json_encode(['status' => 'error', 'msg' => 'period no válido (usar: all_time, weekly, monthly)']));
}

// Sanitizar como int (mismo criterio que gamification_ranking.php)
$limit = max(1, min(200, $limit));

try {
    $days = $period === 'weekly' ? 7 : 30;

    if ($period === 'all_time') {
        // XP total acumulada por institución
        $sql = "
            SELECT TRIM(u.{$campoTipo})                          AS nombre,
                   MAX(TRIM(u.departamento))                     AS departamento,
                   MAX(TRIM(u.ciudad))                           AS ciudad,
                   SUM(ug.total_xp)                              AS total_xp,
                   COUNT(DISTINCT u.id_usuario)                  AS usuarios,
                   ROUND(AVG(ug.current_level), 1)               AS nivel_promedio
            FROM usuarios u
            JOIN user_gamification ug ON ug.user_id = u.id_usuario
            WHERE u.{$campoTipo} IS NOT NULL
              AND TRIM(u.{$campoTipo}) <> ''
              AND u.email_verificado = 1
              AND ug.total_xp > 0
            GROUP BY TRIM(u.{$campoTipo})
            ORDER BY total_xp DESC
            LIMIT {$limit}
        ";
        $stmt = $conexion->prepare($sql);
        $stmt->execute();
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $totalInstituciones = (int)$conexion->query("
            SELECT COUNT(DISTINCT TRIM(u.{$campoTipo}))
            FROM usuarios u
            JOIN user_gamification ug ON ug.user_id = u.id_usuario
            WHERE u.{$campoTipo} IS NOT NULL AND TRIM(u.{$campoTipo}) <> ''
              AND u.email_verificado = 1 AND ug.total_xp > 0
        ")->fetchColumn();
    } else {
        // XP ganada en el período (weekly/monthly)
        $sql = "
            SELECT TRIM(u.{$campoTipo})                          AS nombre,
                   MAX(TRIM(u.departamento))                     AS departamento,
                   MAX(TRIM(u.ciudad))                           AS ciudad,
                   SUM(xt.xp_amount)                             AS total_xp,
                   COUNT(DISTINCT u.id_usuario)                  AS usuarios,
                   ROUND(AVG(ug.current_level), 1)               AS nivel_promedio
            FROM xp_transactions xt
            JOIN usuarios u        ON u.id_usuario = xt.user_id
            JOIN user_gamification ug ON ug.user_id = xt.user_id
            WHERE xt.created_at >= DATE_SUB(NOW(), INTERVAL {$days} DAY)
              AND xt.xp_amount > 0
              AND u.{$campoTipo} IS NOT NULL
              AND TRIM(u.{$campoTipo}) <> ''
              AND u.email_verificado = 1
            GROUP BY TRIM(u.{$campoTipo})
            ORDER BY total_xp DESC
            LIMIT {$limit}
        ";
        $stmt = $conexion->prepare($sql);
        $stmt->execute();
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $stmt = $conexion->prepare("
            SELECT COUNT(DISTINCT TRIM(u.{$campoTipo}))
            FROM xp_transactions xt
            JOIN usuarios u ON u.id_usuario = xt.user_id
            WHERE xt.created_at >= DATE_SUB(NOW(), INTERVAL {$days} DAY)
              AND xt.xp_amount > 0
              AND u.{$campoTipo} IS NOT NULL AND TRIM(u.{$campoTipo}) <> ''
              AND u.email_verificado = 1
        ");
        $stmt->execute();
        $totalInstituciones = (int)$stmt->fetchColumn();
    }

    // ── Procesar ranking ──
    $ranking = [];
    $miInstitucion = null;

    // Institución del usuario actual
    $stmt = $conexion->prepare("SELECT TRIM({$campoTipo}) as mia FROM usuarios WHERE id_usuario = ?");
    $stmt->execute([$user_id]);
    $miNombre = (string)($stmt->fetchColumn() ?: '');

    foreach ($rows as $i => $row) {
        $entry = [
            'posicion'        => $i + 1,
            'nombre'          => $row['nombre'],
            'departamento'    => $row['departamento'] ?: null,
            'ciudad'          => $row['ciudad'] ?: null,
            'total_xp'        => (int)$row['total_xp'],
            'usuarios'        => (int)$row['usuarios'],
            'nivel_promedio'  => (float)$row['nivel_promedio'],
            'es_mia'          => ($miNombre !== '' && strcasecmp($miNombre, (string)$row['nombre']) === 0),
        ];
        $ranking[] = $entry;

        if ($entry['es_mia']) {
            $miInstitucion = [
                'nombre'   => $entry['nombre'],
                'posicion' => $entry['posicion'],
                'total_xp' => $entry['total_xp'],
                'usuarios' => $entry['usuarios'],
            ];
        }
    }

    // Si la institución del usuario no está en el top, calcular su posición real
    if ($miNombre !== '' && $miInstitucion === null) {
        if ($period === 'all_time') {
            // XP total de la institución del usuario (agregado de sus estudiantes)
            $stmt = $conexion->prepare("
                SELECT COUNT(*) + 1
                FROM (
                    SELECT TRIM(u.{$campoTipo}) as inst, SUM(ug.total_xp) as xp
                    FROM usuarios u
                    JOIN user_gamification ug ON ug.user_id = u.id_usuario
                    WHERE u.{$campoTipo} IS NOT NULL AND TRIM(u.{$campoTipo}) <> ''
                      AND u.email_verificado = 1 AND ug.total_xp > 0
                    GROUP BY TRIM(u.{$campoTipo})
                ) t
                WHERE t.xp > (
                    SELECT COALESCE(SUM(ug2.total_xp), 0)
                    FROM usuarios u2
                    JOIN user_gamification ug2 ON ug2.user_id = u2.id_usuario
                    WHERE TRIM(u2.{$campoTipo}) = ?
                      AND u2.email_verificado = 1
                )
            ");
            $stmt->execute([$miNombre]);
        } else {
            $stmt = $conexion->prepare("
                SELECT COUNT(*) + 1
                FROM (
                    SELECT TRIM(u.{$campoTipo}) as inst, SUM(xt.xp_amount) as xp
                    FROM xp_transactions xt
                    JOIN usuarios u ON u.id_usuario = xt.user_id
                    WHERE xt.created_at >= DATE_SUB(NOW(), INTERVAL {$days} DAY)
                      AND xt.xp_amount > 0
                      AND u.{$campoTipo} IS NOT NULL AND TRIM(u.{$campoTipo}) <> ''
                      AND u.email_verificado = 1
                    GROUP BY TRIM(u.{$campoTipo})
                ) t
                WHERE t.xp > (
                    SELECT COALESCE(SUM(xt2.xp_amount), 0)
                    FROM xp_transactions xt2
                    JOIN usuarios u3 ON u3.id_usuario = xt2.user_id
                    WHERE TRIM(u3.{$campoTipo}) = ?
                      AND u3.email_verificado = 1
                      AND xt2.created_at >= DATE_SUB(NOW(), INTERVAL {$days} DAY)
                      AND xt2.xp_amount > 0
                )
            ");
            $stmt->execute([$miNombre]);
        }
        $pos = (int)$stmt->fetchColumn();

        // XP y nº de estudiantes de mi institución (para la tarjeta)
        if ($period === 'all_time') {
            $stmt = $conexion->prepare("
                SELECT COALESCE(SUM(ug.total_xp), 0), COUNT(DISTINCT u.id_usuario)
                FROM usuarios u
                JOIN user_gamification ug ON ug.user_id = u.id_usuario
                WHERE TRIM(u.{$campoTipo}) = ? AND u.email_verificado = 1
            ");
        } else {
            $stmt = $conexion->prepare("
                SELECT COALESCE(SUM(xt.xp_amount), 0), COUNT(DISTINCT u.id_usuario)
                FROM xp_transactions xt
                JOIN usuarios u ON u.id_usuario = xt.user_id
                WHERE TRIM(u.{$campoTipo}) = ? AND u.email_verificado = 1
                  AND xt.created_at >= DATE_SUB(NOW(), INTERVAL {$days} DAY)
                  AND xt.xp_amount > 0
            ");
        }
        $stmt->execute([$miNombre]);
        [$miXp, $miUsuarios] = $stmt->fetch(PDO::FETCH_NUM);

        $miInstitucion = [
            'nombre'   => $miNombre,
            'posicion' => $pos,
            'total_xp' => (int)$miXp,
            'usuarios' => (int)$miUsuarios,
        ];
    }

    echo json_encode([
        'status' => 'ok',
        'data'   => [
            'tipo'                => $tipo,
            'period'              => $period,
            'total_instituciones' => $totalInstituciones,
            'mi_institucion'      => $miInstitucion,
            'ranking'             => $ranking,
        ],
    ], JSON_UNESCAPED_UNICODE);

} catch (Throwable $e) {
    saberplus_log_error(
        $conexion, 'backend', 'ranking_institucional.php: ' . $e->getMessage(),
        ['tipo' => $tipo ?? '?', 'period' => $period ?? '?'], get_class($e), 'fatal'
    );
    error_log('[RANKING_INSTITUCIONAL] Error: ' . $e->getMessage());
    http_response_code(500);
    exit(json_encode(['status' => 'error', 'msg' => 'Error interno en el ranking institucional']));
}
