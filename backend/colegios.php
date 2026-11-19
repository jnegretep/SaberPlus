<?php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");

$departamento = isset($_GET['departamento']) ? trim($_GET['departamento']) : '';
$municipio = isset($_GET['municipio']) ? trim($_GET['municipio']) : '';
$file = __DIR__ . "/data/colegios.csv";

if ($departamento === '' || $municipio === '') {
    echo json_encode(["status" => "error", "msg" => "Faltan parámetros"]);
    exit;
}

if (!file_exists($file)) {
    echo json_encode(["status" => "error", "msg" => "Archivo de datos no encontrado"]);
    exit;
}

$colegios = [];

if (($handle = fopen($file, "r")) !== false) {
    $header = fgetcsv($handle, 10000, ",");
    while (($row = fgetcsv($handle, 10000, ",")) !== false) {
        $dep = trim($row[2] ?? '');
        $mun = trim($row[4] ?? '');
        $nombreColegio = trim($row[6] ?? '');

        if (
            strcasecmp($dep, $departamento) === 0 &&
            strcasecmp($mun, $municipio) === 0 &&
            $nombreColegio !== ''
        ) {
            $colegios[$nombreColegio] = true;
        }
    }
    fclose($handle);
}

echo json_encode([
    "status" => "ok",
    "colegios" => array_values(array_keys($colegios))
]);
