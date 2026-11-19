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
    $out = json_encode(['status'=>'error','msg'=>'Método no permitido'], JSON_UNESCAPED_UNICODE);
    error_log("[context][OUTPUT] $out");
    echo $out;
    exit;
}

require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle.php'; // middleware valida token

function sanitize_utf8($value) {
  if (is_array($value)) {
    foreach ($value as $k => $v) {
      $value[$k] = sanitize_utf8($v);
    }
    return $value;
  }
  if (is_string($value)) {
    $enc = mb_detect_encoding($value, ['UTF-8','ISO-8859-1','Windows-1252'], true);
    if ($enc !== 'UTF-8') {
      $value = mb_convert_encoding($value, 'UTF-8', $enc ?: 'UTF-8');
    }
  }
  return $value;
}

function emit_json_with_logs(string $tag, array $payload, int $httpCode = 200): void {
  http_response_code($httpCode);
  $safePayload = sanitize_utf8($payload);
  error_log("[$tag][RESPONSE ARRAY] " . var_export($safePayload, true));
  $json = json_encode($safePayload, JSON_UNESCAPED_UNICODE);
  if ($json === false) {
    $msg = json_last_error_msg();
    error_log("[$tag][JSON ERROR] $msg");
    $json = json_encode(['status' => 'error', 'msg' => "json_encode fallo: $msg"], JSON_UNESCAPED_UNICODE);
  }
  error_log("[$tag][OUTPUT] $json");
  echo $json;
  exit;
}

