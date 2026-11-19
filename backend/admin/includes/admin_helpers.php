<?php
declare(strict_types=1);

/**
 * Helpers compartidos del módulo Admin.
 * Reúne utilidades que estaban duplicadas en index.php / check_ia.php / export_csv.php.
 */

// ── XSS escaping ──

/** htmlspecialchars con ENT_QUOTES + UTF-8. Versión corta. */
function sp_h(?string $s): string {
    return htmlspecialchars($s ?? '', ENT_QUOTES, 'UTF-8');
}

// ── CSRF ──

/** Genera campo hidden para incluir en cualquier form POST. */
function admin_csrf_field(): string {
    if (empty($_SESSION['admin_csrf'])) {
        $_SESSION['admin_csrf'] = bin2hex(random_bytes(32));
    }
    return '<input type="hidden" name="csrf_token" value="' . sp_h($_SESSION['admin_csrf']) . '">';
}

/** Devuelve el token CSRF actual (para JS / headers). */
function admin_csrf_token(): string {
    if (empty($_SESSION['admin_csrf'])) {
        $_SESSION['admin_csrf'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['admin_csrf'];
}

/** Verifica el token CSRF (desde POST o header X-CSRF-Token). Lanza 403 si falla. */
function admin_csrf_verify(): void {
    $token = $_POST['csrf_token'] ?? $_SERVER['HTTP_X_CSRF_TOKEN'] ?? '';
    if (empty($_SESSION['admin_csrf']) || !hash_equals($_SESSION['admin_csrf'], (string)$token)) {
        http_response_code(403);
        exit('CSRF token inválido. Recarga la página e intenta de nuevo.');
    }
}

// ── Consultas con degradación elegante ──

/** Ejecuta una query escalar con try/catch y devuelve null si falla. */
function safeScalar(PDO $db, string $sql, array $params = []) {
    try {
        $stmt = $db->prepare($sql);
        $stmt->execute($params);
        $val = $stmt->fetchColumn();
        return $val === false ? null : $val;
    } catch (Throwable $e) {
        error_log('[safeScalar] ' . $e->getMessage());
        return null;
    }
}

/** Ejecuta una query y devuelve todas las filas o [] si falla. */
function safeRows(PDO $db, string $sql, array $params = []): array {
    try {
        $stmt = $db->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
        error_log('[safeRows] ' . $e->getMessage());
        return [];
    }
}

// ── Series temporales ──

/**
 * Devuelve serie de N días con conteo de una expresión (COUNT, SUM, etc.).
 * Rellena días sin datos con 0.
 *
 * @return array{fecha:string, valor:int}[]
 */
function adminSerieNDias(PDO $db, int $dias, string $expr, string $tabla, string $colFecha = 'created_at'): array {
    $serie = [];
    $hoy = new DateTimeImmutable();
    for ($i = $dias - 1; $i >= 0; $i--) {
        $fecha = $hoy->modify("-$i day")->format('Y-m-d');
        $serie[$fecha] = 0;
    }
    try {
        $sql = "SELECT DATE($colFecha) AS d, $expr AS v FROM $tabla
                WHERE $colFecha >= (CURDATE() - INTERVAL " . (int)$dias . " DAY)
                GROUP BY d ORDER BY d";
        foreach ($db->query($sql)->fetchAll(PDO::FETCH_ASSOC) as $r) {
            if (isset($serie[$r['d']])) $serie[$r['d']] = (int)$r['v'];
        }
    } catch (Throwable $e) {
        error_log('[adminSerieNDias] ' . $e->getMessage());
    }
    return array_map(
        fn($f, $v) => ['fecha' => $f, 'valor' => $v],
        array_keys($serie),
        array_values($serie)
    );
}

// ── SVG charts (zero-CDN) ──

/**
 * Genera un gráfico SVG inline de líneas a partir de una serie.
 *
 * @param array{fecha:string, valor:int}[] $serie
 */
function admin_svg_serie(array $serie, int $w = 320, int $h = 80, string $color = '#1E4ED8'): string {
    if (empty($serie)) return '<svg width="'.$w.'" height="'.$h.'"></svg>';
    $vals = array_column($serie, 'valor');
    $max = max(1, max($vals));
    $n = count($serie);
    $pad = 4;
    $iw = $w - $pad * 2;
    $ih = $h - $pad * 2;
    $points = [];
    foreach ($vals as $i => $v) {
        $x = $pad + ($n > 1 ? ($i / ($n - 1)) * $iw : $iw / 2);
        $y = $pad + $ih - ($v / $max) * $ih;
        $points[] = "$x,$y";
    }
    $poly = implode(' ', $points);
    // Área bajo la línea
    $areaPoints = $poly . " " . ($pad + $iw) . "," . ($pad + $ih) . " " . $pad . "," . ($pad + $ih);
    return <<<SVG
<svg width="$w" height="$h" viewBox="0 0 $w $h" xmlns="http://www.w3.org/2000/svg">
  <polygon points="$areaPoints" fill="$color" fill-opacity="0.12"/>
  <polyline points="$poly" fill="none" stroke="$color" stroke-width="2"/>
</svg>
SVG;
}

/** Gráfico donut SVG. $data = [['label'=>'Free','value'=>120,'color'=>'#10B981'], ...] */
function admin_svg_donut(array $data, int $size = 120, int $thickness = 18): string {
    $total = array_sum(array_column($data, 'value'));
    if ($total <= 0) return '<svg width="'.$size.'" height="'.$size.'"></svg>';
    $r = ($size - $thickness) / 2;
    $cx = $size / 2; $cy = $size / 2;
    $circunf = 2 * M_PI * $r;
    $offset = 0;
    $paths = '';
    foreach ($data as $d) {
        $frac = $d['value'] / $total;
        $len = $frac * $circunf;
        $color = $d['color'] ?? '#1E4ED8';
        $paths .= sprintf(
            '<circle cx="%s" cy="%s" r="%s" fill="none" stroke="%s" stroke-width="%s" stroke-dasharray="%s %s" stroke-dashoffset="%s" transform="rotate(-90 %s %s)"/>',
            $cx, $cy, $r, $color, $thickness,
            $len, $circunf - $len, -$offset,
            $cx, $cy
        );
        $offset += $len;
    }
    return <<<SVG
<svg width="$size" height="$size" viewBox="0 0 $size $size" xmlns="http://www.w3.org/2000/svg">
  <circle cx="$cx" cy="$cy" r="$r" fill="none" stroke="#E5E7EB" stroke-width="$thickness"/>
  $paths
</svg>
SVG;
}

/** Gráfico de barras horizontal. $data = [['label'=>'Premium','value'=>42], ...] */
function admin_svg_bars(array $data, int $w = 320, int $barH = 18, int $gap = 4, string $color = '#1E4ED8'): string {
    if (empty($data)) return '<svg width="'.$w.'" height="0"></svg>';
    $max = max(1, max(array_column($data, 'value')));
    $n = count($data);
    $h = $n * ($barH + $gap);
    $labelW = 80;
    $valW = 40;
    $barX = $labelW + 8;
    $barAreaW = $w - $barX - $valW - 8;
    $bars = '';
    foreach ($data as $i => $d) {
        $y = $i * ($barH + $gap);
        $v = $d['value'];
        $bw = ($v / $max) * $barAreaW;
        $label = sp_h(mb_substr($d['label'] ?? '', 0, 14));
        $bars .= sprintf(
            '<text x="0" y="%d" font-family="system-ui" font-size="11" fill="#475569">%s</text>' .
            '<rect x="%d" y="%d" width="%d" height="%d" rx="3" fill="%s"/>' .
            '<text x="%d" y="%d" font-family="system-ui" font-size="11" fill="#0F172A" font-weight="600">%d</text>',
            $y + $barH - 4, $label,
            $barX, $y, (int)$bw, $barH, $color,
            $barX + $barAreaW + 6, $y + $barH - 4, $v
        );
    }
    return <<<SVG
<svg width="$w" height="$h" viewBox="0 0 $w $h" xmlns="http://www.w3.org/2000/svg">$bars</svg>
SVG;
}

// ── Formateo ──

function admin_fmt_int($n): string {
    return number_format((int)($n ?? 0), 0, ',', '.');
}

function admin_fmt_cop($n): string {
    return '$ ' . number_format((float)($n ?? 0), 0, ',', '.');
}

function admin_fmt_usd($n): string {
    return 'US$ ' . number_format((float)($n ?? 0), 2, ',', '.');
}

function admin_fmt_pct($n, int $dec = 1): string {
    return number_format((float)($n ?? 0), $dec, ',', '.') . '%';
}

function admin_fmt_fecha(?string $f): string {
    if (empty($f) || $f === '0000-00-00 00:00:00') return '—';
    $t = strtotime($f);
    return $t ? date('d/m/Y H:i', $t) : '—';
}

function admin_fmt_tiempo_relativo(?string $f): string {
    if (empty($f)) return 'nunca';
    $t = strtotime($f);
    if (!$t) return '—';
    $diff = time() - $t;
    if ($diff < 60) return 'hace unos segundos';
    if ($diff < 3600) return 'hace ' . intdiv($diff, 60) . ' min';
    if ($diff < 86400) return 'hace ' . intdiv($diff, 3600) . ' h';
    if ($diff < 2592000) return 'hace ' . intdiv($diff, 86400) . ' días';
    return date('d/m/Y', $t);
}

// ── IP cliente (con soporte de proxy) ──

function admin_client_ip(): string {
    if (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
        $ips = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']);
        return trim($ips[0]);
    }
    return $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
}

// ── JSON response helper para API REST ──

function admin_json_response($data, int $code = 200): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=UTF-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function admin_json_error(string $message, int $code = 400, array $extra = []): void {
    admin_json_response(array_merge(['status' => 'error', 'message' => $message], $extra), $code);
}
