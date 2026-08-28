# FRONTEND.md — A frontend learning track

**For:** a frontend developer moving from junior to mid-level/fullstack
**Companion to:** `motorcycle-pos-build-plan.md`, which mirrors these same phase numbers but is
written for the backend/DevOps side. Read that doc for what each phase's API and data model look
like; this doc is what to build and learn on the React side of the same phase.

---

## The framing idea

You already think in components, state, and props. The jump from junior to mid is not "more
libraries" — it's **owning the boundary**: knowing, for every piece of data on screen, whether it
is *yours* (client state — a form field, a modal being open), the *server's* (a product's stock
count, a sale's status), or the *URL's* (a filter, a page number, a selected customer). Almost
every bug and every unnecessary `useEffect` in a junior codebase comes from blurring those three.
Phase 2 below is where that distinction becomes concrete and unavoidable — treat it as the
highest-leverage phase in this whole list.

Each phase names what you build, the concept it teaches, and why the naive version breaks on a
real POS.

---

### Phase 0 — Foundations *(already done in this repo)*

What's in place: TypeScript `strict` mode (`web/tsconfig.app.json`), a Vitest + Testing Library
smoke test (`web/src/App.test.tsx`), an installable PWA manifest and service worker
(`vite-plugin-pwa` in `web/vite.config.ts`), and type-aware ESLint
(`tseslint.configs.recommendedTypeChecked`).

Concepts to understand, not just have configured:
- **`strictNullChecks`** — what it actually catches: a part with no `barcode`, a customer with no
  `email`, a query result that hasn't loaded yet. Without it, all three type-check as present and
  fail at runtime instead.
- **Vite env modes** — `import.meta.env.VITE_API_URL`, `.env.development` vs `.env.production`,
  and why only `VITE_`-prefixed variables reach the client bundle (anything else would leak
  server secrets into a public bundle).
- **The service worker lifecycle** — install → waiting → activate, and the "stale app" trap: a
  cashier leaves the tablet open for a week and never gets your bug fix until the SW updates.
  `registerType: 'autoUpdate'` sidesteps it here; know what you traded away (silent updates mid-shift).
- **Testing behavior, not implementation** — the smoke test asserts what a user sees (a heading),
  not an internal prop or a state variable name.

### Phase 1 — Auth & staff accounts

Builds against Sanctum login/logout (see build plan Phase 1).

