<?php
declare(strict_types=1);

/**
 * get_active_promos.php — Promociones vigentes para la app (v1.7.0)
 *
 * Endpoint público de SOLO LECTURA (no expone nada sensible: solo
 * promociones activas dentro de su ventana de vigencia y con cupo).
 *
 * La app lo consulta al abrir la pantalla Premium → los banners y
 * precios con descuento se ven en la app AL INSTANTE tras crearlos
 * en /admin → Promociones (sin rebuild ni publicar).
 *
 * Respuesta:
 * {
 *   "status": "ok",
 *   "promos": [
 *     {
 *       "id": 1,
 *       "titulo": "Lanzamiento SaberPlus",
 *       "descripcion": "20% dcto...",
 *       "tipo": "banner",            // banner | codigo
 *       "codigo": null,               // solo si tipo=codigo (el admin elige si mostrarlo)
 *       "descuento_tipo": "porcentaje",
 *       "descuento_valor": 20,
 *       "plan_id": null,              // null = todos los planes
 *       "fecha_fin": "2026-12-31 23:59:59",
 *       "segundos_restantes": 123456
 *     }
 *   ]
 * }
 */

header('Access-Control-Allow-Origin: *');
header('Content-Type: application/json; charset=UTF-8');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET' && $_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit(json_encode(['status' => 'error', 'msg' => 'Método no permitido']));
}

require __DIR__ . '/includes/conexion.php';

try {
    $stmt = $conexion->prepare("
        SELECT id, titulo, descripcion, tipo, codigo,
               descuento_tipo, descuento_valor, plan_id, fecha_fin
        FROM promociones
        WHERE activo = 1
          AND NOW() BETWEEN fecha_inicio AND fecha_fin
          AND (max_usos IS NULL OR usos < max_usos)
        ORDER BY descuento_valor DESC, id DESC
        LIMIT 5
    ");
    $stmt->execute();
    $promos = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $hoy = new DateTimeImmutable('now');
    $salida = [];
    foreach ($promos as $p) {
        $item = [
            'id'                => (int)$p['id'],
            'titulo'            => (string)$p['titulo'],
            'descripcion'       => $p['descripcion'] !== null ? (string)$p['descripcion'] : '',
            'tipo'              => (string)$p['tipo'],
            'codigo'            => null, // nunca se filtra el código: se escribe/canjea
            'descuento_tipo'    => (string)$p['descuento_tipo'],
            'descuento_valor'   => (float)$p['descuento_valor'],
            'plan_id'           => $p['plan_id'] !== null ? (int)$p['plan_id'] : null,
            'fecha_fin'         => (string)$p['fecha_fin'],
            'segundos_restantes' => max(0, (int)($hoy->getTimestamp() - strtotime((string)$p['fecha_fin'])) * -1),
        ];
        $salida[] = $item;
    }

    // Aunque no haya promos se responde ok con lista vacía (cache-friendly).
    echo json_encode([
        'status' => 'ok',
        'promos' => $salida,
    ], JSON_UNESCAPED_UNICODE);
} catch (Exception $e) {
    // Tabla aún no migrada → respuesta vacía, nunca rompe la app.
    error_log('[PROMOS] ' . $e->getMessage());
    echo json_encode(['status' => 'ok', 'promos' => []]);
}
