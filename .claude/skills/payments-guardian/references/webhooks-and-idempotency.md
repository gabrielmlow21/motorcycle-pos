# Webhooks, idempotency, and cash

Detail for rules 5 and 6 in SKILL.md.

The provider is not yet chosen — `DESIGN.md:17-18` leans toward a local aggregator (HitPay,
Billplz, Fiuu, Curlec) for DuitNow QR + FPX + e-wallets. **That decision is open.** These
patterns are provider-agnostic; picking one is a stop-and-ask.

## Trust the webhook, not the browser

Payment status flips only on a verified provider webhook, or on recorded cash with change
calculated server-side. — `CLAUDE.md:44-45`

The browser is not a trustworthy witness that money moved. A customer reaching a "success"
screen proves nothing — the page can be replayed, spoofed, or reached by editing a URL. The
provider's server-to-server callback is the only claim worth acting on, and only after its
signature verifies.

**No endpoint may accept a `paid` status from the client.** Not `PATCH /sales/{id}` with
`{"status":"paid"}`, not a `status` field in the checkout payload. If a request body contains
a payment status, ignore it — do not validate it, do not map it. Payment status is derived
server-side or not at all.

## Verify the signature first

Before parsing the body or touching the database:

```php
// Compute over the RAW body — re-encoding JSON changes bytes and breaks the signature.
$expected = hash_hmac('sha256', $request->getContent(), config('services.payments.webhook_secret'));

// Constant-time compare: a plain === leaks timing information about the correct signature.
if (! hash_equals($expected, $request->header('X-Provider-Signature', ''))) {
    Log::warning('Rejected webhook: bad signature');
    abort(401);
}
```

An unsigned or badly-signed webhook records **nothing** — no payment, no event row, no status
change. Log it and return 401.

The secret comes from config, sourced from Key Vault in production. — `CLAUDE.md:47-48`

Exempt the webhook route from CSRF, and do **not** put it behind Sanctum auth — the provider
has no session. Signature verification is its authentication.

## Idempotency

The same webhook firing twice must not double-count. — `CLAUDE.md:46`

Providers retry on timeout, on a non-2xx response, and sometimes for no visible reason. Assume
every webhook will arrive more than once.

**The primary defense is a UNIQUE index**, not application logic:

```php
// Migration
Schema::create('payment_events', function (Blueprint $table) {
    $table->id();
    $table->string('provider');
    $table->string('provider_event_id');
    $table->json('payload');
    $table->timestamps();

    // The database refuses the duplicate. This is the guarantee — a PHP-level
    // "have I seen this?" check has a race window between the check and the insert.
    $table->unique(['provider', 'provider_event_id']);
});
```

Then insert first and let a duplicate-key violation mean "already processed":

```php
try {
    $event = PaymentEvent::create([
        'provider'          => 'aggregator',
        'provider_event_id' => $payload['event_id'],
        'payload'           => $payload,
    ]);
} catch (QueryException $e) {
    if ($e->getCode() === '23000') {          // integrity constraint violation
        return response()->noContent();        // already handled — 2xx stops the retries
    }
    throw $e;
}

// First time seeing this event — apply it inside a transaction.
DB::transaction(fn () => $this->applyPayment($event));
```

Returning 2xx for a duplicate is deliberate: a non-2xx tells the provider to retry, which
loops forever on an event you have already handled.

**MySQL caveat:** MySQL and MariaDB ignore the second argument to Laravel's `upsert()` and use
the table's own primary and unique indexes to detect existing records. So the unique index must
exist in the migration — application code alone does not make this safe.

**Optional, later:** `Cache::lock()` or `Cache::withoutOverlapping()` serializes handlers if a
provider delivers retries *concurrently* rather than sequentially. This is defense-in-depth,
not the primary guard, and it needs a cache store shared across App Service instances —
`motorcycle-pos-build-plan.md:51` defers Redis to later. Skip for v1; the unique index covers
the realistic case.

## Reconciling to the sale

Match the event to its sale by the provider reference stored when the payment intent was
created — never by amount and timestamp, which collide on a busy Saturday.

Confirm the amount matches the sale's `total_sen` before marking anything paid. A mismatch is a
real signal (partial payment, wrong currency, tampering): log it, alert, and do not flip status.

## Cash

Cash is a first-class method — `DESIGN.md:18`. It has no webhook, so the server computes:

```php
// Change is calculated server-side. A client-supplied change amount is ignored.
$change_sen = $tendered_sen - $total_sen;

if ($change_sen < 0) {
    throw new InsufficientTenderException();
}
```

Record the payment and flip status in the same transaction as the sale. Never trust a
frontend-calculated change figure — it is a display convenience, not an input.

## What to check before shipping

- [ ] Signature verified against the raw body with `hash_equals` before any DB work.
- [ ] Bad signature → 401, nothing recorded.
- [ ] UNIQUE index on `(provider, provider_event_id)` exists in the migration.
- [ ] Duplicate event returns 2xx and records exactly one payment.
- [ ] Amount reconciled against the sale total before flipping status.
- [ ] No endpoint accepts a payment status from the client.
- [ ] Cash change computed server-side; negative tender rejected.
- [ ] Webhook secret from config, never a literal.
