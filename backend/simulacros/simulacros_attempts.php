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
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

try {
  // 1) Leer userId desde POST (id_usuario interno)
  if (!isset($_POST['userId'])) {
    echo json_encode(['status' => 'error', 'message' => 'userId requerido']);
    exit;
  }
$userId = intval($_POST['userId']);
error_log("?? simulacros_attempts.php recibió userId interno: $userId");

  // 2) Convertir id_usuario interno a moodle_id
  $sqlMap = "SELECT moodle_id FROM usuarios WHERE id_usuario = :id";
  $stmtMap = $conexion->prepare($sqlMap);
  $stmtMap->execute([':id' => $userId]);
$mapRow = $stmtMap->fetch(PDO::FETCH_ASSOC);
error_log("?? Mapeo id_usuario=$userId ? moodle_id=" . ($mapRow['moodle_id'] ?? 'NULL'));


  if (!$mapRow || !isset($mapRow['moodle_id'])) {
    echo json_encode(['status' => 'ok', 'attempts' => []]);
    exit;
  }

  $moodleId = intval($mapRow['moodle_id']);
error_log("?? Consultando simulacro_resultados con usuario_id=$moodleId");

  // 3) Consulta: simulacros realizados por usuario usando moodle_id
  $sql = "
    SELECT sr.course_id        AS courseId,
           sr.id               AS attemptId,
           sr.fecha_realizacion AS finishedAt
    FROM simulacro_resultados sr
    WHERE sr.usuario_id = :moodleId
  ";

  $stmt = $conexion->prepare($sql);
  $stmt->execute([':moodleId' => $moodleId]);
  $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

  // 4) Normalizar tipos
  $attempts = array_map(function($r) {
    return [
      'courseId'   => intval($r['courseId']),
      'attemptId'  => intval($r['attemptId']),
      'finished'   => true,
      'finishedAt' => $r['finishedAt'] ? strtotime($r['finishedAt']) : null
    ];
  }, $rows);

  echo json_encode(['status' => 'ok', 'attempts' => $attempts]);

} catch (Exception $e) {
  http_response_code(500);
  echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
error_log("? Se encontraron " . count($rows) . " intentos de simulacros para moodle_id=$moodleId");

}
