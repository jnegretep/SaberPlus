<?php
/**
 * env.php — Cargador central de configuración por entorno para Saber+
 *
 * Orden de prioridad:
 *   1. Variables de entorno reales del servidor (Apache/Nginx SetEnv, systemd, etc.)
 *   2. Archivo backend/.env (gitignored — nunca se sube a git)
 *
 * Uso:
 *   require_once __DIR__ . '/env.php';
 *   $valor = env('DB_USER', 'valor_por_defecto');
 *
 * ⚠️ NINGÚN secreto debe volver a escribirse directamente en el código.
 * ⚠️ Si un secreto llegó a commitearse en git, debe ROTARSE antes de reutilizarlo.
 */

if (!function_exists('env')) {
    /** Carga el archivo .env una sola vez (idempotente). */
    function saberplus_load_env_file(): void {
        static $loaded = false;
        if ($loaded) {
            return;
        }
        $loaded = true;

        $envFile = __DIR__ . '/.env';
        if (!is_readable($envFile)) {
            return;
        }

        $lines = file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        if ($lines === false) {
            return;
        }

        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '' || $line[0] === '#' || !str_contains($line, '=')) {
                continue;
            }
            [$key, $value] = explode('=', $line, 2);
            $key   = trim($key);
            $value = trim($value);

            // Quitar comillas envolventes
            if (strlen($value) >= 2
                && ($value[0] === '"' || $value[0] === "'")
                && $value[strlen($value) - 1] === $value[0]) {
                $value = substr($value, 1, -1);
            }

            // No sobrescribir variables ya definidas en el servidor
            if (getenv($key) === false && !array_key_exists($key, $_ENV)) {
                $_ENV[$key] = $value;
                putenv($key . '=' . $value);
            }
        }
    }

    /**
     * Devuelve el valor de una variable de entorno o el default.
     * Devuelve null (o el default) si la variable no existe o está vacía.
     */
    function env(string $key, ?string $default = null): ?string {
        saberplus_load_env_file();
        $value = $_ENV[$key] ?? getenv($key);
        if ($value === false || $value === null || $value === '') {
            return $default;
        }
        return (string)$value;
    }

    /**
     * Igual que env() pero lanza una excepción clara si el valor falta.
     * Útil para secretos críticos (BD, JWT, Wompi) — fallar rápido y con mensaje claro.
     */
    function env_required(string $key): string {
        $value = env($key);
        if ($value === null) {
            http_response_code(500);
            header('Content-Type: application/json; charset=UTF-8');
            error_log("[ENV] Variable requerida ausente: {$key}. Crea backend/.env a partir de backend/.env.example");
            exit(json_encode([
                'status' => 'error',
                'msg'    => 'Configuración del servidor incompleta (ENV_' . $key . '). Contacta al administrador.'
            ]));
        }
        return $value;
    }
}

saberplus_load_env_file();
