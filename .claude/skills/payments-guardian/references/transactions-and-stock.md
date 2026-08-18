# Transactions and stock

Detail for rules 2 and 3 in SKILL.md.

## One money path

A retail sale and a completed work order **converge on the same payment and invoice path**.
— `DESIGN.md:69-70`

```
  Retail sale  ─┐
                ├──→  payment  ──→  invoice
  Work order   ─┘
```

Two consequences:

- `parts_used` on a work order deducts stock through the *same* `inventory_movements` logic as
  `sale_items`. Not a parallel implementation, not a copy with different column names.
- Phase 7 work-order invoicing reuses the Phase 3/4 sale → payment → invoice flow.

If a change appears to need a second money path, that is a **stop-and-ask**. Two money paths
means two places to fix every future bug, and they drift.

## Stock is the sum of movements

Stock level is computed, never stored as an editable column. — `CLAUDE.md:40-41`

```php
// Every stock change writes an audit row
$table->foreignId('product_id')->constrained();
$table->integer('quantity_delta');           // negative for a sale, positive for a restock
$table->string('reason');                    // sale | restock | adjustment | used_in_service
$table->nullableMorphs('reference');         // the sale / work order that caused it
```

`quantity_delta` is a signed integer — a sale writes `-1`, a restock writes `+10`. Current
level is `SUM(quantity_delta)` for that product. Nothing ever updates a movement row; a
correction is a *new* row with `reason = adjustment`. That is what makes the trail auditable.

A `products.stock_quantity` column that gets written directly defeats the entire design. If
one appears for read performance, it must be a derived cache rebuilt from movements, never the
source of truth, and it needs its own consistency test.

## Transaction boundaries

A sale deducts stock and records payment atomically, or does neither. — `CLAUDE.md:38-39`

```php
use Illuminate\Support\Facades\DB;

// The closure form commits on return and rolls back on any thrown exception.
DB::transaction(function () use ($cart, $user) {
    $sale = Sale::create([...]);

    foreach ($cart->lines as $line) {
        // lockForUpdate blocks other transactions from reading these movement rows
        // for update until this transaction commits — this is what stops two cashiers
        // both selling the last unit.
        $onHand = InventoryMovement::where('product_id', $line->product_id)
            ->lockForUpdate()
            ->sum('quantity_delta');

        if ($onHand < $line->quantity) {
            throw new InsufficientStockException($line->product_id);
        }

        $sale->items()->create([...]);
        InventoryMovement::create([
            'product_id'     => $line->product_id,
            'quantity_delta' => -$line->quantity,
            'reason'         => 'sale',
            'reference_type' => Sale::class,
            'reference_id'   => $sale->id,
        ]);
    }

    return $sale;
});
```

### Why `lockForUpdate`

`motorcycle-pos-build-plan.md:122` poses exactly this question: what happens when two cashiers
sell the last item at once?

Without a lock, both transactions read "1 in stock", both pass the check, and both write a
`-1` movement. Stock lands at `-1` and the shop has sold an item it does not have.

`lockForUpdate()` takes a "for update" lock: it prevents the selected rows from being modified
*or* selected with another shared lock, so the second cashier's read blocks until the first
transaction commits or rolls back. The second then reads the true post-sale level and fails
its check correctly.

`sharedLock()` is **not** sufficient here — it permits other shared locks, so both readers
would still proceed. Use `lockForUpdate()` on any read whose value you are about to act on.

### Keep the body small

Inside a transaction, do not:

- call an external HTTP API (a provider timeout holds locks open),
- dispatch a queued job (it may run before the commit lands),
- send mail or notifications,
- do anything you cannot undo by rolling back.

Do those **after** the transaction returns, using the value it returned. The transaction should
contain database writes and the checks that guard them, nothing else.

### Deadlocks

Two transactions taking the same locks in different orders can deadlock; MySQL kills one.
`DB::transaction($callback, $attempts)` accepts a retry count for exactly this. Reduce the
risk by always locking in a consistent order — e.g. iterate cart lines sorted by `product_id`.

## What to check before shipping

- [ ] Stock is read with `lockForUpdate()` inside the transaction before being acted on.
- [ ] Every stock change writes an `inventory_movements` row with a reason and reference.
- [ ] No direct write to any stored stock-level column.
- [ ] The transaction body contains no HTTP call, queue dispatch, or mail.
- [ ] The work-order path reuses this logic rather than reimplementing it.
- [ ] A mid-transaction failure leaves no sale, no items, and no movements.
