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

require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle.php';

try {
  // 1) Leer body JSON
  $raw = file_get_contents('php://input');
  error_log("[area_trend][RAW BODY] " . ($raw ?: 'EMPTY'));
  $data = json_decode($raw, true);

  if (!is_array($data) || !isset($data['userId']) || !isset($data['area'])) {
    echo json_encode(['status' => 'error', 'msg' => 'userId y area requeridos']);
    exit;
  }

  $userId = intval($data['userId']);
  $area   = strtolower(trim($data['area']));
  error_log("[area_trend] Recibió userId interno=$userId area=$area");

  // 2) Mapear id_usuario interno a moodle_id
  $sqlMap = "SELECT moodle_id FROM usuarios WHERE id_usuario = :id";
  $stmtMap = $conexion->prepare($sqlMap);
  $stmtMap->execute([':id' => $userId]);
  $mapRow = $stmtMap->fetch(PDO::FETCH_ASSOC);
  error_log("[area_trend] Mapeo id_usuario=$userId ? moodle_id=" . ($mapRow['moodle_id'] ?? 'NULL'));

  if (!$mapRow || !isset($mapRow['moodle_id'])) {
    echo json_encode(['status' => 'ok', 'data' => []]);
    exit;
  }

  $moodleId = intval($mapRow['moodle_id']);

  // 3) Validar área y seleccionar columna
  $mapAreas = [
    'lectura'     => 'lectura_puntaje',
    'matematicas' => 'matematicas_puntaje',
    'sociales'    => 'sociales_puntaje',
    'naturales'   => 'naturales_puntaje',
    'ingles'      => 'ingles_puntaje',
  ];

  if (!array_key_exists($area, $mapAreas)) {
    echo json_encode(['status' => 'error', 'msg' => 'Área inválida']);
    exit;
  }

  $col = $mapAreas[$area];
  error_log("[area_trend] Consultando columna=$col para moodle_id=$moodleId");

  // 4) Consulta evolución por simulacro
  $sql = "
    SELECT simulacro_id, course_id, fecha_realizacion, $col AS puntaje
    FROM simulacro_resultados
    WHERE usuario_id = :moodleId
    ORDER BY fecha_realizacion ASC
  ";

  $stmt = $conexion->prepare($sql);
  $stmt->execute([':moodleId' => $moodleId]);
  $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

  // 5) Normalizar tipos
  $trend = array_map(function($r) {
    return [
      'simulacroId' => intval($r['simulacro_id']),
      'courseId'    => intval($r['course_id']),
      'fecha'       => $r['fecha_realizacion'],
      'puntaje'     => $r['puntaje'] !== null ? floatval($r['puntaje']) : null,
    ];
  }, $rows);

  echo json_encode(['status' => 'ok', 'data' => $trend]);

} catch (Exception $e) {
  http_response_code(500);
  error_log("[area_trend][ERROR] " . $e->getMessage());
  echo json_encode(['status' => 'error', 'msg' => $e->getMessage()]);
}
