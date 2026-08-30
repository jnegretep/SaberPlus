<?php
// /var/www/html/api/prepsaber/backend/moodle/MoodleClient.php

class MoodleClient
{
    private string $url;
    private string $format;

    /**
     * @param string $baseUrl   URL completa al endpoint REST de Moodle, p.ej:
     *                          "https://preicfes.corpoinstel.edu.co/webservice/rest/server.php"
     *                          (definida en includes/config.php)
     * @param string $format    Formato de respuesta, normalmente "json"
     */
    public function __construct(string $baseUrl, string $format = 'json')
    {
        $this->url    = rtrim($baseUrl, '/');
        $this->format = $format;
    }

    /**
     * Invoca un WS de Moodle vía POST x-www-form-urlencoded
     *
     * Añadimos fallback automático: si pedimos mod_quiz_get_attempt_data y recibimos
     * la excepción 'attemptalreadyclosed', reintentamos con mod_quiz_get_attempt_review.
     *
     * @param string $token         Token de Moodle
     * @param string $functionName  Nombre de la función WS
     * @param array  $params        Parámetros específicos de la función
     * @return array                JSON decodificado como array asociativo
     * @throws Exception            En caso de error cURL o WS (si el fallback falla)
     */
    public function request(string $token, string $functionName, array $params = []): array
    {
        // Helper interno para ejecutar la llamada
        $doRequest = function(string $fn) use ($token, $params) {
            $postFields = array_merge([
                'wstoken'            => $token,
                'wsfunction'         => $fn,
                'moodlewsrestformat' => $this->format,
            ], $params);

            $postString = http_build_query($postFields, '', '&');

            // Log del endpoint completo (útil para debugging)
            error_log('[MoodleClient] WS URL: ' . $this->url . '?' . $postString);

            $ch = curl_init($this->url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_HTTPHEADER, [
                'Content-Type: application/x-www-form-urlencoded',
            ]);
            curl_setopt($ch, CURLOPT_POSTFIELDS, $postString);
            curl_setopt($ch, CURLOPT_TIMEOUT, 30);

            $response = curl_exec($ch);
            if ($response === false) {
                $err = curl_error($ch);
                curl_close($ch);
                throw new Exception('[MoodleClient] cURL Error: ' . $err);
            }
            curl_close($ch);

            error_log('[MoodleClient] WS raw response: ' . $response);

            $decoded = json_decode($response, true);
            if (!is_array($decoded)) {
                throw new Exception('[MoodleClient] Moodle WS Error: Respuesta inesperada de WS');
            }
            if (isset($decoded['exception'])) {
                // Decodificamos un mensaje amigable si existe
                $msg = $decoded['message'] ?? $decoded['errorcode'] ?? 'Excepción WS';
                // Lanzamos la excepción con el mensaje para que el llamador la maneje
                throw new Exception('[MoodleClient] Moodle WS Error: ' . $msg);
            }
            return $decoded;
        };

        // Intento principal
        try {
            return $doRequest($functionName);
        } catch (Exception $e) {
            $errMsg = $e->getMessage();
            error_log("[MoodleClient] Request failed for function={$functionName} : {$errMsg}");

            // Fallback específico: si pedimos mod_quiz_get_attempt_data y la excepción indica intento cerrado,
            // reintentamos con mod_quiz_get_attempt_review (respuesta de revisión).
           if ($functionName === 'mod_quiz_get_attempt_data' &&
    (
        stripos($errMsg, 'attemptalreadyclosed') !== false ||
        stripos($errMsg, 'ya ha sido finalizado') !== false
    )
) {
    error_log('[MoodleClient] Detected closed attempt  switching to mod_quiz_get_attempt_review');
    try {
        return $doRequest('mod_quiz_get_attempt_review');
    } catch (Exception $e2) {
        error_log('[MoodleClient] Fallback to review failed: ' . $e2->getMessage());
        throw new Exception($errMsg . ' | fallback: ' . $e2->getMessage());
    }
}

            // No aplicable el fallback -> re-lanzar
            throw $e;
        }
    }
}
