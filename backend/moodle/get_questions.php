<?php
// 1. Carga configuración y cliente
$config = require __DIR__ . '/config.php';
require __DIR__ . '/MoodleClient.php';

$client = new MoodleClient($config);

// 2. Validar parámetro quiz_id
if (! isset($_GET['quiz_id']) || ! is_numeric($_GET['quiz_id'])) {
    header('Content-Type: application/json', true, 400);
    echo json_encode(['error' => 'Parámetro quiz_id faltante o inválido']);
    exit;
}

$quizId = intval($_GET['quiz_id']);

try {
    // 3. Llamada a Moodle: obtenemos las preguntas del quiz
    //    Moodle espera quizid[0] si fuera array, pero aquí es un único valor
    $response = $client->request(
        'mod_quiz_get_quiz_questions',
        ['quizid' => $quizId]
    );

    // 4. Extraer y normalizar
    //    Suponemos que la respuesta tiene clave 'questions' con array de preguntas
    $rawQuestions = $response['questions'] ?? [];
    $questions = array_map(function($q) {
        return [
            'id'           => $q['id'],
            'name'         => $q['name'],
            'type'         => $q['qtype'],
            'questiontext' => $q['questiontext'],   // HTML o Markdown según tu configuración
            'defaultmark'  => $q['defaultmark'],
        ];
    }, $rawQuestions);

    // 5. Devolver JSON
    header('Content-Type: application/json', true, 200);
    echo json_encode($questions);

} catch (Exception $e) {
    header('Content-Type: application/json', true, 500);
    echo json_encode(['error' => $e->getMessage()]);
}
