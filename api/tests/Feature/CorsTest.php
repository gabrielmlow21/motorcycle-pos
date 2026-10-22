<?php

namespace Tests\Feature;

use Tests\TestCase;

class CorsTest extends TestCase
{
    private const PWA_ORIGIN = 'https://pos.example.test';

    protected function setUp(): void
    {
        parent::setUp();

        config(['cors.allowed_origins' => [self::PWA_ORIGIN]]);
    }

    public function test_the_pwa_origin_may_call_the_api(): void
    {
        $this->get('/up', ['Origin' => self::PWA_ORIGIN])
            ->assertOk()
            ->assertHeader('Access-Control-Allow-Origin', self::PWA_ORIGIN);
    }

    public function test_an_unknown_origin_is_not_allowed(): void
    {
        $response = $this->get('/up', ['Origin' => 'https://not-the-shop.example.test']);

        // With exactly one allowed origin, the CORS library always echoes that origin back
        // rather than omitting the header. The browser blocks the request because the
        // value doesn't match the caller, so what matters is that it never names the caller.
        $this->assertNotSame(
            'https://not-the-shop.example.test',
            $response->headers->get('Access-Control-Allow-Origin'),
        );
    }
}
