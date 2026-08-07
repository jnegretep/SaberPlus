<?php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");

$departamento = isset($_GET['departamento']) ? trim($_GET['departamento']) : '';
$file = __DIR__ . "/data/colegios.csv";

if ($departamento === '') {
    echo json_encode(["status" => "error", "msg" => "Falta parámetro departamento"]);
    exit;
}

if (!file_exists($file)) {
    echo json_encode(["status" => "error", "msg" => "Archivo de datos no encontrado"]);
    exit;
}

$municipios = [];

if (($handle = fopen($file, "r")) !== false) {
    $header = fgetcsv($handle, 10000, ",");
    while (($row = fgetcsv($handle, 10000, ",")) !== false) {
        $dep = trim($row[2] ?? '');
        $mun = trim($row[4] ?? '');
        if (strcasecmp($dep, $departamento) === 0 && $mun !== '') {
            $municipios[$mun] = true;
        }
    }
    fclose($handle);
}

echo json_encode([
    "status" => "ok",
    "municipios" => array_values(array_keys($municipios))
]);
