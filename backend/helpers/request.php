<?php
/**
 * helpers/request.php
 * Helpers para parsear entradas JSON, validaciones, paginación.
 */

declare(strict_types=1);

/**
 * Lee el body JSON (POST/PUT) y devuelve array.
 */
function read_json_body(): array
{
    $raw = file_get_contents('php://input');
    if (empty($raw)) return [];
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        send_error('Body JSON inválido.', 'BAD_JSON', 400);
    }
    return $data;
}

/**
 * Lee un valor del body JSON con clave y default.
 */
function input(array $data, string $key, $default = null)
{
    return $data[$key] ?? $default;
}

/**
 * Lee un valor requerido. Si falta → 400.
 */
function input_required(array $data, string $key)
{
    if (!isset($data[$key]) || $data[$key] === '' || $data[$key] === null) {
        send_error("Campo requerido: $key", 'MISSING_FIELD', 422);
    }
    return $data[$key];
}

/**
 * Lee parámetros de paginación desde query string.
 */
function pagination_params(): array
{
    $page = max(1, (int)($_GET['page'] ?? 1));
    $size = (int)($_GET['size'] ?? DEFAULT_PAGE_SIZE);
    $size = min(max(1, $size), MAX_PAGE_SIZE);
    return [
        'page'  => $page,
        'size'  => $size,
        'offset' => ($page - 1) * $size,
    ];
}

/**
 * Valida formato de email.
 */
function is_valid_email(string $email): bool
{
    return (bool)filter_var($email, FILTER_VALIDATE_EMAIL);
}

/**
 * Genera un UUID v4.
 */
function uuid_v4(): string
{
    $data = random_bytes(16);
    $data[6] = chr(0x40 | (ord($data[6]) & 0x0F));
    $data[8] = chr(0x80 | (ord($data[8]) & 0x3F));
    return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
}

/**
 * Genera un slug seguro para nombre de archivo.
 */
function slugify(string $text): string
{
    $text = trim($text);
    // Transliterar caracteres acentuados
    $text = iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $text) ?: $text;
    $text = strtolower($text);
    $text = preg_replace('/[^a-z0-9]+/', '-', $text);
    $text = trim($text, '-');
    return $text ?: 'file';
}

/**
 * Limpia string para mostrar / almacenar.
 */
function clean_string(?string $value): ?string
{
    if ($value === null) return null;
    $value = trim($value);
    return $value === '' ? null : $value;
}
