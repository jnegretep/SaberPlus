<?php
$file = __DIR__ . "/data/colegios.csv";

if (!file_exists($file)) {
    die("Archivo no encontrado\n");
}

if (($handle = fopen($file, "r")) !== false) {
    $header = fgetcsv($handle, 10000, ",");
    $row = fgetcsv($handle, 10000, ",");
    fclose($handle);

    echo "Cabecera:\n";
    print_r($header);
    echo "\nPrimera fila:\n";
    print_r($row);
}
