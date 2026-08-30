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
    error_log("[rank][OUTPUT] $out");
    echo $out;
    exit;
}

require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle.php'; // middleware valida token

/**
 * Sanea recursivamente valores a UTF-8 para evitar fallos de json_encode.
 */
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

/**
 * Emite respuesta JSON con logs robustos.
 */
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
  error_log("[rank][RAW BODY] " . ($raw ?: 'EMPTY'));
  $data = json_decode($raw, true);

  if (!is_array($data) || !isset($data['userId'])) {
    emit_json_with_logs('rank', ['status' => 'error', 'msg' => 'userId requerido']);
  }

  $userId = intval($data['userId']);
  $scope  = isset($data['scope']) ? strtolower(trim((string)$data['scope'])) : 'national';
  $area   = isset($data['area']) ? strtolower(trim((string)$data['area'])) : null;
  $topN   = isset($data['top']) ? max(1, intval($data['top'])) : 20;

  $allowedScopes = ['city','dept','school','national'];
  if (!in_array($scope, $allowedScopes, true)) {
    emit_json_with_logs('rank', ['status'=>'error','msg'=>'Scope inválido']);
  }

  // 2) Mapear id_usuario interno a moodle_id y datos de contexto
  $sqlMap = "SELECT moodle_id, colegio, ciudad, departamento FROM usuarios WHERE id_usuario = :id";
  $stmtMap = $conexion->prepare($sqlMap);
  $stmtMap->execute([':id' => $userId]);
  $mapRow = $stmtMap->fetch(PDO::FETCH_ASSOC);
  error_log("[rank] Mapeo id_usuario=$userId ? moodle_id=" . ($mapRow['moodle_id'] ?? 'NULL'));

  if (!$mapRow || !isset($mapRow['moodle_id'])) {
    emit_json_with_logs('rank', [
      'status' => 'ok',
      'data' => [
        'eligibility' => ['cumple' => false, 'minIntentos' => 1],
        'tuPosicion' => null,
        'top' => []
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
      emit_json_with_logs('rank', ['status'=>'error','msg'=>'Área inválida']);
    }
  }

  error_log("[rank] scope=$scope area=" . ($area ?: 'global') . " campo=$campoPuntaje");

  // 4) Construir filtro de segmento
  $whereScope = '';
  $paramsScope = [];

  switch ($scope) {
    case 'school':
      if ($colegioVal) {
        $whereScope = "WHERE r.colegio = :colegio";
        $paramsScope[':colegio'] = $colegioVal;
      } else {
        emit_json_with_logs('rank', [
          'status' => 'ok',
          'data' => [
            'eligibility' => ['cumple' => false, 'minIntentos' => 1],
            'tuPosicion' => null,
            'top' => []
          ]
        ]);
      }
      break;
    case 'city':
      if ($ciudadVal) {
        $whereScope = "WHERE r.ciudad = :ciudad";
        $paramsScope[':ciudad'] = $ciudadVal;
      } else {
        emit_json_with_logs('rank', [
          'status' => 'ok',
          'data' => [
            'eligibility' => ['cumple' => false, 'minIntentos' => 1],
            'tuPosicion' => null,
            'top' => []
          ]
        ]);
      }
      break;
    case 'dept':
      if ($deptoVal) {
        $whereScope = "WHERE r.departamento = :depto";
        $paramsScope[':depto'] = $deptoVal;
      } else {
        emit_json_with_logs('rank', [
          'status' => 'ok',
          'data' => [
            'eligibility' => ['cumple' => false, 'minIntentos' => 1],
            'tuPosicion' => null,
            'top' => []
          ]
        ]);
      }
      break;
    case 'national':
      $whereScope = "";
      break;
  }

  // 5) Calcular promedios por usuario en el segmento (incluye nombre y avatar)
  $sqlRank = "
    SELECT 
      r.usuario_id,
      ROUND(AVG($campoPuntaje), 1) AS promedio,
      u.nombre AS nombre,
      u.avatar_path AS avatar
    FROM simulacro_resultados r
    LEFT JOIN usuarios u ON u.moodle_id = r.usuario_id
    $whereScope
    GROUP BY r.usuario_id, u.nombre, u.avatar_path
    HAVING COUNT(r.id) >= 1
    ORDER BY promedio DESC
    LIMIT :topN
  ";
  $stmtRank = $conexion->prepare($sqlRank);
  foreach ($paramsScope as $k => $v) {
    $stmtRank->bindValue($k, $v);
  }
  $stmtRank->bindValue(':topN', $topN, PDO::PARAM_INT);
  $stmtRank->execute();
  $topRows = $stmtRank->fetchAll(PDO::FETCH_ASSOC);

  // Post-procesar para asegurar tipos numéricos y claves presentes
foreach ($topRows as &$row) {
    // Fuerza promedio a float
    if (isset($row['promedio'])) {
        $row['promedio'] = floatval($row['promedio']);
    } else {
        $row['promedio'] = null;
    }

    // Normaliza nombre y avatar
    $row['nombre'] = $row['nombre'] ?? null;

    if (!empty($row['avatar'])) {
        // ✅ FASE 4: URL centralizada en includes/config.php
        $row['avatar'] = getAvatarUrl($row['avatar']);
    } else {
        $row['avatar'] = null;
    }
}
unset($row);

  // 6) Calcular posición del usuario en todo el segmento (no necesita JOIN)
  $sqlAll = "
    SELECT 
      r.usuario_id, 
      ROUND(AVG($campoPuntaje), 1) AS promedio
    FROM simulacro_resultados r
    $whereScope
    GROUP BY r.usuario_id
    HAVING COUNT(r.id) >= 1
    ORDER BY promedio DESC
  ";
  $stmtAll = $conexion->prepare($sqlAll);
  foreach ($paramsScope as $k => $v) {
    $stmtAll->bindValue($k, $v);
  }
  $stmtAll->execute();
  $allRows = $stmtAll->fetchAll(PDO::FETCH_ASSOC);

  $tuPosicion = null;
  $eligibility = ['cumple' => false, 'minIntentos' => 1];
  if ($allRows && count($allRows) >= 1) {
    $eligibility['cumple'] = true;
    foreach ($allRows as $idx => $row) {
      if (intval($row['usuario_id']) === $moodleId) {
        $tuPosicion = $idx + 1; // posiciones 1-based
        break;
      }
    }
  }

  // 7) Respuesta final
  $totalParticipantes = is_array($allRows) ? count($allRows) : 0;

  emit_json_with_logs('rank', [
    'status' => 'ok',
    'data' => [
      'eligibility'        => $eligibility,
      'tuPosicion'         => $tuPosicion,
      'top'                => $topRows,
      'totalParticipantes' => $totalParticipantes
    ]
  ]);

} catch (Exception $e) {
  error_log("[rank][ERROR] " . $e->getMessage());
  emit_json_with_logs('rank', ['status' => 'error', 'msg' => $e->getMessage()], 500);
}
