<?php
/**
 * TRAZA - Configuración de Base de Datos
 * Conexión PDO con MySQL
 */

define('DB_HOST', 'localhost');
define('DB_NAME', 'traza');
define('DB_USER', 'root');
define('DB_PASS', '');
define('DB_CHARSET', 'utf8mb4');

// Configuración de la aplicación
define('APP_SECRET', 'cambia_esto_por_un_secreto_seguro_2025');
define('UPLOAD_DIR', __DIR__ . '/../uploads/');
define('UPLOAD_URL', '/uploads/');
define('MAX_UPLOAD_SIZE', 10 * 1024 * 1024); // 10 MB
define('ALLOWED_MIME_TYPES', ['image/jpeg', 'image/png', 'image/webp', 'image/heic']);

/**
 * Obtener conexión PDO a la base de datos
 */
function getDB(): PDO {
    static $pdo = null;
    if ($pdo === null) {
        $dsn = "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=" . DB_CHARSET;
        $options = [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ];
        $pdo = new PDO($dsn, DB_USER, DB_PASS, $options);
    }
    return $pdo;
}

/**
 * Respuesta JSON estándar
 */
function jsonResponse(array $data, int $code = 200): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

/**
 * Leer cuerpo de la petición como JSON
 */
function getJsonInput(): array {
    $raw = file_get_contents('php://input');
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        return [];
    }
    return $data;
}

/**
 * Generar token JWT simple (HS256)
 */
function generateJWT(array $payload): string {
    $header = base64_encode(json_encode(['typ' => 'JWT', 'alg' => 'HS256']));
    $payload['exp'] = time() + (8 * 3600); // 8 horas
    $payload['iat'] = time();
    $payloadEnc = base64_encode(json_encode($payload));
    $signature = base64_encode(hash_hmac('sha256', "$header.$payloadEnc", APP_SECRET, true));
    return "$header.$payloadEnc.$signature";
}

/**
 * Validar y decodificar token JWT
 */
function validateJWT(?string $token): ?array {
    if (!$token || count(explode('.', $token)) !== 3) {
        return null;
    }
    [$header, $payload, $signature] = explode('.', $token);
    $expectedSig = base64_encode(hash_hmac('sha256', "$header.$payload", APP_SECRET, true));
    if (!hash_equals($expectedSig, $signature)) {
        return null;
    }
    $data = json_decode(base64_decode($payload), true);
    if (!$data || ($data['exp'] ?? 0) < time()) {
        return null;
    }
    return $data;
}

/**
 * Procesar y guardar imagen subida
 */
function processUploadedImage(array $file, string $subfolder = ''): array {
    if ($file['error'] !== UPLOAD_ERR_OK) {
        throw new RuntimeException('Error al subir el archivo');
    }
    if ($file['size'] > MAX_UPLOAD_SIZE) {
        throw new RuntimeException('El archivo excede el tamaño máximo permitido (10 MB)');
    }
    
    $finfo = new finfo(FILEINFO_MIME_TYPE);
    $mime = $finfo->file($file['tmp_name']);
    if (!in_array($mime, ALLOWED_MIME_TYPES)) {
        throw new RuntimeException('Tipo de archivo no permitido. Use JPG, PNG o WebP');
    }
    
    // Crear subcarpeta por año/mes
    $datePath = date('Y/m');
    $targetDir = UPLOAD_DIR . $subfolder . $datePath . '/';
    if (!is_dir($targetDir)) {
        mkdir($targetDir, 0755, true);
    }
    
    // Generar nombre único
    $ext = match ($mime) {
        'image/jpeg' => 'jpg',
        'image/png'  => 'png',
        'image/webp' => 'webp',
        'image/heic' => 'heic',
        default      => 'jpg',
    };
    $filename = uniqid('ev_') . '.' . $ext;
    $filepath = $targetDir . $filename;
    
    if (!move_uploaded_file($file['tmp_name'], $filepath)) {
        throw new RuntimeException('Error al guardar el archivo');
    }
    
    return [
        'photo_path'     => $subfolder . $datePath . '/' . $filename,
        'thumbnail_path' => $subfolder . $datePath . '/thumb_' . $filename,
        'file_size'      => $file['size'],
        'mime_type'      => $mime,
    ];
}
