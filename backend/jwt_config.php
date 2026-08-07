<?php
// jwt_config.php
return [
    'secret'         => '90c5de59689bec58fe84e8f2006a6e7bafaffb906e4996e63ceee55fe2cfc9a9',
    'algo'           => 'HS256',
    'issuer'         => 'prep-saber',
    'audience'       => 'prep-saber-users',
    'expiry_seconds' => 86400,
];
