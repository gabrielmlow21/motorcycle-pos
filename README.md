# motorcycle-pos

A production point-of-sale system for a working motorcycle shop in Malaysia. It combines retail
(parts and accessories sales with inventory tracking) and workshop operations (service and repair
work orders tied to customer vehicles), and handles real payments including cash and DuitNow QR.

Two halves in one repo:

- `/api` — Laravel 13 (PHP 8.3+) JSON API. The single source of truth for data, money, and auth.
- `/web` — React PWA (Vite + TypeScript). The only client of the API. Runs on a shop tablet.

## Setup on a new machine

Requires macOS with [Homebrew](https://brew.sh) and [nvm](https://github.com/nvm-sh/nvm).

```bash
git clone <this repo> && cd motorcycle-pos

brew bundle install        # PHP, Composer, gh, Docker Desktop
open -a Docker             # start Docker and wait for it to finish booting
nvm install && nvm use     # Node version from web/.nvmrc

make setup                 # database, dependencies, app key, migrations
```

Then run the two halves in separate terminals:

```bash
make dev-api   # http://localhost:8000
make dev-web   # http://localhost:5173
```

`make` on its own lists every available command.

### How local development is wired

The application runs **natively** — `php artisan serve` and `npm run dev` — because production
is App Service's PHP runtime and Static Web Apps, not containers. Only the database is
containerised (`compose.yaml`).

That split is deliberate. Local development runs against **MySQL 8.0, the same engine as
production**, rather than SQLite. SQLite treats `SELECT ... FOR UPDATE` as a no-op and locks the
whole database file instead of a row, so the concurrency behaviour behind stock deduction and
payments cannot be exercised on it — a race condition would pass its tests locally and fail on a
shop floor. For the same reason the test suite runs against a real `pos_test` database rather
than SQLite in memory.

## Where to look

- **DESIGN.md** — architecture, data model, and the *why* behind decisions.
- **CLAUDE.md** — day-to-day conventions and commands.
- **motorcycle-pos-build-plan.md** — the phased backend/DevOps build order (Laravel + Azure).
- **FRONTEND.md** — the phased frontend concept track, mirroring the same phases.
