<?php
$in = __DIR__ . "/data/colegios.csv";
$out = __DIR__ . "/data/colegios_limpio.csv";

if (!file_exists($in)) {
    die("? Archivo no encontrado: $in\n");
}

$contenido = file_get_contents($in);

// 1?? Detectar codificación y convertir a UTF-8
$encoding = mb_detect_encoding($contenido, ['UTF-8', 'ISO-8859-1', 'Windows-1252'], true);
if ($encoding !== 'UTF-8') {
    $contenido = mb_convert_encoding($contenido, 'UTF-8', $encoding);
    echo "? Convertido de $encoding a UTF-8\n";
}

// 2?? Quitar comillas dobles sobrantes y espacios
$contenido = preg_replace('/"{2,}/', '"', $contenido);
$contenido = str_replace("\r", "", $contenido);
$contenido = trim($contenido);

// 3?? Guardar nuevo archivo
file_put_contents($out, $contenido);

echo "? Archivo limpio guardado en: $out\n";
