# Skills

Skills load on demand: only each skill's `name` and `description` sit in context until one
triggers, at which point its `SKILL.md` loads, and its `references/*.md` load only if needed.

## Ours

- **`payments-guardian`** — money, stock, payments, and webhook rules for this POS. Encodes
  `CLAUDE.md:36-50` and `DESIGN.md` as procedure. Maintained by us; change it when CLAUDE.md
  changes.

## Vendored from Jeffallan/claude-skills

Copied from https://github.com/Jeffallan/claude-skills (MIT — see
`vendor-licenses/Jeffallan-claude-skills-LICENSE`) at the 2026-08-18 HEAD. Eleven of the
upstream 67 were selected as relevant to this stack; the rest target other languages and
frameworks.

| Skill | Used for |
|---|---|
| `laravel-specialist` | Eloquent, Sanctum, API resources, queues |
| `secure-code-guardian` | Auth and input-validation implementation |
| `security-reviewer` | Standalone security audit pass |
| `php-pro` | PHP 8.3 idiom |
| `react-expert` / `typescript-pro` | The `/web` PWA |
| `test-master` | Test coverage |
| `database-optimizer` | Indexing and query performance |
| `devops-engineer` | GitHub Actions, deploy pipeline |
| `api-designer` | API contract shape |
| `the-fool` | Pre-mortem / red-team on plans |

These were **vendored rather than installed** via the plugin marketplace so they are
version-controlled, reviewable in diffs, and modifiable where they conflict with project rules.
The tradeoff: no automatic upstream updates. To refresh one, re-copy it and re-apply the
modification below.

### Modifications from upstream

- **`laravel-specialist/references/eloquent.md`** — the "Custom Casts" `Money` example returned
  a `float` from `get()` and multiplied a float in `set()`. That violates `CLAUDE.md:37`
  (integer sen, never float), so it was replaced with an integer-only `SenCast` and marked with
  an inline warning. Do not restore the upstream form.

### Known gaps and caveats

- **Nothing upstream covers payments.** `secure-code-guardian` explicitly scopes out payment
  processing and webhooks, and no skill addresses Malaysian rails (DuitNow QR / FPX / e-wallets)
  or MyInvois. That gap is why `payments-guardian` exists.
- **`database-optimizer` leans PostgreSQL.** It ships both `mysql-tuning.md` and
  `postgresql-tuning.md`; this project is MySQL on Azure Flexible Server. Prefer the MySQL
  reference and ignore Postgres-specific advice.
- **Upstream targets Laravel 10/11 and PHP 8.1+**; this project is Laravel 13 / PHP 8.3+. Some
  patterns may be dated.
- **`CLAUDE.md` overrides all skill guidance.** Where a vendored skill disagrees with project
  conventions, CLAUDE.md wins — flag the conflict rather than following the skill.