- **Route structure**: install `react-router`, add a public `/login` route and a protected layout
  route wrapping everything else. A protected-route component checks auth state and redirects —
  this is UX affordance only; the real gate is Laravel middleware (`CLAUDE.md`: "hiding a button
  in React is UX, not security").
- **Auth state**: a context + `useReducer` holding `{ user, status }` (`idle | loading |
  authenticated | anonymous`) — not a bare boolean, because "checking on load" is a real state a
  boolean can't represent without an extra flag.
- **Token storage tradeoff**: `localStorage` is simplest but readable by any injected script (XSS);
  an in-memory token with a silent-refresh endpoint is safer but means every hard refresh
  re-authenticates. Pick one, write down why.
- **A typed fetch wrapper**: attaches the token, throws a typed error on non-2xx, and on 401 clears
  auth state and redirects to login in one place instead of every call site.
- **`AbortController`** on requests tied to a component's lifetime, so a fast route change doesn't
  resolve a stale request into a mounted-elsewhere component.
- **Route-level `lazy()` + `Suspense`**: split the login screen from the main app bundle — a
  cashier's tablet shouldn't download the reporting dashboard to see a login form.

### Phase 2 — Parts & inventory *(the pivotal phase — see framing note above)*

Builds against products/parts CRUD and `inventory_movements` (build plan Phase 2).

- **Server state vs client state**: install TanStack Query. A parts list, a single product, stock
  levels — none of that is "your" state; it's a cached, revalidatable copy of the server's state.
  Replacing hand-rolled `useEffect` + `useState` + loading-flag fetching with `useQuery` removes an
  entire class of race-condition and stale-closure bugs, and you get caching, retries, and
  refetch-on-window-focus for free.
- **Query keys and invalidation**: `['products', { search, page }]` as a key; after a restock
  mutation succeeds, `invalidateQueries(['products'])` so the list reflects the new stock without a
  manual refetch call anywhere.
- **`staleTime`** and why a barcode scan result should be near-instant from cache while a stock
  count should revalidate aggressively.
- **Paginated or infinite lists** for a growing parts catalog — `useInfiniteQuery` or
  cursor-based `useQuery` per page.
- **Debounced/deferred search**: `useDeferredValue` (or a manual debounce) so typing into "search
  parts" doesn't fire a request per keystroke, and the UI stays responsive while a slow search
  resolves.
- **List virtualization** once the parts table is realistically sized (hundreds of SKUs) —
  rendering only visible rows.
- **React Hook Form + Zod**: define the "add part" schema once in Zod, derive the TS type from it
  (`z.infer<typeof schema>`), and reuse the same schema for client-side validation. Map Laravel's
  422 validation error shape onto form fields instead of a generic toast.
- **Image upload with progress**: `XMLHttpRequest` or `fetch` with a `ReadableStream` for upload
  progress, since native `fetch` doesn't expose upload progress by itself.
- **Barcode scanner input**: a keyboard-wedge scanner "types" the barcode very fast followed by
  Enter. A naive `onChange` per keystroke works, but the real problem is focus — the input must
  stay focused during a checkout flow, and a stray click elsewhere silently breaks scanning until
  someone notices. Build focus-management around this deliberately, don't discover it in the shop.

### Phase 3 — Sales & checkout *(money math on the client)*

Builds against the `sales`/`sale_items` model and atomic stock deduction (build plan Phase 3).

- **Cart as client state**: nobody else needs to know about an in-progress cart, so `useReducer`
  (or Zustand once more than one component needs it) is the right tool — this is not server state.
- **Money display, not money math**: sen integers arrive from the server; format with
  `Intl.NumberFormat('ms-MY', { style: 'currency', currency: 'MYR' })` for display only. The
  client-computed running total is a **display estimate** — per `CLAUDE.md`, the server total
  (computed atomically, with tax and discounts) is the only one that's authoritative. Never let the
  client total be what gets charged.
- **Idempotency key**: generate a UUID client-side when the cart is first opened, send it with the
  checkout POST, and reuse the same key on retry — this is what lets the server safely dedupe a
  double-submit or a retried request after a flaky connection.
- **Mutation lifecycle**: `useMutation`'s `pending`/`error`/`success` states drive a disabled
  checkout button during submission — the actual defense against double-charging a customer who
  double-taps "Pay."
- **Error boundaries per route**: a rendering bug in the receipt view shouldn't take down the whole
  POS mid-shift.
- **Keyboard-first UX**: a cashier's hands are often on a keyboard or scanner, not a mouse. Hotkeys
  for common actions, a real focus trap in the payment dialog, `aria-live="polite"` on the running
  total so a screen reader announces it as items are added.
- **Print stylesheet**: a `@media print` stylesheet for the receipt, separate from the screen
  layout.

### Phase 4 — Payments *(a state machine, not a boolean)*

Builds against the webhook-confirmed payment flow (build plan Phase 4).

- **Model the screen as a state machine**: `idle → qr_shown → polling → paid | expired | failed`,
  as a discriminated union reducer (`{ status: 'polling'; expiresAt: number } | { status: 'paid';
  reference: string } | ...`). This is the cleanest place in the whole app to feel *why*
  `useState(isPaid)`, `useState(isExpired)`, `useState(isPolling)` as separate booleans stops
  scaling — they can represent impossible combinations (paid *and* expired) that the reducer
  can't.
- **Polling with backoff**, and correct `useEffect` cleanup so a component unmount (cashier
  navigates away) stops the poll instead of leaking an interval.
- **The webhook race**: the payment can confirm server-side in the exact instant the client's local
  countdown hits zero. Decide, and encode in the reducer, which wins — don't let it be undefined
  behavior.
- Never render "Paid" from client-derived state alone — this screen's whole point is to *reflect*
  a payment status the server owns, per `CLAUDE.md`'s payment rules.

### Phase 5 — Receipt printing & hardware

Builds against the print-bridge integration (build plan Phase 5).

- **Feature detection + graceful degradation**: try the local print bridge; on failure, offer a PDF
  download instead of a dead-end error.
- **Why the browser can't usually talk to the printer directly**: understand Web Serial/WebUSB
  well enough to know why a small local helper process is the pragmatic choice here, not a gap in
  your React knowledge.

### Phase 6 — Customers & vehicles

Builds against customer/vehicle CRUD and search (build plan Phase 6).

- **URL as state**: filters, sort order, and page number belong in `useSearchParams`, not
  component state — a shared link or a page reload should reproduce the same filtered view. This
  is the third leg of the state-ownership triangle from the framing note.
- **Nested routes**: `/customers/:id` → `/customers/:id/vehicles/:vehicleId` → history, each level
  fetching only what it owns.
- **A real data table** (TanStack Table) for sortable, paginated customer/vehicle lists.
- **Skeletons and empty states** that are actually designed, not an afterthought spinner.

### Phase 7 — Service / repair work orders

Builds against the work-order status machine (build plan Phase 7).

- **Dynamic field arrays**: labor lines and parts-used rows added/removed at runtime (React Hook
  Form's `useFieldArray`), with the total *derived* from the rows on render, never stored as its
  own field that can drift out of sync.
- **Optimistic updates with rollback**: flipping a work order to `in_progress` can update the UI
  immediately and roll back if the server rejects it — TanStack Query's optimistic-update pattern.
- **The status machine again**, now rendered as a board (open → in_progress → done → invoiced →
  paid) — the same discriminated-union thinking from Phase 4, applied to a longer-lived state.

### Phase 8 — Reporting & hardening

Builds against the reporting endpoints (build plan Phase 8).

- **Charts** for daily sales / top parts / low stock.
- **Profiling for real**: React DevTools Profiler to find an actual re-render problem before
  reaching for `memo`/`useMemo` — using them without a measured problem just adds indirection.
- **Bundle analysis and route splitting**: confirm the reporting dashboard isn't shipped to the
  checkout screen's bundle.
- **Web Vitals and Lighthouse, run on the actual shop tablet**, not just a dev laptop — that's the
  real device class this app has to be fast on.
- **Playwright E2E** covering the checkout path end-to-end, the one flow that must never silently
  break.
- **Source maps + error tracking** in production, so a bug report from the shop floor comes with a
  stack trace instead of a screenshot.

---

## Cross-cutting: the offline cart

Called out separately because it's the hardest, highest-value feature here, and `DESIGN.md`'s open
decision #2 already scopes it: **online-first with a degraded local cart that queues the sale and
syncs on reconnect — not full offline-first for v1.** Don't start this before Phase 3 ships; it
builds directly on the cart and checkout mutation from that phase.

Teaches: IndexedDB for a durable local queue (survives a tab close, unlike memory state), the
Background Sync API for triggering a sync when connectivity returns, why `navigator.onLine` is
unreliable (a device can report "online" while actually having no route to your API) and needs to
be paired with an actual health check, draining the queue in order on reconnect, and duplicate
prevention when a queued sale is replayed — this is exactly what the idempotency key from Phase 3
is for.

## Cross-cutting: fullstack skills

The single item with the highest transition value toward fullstack work: generate TypeScript types
from the Laravel API's OpenAPI spec (`openapi-typescript`) so the request/response contract is
checked by the compiler instead of by hope and manual interface-writing. A field renamed on the
Laravel side becomes a build failure in `/web`, not a runtime surprise.

Also worth building, and genuinely mid-level concerns rather than polish: a small design-token
layer (spacing/color/type scale as CSS custom properties or a Tailwind theme, not scattered magic
numbers), dark mode as a consequence of that token layer, and Bahasa Malaysia/English i18n — real
for this shop's staff, not a demo feature.

---

## Closing note

This is a multi-year list, not a sprint backlog — treat the phase order as the recommendation, and
don't feel behind for not knowing all of it yet. If only one section here gets deep attention,
make it Phase 2's server-state/client-state split: once that boundary is instinctive, most of the
rest of this list is a variation on it.
