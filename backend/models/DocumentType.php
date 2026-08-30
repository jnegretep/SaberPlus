<?php
/**
 * models/DocumentType.php
 */

declare(strict_types=1);

class DocumentType
{
    public static function all(PDO $db, int $institutionId, bool $onlyActive = true): array
    {
        $sql = 'SELECT * FROM document_types WHERE institution_id = ?';
        if ($onlyActive) $sql .= ' AND is_active = 1';
        $sql .= ' ORDER BY sort_order ASC, name ASC';
        $stmt = $db->prepare($sql);
        $stmt->execute([$institutionId]);
        return $stmt->fetchAll();
    }

    public static function findById(PDO $db, int $id): ?array
    {
        $stmt = $db->prepare('SELECT * FROM document_types WHERE id = ?');
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    /**
     * Dado un texto OCR (encabezado del documento), devuelve el tipo
     * de documento más probable según las keywords.
     *
     * @return array ['type' => ?array, 'confidence' => int, 'alternatives' => array]
     */
    public static function classifyByText(PDO $db, int $institutionId, string $ocrText): array
    {
        $types = self::all($db, $institutionId);
        $upper = mb_strtoupper($ocrText, 'UTF-8');

        $scored = [];
        foreach ($types as $t) {
            $keywords = json_decode($t['keywords_ocr'] ?? '[]', true) ?: [];
            if (!$keywords) continue;
            $hits = 0;
            foreach ($keywords as $kw) {
                $kwU = mb_strtoupper(trim($kw), 'UTF-8');
                if ($kwU !== '' && mb_strpos($upper, $kwU) !== false) {
                    $hits++;
                }
            }
            if ($hits > 0) {
                $scored[] = [
                    'type'       => $t,
                    'hits'       => $hits,
                    'confidence' => min(100, 60 + $hits * 20),
                ];
            }
        }
        usort($scored, fn($a, $b) => $b['hits'] <=> $a['hits']);

        $top = $scored[0] ?? null;
        $alternatives = array_slice(array_map(fn($x) => [
            'id'         => (int)$x['type']['id'],
            'name'       => $x['type']['name'],
            'code'       => $x['type']['code'],
            'confidence' => $x['confidence'],
        ], $scored), 0, 3);

        return [
            'type'         => $top ? $top['type'] : null,
            'confidence'   => $top ? $top['confidence'] : 0,
            'alternatives' => $alternatives,
        ];
    }
}
