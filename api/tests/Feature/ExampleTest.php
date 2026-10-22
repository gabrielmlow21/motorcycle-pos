<?php

namespace Tests\Feature;

use Tests\TestCase;

class ExampleTest extends TestCase
{
    public function test_the_root_returns_an_ok_status(): void
    {
        $this->get('/')
            ->assertOk()
            ->assertExactJson(['status' => 'ok']);
    }
}
