<?php
/** GET /api/periods/list.php */
require_once __DIR__ . '/../../helpers/bootstrap.php';
$payload = require_auth();
$periods = AcademicPeriod::all($pdo, (int)$payload['inst']);
send_json(true, array_map(fn($p) => [
    'id'          => (int)$p['id'],
    'name'        => $p['name'],
    'code'        => $p['code'],
    'start_date'  => $p['start_date'],
    'end_date'    => $p['end_date'],
    'is_current'  => (bool)$p['is_current'],
], $periods));
