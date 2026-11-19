<?php
// /var/www/html/api/prepsaber/backend/get_notifications.php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require __DIR__ . '/includes/conexion.php'; // ? conexión correcta

// ?? Asegurar sesión MySQL en UTC
$conexion->exec("SET time_zone = '+00:00'");

// ?? Helpers de tiempo
function toIsoUtc(?string $dt): ?string {
    if (!$dt) return null;
    try {
        $d = new DateTimeImmutable($dt, new DateTimeZone('UTC'));
        return $d->format('Y-m-d\TH:i:s\Z'); // ISO 8601 en UTC
    } catch (Throwable $e) {
        return null;
    }
}

function toServerLocal(?string $dt, string $tz = 'America/Bogota'): ?string {
    if (!$dt) return null;
    try {
        $utc = new DateTimeImmutable($dt, new DateTimeZone('UTC'));
        $loc = $utc->setTimezone(new DateTimeZone($tz));
        return $loc->format('Y-m-d H:i:s');
    } catch (Throwable $e) {
        return null;
    }
}

// ?? Normalización defensiva UTF-8
function ensureUtf8(?string $s): ?string {
    if ($s === null) return null;
    return mb_check_encoding($s, 'UTF-8') ? $s : mb_convert_encoding($s, 'UTF-8', 'Windows-1252, ISO-8859-1');
}

$user_id = $_GET['user_id'] ?? null;
$page    = (int)($_GET['page'] ?? 1);
$limit   = (int)($_GET['limit'] ?? 5); // ?? por defecto 5 para paginación
$offset  = ($page > 0 ? ($page - 1) * $limit : 0);

error_log("[get_notifications][INPUT] user_id={$user_id} page={$page} limit={$limit} offset={$offset}");

if (empty($user_id)) {
    http_response_code(400);
    echo json_encode(["success" => false, "message" => "Falta user_id"], JSON_UNESCAPED_UNICODE);
    exit;
}

try {
    // ?? Obtener total de notificaciones para paginación
    $stmtCount = $conexion->prepare("SELECT COUNT(*) AS total FROM notifications WHERE user_id = :user_id");
    $stmtCount->execute([":user_id" => $user_id]);
    $totalRow = $stmtCount->fetch(PDO::FETCH_ASSOC);
    $totalCount = (int)($totalRow['total'] ?? 0);

    // ?? Consulta principal (fechas almacenadas en UTC)
    $sql = "
        SELECT 
            id,
            type,
            title,
            body,
            payload_json,
            created_at,
            read_at
        FROM notifications
        WHERE user_id = :user_id
        ORDER BY created_at DESC
        LIMIT :limit OFFSET :offset
    ";
    $stmt = $conexion->prepare($sql);
    $stmt->bindValue(":user_id", (int)$user_id, PDO::PARAM_INT);
    $stmt->bindValue(":limit", $limit, PDO::PARAM_INT);
    $stmt->bindValue(":offset", $offset, PDO::PARAM_INT);
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // ?? Normalizar resultados
    foreach ($rows as &$row) {
        // Decodificar payload_json si es válido
        if (!empty($row['payload_json'])) {
            $decoded = json_decode($row['payload_json'], true);
            $row['payload'] = (json_last_error() === JSON_ERROR_NONE) ? $decoded : [];
        } else {
            $row['payload'] = [];
        }
        unset($row['payload_json']);

        // Normalizar cadenas a UTF-8 (defensivo)
        $row['title'] = ensureUtf8($row['title']);
        $row['body']  = ensureUtf8($row['body']);

        // Añadir campos ISO 8601 en UTC (con Z)
        $row['created_at_iso'] = toIsoUtc($row['created_at']); // ej: 2025-12-02T23:05:44Z
        $row['read_at_iso']    = toIsoUtc($row['read_at']);

        // (Opcional) Hora local del servidor (Colombia -05:00), para testing o web:
        $row['created_at_local'] = toServerLocal($row['created_at'], 'America/Bogota');
        $row['read_at_local']    = toServerLocal($row['read_at'], 'America/Bogota');
    }

    $count = is_array($rows) ? count($rows) : 0;
    error_log("[get_notifications][RESULT] rows={$count} total={$totalCount}");

    echo json_encode([
        "success" => true,
        "notifications" => $rows,
        "page" => $page,
        "limit" => $limit,
        "count" => $count,
        "total_count" => $totalCount
    ], JSON_UNESCAPED_UNICODE);
} catch (\Throwable $e) {
    error_log("[get_notifications][ERROR] ".$e->getMessage());
    http_response_code(500);
    echo json_encode([
        "success" => false,
        "message" => "Error interno",
        "detail" => $e->getMessage()
    ], JSON_UNESCAPED_UNICODE);
}
