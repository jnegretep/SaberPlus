<?php
declare(strict_types=1);

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: POST, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    exit(json_encode(['status'=>'error','msg'=>'Método no permitido']));
}

require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle.php'; // tu middleware ya valida el token

try {
  // 1) Leer body JSON
  $raw = file_get_contents('php://input');
  error_log("[summary][RAW BODY] " . ($raw ?: 'EMPTY'));
  $data = json_decode($raw, true);

  if (!is_array($data) || !isset($data['userId'])) {
    error_log("[summary][ERROR] JSON inválido o userId no recibido. Data recibida: " . print_r($data, true));
    echo json_encode(['status' => 'error', 'msg' => 'userId requerido']);
    exit;
  }

  $userId = intval($data['userId']);
  error_log("[summary] Recibió userId interno: $userId");

  // 2) Mapear id_usuario interno a moodle_id
  $sqlMap = "SELECT moodle_id FROM usuarios WHERE id_usuario = :id";
  $stmtMap = $conexion->prepare($sqlMap);
  $stmtMap->execute([':id' => $userId]);
  $mapRow = $stmtMap->fetch(PDO::FETCH_ASSOC);
  error_log("[summary] Mapeo id_usuario=$userId ? moodle_id=" . ($mapRow['moodle_id'] ?? 'NULL'));

  if (!$mapRow || !isset($mapRow['moodle_id'])) {
    $response = [
      'status' => 'ok',
      'data' => [
        'simulacros_realizados' => 0,
        'ultima_fecha' => null,
        'promedio_global' => null,
        'tiempo_promedio_seg' => null,
        'areas' => [
          'lectura' => null,
          'matematicas' => null,
          'sociales' => null,
          'naturales' => null,
          'ingles' => null,
        ],
      ]
    ];
    
    // IMPRIMIR DATOS ANTES DE SALIR
    error_log("[summary][RESPONSE] Usuario sin moodle_id. Response: " . json_encode($response, JSON_PRETTY_PRINT));
    
    echo json_encode($response);
    exit;
  }

  $moodleId = intval($mapRow['moodle_id']);
  error_log("[summary] Consultando simulacro_resultados con usuario_id=$moodleId");

  // 3) Consulta agregada
  $sql = "
    SELECT
      COUNT(*) AS simulacros_realizados,
      MAX(fecha_realizacion) AS ultima_fecha,
      AVG(puntaje_global) AS promedio_global,
      AVG(tiempo_empleado) AS tiempo_promedio_seg,
      AVG(lectura_puntaje) AS lectura,
      AVG(matematicas_puntaje) AS matematicas,
      AVG(sociales_puntaje) AS sociales,
      AVG(naturales_puntaje) AS naturales,
      AVG(ingles_puntaje) AS ingles
    FROM simulacro_resultados
    WHERE usuario_id = :moodleId
  ";

  $stmt = $conexion->prepare($sql);
  $stmt->execute([':moodleId' => $moodleId]);
  $row = $stmt->fetch(PDO::FETCH_ASSOC) ?: [];
  
  // IMPRIMIR DATOS OBTENIDOS DE LA BD
  error_log("[summary][DB_RESULT] " . print_r($row, true));

  // 4) Normalización de tipos
  $simRealizados = isset($row['simulacros_realizados']) ? intval($row['simulacros_realizados']) : 0;
  $ultimaFecha = $row['ultima_fecha'] ?? null;
  $promGlobal  = isset($row['promedio_global']) ? floatval($row['promedio_global']) : null;
  $tiempoProm  = isset($row['tiempo_promedio_seg']) ? intval($row['tiempo_promedio_seg']) : null;

  $areas = [
    'lectura'     => isset($row['lectura']) ? floatval($row['lectura']) : null,
    'matematicas' => isset($row['matematicas']) ? floatval($row['matematicas']) : null,
    'sociales'    => isset($row['sociales']) ? floatval($row['sociales']) : null,
    'naturales'   => isset($row['naturales']) ? floatval($row['naturales']) : null,
    'ingles'      => isset($row['ingles']) ? floatval($row['ingles']) : null,
  ];

  $response = [
    'status' => 'ok',
    'data' => [
      'simulacros_realizados' => $simRealizados,
      'ultima_fecha' => $ultimaFecha,
      'promedio_global' => $promGlobal,
      'tiempo_promedio_seg' => $tiempoProm,
      'areas' => $areas,
    ]
  ];

  // IMPRIMIR RESPUESTA FINAL ANTES DE ENVIAR
  error_log("[summary][FINAL_RESPONSE] " . json_encode($response, JSON_PRETTY_PRINT));
  
  // También puedes imprimir datos adicionales para depuración
  error_log("[summary][DEBUG_INFO] userId: $userId, moodleId: $moodleId, simulacros: $simRealizados");

  echo json_encode($response);

} catch (Exception $e) {
  http_response_code(500);
  error_log("[summary][ERROR] " . $e->getMessage());
  error_log("[summary][ERROR_TRACE] " . $e->getTraceAsString());
  echo json_encode(['status' => 'error', 'msg' => $e->getMessage()]);
}