# CLAUDE.md

Project context for Claude Code. This file is loaded automatically at the start of each
session — keep it short, accurate, and current. Day-to-day rules live here; the *why*
behind the architecture lives in DESIGN.md.

## What this is
A point-of-sale (POS) system for a motorcycle shop in Malaysia. This is a **real production
system that handles real money** — correctness of financial data and auth matters more than
speed of delivery. Two halves in one repo (monorepo-lite):

- `/api` — Laravel 13 (PHP 8.3+) JSON API. The single source of truth for data, money, and auth.
- `/web` — React PWA (Vite + TypeScript). The only client of the API. Runs on a shop tablet.

## Stack
- Backend: Laravel 13, PHP 8.3+, MySQL (Azure Database for MySQL Flexible Server), Sanctum auth.
- Frontend: React + Vite, installable PWA, TypeScript.
- Hosting: API on Azure App Service (Linux/PHP); web on Azure Static Web Apps.
- CI/CD: GitHub Actions, path-filtered so a frontend change never redeploys the backend.

## Commands
Backend (run inside `/api`):
- `composer install` — install deps
- `php artisan serve` — run locally
- `php artisan migrate` — run migrations (use `--force` only in CI/prod, deliberately)
- `php artisan test` — run tests
- `./vendor/bin/pint` — format/lint

Frontend (run inside `/web`):
- `npm install` — install deps
- `npm run dev` — run locally
- `npm run build` — production build (outputs to `dist/`)
- `npm run test` — run tests
- `npm run lint` — lint

## Conventions — follow these strictly
- **Money is stored and calculated as integers (sen), never floats.** All money math server-side.
- **Stock changes and payments happen inside database transactions** — a sale deducts stock
  and records payment atomically, or not at all. Never leave a half-finished sale.
- **Stock level = the sum of `inventory_movements`**, never a directly-edited column. Every
  change (sale, restock, adjustment, used-in-service) leaves an audit row.
- **Authorization is enforced server-side** in middleware/policies. Hiding a button in React
  is UX, not security.
- **Never set a sale or work order to `paid` from the frontend.** Payment status flips only on
  a verified provider webhook, or on recorded cash with change calculated server-side.
- **Payment webhooks must be idempotent** — the same webhook firing twice must not double-count.
- **Secrets never live in code or git.** Local: `.env` (gitignored). Production: App Service
  configuration / Key Vault.
- **No hard deletes** of customers, sales, invoices, or work orders — use soft deletes.
- **SST/tax rate is a configurable setting**, never a hardcoded constant.

## Guardrails for AI-written code
- The human reviews every diff. For **auth, payment, and stock-deduction** code, explain it
  plainly and keep tests — these areas must be understood by the human before they ship.
- Write or update tests for every new endpoint. Prefer small, reviewable diffs on feature branches.
- When introducing an unfamiliar pattern, leave a one-line comment saying what it does and why.

## Where to look
- Architecture, data model, and the rationale behind decisions → **DESIGN.md**.
- The decisions at the top of DESIGN.md are confirmed (2026-08-28) — build against them.
