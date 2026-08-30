<?php
declare(strict_types=1);

// ================================
// get_course_contents.php  versión estable con URLs absolutas + cuestionarios
// ================================

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Allow-Methods: GET, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    exit(json_encode(['status'=>'error','msg'=>'Método no permitido']));
}

require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/../includes/conexion.php';
require __DIR__ . '/../includes/moodle.php';
$configJwt = require __DIR__ . '/../jwt_config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

// --- Autenticación JWT ---
$hdrs       = function_exists('getallheaders') ? getallheaders() : [];
$authHeader = $hdrs['Authorization'] ?? $hdrs['authorization'] ?? $_SERVER['HTTP_AUTHORIZATION'] ?? '';

if (!preg_match('/Bearer\s+(\S+)/', $authHeader, $m)) {
    http_response_code(401);
    exit(json_encode(['status'=>'error','msg'=>'No autorizado']));
}
$appToken = $m[1];

try {
    $decoded      = JWT::decode($appToken, new Key($configJwt['secret'], 'HS256'));
    $moodleUserId = (int)$decoded->data->moodle_userid;
} catch (Exception $e) {
    http_response_code(401);
    exit(json_encode(['status'=>'error','msg'=>'Token inválido']));
}

// --- Parámetro obligatorio ---
$courseId = filter_input(INPUT_GET, 'courseid', FILTER_VALIDATE_INT);
if (!$courseId) {
    http_response_code(400);
    exit(json_encode(['status'=>'error','msg'=>'Parámetro courseid faltante o inválido']));
}

// --- Obtener moodle_token del usuario ---
$stmt = $conexion->prepare("
    SELECT moodle_token
      FROM usuarios
     WHERE moodle_id = :mid
     LIMIT 1
");
$stmt->execute([':mid' => $moodleUserId]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$row) {
    http_response_code(404);
    exit(json_encode(['status'=>'error','msg'=>'Usuario no encontrado']));
}
$moodleToken = $row['moodle_token'];

// ✅ FASE 4: URL centralizada en includes/config.php
$proxyBase = getBackendFileProxyUrl();

try {
    $client = getMoodleClient();
    $result = $client->request($moodleToken, 'core_course_get_contents', [
        'courseid' => $courseId
    ]);

    $sectionsOut = [];

    foreach ($result as $section) {
        $summary   = $section['summary'] ?? '';
        $name      = $section['name'] ?? '';
        $sectionId = $section['id'] ?? null;
        $files     = [];
        $modules   = [];

        // --- Reemplazar pluginfile.php por el proxy ---
        if (!empty($summary)) {
            $summary = preg_replace_callback(
                '#(https?://[^\s"\']*pluginfile\.php[^\s"\']*)#',
                fn($m) => $proxyBase . '?url=' . urlencode($m[1]),
                $summary
            );

            // Reemplazar rutas relativas de /api/
            $summary = str_replace('src="/api/', 'src="'.$base_url.'/api/', $summary);
        }

        // --- Adjuntar archivos si existen ---
        if (!empty($section['summaryfiles'])) {
            foreach ($section['summaryfiles'] as $sf) {
                if (!empty($sf['fileurl'])) {
                    $files[] = $proxyBase . '?url=' . urlencode($sf['fileurl']);
                }
            }
        }

      // --- Agregar módulos (recursos, páginas, cuestionarios, etc.) ---
if (!empty($section['modules'])) {
    foreach ($section['modules'] as $mod) {
        $modName   = $mod['name'] ?? '';
        $modType   = $mod['modname'] ?? '';
        $modId     = $mod['id'] ?? null;        // cmid
        $modUrl    = $mod['url'] ?? '';
        $modInst   = $mod['instance'] ?? null;  // ?? este es el quiz.id real
        $contents  = [];

        if (!empty($mod['contents'])) {
            foreach ($mod['contents'] as $c) {
                if (!empty($c['fileurl'])) {
                    $contents[] = $proxyBase . '?url=' . urlencode($c['fileurl']);
                }
            }
        }

        $modules[] = [
            'id'       => $modId,
            'instance' => $modInst,   // ?? añade este campo
            'name'     => $modName,
            'modname'  => $modType,
            'url'      => $modUrl,
            'contents' => $contents
        ];
    }
}

        $sectionsOut[] = [
            'sectionid' => $sectionId,
            'name'      => $name,
            'summary'   => $summary,
            'files'     => $files,
            'modules'   => $modules
        ];
    }

    echo json_encode([
        'status'   => 'ok',
        'courseid' => $courseId,
        'sections' => $sectionsOut
    ], JSON_UNESCAPED_UNICODE);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'status'=>'error',
        'msg'=>'Error Moodle WS',
        'debug'=>$e->getMessage()
    ]);
}
