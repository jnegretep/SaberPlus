<?php
// api_saber_plus_ia.php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST');
header('Access-Control-Allow-Headers: Content-Type');

require_once __DIR__ . '/includes/conexion.php'; 

$data = json_decode(file_get_contents('php://input'), true);

$moodle_id = $data['moodle_id'] ?? null;
$mensaje_estudiante = $data['mensaje'] ?? '';

if (!$moodle_id || trim($mensaje_estudiante) === '') {
    echo json_encode(["exito" => false, "error" => "Falta el moodle_id o el mensaje"]);
    exit;
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

    // Conectar con DeepSeek
    $api_key = 'sk-d8728470d5fa4b47934c24b4a2a0d048'; 
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
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Content-Type: application/json',
        'Authorization: Bearer ' . $api_key
    ]);

    $response = curl_exec($ch);
    $httpcode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($httpcode == 200) {
        $respuesta = json_decode($response, true);
        $texto_ia = $respuesta['choices'][0]['message']['content'];
        
        // Limpiar BOM invisible
        $texto_ia = preg_replace('/^\xEF\xBB\xBF/', '', $texto_ia);
        
        echo json_encode([
            "exito" => true, 
            "respuesta" => $texto_ia
        ]);
    } else {
        echo json_encode([
            "exito" => false, 
            "error" => "Error de DeepSeek", 
            "detalle" => $response
        ]);
    }

} catch (Exception $e) {
    echo json_encode([
        "exito" => false, 
        "error" => "Error del servidor PHP", 
        "detalle" => $e->getMessage()
    ]);
}
?>