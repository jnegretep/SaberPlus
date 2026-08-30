<?php
/**
 * controllers/DocumentTypeController.php
 */

declare(strict_types=1);

class DocumentTypeController
{
    /** GET /api/types/list.php */
    public static function list(PDO $db): void
    {
        $payload = require_auth();
        $types = DocumentType::all($db, (int)$payload['inst']);

        $list = array_map(function ($t) {
            return [
                'id'           => (int)$t['id'],
                'name'         => $t['name'],
                'code'         => $t['code'],
                'description'  => $t['description'],
                'icon'         => $t['icon'],
                'color_hex'    => $t['color_hex'],
                'keywords_ocr' => json_decode($t['keywords_ocr'] ?? '[]', true) ?: [],
                'sort_order'   => (int)$t['sort_order'],
                'is_active'    => (bool)$t['is_active'],
            ];
        }, $types);

        send_json(true, $list);
    }

    /** GET /api/types/classify.php?ocr_text= */
    public static function classify(PDO $db): void
    {
        $payload = require_auth();
        $ocrText = $_GET['ocr_text'] ?? '';
        if (!$ocrText) send_error('ocr_text requerido.', 'MISSING_PARAM', 422);

        $match = DocumentType::classifyByText($db, (int)$payload['inst'], $ocrText);
        $type = $match['type'];
        $publicType = $type ? [
            'id'        => (int)$type['id'],
            'name'      => $type['name'],
            'code'      => $type['code'],
            'color_hex' => $type['color_hex'],
            'icon'      => $type['icon'],
        ] : null;

        send_json(true, [
            'type'         => $publicType,
            'confidence'   => $match['confidence'],
            'alternatives' => $match['alternatives'],
        ]);
    }
}
