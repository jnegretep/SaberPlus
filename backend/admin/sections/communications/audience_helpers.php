<?php
declare(strict_types=1);

/**
 * SABER+ COMMAND CENTER — Comunicaciones
 * Helper de audiencia: construye SQL de filtrado sobre `usuarios`.
 *
 * Archivo aparte para que tanto el controller (admin/sections/communications)
 * como el cron (cron_send_campaigns.php) compartan exactamente la misma lógica
 * de segmentación, evitando drift entre el "preview" del admin y el envío real.
 *
 * No tiene dependencias: solo PDO + PHP 8. No arranca sesión, no envía headers.
 * Pensado para poder ser incluido desde CLI y desde web.
 *
 * Estructura del filtro (audience_filter JSON en notification_campaigns):
 *   [
 *     'mode' => 'all'|'plan'|'departamento'|'days_inactive'|'user_ids'|'segment',
 *     'plan' => ['free','premium','trial','early_bird'],   // mode=plan
 *     'departamento' => 'Bogotá D.C.',                    // mode=departamento (legacy)
 *     'departamentos' => ['Bogotá D.C.','Antioquia'],     // mode=departamento (multi)
 *     'days_inactive' => 30,                               // mode=days_inactive
 *     'user_ids' => [12, 34, 56],                         // mode=user_ids
 *     'segment_id' => 7,                                  // mode=segment
 *   ]
 *
 * Siempre se añade el predicado base:
 *   fcm_token IS NOT NULL AND fcm_token != '' AND email_verificado = 1
 */

/** Planes válidos (whitelist para evitar inyección en IN). */
function admin_campaign_valid_plans(): array {
    return ['free', 'premium', 'trial', 'early_bird'];
}

/**
 * Construye la cláusula WHERE + parámetros bind para SELECT sobre `usuarios`.
 *
 * @return array{0:string,1:array<int|string,mixed>}  [$whereSql, $params]
 */
function admin_campaign_filter_sql(array $filter): array {
    // Predicado base (siempre presente)
    $where = [
        'fcm_token IS NOT NULL',
        "fcm_token != ''",
        'email_verificado = 1',
    ];
    $params = [];

    $mode = $filter['mode'] ?? 'all';
    if (!is_string($mode)) $mode = 'all';

    // ── Por plan ──
    if ($mode === 'plan') {
        $planesValidos = admin_campaign_valid_plans();
        $planes = is_array($filter['plan'] ?? null)
            ? array_values(array_filter(
                $filter['plan'],
                fn($p) => is_string($p) && in_array($p, $planesValidos, true)
              ))
            : [];
        if (!empty($planes)) {
            $placeholders = implode(',', array_fill(0, count($planes), '?'));
            $where[] = "access_level IN ($placeholders)";
            foreach ($planes as $p) $params[] = $p;
        } else {
            // Modo plan sin planes seleccionados → audiencia vacía (fail-safe)
            $where[] = '1 = 0';
        }
    }

    // ── Por departamento (acepta lista o string) ──
    if ($mode === 'departamento') {
        $deps = [];
        if (!empty($filter['departamentos']) && is_array($filter['departamentos'])) {
            $deps = array_values(array_filter($filter['departamentos'], 'is_string'));
        } elseif (!empty($filter['departamento']) && is_string($filter['departamento'])) {
            $deps = [$filter['departamento']];
        }
        $deps = array_values(array_unique(array_filter($deps, fn($d) => trim((string)$d) !== '')));
        if (!empty($deps)) {
            $placeholders = implode(',', array_fill(0, count($deps), '?'));
            $where[] = "departamento IN ($placeholders)";
            foreach ($deps as $d) $params[] = $d;
        } else {
            $where[] = '1 = 0';
        }
    }

    // ── Por días de inactividad (>= N días sin login, o nunca logueado) ──
    if ($mode === 'days_inactive') {
        $days = isset($filter['days_inactive']) ? (int)$filter['days_inactive'] : 0;
        if ($days > 0) {
            // INTERVAL requiere literal entero — interpolamos tras int cast estricto
            $days = max(1, min(3650, $days));
            $where[] = "(ultimo_login IS NULL OR ultimo_login <= (NOW() - INTERVAL {$days} DAY))";
        } else {
            $where[] = '1 = 0';
        }
    }

    // ── Por IDs específicos ──
    if ($mode === 'user_ids') {
        $ids = is_array($filter['user_ids'] ?? null)
            ? array_values(array_filter(
                $filter['user_ids'],
                fn($i) => is_numeric($i) && (int)$i > 0
              ))
            : [];
        $ids = array_values(array_unique(array_map('intval', $ids)));
        if (!empty($ids)) {
            $placeholders = implode(',', array_fill(0, count($ids), '?'));
            $where[] = "id_usuario IN ($placeholders)";
            foreach ($ids as $i) $params[] = $i;
        } else {
            $where[] = '1 = 0';
        }
    }

    return [implode(' AND ', $where), $params];
}

