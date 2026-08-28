# motorcycle-pos

A production point-of-sale system for a working motorcycle shop in Malaysia. It combines retail
(parts and accessories sales with inventory tracking) and workshop operations (service and repair
work orders tied to customer vehicles), and handles real payments including cash and DuitNow QR.

Two halves in one repo:

- `/api` — Laravel 13 (PHP 8.3+) JSON API. The single source of truth for data, money, and auth.
- `/web` — React PWA (Vite + TypeScript). The only client of the API. Runs on a shop tablet.

## Where to look

- **DESIGN.md** — architecture, data model, and the *why* behind decisions.
- **CLAUDE.md** — day-to-day conventions and commands.
- **motorcycle-pos-build-plan.md** — the phased backend/DevOps build order (Laravel + Azure).
- **FRONTEND.md** — the phased frontend concept track, mirroring the same phases.
