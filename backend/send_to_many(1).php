<?php
/**
 * Envía una notificación a múltiples usuarios
 *
 * @param array  $userIds  IDs de usuarios destino
 * @param string $type     Tipo de evento (challenge_created, challenge_accepted, etc.)
 * @param array  $data     Payload estructurado del evento
 */

function sendNotificationToMany(array $userIds, string $type, array $data = [])
{
    // Limpiar y normalizar usuarios
    $userIds = array_values(array_unique(
        array_filter(
            array_map('intval', $userIds),
            fn($u) => $u > 0
        )
    ));

    if (empty($userIds)) {
        error_log("[send_to_many][SKIP] Sin usuarios válidos type={$type}");
        return;
    }

    // Payload base común para todos los eventos
    $basePayload = [
        "type"      => $type,
        "timestamp" => date('c'), // ISO-8601
        "data"      => $data
    ];

    foreach ($userIds as $uid) {

        $payload = array_merge($basePayload, [
            "id_usuario" => $uid
        ]);

        $jsonPayload = json_encode($payload, JSON_UNESCAPED_UNICODE);

        $ch = curl_init("http://172.93.49.94/api/prepsaber/backend/send_notification.php");
        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $jsonPayload,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER     => [
                "Content-Type: application/json; charset=UTF-8"
            ],
            CURLOPT_TIMEOUT        => 8,
            CURLOPT_CONNECTTIMEOUT => 4
        ]);

        $resp = curl_exec($ch);
        $http = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err  = curl_error($ch);
        curl_close($ch);

        if ($err) {
            error_log("[send_to_many][ERROR] user={$uid} type={$type} curl={$err}");
            error_log("[send_to_many][PAYLOAD] " . $jsonPayload);
            continue;
        }

        if ($http !== 200) {
            error_log("[send_to_many][WARN] user={$uid} type={$type} HTTP={$http}");
            error_log("[send_to_many][RESP] " . substr($resp ?? '', 0, 500));
            error_log("[send_to_many][PAYLOAD] " . $jsonPayload);
            continue;
        }

        error_log("[send_to_many][OK] user={$uid} type={$type}");
    }
}