/**
 * Resuelve un filtro que apunta a un `notification_segments` recursivamente
 * (un segmento puede apuntar a otro segmento — hasta 3 niveles de profundidad).
 */
function admin_campaign_resolve_segment(PDO $db, array $filter, int $depth = 0): array {
    if ($depth >= 3) return $filter; // protección anti-loop
    $mode = $filter['mode'] ?? '';
    if ($mode !== 'segment' || empty($filter['segment_id'])) {
        return $filter;
    }
    try {
        $stmt = $db->prepare('SELECT filter FROM notification_segments WHERE id = ? LIMIT 1');
        $stmt->execute([(int)$filter['segment_id']]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$row || empty($row['filter'])) {
            // Segmento inexistente o vacío → forzar audiencia vacía
            return ['mode' => 'user_ids', 'user_ids' => []];
        }
        $segFilter = json_decode((string)$row['filter'], true);
        if (!is_array($segFilter)) {
            return ['mode' => 'user_ids', 'user_ids' => []];
        }
        return admin_campaign_resolve_segment($db, $segFilter, $depth + 1);
    } catch (Throwable $e) {
        error_log('[campaign_filter] Error resolviendo segmento: ' . $e->getMessage());
        return ['mode' => 'user_ids', 'user_ids' => []];
    }
}

/** Cuenta el total de destinatarios para un filtro dado. */
function admin_campaign_count_audience(PDO $db, array $filter): int {
    $resolved = admin_campaign_resolve_segment($db, $filter);
    [$where, $params] = admin_campaign_filter_sql($resolved);
    try {
        $stmt = $db->prepare("SELECT COUNT(*) FROM usuarios WHERE $where");
        $stmt->execute($params);
        return (int)$stmt->fetchColumn();
    } catch (Throwable $e) {
        error_log('[campaign_filter] count error: ' . $e->getMessage());
        return 0;
    }
}

/**
 * Devuelve una muestra de hasta $limit destinatarios (datos seguros para mostrar en admin).
 * No expone fcm_token ni passwords.
 */
function admin_campaign_sample_audience(PDO $db, array $filter, int $limit = 20): array {
    $resolved = admin_campaign_resolve_segment($db, $filter);
    [$where, $params] = admin_campaign_filter_sql($resolved);
    $limit = max(1, min(100, $limit));
    try {
        $stmt = $db->prepare(
            "SELECT id_usuario, nombre, email, access_level, departamento, ciudad, ultimo_login
             FROM usuarios
             WHERE $where
             ORDER BY id_usuario ASC
             LIMIT $limit"
        );
        $stmt->execute($params);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
        error_log('[campaign_filter] sample error: ' . $e->getMessage());
        return [];
    }
}

/**
 * Obtiene TODOS los destinatarios (sin fcm_token — el cron lo traerá aparte
 * para no tenerlo en memoria más de lo necesario).
 *
 * Para campañas muy grandes se recomienda usar admin_campaign_audience_cursor().
 */
function admin_campaign_fetch_audience(PDO $db, array $filter, int $offset = 0, int $batch = 100): array {
    $resolved = admin_campaign_resolve_segment($db, $filter);
    [$where, $params] = admin_campaign_filter_sql($resolved);
    $batch = max(1, min(500, $batch));
    $offset = max(0, $offset);
    try {
        $stmt = $db->prepare(
            "SELECT id_usuario, nombre, email, fcm_token, access_level, departamento
             FROM usuarios
             WHERE $where
             ORDER BY id_usuario ASC
             LIMIT $batch OFFSET $offset"
        );
        $stmt->execute($params);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
        error_log('[campaign_filter] fetch error: ' . $e->getMessage());
        return [];
    }
}

