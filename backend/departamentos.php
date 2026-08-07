<?php
header('Content-Type: application/json; charset=utf-8');

$archivo = __DIR__ . '/data/colegios.csv';

if (!file_exists($archivo)) {
    echo json_encode(["status" => "error", "message" => "Archivo no encontrado"], JSON_UNESCAPED_UNICODE);
    exit;
}

$handle = fopen($archivo, 'r');
if (!$handle) {
    echo json_encode(["status" => "error", "message" => "No se pudo abrir el archivo"], JSON_UNESCAPED_UNICODE);
    exit;
}

$departamentos = [];
$primeraLinea = true;

while (($data = fgetcsv($handle, 0, ',')) !== false) {
    if ($primeraLinea) {
        $primeraLinea = false;
        continue;
    }

    // Asegura UTF-8 correctamente
    $nombreDepartamento = trim($data[2] ?? '');
    $nombreDepartamento = mb_convert_encoding($nombreDepartamento, 'UTF-8', 'UTF-8, ISO-8859-1, Windows-1252');

    if ($nombreDepartamento && !in_array($nombreDepartamento, $departamentos)) {
        $departamentos[] = $nombreDepartamento;
    }
}

fclose($handle);

sort($departamentos);

echo json_encode(["status" => "ok", "departamentos" => $departamentos], JSON_UNESCAPED_UNICODE);
