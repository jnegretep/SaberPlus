<?php
// test_deepseek.php
header('Content-Type: application/json');

 $api_key = 'sk-d8728470d5fa4b47934c24b4a2a0d048';

// URL oficial de DeepSeek (formato compatible con OpenAI)
 $url = 'https://api.deepseek.com/chat/completions';

 $payload = [
    "model" => "deepseek-chat", // Este es el modelo V3 (el más rápido y barato)
    "messages" => [
        [
            "role" => "system", 
            "content" => "Eres un profesor colombiano de matemáticas. Responde en máximo 2 oraciones."
        ],
        [
            "role" => "user", 
            "content" => "¿Qué es el Teorema de Pitágoras?"
        ]
    ],
    "temperature" => 0.7,
    "max_tokens" => 150
];

 $ch = curl_init($url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Content-Type: application/json',
    'Authorization: Bearer ' . $api_key
]);
// Si tu servidor tiene certificados antiguos y te da error SSL, descomenta la siguiente línea SOLO para probar:
// curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);

 $response = curl_exec($ch);
 $httpcode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
 $error = curl_error($ch);
curl_close($ch);

if ($error) {
    echo json_encode(["exito" => false, "error_curl" => $error]);
} elseif ($httpcode == 200) {
    $respuesta = json_decode($response, true);
    $texto = $respuesta['choices'][0]['message']['content'];
    echo json_encode(["exito" => true, "respuesta_ia" => $texto]);
} else {
    echo json_encode(["exito" => false, "error_http" => $httpcode, "detalle" => $response]);
}
?>