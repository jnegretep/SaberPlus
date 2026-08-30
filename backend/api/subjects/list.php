<?php
/** GET /api/subjects/list.php */
require_once __DIR__ . '/../../helpers/bootstrap.php';
$payload = require_auth();
$subjects = Subject::all($pdo, (int)$payload['inst']);
send_json(true, array_map(fn($s) => [
    'id'   => (int)$s['id'],
    'name' => $s['name'],
    'code' => $s['code'],
], $subjects));
