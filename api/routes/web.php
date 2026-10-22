<?php

use Illuminate\Support\Facades\Route;

// This is a JSON API with no server-rendered pages; the React PWA is the only client.
Route::get('/', fn () => ['status' => 'ok']);
