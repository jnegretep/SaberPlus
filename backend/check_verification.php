<?php
// /var/www/html/api/prepsaber/backend/check_verification.php
header('Content-Type: application/json');
require __DIR__ . '/includes/conexion.php';

$input = json_decode(file_get_contents('php://input'), true);
$userId = $input['user_id'] ?? 0;

if (!$userId) {
    echo json_encode(['verified' => false, 'error' => 'user_id required']);
    exit;
}

$stmt = $conexion->prepare("SELECT email_verificado FROM usuarios WHERE id_usuario = ?");
$stmt->execute([$userId]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);

echo json_encode(['verified' => $row ? (bool)$row['email_verificado'] : false]);