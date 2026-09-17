<?php
// wompi_config.php
return [
    'public_key'   => 'pub_prod_gSFzmpYJuYAt2ALRMIF9edb86w7gdDQ9',
    'private_key'  => 'prv_prod_u8TLiNWX5fplD3rL7BvoV5AE43ZzpUU2',
    'events_secret'=> 'prod_events_PcmnIXxmXhuJKNfx0KFfiV0udcDS2V7j',
    'integrity'    => 'prod_integrity_ofgKaEpSvgxKiBImSq4idGZIaY02ByNh',
    
    'currency'     => 'COP',
    'redirect_url' => 'http://corpoinstel.edu.co/api/prepsaber/backend/wompi_return.php',
    'webhook_url'  => 'http://corpoinstel.edu.co/api/prepsaber/backend/wompi_webhook.php',
    
    // Modo: 'production' o 'sandbox'
    'environment'  => 'production',
];