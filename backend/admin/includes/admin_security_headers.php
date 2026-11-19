<?php
declare(strict_types=1);

/**
 * Headers de seguridad HTTP para el panel admin.
 * Aplica antes de cualquier output.
 */

function admin_security_headers(): void {
    if (headers_sent()) return;

    header('X-Frame-Options: DENY');
    header('X-Content-Type-Options: nosniff');
    header('Referrer-Policy: strict-origin-when-cross-origin');
    header('X-XSS-Protection: 1; mode=block');

    // HSTS solo en HTTPS (no aplica en localhost dev)
    if (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') {
        header('Strict-Transport-Security: max-age=31536000; includeSubDomains');
    }

    // CSP: bastante estricta. Permite inline (style/script) porque el admin actual
    // usa CSS y JS inline. Si en el futuro se extraen a assets, endurecer esto.
    header("Content-Security-Policy: " .
        "default-src 'self'; " .
        "script-src 'self' 'unsafe-inline'; " .
        "style-src 'self' 'unsafe-inline'; " .
        "img-src 'self' data: https:; " .
        "font-src 'self' data:; " .
        "connect-src 'self'; " .
        "frame-ancestors 'none'; " .
        "base-uri 'self'; " .
        "form-action 'self'"
    );

    // No cachear respuestas admin
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
    header('Pragma: no-cache');
    header('Expires: 0');
}
