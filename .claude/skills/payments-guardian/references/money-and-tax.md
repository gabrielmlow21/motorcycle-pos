# Money and tax

Detail for rules 1 and 8 in SKILL.md. Malaysian ringgit: 1 RM = 100 sen.

## Integer sen everywhere

Store and calculate every amount as an integer number of sen. RM 149.90 is `14990`.

Floats cannot represent most decimal fractions exactly. `0.1 + 0.2 !== 0.3` in PHP as in most
languages, and those errors accumulate across line items until a total is visibly wrong. This
is not a theoretical concern — it is the single most common way POS systems leak money.

```php
// Migration — money columns
$table->unsignedInteger('unit_price_sen');   // RM 149.90 -> 14990
$table->unsignedInteger('line_total_sen');
$table->unsignedInteger('total_sen');

// Model
protected function casts(): array
{
    return ['unit_price_sen' => 'integer', 'total_sen' => 'integer'];
}
```

**Naming.** Suffix every money column, property, and variable with `_sen`. A bare `$total` is
ambiguous and ambiguity is how a ringgit value gets multiplied by 100 twice. The suffix makes
a unit error visible while reading the diff.

**Never** use `float`, `double`, or `->cast('decimal:2')` for money. Do not accept a decimal
string from the frontend and multiply by 100 in PHP — parse to integer sen at the boundary,
validate it, and keep it integer from there.

**Conversion happens at the edges only.** Integer sen in the database and in all math; format
to `RM 149.90` in the API resource or the React component, at the moment of display.

## Rounding

Money math is exact and needs no rounding **except** where tax produces a fraction of a sen.
That is the only place a rounding rule applies, so it is stated once here and pinned by a test.

**The rule: round half up, once, at the tax subtotal — not per line item.**

Rounding each line and summing produces a different total than summing and rounding once. Pick
one and never mix them. Rounding once at the subtotal is the convention here.

```php
// $subtotal_sen and $rate come from config; intdiv/round applied exactly once
$tax_sen = (int) round($subtotal_sen * $rate, 0, PHP_ROUND_HALF_UP);
$total_sen = $subtotal_sen + $tax_sen;
```

`round()` returns a float, so the `(int)` cast is required. The input is an integer and the
rate is small, so this stays well inside the exact-integer range of a double — but the cast
must not be dropped.

**If the shop's accountant specifies a different convention** (banker's rounding, or per-line),
that is a stop-and-ask, not a judgement call. Change it here and update the test together.

## SST rate

The rate is a configurable setting, never a constant. — `CLAUDE.md:50`

```php
// config/tax.php
return [
    'sst_rate' => env('SST_RATE'),   // no default — absence must be loud
];
```

Deliberately no default. A missing rate should fail loudly at checkout rather than silently
charge 0% or a stale guess.

**Do not invent a rate.** Not in code, not in a test fixture presented as real, not behind a
TODO. `motorcycle-pos-build-plan.md:126` says to confirm the current SST treatment for
motorcycle parts and service with an accountant or LHDN. If the rate is not in config and you
need one, **stop and ask** — see SKILL.md.

Tests may use an obviously synthetic rate (e.g. 10%) set explicitly in the test body, so the
arithmetic is checkable without implying that number is real.

## Rate changes

A rate change must not retroactively alter past invoices. Store the rate actually applied on
the sale or invoice row (`sst_rate_applied`), rather than recomputing historical tax from
current config. A reprinted receipt from last year must show last year's tax.

## What to check before shipping

- [ ] Every money column is an integer and named `*_sen`.
- [ ] No float or `decimal` cast anywhere on a money path.
- [ ] Rounding happens once, at the tax subtotal, half-up.
- [ ] The SST rate is read from config; no literal rate in application code.
- [ ] The rate applied is stored on the record for historical accuracy.
