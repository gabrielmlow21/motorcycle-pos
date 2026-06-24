# Motorcycle Shop POS — AI-Assisted Build & Learning Plan

**For:** A React frontend developer learning backend + DevOps
**Stack:** React (frontend) · Laravel 13 (API) · Azure (hosting + DevOps)
**Workflow:** AI writes most of the code; you review every change and learn the backend/DevOps concepts as you go
**Context:** Real production system for an operating motorcycle shop in Malaysia
**v1 scope:** Sales & checkout · Parts & inventory · Service/repair work orders · Customer records

---

## 1. The core idea behind this plan

You already think in components, state, and props. The gap you're closing is everything *behind* the API call: how data is modeled, how money is handled safely, how a server is deployed, and how it stays up. Because this is a real shop handling real money, the plan is built around one rule:

> **AI can write the code, but you must understand the parts that touch money, stock counts, and authentication before they go live.** Everything else you can learn more gradually.

So each phase below has three columns of thinking: *what the AI builds*, *what you review and must understand*, and *the Azure/DevOps skill you pick up*.

---

## 2. Decisions still open (I did not assume these)

These genuinely change the build. I've given a recommendation for each so you're not blocked, but confirm them before Phase 2.

| Decision | Why it matters | My recommended default |
|---|---|---|
| **Shop annual turnover vs RM1M** | Determines whether MyInvois e-invoicing is legally required. Above RM1M → mandatory (RM1m–RM5m band enforced Jan 2027, soft launch 2026). Below RM1M → currently exempt. | **Design the invoice layer to be MyInvois-ready regardless**, but only wire up the API submission if you're above (or approaching) RM1M. Cheap to design in, expensive to retrofit. |
| **Offline resilience** | A shop can't stop selling when the internet drops. Full offline-first is complex; online-only is simpler but risky. | **Online-first with a graceful degraded mode**: cart works locally and queues the sale to sync when the connection returns. Avoid full offline-first sync for v1. |
| **Payment provider** | Malaysian customers expect DuitNow QR, FPX, and e-wallets (Touch 'n Go, GrabPay). Stripe alone won't cover DuitNow QR. | **A local aggregator** — HitPay, Billplz, Fiuu, or Curlec — that exposes DuitNow QR + FPX + e-wallets through one API and supports in-person POS. Keep **cash** as a first-class method too. |
| **Hardware** | Real POS needs receipt printing and barcode scanning. | **Thermal receipt printer (ESC/POS)** + **USB barcode scanner (keyboard-wedge)** + optional **cash drawer** triggered by the printer. Scanners are trivial (they type into a focused input); printing needs a small bridge — see Phase 5. |

If any default is wrong for you, tell me and I'll adjust the affected phases.

---

## 3. The recommended stack (and why)

**Frontend — React as a PWA.** Build with Vite + React. Make it an installable Progressive Web App so it can run full-screen on a shop tablet and survive brief network drops. Consider adding TypeScript — as someone moving toward backend work, typed contracts between your frontend and API will teach you good habits and catch bugs.

**Backend — Laravel 13 (PHP 8.3+), API-only.** Laravel generates a clean JSON API; your React app is the only client. This separation is itself a great lesson: you'll see exactly where the frontend ends and the backend begins. Auth via **Laravel Sanctum** (token-based, simple, well-documented).

**Database — Azure Database for MySQL (Flexible Server).** MySQL is the most common Laravel pairing and the gentlest to learn. "Flexible Server" is the managed option — Azure handles backups, patching, and failover so you learn database *operations* without running a server yourself.

**Azure services you'll touch (roughly in order):**
- **App Service (Linux, PHP)** — hosts the Laravel API. Your first deployment lesson.
- **Static Web Apps** — hosts the React PWA, free tier, built-in GitHub Actions deploy.
- **Azure Database for MySQL Flexible Server** — the data.
- **Blob Storage** — product images, receipt PDFs, work-order photos.
- **Key Vault** — secrets (DB password, payment API keys) kept out of code.
- **Application Insights** — logs, errors, and "why is it slow" answers.
- **Cache for Redis** *(later)* — sessions, queues, fast lookups.

**CI/CD — GitHub Actions.** Simpler and free for a solo learner versus Azure DevOps, and it deploys cleanly to both Static Web Apps and App Service.

---

## 4. Data model sketch (the shape of the shop)

A motorcycle shop is half retail, half service, so the model has to hold both. Core entities:

- **users** — staff with roles: `cashier`, `mechanic`, `manager`.
- **customers** — name, phone, email.
- **vehicles** — make, model, plate, year, optional VIN; belongs to a customer. *(This is the moto-shop differentiator — service history hangs off the vehicle.)*
- **suppliers** — for parts reordering.
- **products / parts** — SKU, barcode, name, category, cost price, sell price, stock quantity, reorder level, supplier.
- **inventory_movements** — every stock change (sale, restock, adjustment, used-in-service). Stock level is the *sum* of movements, never edited directly — this gives you an audit trail.
- **sales (orders)** — header + **sale_items** lines; links to payment, tax, discounts.
- **work_orders** — vehicle, customer, reported complaint, assigned mechanic, status (`open → in_progress → done → invoiced → paid`), with **labor_lines** and **parts_used** (which deduct from inventory).
- **payments** — amount, method (`cash`, `duitnow_qr`, `fpx`, `ewallet`, `card`), reference, links to a sale or work order.
- **invoices** — the document layer; structured so it can map to MyInvois fields later.

A sale and a work-order invoice both ultimately produce a **payment** and a **receipt/invoice** — keep that convergence in mind so you don't build two separate money paths.

---

## 5. The AI-build workflow (how "AI writes, you learn" actually works)

**Tools:**
- **Claude Code** (the agentic CLI/desktop tool) for the actual building — it can scaffold, edit across files, run migrations, and write tests. Docs: https://docs.claude.com/en/docs/claude-code/overview
- **Claude in the chat app** for planning, "explain this to me," and reviewing concepts before you accept code.

**The loop for every feature:**
1. **You write the spec** in plain language (use this document's phases as the source). Writing the spec is where you do your thinking — don't outsource that.
2. **AI builds** the migration, model, controller, validation, route, tests, and the React screen.
3. **You review the diff.** Read every changed file. For anything unfamiliar, ask: *"Explain what this controller does line by line, and what would break if it were wrong."*
4. **Run the tests** the AI wrote, then add one case yourself to prove you understand it.
5. **Commit on a feature branch**, merge when it's green.

**Non-negotiable guardrails (because real money flows through this):**
- Never let AI-written **auth, payment, or stock-deduction** code ship until *you* can explain it. These are the places a bug costs real ringgit or leaks customer data.
- All **money math in the database uses integers (cents)** or `decimal`, never floats. Confirm the AI does this.
- All **stock changes and payments happen inside database transactions** so a half-finished sale can't corrupt inventory. Ask the AI to show you the transaction boundaries.
- **Secrets never go in code or git** — they live in `.env` locally and Key Vault in production.
- Keep a short **learning log**: one line per concept the AI used that was new to you. This is how the "I want to learn" goal actually gets met instead of quietly skipped.

---

## 6. Phased roadmap

Heads-up: choosing all four capabilities for v1 is ambitious — it's effectively a full POS plus a workshop system. The phasing below ships a thin working slice first ("walking skeleton") and then adds one capability at a time, so the shop could start using it early and you learn in digestible steps.

### Phase 0 — Foundations & a deployed "hello world" *(learn the pipeline before the product)*
- **AI builds:** an empty Laravel 13 API returning `{"status":"ok"}`, an empty React PWA, both in one git repo.
- **You review & learn:** how a Laravel request flows (route → controller → response); the React build output; what a `.env` file is.
- **Azure/DevOps:** create the resource group; deploy the API to App Service and the PWA to Static Web Apps; set up GitHub Actions so a `git push` redeploys both. **This is the single most valuable early lesson — get to a live URL before writing real features.**
- **Done when:** pushing to `main` automatically updates a live site and a live API endpoint.

### Phase 1 — Auth & staff accounts *(the security backbone)*
- **AI builds:** Sanctum login/logout, users table, roles (`cashier`/`mechanic`/`manager`), a protected React shell with login.
- **You review & learn:** how tokens work, middleware/route protection, password hashing, why you never store plain passwords. **Understand this fully — it's the gate on everything else.**
- **Azure/DevOps:** move DB credentials and app keys into Key Vault; connect Azure Database for MySQL.
- **Done when:** only logged-in staff reach the app, and a manager sees things a cashier doesn't.

### Phase 2 — Parts & inventory *(your first real CRUD + the stock concept)*
- **AI builds:** products/parts CRUD, suppliers, `inventory_movements`, stock-level calculation, low-stock flags, barcode field, React screens to list/add/edit parts and scan a barcode into search.
- **You review & learn:** Eloquent relationships, migrations, validation, and why stock is a *sum of movements* (audit trail) rather than an editable number. Watch for N+1 query problems — ask the AI to point them out.
- **Azure/DevOps:** Blob Storage for product images; database backups; first look at Application Insights.
- **Done when:** staff can scan a part, see live stock, restock it, and the history is traceable.

### Phase 3 — Sales & checkout *(the heart of the POS — money math)*
- **AI builds:** a cart, line items, configurable tax (SST), discounts, the checkout flow, a `sales` + `sale_items` model, stock deduction *inside a transaction*, and a receipt.
- **You review & learn:** **database transactions and integer money math — this is the phase to slow down on.** Walk through what happens if two cashiers sell the last item at once. Understand rollback.
- **Azure/DevOps:** deployment slots (a "staging" slot so you test before customers hit it); structured logging of every sale.
- **Done when:** a complete sale deducts stock atomically, applies tax correctly, and produces a receipt — and you can explain the transaction code.

> ⚠️ Confirm the current **SST treatment and rate** for motorcycle parts/service with your accountant or LHDN — don't hardcode a number from memory. Build the tax rate as a **configurable setting**, not a constant.

### Phase 4 — Payments (DuitNow QR, FPX, e-wallets, cash) *(integrating a real provider)*
- **AI builds:** integration with your chosen aggregator (HitPay/Billplz/Fiuu/Curlec) — generate a **dynamic DuitNow QR** for the sale total, handle the **webhook** that confirms payment, reconcile it to the sale, and record cash payments with change calculation.
- **You review & learn:** webhooks and why you trust the provider's server callback over the browser; idempotency (don't double-count a payment if a webhook fires twice); never marking a sale paid from the frontend alone.
- **Azure/DevOps:** a secure public webhook endpoint; payment keys in Key Vault; alerting in Application Insights for failed payments.
- **Done when:** a customer scans a DuitNow QR, pays, and the sale flips to "paid" via the verified webhook.

### Phase 5 — Receipt printing & hardware *(the physical shop layer)*
- **AI builds:** receipt formatting and an ESC/POS printing path (a small local print bridge or browser print to the thermal printer); cash-drawer trigger; barcode-scanner-friendly focused inputs.
- **You review & learn:** why hardware usually needs a local helper rather than direct browser access; graceful fallback to PDF if the printer is offline.
- **Azure/DevOps:** nothing new — this lives at the shop, not in the cloud. Good moment to document the on-site setup.
- **Done when:** a finished sale prints a receipt and pops the drawer.

### Phase 6 — Customers & vehicles *(the CRM moto shops actually need)*
- **AI builds:** customer CRUD, vehicles linked to customers, attach a sale/work order to a customer, view a customer's purchase and service history.
- **You review & learn:** one-to-many relationships at scale, search/pagination, soft deletes (never hard-delete a customer record).
- **Azure/DevOps:** query performance and indexing as the customer table grows.
- **Done when:** scanning or searching a customer shows their bikes and full history.

### Phase 7 — Service / repair work orders *(the workshop system)*
- **AI builds:** create a work order against a vehicle, add labor lines + parts (parts deduct from inventory, reusing Phase 2/3 logic), assign a mechanic, status workflow, convert a completed work order into an invoice + payment (reusing Phase 3/4).
- **You review & learn:** how to *reuse* the sale/payment paths instead of duplicating them — a real lesson in not repeating yourself. State machines for status transitions.
- **Azure/DevOps:** background jobs/queues (e.g., SMS/WhatsApp "your bike is ready") — your intro to Laravel queues, later backed by Redis.
- **Done when:** a repair job flows from intake to paid invoice, and parts used are reflected in stock.

### Phase 8 — Reporting, hardening & compliance *(make it production-grade)*
- **AI builds:** daily sales summary, top-selling parts, low-stock report, basic dashboard; MyInvois invoice mapping if you're in scope.
- **You review & learn:** how the invoice maps to the **MyInvois** structured fields (single transactions above RM10,000 require an individual e-invoice even during the relaxation period); data retention and audit basics.
- **Azure/DevOps:** custom domain + HTTPS; automated DB backup verification (restore-test once!); uptime/error alerts; a documented restore-from-backup runbook.
- **Done when:** the owner gets daily numbers, and you've *proven* you can restore the database from a backup.

---

## 7. Malaysia production checklist

- **Payments:** local aggregator live with DuitNow QR + FPX + at least Touch 'n Go and GrabPay; cash handled with change; every payment confirmed server-side via webhook.
- **e-invoicing (MyInvois):** confirm in-scope status by turnover. If in scope, the invoice layer submits to LHDN's MyInvois (API integration uses a digital certificate and a defined field set). If exempt, keep the layer MyInvois-shaped so a future switch is a small job, not a rebuild.
- **Tax (SST):** configurable rate, confirmed with a professional — never hardcoded.
- **Security:** all secrets in Key Vault; HTTPS only; roles enforced server-side (not just hidden in the UI); customer data not over-collected.
- **Resilience:** automated daily DB backups *and a tested restore*; degraded-mode selling when offline; payment idempotency.
- **Monitoring:** Application Insights catching errors and failed payments with alerts.

---

## 8. Concepts you'll have learned by the end

**Backend / Laravel:** routing, controllers, migrations, Eloquent ORM and relationships, validation, middleware, token auth (Sanctum), **database transactions**, queues/background jobs, API design, N+1 query avoidance, webhooks, idempotency.

**DevOps / Azure:** resource groups, App Service deployment, managed databases, environment config and secrets (Key Vault), CI/CD with GitHub Actions, deployment slots/staging, Blob Storage, monitoring with Application Insights, backups and restore drills, custom domains + TLS.

---

## 9. Risks & honest gotchas

- **Scope is large for a "v1."** Treat Phases 0–5 as your true first release for the shop floor; 6–8 can follow once it's earning its keep.
- **Money bugs are the dangerous ones.** Slow down on Phases 3 and 4. If you only deeply understand two areas of AI-written code, make them *auth* and *payments/stock*.
- **AI confidently writes plausible-but-wrong code.** The review step isn't optional ceremony — it's where the learning and the safety both live.
- **Compliance shifts.** The MyInvois thresholds and timelines have already changed more than once; re-check LHDN before you build the e-invoice integration.

---

## 10. Sources & further reading

- Laravel 13 release notes — https://laravel.com/docs/13.x/releases
- Laravel version support timeline — https://endoflife.date/laravel
- LHDN MyInvois e-invoicing (official) — https://www.hasil.gov.my/en/e-invoice/
- DuitNow QR developer docs (PayNet) — https://docs.developer.paynet.my/docs/duitNow-QR/introduction/overview
- Claude Code (AI build tool) — https://docs.claude.com/en/docs/claude-code/overview
- Azure App Service for PHP/Laravel and Static Web Apps — https://learn.microsoft.com/azure/

---

*Next step: confirm the four open decisions in Section 2, then we start at Phase 0 — getting an empty app live on Azure before writing a single real feature.*
