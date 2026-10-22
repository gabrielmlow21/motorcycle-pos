<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Cross-Origin Resource Sharing (CORS) Configuration
    |--------------------------------------------------------------------------
    |
    | The React PWA is served from a different origin (Azure Static Web Apps)
    | than this API, so the browser needs CORS headers to allow its requests.
    |
    | CORS is configured here only. Do not also enable it on the App Service
    | CORS blade: both would add Access-Control-Allow-Origin and browsers
    | reject a response that carries the header twice.
    |
    | Allowed origins come from CORS_ALLOWED_ORIGINS (comma-separated), so the
    | production URL lives in App Service configuration rather than in code.
    | When it is unset, no cross-origin requests are allowed.
    |
    */

    'paths' => ['api/*', 'sanctum/csrf-cookie', 'up'],

    'allowed_methods' => ['*'],

    'allowed_origins' => array_values(array_filter(array_map(
        'trim',
        explode(',', (string) env('CORS_ALLOWED_ORIGINS', '')),
    ))),

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    'supports_credentials' => false,

];
