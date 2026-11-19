<?php
declare(strict_types=1);

/**
 * wompi_webhook.php
 * Procesa eventos de Wompi (APPROVED / DECLINED / ERROR)
 */

error_reporting(E_ALL);
ini_set('log_errors', '1');
ini_set('display_errors', '0');

header('Content-Type: application/json');

require __DIR__ . '/includes/conexion.php';
$wompiConfig = require __DIR__ . '/wompi_config.php';

function logWebhook(string $msg): void {
    $logFile = __DIR__ . '/wompi_webhook.log';
    $timestamp = date('Y-m-d H:i:s');
    file_put_contents($logFile, "[$timestamp] $msg\n", FILE_APPEND);
}

$raw = file_get_contents('php://input');
$data = json_decode($raw, true);

if (!$data || !isset($data['event']) || !isset($data['signature'])) {
    logWebhook('Payload inválido');
    http_response_code(400);
    exit;
}

/* =======================
   VERIFICAR FIRMA (Mantenemos tu lógica que ya funciona)
   ======================= */
$receivedChecksum = $data['signature']['checksum'] ?? '';
$timestamp = (string)($data['timestamp'] ?? '');
$tx = $data['data']['transaction'];

$stringToHash = $tx['id'] . $tx['status'] . $tx['amount_in_cents'] . $timestamp . $wompiConfig['events_secret'];
$expectedChecksum = hash('sha256', $stringToHash);

if (!hash_equals($expectedChecksum, $receivedChecksum)) {
    logWebhook("Firma inválida.");
    http_response_code(401);
    exit;
}

if ($data['event'] !== 'transaction.updated') {
    echo json_encode(['status' => 'ok']);
    exit;
}

$status        = strtoupper($tx['status'] ?? '');
$reference     = $tx['reference'] ?? '';
$paymentMethod = $tx['payment_method_type'] ?? 'unknown';

/* =======================
   BUSCAR PAGO (Ajustado a tu tabla sin plan_id)
   ======================= */
$stmt = $conexion->prepare("SELECT * FROM payments WHERE reference_code = :ref LIMIT 1");
$stmt->execute([':ref' => $reference]);
$payment = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$payment) {
    logWebhook("Pago no encontrado: $reference");
    http_response_code(404);
    exit;
}

if (in_array(strtolower($payment['status']), ['approved', 'declined'], true)) {
    echo json_encode(['status' => 'ok', 'msg' => 'Ya procesado']);
    exit;
}

/* =======================
   ACTUALIZAR ESTADO DEL PAGO
   ======================= */
$stmt = $conexion->prepare("
    UPDATE payments
    SET status = :status, payment_method = :method, updated_at = NOW()
    WHERE id = :id
");
$stmt->execute([
    ':status' => strtolower($status),
    ':method' => $paymentMethod,
    ':id'     => $payment['id'],
]);

/* =======================
   ACTIVACIÓN PREMIUM (Según tu tabla 'usuarios')
   ======================= */
if ($status === 'APPROVED') {
    $userId = $payment['user_id'];

    // Actualizar tabla Usuarios basándonos en tus columnas: access_level y unlocked_at
    $stmt = $conexion->prepare("
        UPDATE usuarios
        SET access_level = 'premium', 
            unlocked_at = NOW()
        WHERE moodle_id = :user_id
    ");
    $stmt->execute([':user_id' => $userId]);

    logWebhook("¡Usuario $userId activado como PREMIUM!");
}

echo json_encode(['status' => 'ok']);