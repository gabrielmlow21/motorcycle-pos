# Test checklist

`CLAUDE.md:55` requires tests for every new endpoint. For money code that means these specific
cases. Each one encodes a rule from SKILL.md — if a rule cannot fail a test, it is not enforced.

Write the failing test **before** the implementation and watch it fail. A guard you never saw
reject something is a guard you have not tested.

Run with `php artisan test` inside `/api`.

## 1. Rollback leaves nothing

A sale that fails midway writes zero rows — no sale, no items, no movements, no payment.

```php
it('leaves no trace when a sale fails midway', function () {
    $product = Product::factory()->withStock(5)->create();

    // Second line references a product that will fail the stock check
    expect(fn () => $this->checkout([
        ['product_id' => $product->id, 'quantity' => 1],
        ['product_id' => Product::factory()->withStock(0)->create()->id, 'quantity' => 1],
    ]))->toThrow(InsufficientStockException::class);

    expect(Sale::count())->toBe(0);
    expect(SaleItem::count())->toBe(0);
    expect(InventoryMovement::where('reason', 'sale')->count())->toBe(0);
    expect(Payment::count())->toBe(0);
});
```

Assert on **counts of zero**, not on the sale's absence alone. A half-written sale that leaves
an orphaned movement is exactly the corruption this rule exists to prevent.

## 2. Concurrency — exactly one sale of the last unit

Two cashiers sell the last unit simultaneously; one succeeds, one fails, stock lands at zero.

This needs two real database connections — `RefreshDatabase` wraps each test in a transaction,
which hides the behaviour. Use `DatabaseTransactions` off for this test, or drive two processes.
Verify the outcome, not the timing:

```php
it('allows only one sale of the last unit', function () {
    $product = Product::factory()->withStock(1)->create();

    $results = $this->runConcurrently(2, fn () => $this->checkout([
        ['product_id' => $product->id, 'quantity' => 1],
    ]));

    expect(collect($results)->filter(fn ($r) => $r->succeeded))->toHaveCount(1);
    expect($product->currentStock())->toBe(0);   // never -1
});
```

If concurrent testing proves impractical in CI, assert instead that the stock read uses
`lockForUpdate()` — a weaker test, but it must not be silently dropped. Note the limitation
in the test file.

## 3. Duplicate webhook records one payment

```php
it('records one payment when the same webhook arrives twice', function () {
    $sale = Sale::factory()->awaitingPayment()->create(['total_sen' => 14990]);
    $payload = $this->webhookPayload($sale, event_id: 'evt_abc123');

    $this->postSignedWebhook($payload)->assertSuccessful();
    $this->postSignedWebhook($payload)->assertSuccessful();   // 2xx, or the provider retries

    expect(Payment::where('sale_id', $sale->id)->count())->toBe(1);
    expect($sale->fresh()->total_paid_sen)->toBe(14990);
});
```

Assert the **payment total**, not just the row count — double-counting into an existing row
would pass a count check.

## 4. Bad signature is rejected and records nothing

```php
it('rejects an unsigned webhook without recording anything', function () {
    $sale = Sale::factory()->awaitingPayment()->create();

    $this->postJson('/api/webhooks/payments', $this->webhookPayload($sale))
        ->assertUnauthorized();

    expect(PaymentEvent::count())->toBe(0);
    expect(Payment::count())->toBe(0);
    expect($sale->fresh()->status)->not->toBe('paid');
});
```

Cover both a missing signature and a wrong one.

## 5. Frontend cannot set paid status

```php
it('ignores a paid status supplied by the client', function () {
    $sale = Sale::factory()->awaitingPayment()->create();

    $this->actingAs(User::factory()->cashier()->create())
        ->patchJson("/api/sales/{$sale->id}", ['status' => 'paid']);

    expect($sale->fresh()->status)->not->toBe('paid');
});
```

Whether this returns 422 or silently drops the field, the sale must not become paid. Assert the
outcome rather than the status code.

## 6. Cash change is computed server-side

```php
it('calculates change server-side and rejects short tender', function () {
    $sale = Sale::factory()->awaitingPayment()->create(['total_sen' => 14990]);

    // A wrong client-supplied change value must not be trusted
    $response = $this->recordCash($sale, tendered_sen: 20000, change_sen: 99999);
    expect($response->json('change_sen'))->toBe(5010);

    expect(fn () => $this->recordCash($sale, tendered_sen: 10000))
        ->toThrow(InsufficientTenderException::class);
});
```

## 7. Tax at the configured rate

```php
it('applies the configured SST rate and pins the rounding rule', function () {
    // Synthetic rate — NOT a claim about the real Malaysian SST rate.
    config(['tax.sst_rate' => 0.10]);

    $sale = $this->checkout([...]);            // subtotal 14990 sen

    expect($sale->tax_sen)->toBe(1499);        // round half up, once, at the subtotal
    expect($sale->total_sen)->toBe(16489);
});

it('does not retroactively change tax on past invoices', function () {
    config(['tax.sst_rate' => 0.10]);
    $sale = $this->checkout([...]);
    $taxAtSale = $sale->tax_sen;

    config(['tax.sst_rate' => 0.15]);          // rate changes later

    expect($sale->fresh()->tax_sen)->toBe($taxAtSale);
});
```

Set the rate explicitly in the test. Never let a money test read a real rate from config — the
test would change meaning when the rate changes.

Include a case that produces a fraction of a sen, so the rounding rule is actually exercised.

## 8. Authorization is server-side

For every money endpoint, assert a role that should not reach it gets 403 — from the API, not
from a hidden button. — `CLAUDE.md:42-43`

```php
it('forbids a cashier from voiding a completed sale', function () {
    $sale = Sale::factory()->paid()->create();

    $this->actingAs(User::factory()->cashier()->create())
        ->deleteJson("/api/sales/{$sale->id}")
        ->assertForbidden();
});
```

## Before merge

- [ ] Rollback test asserts zero rows across all four tables.
- [ ] Concurrency test present, or its absence explicitly noted in the test file.
- [ ] Duplicate webhook asserts one payment *and* the correct total.
- [ ] Bad-signature test covers missing and wrong signatures.
- [ ] Client-supplied `paid` status proven ineffective.
- [ ] Cash change computed server-side; short tender rejected.
- [ ] Tax test sets a synthetic rate explicitly and pins rounding.
- [ ] Every money endpoint has a 403 test for the wrong role.
- [ ] `php artisan test` passes and `./vendor/bin/pint` is clean.
