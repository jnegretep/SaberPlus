<?php
// api_saber_plus_ia.php — Tutor IA de Saber+ (DeepSeek)
// ⚠️ SEGURIDAD: requiere JWT del usuario autenticado; el moodle_id se toma
// del token, nunca del body. La API key vive en backend/.env.
// v2 (Task 3-f): timeouts curl, mapeo claro de errores de DeepSeek (saldo /
// key inválida / rate-limit / timeout), límite de peticiones por usuario y
// respuestas SIEMPRE {exito, error, codigo} con HTTP 200 (la app decide el UX).
header('Content-Type: application/json; charset=UTF-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

require_once __DIR__ . '/vendor/autoload.php';
require_once __DIR__ . '/includes/conexion.php';
require_once __DIR__ . '/env.php';

/**
 * Responde SIEMPRE con HTTP 200 y JSON {exito:false, codigo, error}.
 * Así la app recibe JSON parseable y mapea `codigo` → mensaje UX correcto
 * (SIN_SALDO / KEY_INVALIDA / RATE_LIMIT / TIMEOUT / ERROR_IA).
 */
function ia_error(string $codigo, string $error): void {
    http_response_code(200);
    echo json_encode([
        'exito'  => false,
        'codigo' => $codigo,
        'error'  => $error,
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

/**
 * Rate-limit por usuario SIN tablas nuevas: /tmp/saberplus_ia_rl_{moodle_id}.json
 * guarda los timestamps de las últimas peticiones; más de 6 en 60s = bloqueado.
 * Escritura atómica con flock. Si el filesystem falla, deja pasar (fail-open:
 * es una protección de UX/saldo, no de seguridad).
 */
function ia_rate_limit_excedido(int $moodle_id): bool {
    $archivo = sys_get_temp_dir() . '/saberplus_ia_rl_' . $moodle_id . '.json';
    $fp = @fopen($archivo, 'c+');
    if ($fp === false) {
        return false;
    }
    $ahora = time();
    $timestamps = [];
    $permitido = true;
    try {
        if (flock($fp, LOCK_EX)) {
            $raw = stream_get_contents($fp);
            if (is_string($raw) && $raw !== '') {
                $dec = json_decode($raw, true);
                if (is_array($dec)) {
                    foreach ($dec as $t) {
                        // Conservar solo las peticiones de los últimos 60s
                        if (is_numeric($t) && ($ahora - (int)$t) < 60) {
                            $timestamps[] = (int)$t;
                        }
                    }
                }
            }
            $permitido = count($timestamps) < 6;
            if ($permitido) {
                $timestamps[] = $ahora;
            }
            ftruncate($fp, 0);
            rewind($fp);
            fwrite($fp, json_encode($timestamps));
            fflush($fp);
            flock($fp, LOCK_UN);
        }
    } finally {
        fclose($fp);
    }
    return !$permitido;
}

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    ia_error('METODO', 'Método no permitido.');
}

// ── Autenticación JWT obligatoria ──
$allHeaders = function_exists('getallheaders') ? getallheaders() : [];
$authHeader = $allHeaders['Authorization'] ?? $allHeaders['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';

if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
    http_response_code(401);
    echo json_encode(["exito" => false, "error" => "No autorizado"]);
    exit;
}

$configJwt = require __DIR__ . '/jwt_config.php';
try {
    $decoded = \Firebase\JWT\JWT::decode($m[1], new \Firebase\JWT\Key($configJwt['secret'], 'HS256'));
    // El moodle_id SIEMPRE viene del token autenticado — ignora cualquier valor del body
    $moodle_id = (int)($decoded->data->moodle_userid ?? 0);
} catch (Exception $e) {
    http_response_code(401);
    echo json_encode(["exito" => false, "error" => "Token inválido"]);
    exit;
}

if ($moodle_id <= 0) {
    http_response_code(401);
    echo json_encode(["exito" => false, "error" => "Token sin identificador de usuario"]);
    exit;
}

$data = json_decode(file_get_contents('php://input'), true);
if (!is_array($data)) {
    $data = [];
}

// ── Guard de entrada: mensaje máximo 2000 caracteres ──
$mensaje_estudiante = trim((string)($data['mensaje'] ?? ''));
$mensaje_estudiante = mb_substr($mensaje_estudiante, 0, 2000);

if ($mensaje_estudiante === '') {
    ia_error('MENSAJE_VACIO', 'Escribe un mensaje para que el tutor pueda ayudarte.');
}

// ── Rate-limit por usuario (protege el saldo de la API key) ──
if (ia_rate_limit_excedido($moodle_id)) {
    ia_error('RATE_LIMIT', 'Vas muy rápido, espera unos segundos.');
}

try {
    // Obtener datos del usuario
    $sqlUsuario = "SELECT nombre, colegio, ciudad, departamento, grado FROM usuarios WHERE moodle_id = :moodle_id LIMIT 1";
    $stmtUser = $conexion->prepare($sqlUsuario);
    $stmtUser->bindParam(':moodle_id', $moodle_id, PDO::PARAM_INT);
    $stmtUser->execute();
    $usuario = $stmtUser->fetch(PDO::FETCH_ASSOC);

    // Obtener último simulacro
    $sqlSimulacro = "SELECT puntaje_global, lectura_puntaje, matematicas_puntaje, sociales_puntaje, naturales_puntaje, ingles_puntaje, fecha_realizacion 
                     FROM simulacro_resultados 
                     WHERE usuario_id = :moodle_id 
                     ORDER BY fecha_realizacion DESC LIMIT 1";
    $stmtSim = $conexion->prepare($sqlSimulacro);
    $stmtSim->bindParam(':moodle_id', $moodle_id, PDO::PARAM_INT);
    $stmtSim->execute();
    $simulacro = $stmtSim->fetch(PDO::FETCH_ASSOC);

    // Construir prompt base
    $prompt_sistema = "Eres 'Saber+', el tutor virtual inteligente para las Pruebas Saber 11° de Colombia. Tu tono es amigable, motivador, usas 'tú'. NO respondas temas ajenos al ICFES, estudio o motivación escolar.\n\n";

    if ($usuario) {
        $nombre = explode(' ', ($usuario['nombre'] ?? 'Estudiante'))[0];
        $grado = $usuario['grado'] ?? '11';
        $colegio = $usuario['colegio'] ?? 'su colegio';
        $ciudad = $usuario['ciudad'] ?? 'su ciudad';
        
        $prompt_sistema .= "CONTEXTO DEL ESTUDIANTE: Se llama {$nombre}, está en grado {$grado}, estudia en {$colegio} ubicado en {$ciudad}.\n";
    } else {
        $nombre = 'Estudiante';
    }

    // 🔥 CASO 1: ANÁLISIS POR ÁREA ESPECÍFICA (AreaTrendScreen)
    $area_enfoque = $data['area_enfoque'] ?? null;
    $area_stats = $data['area_stats'] ?? null;

    if ($area_enfoque && $area_stats && !isset($area_stats['promedio_global'])) {
        // Esto es del AreaTrendScreen (tiene 'promedio', 'tendencia', 'mejor')
        $nombres_areas = [
            'lectura' => 'Lectura Crítica',
            'matematicas' => 'Matemáticas',
            'sociales' => 'Ciencias Sociales',
            'naturales' => 'Ciencias Naturales',
            'ingles' => 'Inglés'
        ];
        $nombre_area_bonito = $nombres_areas[$area_enfoque] ?? $area_enfoque;
        $promedio = floatval($area_stats['promedio'] ?? 0);
        $tendencia = floatval($area_stats['tendencia'] ?? 0);
        $mejor_puntaje = floatval($area_stats['mejor'] ?? 0);

        $prompt_sistema .= "MODO ESPECIALISTA: Eres un tutor EXPERTO en {$nombre_area_bonito} para el ICFES.\n";
        $prompt_sistema .= "DATOS DEL ESTUDIANTE EN {$nombre_area_bonito}:\n";
        $prompt_sistema .= "- Promedio actual: {$promedio} puntos\n";
        $prompt_sistema .= "- Tendencia: " . ($tendencia >= 0 ? "+{$tendencia}" : "{$tendencia}") . " puntos\n";
        $prompt_sistema .= "- Mejor puntaje histórico: {$mejor_puntaje} puntos\n";
        
        if ($promedio < 40) {
            $prompt_sistema .= "DIAGNÓSTICO: Nivel BÁSICO. Necesita reforzar fundamentos.\n";
        } elseif ($promedio < 65) {
            $prompt_sistema .= "DIAGNÓSTICO: En PROCESO. Conoce teoría pero falla en preguntas tipo ICFES.\n";
        } else {
            $prompt_sistema .= "DIAGNÓSTICO: Nivel AVANZADO. Enfócate en preguntas de alta complejidad.\n";
        }

        $prompt_sistema .= "\nRESPONDE: Análisis breve (4 líneas) + 2 temas para estudiar esta semana.\n";
        if ($area_enfoque == 'matematicas' || $area_enfoque == 'naturales') {
            $prompt_sistema .= "USA LaTeX: \\( x^2 + 5x + 6 = 0 \\)\n";
        }

    // 🔥 CASO 2: ANÁLISIS GLOBAL (StatsHomeScreen)
    } elseif ($area_stats && isset($area_stats['promedio_global'])) {
        $stats = $area_stats;
        
        $promedio_global = floatval($stats['promedio_global'] ?? 0);
        $simulacros_realizados = intval($stats['simulacros_realizados'] ?? 0);
        $tiempo_promedio = intval($stats['tiempo_promedio_seg'] ?? 0);
        $mejor_area = $stats['mejor_area'] ?? 'ninguna';
        $mejor_puntaje = floatval($stats['mejor_puntaje'] ?? 0);
        $peor_area = $stats['peor_area'] ?? 'ninguna';
        $peor_puntaje = floatval($stats['peor_puntaje'] ?? 0);

        $prompt_sistema .= "MODO ANALISTA GLOBAL: Eres un consejero académico que revisa el RENDIMIENTO GENERAL.\n\n";
        $prompt_sistema .= "📊 ESTADÍSTICAS GLOBALES:\n";
        $prompt_sistema .= "- Simulacros realizados: {$simulacros_realizados}\n";
        $prompt_sistema .= "- Puntaje promedio GLOBAL: {$promedio_global} puntos\n";
        $prompt_sistema .= "- Tiempo promedio: " . floor($tiempo_promedio / 60) . "min " . ($tiempo_promedio % 60) . "seg\n";
        $prompt_sistema .= "- 🏆 Mejor área: {$mejor_area} con {$mejor_puntaje} puntos\n";
        $prompt_sistema .= "- ⚠️ Área a mejorar: {$peor_area} con {$peor_puntaje} puntos\n\n";

        if ($promedio_global < 45) {
            $prompt_sistema .= "DIAGNÓSTICO: Nivel BÁSICO. Prioridad: {$peor_area}.\n";
        } elseif ($promedio_global < 70) {
            $prompt_sistema .= "DIAGNÓSTICO: BIEN pero puede mejorar. Usa {$mejor_area} para mejorar {$peor_area}.\n";
        } else {
            $prompt_sistema .= "DIAGNÓSTICO: ¡Excelente! Mantén el ritmo.\n";
        }

        $prompt_sistema .= "\nRESPONDE: Resumen ejecutivo (5 líneas) + 3 acciones concretas para la semana.\n";
        $prompt_sistema .= "USA emojis (📚, 🎯, ⏰) y sé motivador.\n";

    // 🔥 CASO 3: CHAT NORMAL CON DATOS DEL ÚLTIMO SIMULACRO
    } elseif ($simulacro) {
        $fecha = $simulacro['fecha_realizacion'] ?? 'fecha desconocida';
        $global = $simulacro['puntaje_global'] ?? 0;
        $lectura = $simulacro['lectura_puntaje'] ?? 0;
        $mates = $simulacro['matematicas_puntaje'] ?? 0;
        $sociales = $simulacro['sociales_puntaje'] ?? 0;
        $naturales = $simulacro['naturales_puntaje'] ?? 0;
        $ingles = $simulacro['ingles_puntaje'] ?? 0;
        
        $prompt_sistema .= "DATOS DEL ÚLTIMO SIMULACRO ({$fecha}):\n";
        $prompt_sistema .= "- Puntaje global: {$global}\n";
        $prompt_sistema .= "- Lectura: {$lectura}, Matemáticas: {$mates}, Sociales: {$sociales}, Naturales: {$naturales}, Inglés: {$ingles}\n\n";
        $prompt_sistema .= "INSTRUCCIÓN: Responde la pregunta del estudiante usando estos datos reales si es relevante.\n";
        
    } else {
        $prompt_sistema .= "ESTADO: El estudiante aún NO ha presentado NINGÚN simulacro en Saber+.\n";
        $prompt_sistema .= "INSTRUCCIÓN: Motívalo a empezar. No des consejos específicos sin datos.\n";
    }

    $prompt_sistema .= "\nREGLAS: Máximo 300 tokens. Usa **negritas** si es necesario. Saluda con '¡Hola {$nombre}!' si lo conoces.\n";

    // Conectar con DeepSeek — API key desde backend/.env
    // ⚠️ NO usamos env_required(): esa función hace exit() con un JSON
    // {status,msg} que la app no entiende. Con env() respondemos KEY_INVALIDA
    // limpio y quedará visible en admin/check_ia.php.
    $api_key = env('DEEPSEEK_API_KEY');
    if ($api_key === null || $api_key === '') {
        error_log('[IA][ENV] DEEPSEEK_API_KEY ausente — configura backend/.env (copia de .env.example)');
        ia_error('KEY_INVALIDA', 'El tutor IA está temporalmente fuera de servicio. El equipo ya fue notificado.');
    }

    $url = 'https://api.deepseek.com/chat/completions';

    $payload = [
        "model" => "deepseek-chat",
        "messages" => [
            ["role" => "system", "content" => $prompt_sistema],
            ["role" => "user", "content" => $mensaje_estudiante]
        ],
        "temperature" => 0.7,
        "max_tokens" => 400
    ];

    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
    curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10);
    curl_setopt($ch, CURLOPT_TIMEOUT, 60);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Content-Type: application/json',
        'Authorization: Bearer ' . $api_key
    ]);

    $response = curl_exec($ch);
    $httpcode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curl_errno = curl_errno($ch);
    curl_close($ch);

    // Timeout de red (curl errno 28) — HTTP 200, que la app decida el mensaje
    if ($curl_errno === 28) {
        ia_error('TIMEOUT', 'El tutor tardó demasiado en responder. Intenta de nuevo.');
    }

    if ($response === false || $curl_errno !== 0) {
        error_log("[IA][CURL] errno={$curl_errno} moodle_id={$moodle_id}");
        ia_error('ERROR_IA', 'El tutor IA no está disponible en este momento. Intenta más tarde.');
    }

    if ($httpcode !== 200) {
        // Log completo para diagnóstico (jamás la key — solo su longitud)
        error_log("[IA][DEEPSEEK] HTTP {$httpcode} body=" . substr((string)$response, 0, 800) . " key_len=" . strlen($api_key));

        // Mapear el error que devuelve DeepSeek en el body:
        // { "error": { "message": "...", "type": "...", "code": "..." } }
        $err_txt = '';
        $err_json = json_decode((string)$response, true);
        if (is_array($err_json) && isset($err_json['error'])) {
            $e = $err_json['error'];
            if (is_array($e)) {
                $err_txt = (string)($e['message'] ?? '') . ' ' . (string)($e['code'] ?? '') . ' ' . (string)($e['type'] ?? '');
            } elseif (is_string($e)) {
                $err_txt = $e;
            }
        }
        $err_txt = strtolower($err_txt . ' http' . $httpcode);

        if (str_contains($err_txt, 'insufficient') || str_contains($err_txt, 'balance')) {
            // MUY común en DeepSeek: la cuenta se quedó sin saldo (HTTP 402)
            ia_error('SIN_SALDO', 'El tutor IA está temporalmente fuera de servicio. El equipo ya fue notificado.');
        } elseif (str_contains($err_txt, 'authentication') || str_contains($err_txt, 'invalid_api_key') || $httpcode === 401) {
            ia_error('KEY_INVALIDA', 'El tutor IA está temporalmente fuera de servicio. El equipo ya fue notificado.');
        } elseif (str_contains($err_txt, 'rate_limit') || $httpcode === 429) {
            ia_error('RATE_LIMIT', 'Va muy rápido, espera unos segundos.');
        }
        ia_error('ERROR_IA', 'El tutor IA no está disponible en este momento. Intenta más tarde.');
    }

    // Validar contenido de la respuesta (200 sin contenido = error igual)
    $respuesta = json_decode((string)$response, true);
    $texto_ia = $respuesta['choices'][0]['message']['content'] ?? '';

    if (trim((string)$texto_ia) === '') {
        error_log("[IA][DEEPSEEK] HTTP 200 sin contenido body=" . substr((string)$response, 0, 500));
        ia_error('ERROR_IA', 'El tutor IA no está disponible en este momento. Intenta más tarde.');
    }

    // Limpiar BOM invisible
    $texto_ia = preg_replace('/^\xEF\xBB\xBF/', '', $texto_ia);

    echo json_encode([
        "exito" => true, 
        "respuesta" => $texto_ia
    ], JSON_UNESCAPED_UNICODE);

} catch (Exception $e) {
    error_log("[IA][ERROR] " . $e->getMessage());
    ia_error('ERROR_IA', 'Error del servidor. Intenta más tarde.');
}
?>
