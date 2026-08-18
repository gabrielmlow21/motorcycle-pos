---
name: payments-guardian
description: >
  Use when writing or reviewing any code that touches money, stock levels, payments, or
  payment webhooks in this POS — checkout, cart totals, SST/tax, sales, work-order invoicing,
  inventory_movements, stock deduction, cash handling and change, DuitNow QR / FPX / e-wallet
  integration, and provider webhook handlers. Enforces the money rules in CLAUDE.md: integer
  sen, atomic transactions, stock as the sum of movements, idempotent webhooks, and never
  flipping paid status from the frontend.
---

# Payments Guardian

This is a real production POS for a motorcycle shop handling real money. A bug here costs
real ringgit or corrupts stock counts. Correctness beats delivery speed, every time.

This skill encodes rules that already exist in `CLAUDE.md` and `DESIGN.md`. It does not
invent policy. Where a rule is cited, the citation is the authority — if this skill and
CLAUDE.md ever disagree, **CLAUDE.md wins** and this file needs fixing.

## Non-negotiables

Check every one of these before calling money code done. Each cites its source.

1. **Integer sen only.** Money is stored and calculated as integers. Never floats, never
   `money_format`, never a `decimal` cast that round-trips through a float. All money math
   happens server-side. — `CLAUDE.md:37`
2. **Atomic stock + payment.** A sale deducts stock and records payment inside one database
   transaction, or does neither. No half-finished sales. — `CLAUDE.md:38-39`
3. **Stock is the sum of `inventory_movements`.** Never a directly-edited column. Every
   change — sale, restock, adjustment, used-in-service — leaves an audit row. — `CLAUDE.md:40-41`
4. **Authorization is server-side.** Middleware and policies. A hidden React button is UX,
   not security. — `CLAUDE.md:42-43`
5. **Never set `paid` from the frontend.** Payment status flips only on a verified provider
   webhook, or on recorded cash with change calculated server-side. — `CLAUDE.md:44-45`
6. **Webhooks are idempotent.** The same webhook firing twice must not double-count. — `CLAUDE.md:46`
7. **No hard deletes** of customers, sales, invoices, or work orders. Soft deletes only. — `CLAUDE.md:49`
8. **SST rate is configurable.** Never a hardcoded constant. — `CLAUDE.md:50`
9. **Secrets never in code or git.** `.env` locally, App Service config / Key Vault in
   production. — `CLAUDE.md:47-48`

## Procedure

Work in this order. The order matters: the failing test comes before the implementation so
you prove the guard works rather than assuming it.

1. **Identify the money path.** Is this a retail sale, a work order, or both? They converge
   on one payment + invoice path — see `references/transactions-and-stock.md`. If your change
   seems to need a *second* money path, stop and ask.
2. **Model the money.** Every amount an integer in sen. Name columns so the unit is
   unmistakable (`total_sen`, not `total`). See `references/money-and-tax.md`.
3. **Draw the transaction boundary.** Decide exactly what must succeed or fail together, and
   what locks are needed, before writing the body. See `references/transactions-and-stock.md`.
4. **Write the failing test first.** At minimum the rollback case and the concurrency case
   from `references/test-checklist.md`. Watch them fail.
5. **Implement.** Keep the transaction body small — no HTTP calls, no queue dispatches, no
   mail inside it.
6. **Verify against the checklist.** Run `php artisan test` in `/api`. Walk the
   non-negotiables above one at a time.
7. **Explain it plainly.** See below — this is part of the deliverable.

## Stop and ask — hard stops

These are **not** "proceed with a placeholder and flag it." Halt and ask the human. A guessed
value that survives review costs real money, and `CLAUDE.md:60` says the open decisions must
not be assumed.

Stop when:

- **An SST rate is needed and is not in config.** Do not invent a number, not even a
  plausible one, and not even behind a TODO. Ask. — `CLAUDE.md:50`
- **Any of the four open decisions in `DESIGN.md:8-20` would be settled by your code** —
  MyInvois scope, offline resilience, payment provider, or hardware. Writing code that assumes
  one of these silently decides it.
- **The change appears to need a second money path** that duplicates sale → payment → invoice.
  — `DESIGN.md:69-70`
- **A test would need weakening to pass.** If a money test is inconvenient, the code is
  suspect, not the test.

When you stop, state what you need, why it cannot be defaulted, and what you will do once
answered. Then wait.

## Explain it plainly

`CLAUDE.md:52-54` requires the human to understand auth, payment, and stock-deduction code
before it ships. So for any change in those areas, deliver a plain-language explanation
alongside the diff:

- Where the transaction starts and ends, and what is inside it.
- What happens if it fails halfway — name the rows that do *not* get written.
- What two cashiers hitting it simultaneously will experience.

If you cannot explain the failure mode in plain language, the code is not ready to ship.
This is a deliverable, not an optional extra.

## Reference files

Read these when the task touches them — they hold the detail, this file holds the procedure.

- `references/money-and-tax.md` — integer sen, the rounding rule, configurable SST.
- `references/transactions-and-stock.md` — transaction boundaries, `lockForUpdate`,
  movements-as-sum, the one-money-path rule.
- `references/webhooks-and-idempotency.md` — signature verification, replay safety, the cash path.
- `references/test-checklist.md` — the tests that must exist before merge.
