<?php
header('Content-Type: text/plain; charset=UTF-8');

// ?? REEMPLAZA ESTA URL CON LA URL REAL DE TU WORKER EN CLOUDFLARE
$worker_url = 'https://deepseek-proxy.instel91.workers.dev/';

// Payload estándar de DeepSeek (formato OpenAI)
$payload = [
    "model" => "deepseek-chat",
    "messages" => [
        ["role" => "user", "content" => "Di 'Hola, soy DeepSeek conectado por Cloudflare' y nada más."]
    ],
    "temperature" => 0.7,
    "max_tokens" => 50
];

$json_payload = json_encode($payload, JSON_UNESCAPED_UNICODE);

echo "Enviando petición al Worker de Cloudflare...\n";
echo "URL: $worker_url\n\n";

$ch = curl_init($worker_url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, $json_payload);
curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10);
curl_setopt($ch, CURLOPT_TIMEOUT, 30);
// NO forzamos IPv6 ni IPv4. Cloudflare se encarga de la red.
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Content-Type: application/json'
]);

$t0 = microtime(true);
$response = curl_exec($ch);
$httpcode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$curl_errno = curl_errno($ch);
$curl_err = curl_error($ch);
curl_close($ch);

$latencia = (int)round((microtime(true) - $t0) * 1000);

echo "====================================\n";
echo "HTTP CODE: $httpcode\n";
echo "LATENCIA: {$latencia}ms\n";
echo "CURL ERROR: " . ($curl_errno ? "($curl_errno) $curl_err" : "Ninguno") . "\n";
echo "====================================\n";
echo "RESPUESTA CRUDA:\n";
echo $response . "\n\n";

$json = json_decode($response, true);
if (isset($json['choices'][0]['message']['content'])) {
    echo "? ¡ÉXITO! DeepSeek dice:\n";
    echo trim($json['choices'][0]['message']['content']) . "\n";
} else {
    echo "? ERROR: No se pudo extraer el texto de la respuesta.\n";
    if (is_array($json) && isset($json['error'])) {
        echo "Motivo del error: " . print_r($json['error'], true) . "\n";
    }
}