try {
  // 1) Leer body JSON
  $raw = file_get_contents('php://input');
  error_log("[context][RAW BODY] " . ($raw ?: 'EMPTY'));
  $data = json_decode($raw, true);

  if (!is_array($data) || !isset($data['userId'])) {
    emit_json_with_logs('context', ['status' => 'error', 'msg' => 'userId requerido']);
  }

  $userId = intval($data['userId']);
  $scope  = isset($data['scope']) ? strtolower(trim((string)$data['scope'])) : 'national';
  $area   = isset($data['area']) ? strtolower(trim((string)$data['area'])) : null;

  $allowedScopes = ['city','dept','school','national'];
  if (!in_array($scope, $allowedScopes, true)) {
    emit_json_with_logs('context', ['status'=>'error','msg'=>'Scope inválido']);
  }

  // 2) Mapear id_usuario interno a moodle_id y datos de contexto
  $sqlMap = "SELECT moodle_id, colegio, ciudad, departamento FROM usuarios WHERE id_usuario = :id";
  $stmtMap = $conexion->prepare($sqlMap);
  $stmtMap->execute([':id' => $userId]);
  $mapRow = $stmtMap->fetch(PDO::FETCH_ASSOC);
  error_log("[context] Mapeo id_usuario=$userId ? moodle_id=" . ($mapRow['moodle_id'] ?? 'NULL'));

  if (!$mapRow || !isset($mapRow['moodle_id'])) {
    emit_json_with_logs('context', [
      'status' => 'ok',
      'data' => [
        'tuPromedio' => null,
        'segmentoPromedio' => null,
        'n' => 0,
        'percentil' => null,
        'status' => 'insufficient'
      ]
    ]);
  }

  $moodleId   = intval($mapRow['moodle_id']);
  $colegioVal = $mapRow['colegio'] ?? null;
  $ciudadVal  = $mapRow['ciudad'] ?? null;
  $deptoVal   = $mapRow['departamento'] ?? null;

  // 3) Determinar campo de puntaje (aceptar 'global' y null como puntaje_global)
  $areaToColumn = [
    'lectura'     => 'lectura_puntaje',
    'matematicas' => 'matematicas_puntaje',
    'sociales'    => 'sociales_puntaje',
    'naturales'   => 'naturales_puntaje',
    'ingles'      => 'ingles_puntaje',
  ];
  $campoPuntaje = 'puntaje_global';
  if ($area !== null) {
    if ($area === 'global') {
      $campoPuntaje = 'puntaje_global';
    } elseif (isset($areaToColumn[$area])) {
      $campoPuntaje = $areaToColumn[$area];
    } else {
      emit_json_with_logs('context', ['status'=>'error','msg'=>'Área inválida']);
    }
  }

  error_log("[context] scope=$scope area=" . ($area ?: 'global') . " campo=$campoPuntaje");

  // 4) Promedio del usuario (redondeado)
  $sqlUser = "SELECT ROUND(AVG($campoPuntaje), 1) AS promedio FROM simulacro_resultados WHERE usuario_id = :uid";
  $stmtUser = $conexion->prepare($sqlUser);
  $stmtUser->execute([':uid' => $moodleId]);
  $rowUser = $stmtUser->fetch(PDO::FETCH_ASSOC) ?: [];
  $tuPromedio = isset($rowUser['promedio']) ? floatval($rowUser['promedio']) : null;

  if ($tuPromedio === null) {
    emit_json_with_logs('context', [
      'status' => 'ok',
      'data' => [
        'tuPromedio' => null,
        'segmentoPromedio' => null,
        'n' => 0,
        'percentil' => null,
        'status' => 'insufficient'
      ]
    ]);
  }

  // 5) Promedio del segmento
  $whereScope = '';
  $paramsScope = [];

  switch ($scope) {
    case 'school':
      if ($colegioVal) {
        $whereScope = "WHERE r.colegio = :colegio";
        $paramsScope[':colegio'] = $colegioVal;
      } else {
        // Sin dato de colegio ? no hay segmento
        emit_json_with_logs('context', [
          'status' => 'ok',
          'data' => [
            'tuPromedio' => $tuPromedio,
            'segmentoPromedio' => null,
            'n' => 0,
            'percentil' => null,
            'status' => 'insufficient'
          ]
        ]);
      }
      break;
    case 'city':
      if ($ciudadVal) {
        $whereScope = "WHERE r.ciudad = :ciudad";
        $paramsScope[':ciudad'] = $ciudadVal;
      } else {
        emit_json_with_logs('context', [
          'status' => 'ok',
          'data' => [
            'tuPromedio' => $tuPromedio,
            'segmentoPromedio' => null,
            'n' => 0,
            'percentil' => null,
            'status' => 'insufficient'
          ]
        ]);
      }
      break;
    case 'dept':
      if ($deptoVal) {
        $whereScope = "WHERE r.departamento = :depto";
        $paramsScope[':depto'] = $deptoVal;
      } else {
        emit_json_with_logs('context', [
          'status' => 'ok',
          'data' => [
            'tuPromedio' => $tuPromedio,
            'segmentoPromedio' => null,
            'n' => 0,
            'percentil' => null,
            'status' => 'insufficient'
          ]
        ]);
      }
      break;
    case 'national':
      $whereScope = "";
      break;
  }

  $sqlSeg = "
    SELECT ROUND(AVG($campoPuntaje), 1) AS promedio, COUNT(DISTINCT r.usuario_id) AS n
    FROM simulacro_resultados r
    $whereScope
  ";
  $stmtSeg = $conexion->prepare($sqlSeg);
  $stmtSeg->execute($paramsScope);
  $rowSeg = $stmtSeg->fetch(PDO::FETCH_ASSOC) ?: [];
  $segmentoPromedio = isset($rowSeg['promedio']) ? floatval($rowSeg['promedio']) : null;
  $n = isset($rowSeg['n']) ? intval($rowSeg['n']) : 0;

  // 6) Cohortes mínimas por scope y flag "preliminar"
  $MIN_COHORTE = [
    'national' => 2,
    'dept'     => 3,
    'city'     => 3,
    'school'   => 3,
  ];
  $minCohorte = $MIN_COHORTE[$scope] ?? 3;
  $preliminar = false;

  // Si no hay nadie en el segmento, devolvemos insufficient
  if ($n === 0 || $segmentoPromedio === null) {
    emit_json_with_logs('context', [
      'status' => 'ok',
      'data' => [
        'tuPromedio'       => $tuPromedio,
        'segmentoPromedio' => null,
        'n'                => $n,
        'percentil'        => null,
        'status'           => 'insufficient',
        'scope'            => $scope,
        'area'             => $area ?: 'global',
        'preliminar'       => false,
        'nMin'             => $minCohorte,
      ]
    ]);
  }

  if ($n < $minCohorte) {
    $preliminar = true; // seguimos calculando, pero marcamos preliminar
  }

  // 7) Status comparativo
  $status = 'equal';
  if ($segmentoPromedio !== null) {
    if ($tuPromedio > $segmentoPromedio) $status = 'up';
    elseif ($tuPromedio < $segmentoPromedio) $status = 'down';
  }

  // 8) Percentil aproximado
  $percentil = null;
  try {
    $sqlDist = "
      SELECT u_prom.promedio AS prom
      FROM (
        SELECT r.usuario_id, ROUND(AVG($campoPuntaje), 1) AS promedio
        FROM simulacro_resultados r
        $whereScope
        GROUP BY r.usuario_id
      ) AS u_prom
      ORDER BY u_prom.promedio ASC
    ";
    $stmtDist = $conexion->prepare($sqlDist);
    $stmtDist->execute($paramsScope);
    $promedios = $stmtDist->fetchAll(PDO::FETCH_COLUMN);

    if ($promedios && count($promedios) > 0) {
      $total = count($promedios);
      $belowOrEqual = 0;
      foreach ($promedios as $p) {
        if (floatval($p) <= $tuPromedio) $belowOrEqual++;
      }
      $percentil = round(($belowOrEqual / $total) * 100, 1);
    }
  } catch (Exception $pe) {
    error_log("[context][percentil] fallo calculo: " . $pe->getMessage());
    $percentil = null;
  }

  // 9) Respuesta final
  $response = [
    'status' => 'ok',
    'data' => [
      'tuPromedio'        => $tuPromedio,
      'segmentoPromedio'  => $segmentoPromedio,
      'n'                 => $n,
      'percentil'         => $percentil,
      'status'            => $status,
      'scope'             => $scope,
      'area'              => $area ?: 'global',
      'preliminar'        => $preliminar,
      'nMin'              => $minCohorte,
    ]
  ];

  // Sanea y emite con logs
  $safeResponse = sanitize_utf8($response);
  error_log("[context][RESPONSE ARRAY] " . var_export($safeResponse, true));
  $jsonOut = json_encode($safeResponse, JSON_UNESCAPED_UNICODE);
  if ($jsonOut === false) {
    $msg = json_last_error_msg();
    error_log("[context][JSON ERROR] $msg");
    $jsonOut = json_encode(['status'=>'error','msg'=>"json_encode fallo: $msg"], JSON_UNESCAPED_UNICODE);
  }
  error_log("[context][OUTPUT] " . $jsonOut);
  echo $jsonOut;
  exit;

} catch (Exception $e) {
  http_response_code(500);
  error_log("[context][ERROR] " . $e->getMessage());
  emit_json_with_logs('context', ['status' => 'error', 'msg' => $e->getMessage()], 500);
}