/**
 * Genera un resumen legible del filtro para mostrar en tablas / vista detalle.
 * Ej: "Por plan: premium, trial · 2 criterios"
 */
function admin_campaign_filter_summary(array $filter): string {
    $mode = $filter['mode'] ?? 'all';
    switch ($mode) {
        case 'all':
            return 'Todos los usuarios con FCM token';
        case 'plan':
            $planes = is_array($filter['plan'] ?? null) ? $filter['plan'] : [];
            $planes = array_filter($planes, fn($p) => in_array($p, admin_campaign_valid_plans(), true));
            return 'Por plan: ' . (empty($planes) ? '(vacío)' : implode(', ', $planes));
        case 'departamento':
            $deps = [];
            if (!empty($filter['departamentos']) && is_array($filter['departamentos'])) {
                $deps = $filter['departamentos'];
            } elseif (!empty($filter['departamento'])) {
                $deps = [$filter['departamento']];
            }
            $deps = array_filter($deps, fn($d) => trim((string)$d) !== '');
            return 'Por departamento: ' . (empty($deps) ? '(vacío)' : implode(', ', $deps));
        case 'days_inactive':
            $d = (int)($filter['days_inactive'] ?? 0);
            return "Inactivos >= $d dias";
        case 'user_ids':
            $ids = is_array($filter['user_ids'] ?? null) ? $filter['user_ids'] : [];
            $ids = array_filter($ids, fn($i) => is_numeric($i) && (int)$i > 0);
            $count = count($ids);
            return "IDs especificos: $count destinatarios";
        case 'segment':
            return 'Segmento guardado #' . (int)($filter['segment_id'] ?? 0);
        default:
            return '—';
    }
}

/**
 * Valida y normaliza un filtro recibido por POST desde el form.
 * Limpia valores inválidos y aplica defaults seguros.
 */
function admin_campaign_normalize_filter(array $raw): array {
    $mode = $raw['mode'] ?? 'all';
    $allowedModes = ['all', 'plan', 'departamento', 'days_inactive', 'user_ids', 'segment'];
    if (!in_array($mode, $allowedModes, true)) {
        $mode = 'all';
    }

    $filter = ['mode' => $mode];

    if ($mode === 'plan') {
        $planes = $raw['plan'] ?? [];
        if (!is_array($planes)) $planes = [];
        $filter['plan'] = array_values(array_filter(
            $planes,
            fn($p) => is_string($p) && in_array($p, admin_campaign_valid_plans(), true)
        ));
    } elseif ($mode === 'departamento') {
        $depInput = trim((string)($raw['departamento'] ?? ''));
        $deps = [];
        if ($depInput !== '') {
            // Acepta separados por coma, punto y coma, salto de línea
            $parts = preg_split('/[\s,;]+/', $depInput) ?: [];
            foreach ($parts as $p) {
                $p = trim($p);
                if ($p !== '') $deps[] = $p;
            }
        }
        if (!empty($raw['departamentos']) && is_array($raw['departamentos'])) {
            foreach ($raw['departamentos'] as $d) {
                $d = trim((string)$d);
                if ($d !== '' && !in_array($d, $deps, true)) $deps[] = $d;
            }
        }
        $filter['departamentos'] = $deps;
        $filter['departamento']  = $deps[0] ?? '';
    } elseif ($mode === 'days_inactive') {
        $days = (int)($raw['days_inactive'] ?? 0);
        $filter['days_inactive'] = max(0, min(3650, $days));
    } elseif ($mode === 'user_ids') {
        $idsInput = trim((string)($raw['user_ids_text'] ?? ''));
        $ids = [];
        if ($idsInput !== '') {
            foreach (preg_split('/[\s,;]+/', $idsInput) ?: [] as $tok) {
                $tok = trim($tok);
                if (is_numeric($tok) && (int)$tok > 0) $ids[] = (int)$tok;
            }
        }
        $filter['user_ids'] = array_values(array_unique($ids));
    } elseif ($mode === 'segment') {
        $sid = (int)($raw['segment_id'] ?? 0);
        $filter['segment_id'] = $sid > 0 ? $sid : 0;
    }

    return $filter;
}
