<?php
/**
 * includes/avatar_helper.php — ✅ v2.0
 *
 * Helper compartido para guardar avatares en base64 (registro y edición
 * de perfil). Reemplaza la lógica duplicada de register.php y
 * update_profile.php, que guardaba el archivo sin validar el tipo real
 * de imagen ni verificar que la escritura hubiera funcionado (causaba
 * filas con avatar_path apuntando a archivos inexistentes).
 *
 * Qué hace:
 *   - Valida magic bytes (JPEG / PNG / WebP), no la extensión.
 *   - Verifica que el directorio exista (lo crea si hace falta).
 *   - Verifica que file_put_contents() haya escrito el archivo.
 *   - Nunca lanza: devuelve null ante cualquier fallo y deja rastro en
 *     error_log para el administrador.
 */

if (!function_exists('saberplus_guardar_avatar_base64')) {
    /**
     * Guarda un avatar base64 en uploads/avatars/.
     *
     * @param string|null $avatarBase64 Contenido base64 (sin prefijo data:).
     * @param string      $contexto     Etiqueta para los logs.
     * @return string|null Nombre del archivo guardado, o null si falló.
     */
    function saberplus_guardar_avatar_base64(?string $avatarBase64, string $contexto = 'AVATAR'): ?string
    {
        if (empty($avatarBase64)) {
            return null;
        }

        try {
            $decoded = base64_decode($avatarBase64);
            if ($decoded === false || strlen($decoded) < 64) {
                error_log("[$contexto] Avatar base64 inválido o demasiado pequeño");
                return null;
            }

            // Tipo real por magic bytes — nunca confiar en el nombre/extensión.
            $ext  = null;
            $len  = strlen($decoded);
            $head = substr($decoded, 0, 12);
            if ($len > 3 && $head[0] === "\xFF" && $head[1] === "\xD8" && $head[2] === "\xFF") {
                $ext = 'jpg';
            } elseif ($len > 8 && substr($decoded, 0, 8) === "\x89PNG\r\n\x1a\n") {
                $ext = 'png';
            } elseif ($len > 12 && substr($head, 0, 4) === 'RIFF' && substr($head, 8, 4) === 'WEBP') {
                $ext = 'webp';
            }
            if ($ext === null) {
                error_log("[$contexto] Tipo de imagen no permitido (solo jpg/png/webp)");
                return null;
            }

            $avatarsDir = __DIR__ . '/../uploads/avatars/';
            if (!is_dir($avatarsDir) && !mkdir($avatarsDir, 0777, true)) {
                error_log("[$contexto] No se pudo crear el directorio uploads/avatars (permisos)");
                return null;
            }

            $filename = 'avatar_' . uniqid() . '.' . $ext;
            if (file_put_contents($avatarsDir . $filename, $decoded) === false) {
                error_log("[$contexto] Escritura fallida de avatar: revisa permisos de uploads/avatars");
                return null;
            }

            return $filename;
        } catch (Exception $e) {
            error_log("[$contexto] Error guardando avatar: " . $e->getMessage());
            return null;
        }
    }
}
