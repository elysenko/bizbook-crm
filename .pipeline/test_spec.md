# Test Specification

> **WARNING:** `.pipeline/surface.json` was not present. The API surface below was
> derived from the "Surface contract" section of `.pipeline/tasks.md` and the approved
> spec. If a machine-readable `surface.json` is produced later, reconcile this file
> against it (in particular the exact request/response field names).

Conventions used below:
- All prices are integer **cents** (`price_cents`, `total_cents`). UI formats as currency.
- `date` is an ISO date `YYYY-MM-DD`; `start_time` is `HH:MM` (24h).
- Auth model is `full_auth`: the **first** signup becomes ADMIN, later signups are USER.
- Authenticated requests send `Authorization: Bearer <jwt>`.
- "Relative dates" (today/tomorrow/yesterday) are computed from the server clock at test time; tests must derive them dynamically rather than hard-coding.

## Coverage summary
- Total cases: 78
- API endpoints covered: 20 / 20 (derived from tasks.md; surface.json absent)
- User journeys covered: 12

## API tests

### `POST /api/auth/signup`
- **Happy path (first user → ADMIN)**: on an empty DB (ignoring seeded accounts, or a fresh test DB), `{email, password, name}` → `201/200` with a token or user body; `GET /api/auth/me` for that token returns `role == "ADMIN"`.
- **Happy path (subsequent user → USER)**: a second signup with a new email → success; `me` shows `role == "USER"`.
- **Validation failures**:
  - Missing `email` or `password` → `422` (Pydantic) or `400`.
  - Malformed email string → `422`/`400`.
  - Duplicate email (already registered) → `409`/`400`, no second user created.
- **Auth failures**: none (public endpoint).
- **Idempotency / edge cases**: password is never returned in any response body; stored value is a bcrypt hash, not plaintext.

### `POST /api/auth/login`
- **Happy path**: correct `{email, password}` for a seeded/created user → `200` with a JWT access token; token decodes to the correct user/role.
- **Validation failures**: missing `email` or `password` → `422`/`400`.
- **Auth failures**:
  - Wrong password → `401`.
  - Unknown email → `401` (must not distinguish "no such user" from "bad password").
- **Idempotency / edge cases**: two logins issue usable tokens; token authorizes a subsequent `GET /api/auth/me`.

### `GET /api/auth/me`
- **Happy path**: valid Bearer token → `200` with `{id, email, name, role}` for the token owner.
- **Auth failures**:
  - No `Authorization` header → `401`.
  - Malformed/garbage token → `401`.
  - Expired/invalid-signature token → `401`.

### `GET /api/clients?q=`
- **Happy path**: authed request with no `q` → `200` array of clients (seeded ≥5).
- **Happy path (search)**: `?q=<substring of a seeded client name/phone>` → only matching clients returned; non-matching `q` → empty array `[]` (not error).
- **Auth failures**: no token → `401`.

### `POST /api/clients`
- **Happy path**: authed `{name, phone, email?, notes?}` with name+phone → `201`/`200`, body echoes created client with an `id` and `created_at`; appears in a subsequent `GET /api/clients`.
- **Validation failures**:
  - Missing `name` → `422`/`400`.
  - Missing `phone` → `422`/`400`.
- **Auth failures**: no token → `401`.

### `GET /api/clients/:id`
- **Happy path**: existing id → `200` with full client record.
- **Validation / edge cases**: non-existent id → `404`.
- **Auth failures**: no token → `401`.

### `PUT /api/clients/:id`
- **Happy path**: authed update of `name`/`phone`/`email`/`notes` → `200`; subsequent `GET` reflects new values.
- **Validation failures**: clearing a required field (`name`/`phone`) → `422`/`400`.
- **Edge cases**: non-existent id → `404`.
- **Auth failures**: no token → `401`.

### `GET /api/clients/:id/appointments`
- **Happy path**: client with history → `200` array containing past + upcoming appointments, ordered (by date then start_time); each row includes linked service info.
- **Edge cases**: client with no appointments → `200` empty array; non-existent client id → `404`.
- **Auth failures**: no token → `401`.

### `GET /api/services`
- **Happy path (any authed role)**: ADMIN or USER token → `200` array of services (seeded 4); each has `name`, `duration_minutes`, `price_cents` (integer).
- **Auth failures**: no token → `401`.

### `POST /api/services`
- **Happy path (admin)**: ADMIN token, `{name, duration_minutes>0, price_cents>=0}` → `201`/`200`; appears in `GET /api/services`.
- **Validation failures**: `duration_minutes <= 0` → `422`/`400`; `price_cents < 0` → `422`/`400`; missing `name` → `422`/`400`.
- **Auth failures**: USER token → `403`; no token → `401`.

### `PUT /api/services/:id`
- **Happy path (admin)**: ADMIN updates price/duration/name → `200`; `GET` reflects change.
- **Validation failures**: `duration_minutes <= 0` or `price_cents < 0` → `422`/`400`.
- **Auth failures**: USER token → `403`; no token → `401`. Non-existent id → `404`.

### `GET /api/appointments?date=YYYY-MM-DD`
- **Happy path**: authed, `?date=<today>` → `200` array of that day's appointments, **time-ordered**, each joined with client (incl. name/phone) and service (incl. price).
- **Validation failures**: malformed `date` (e.g. `2026-13-40` or `not-a-date`) → `422`/`400`. Missing `date` → either defaults to today (documented) or `422`; assert whichever the implementation chooses is consistent.
- **Edge cases**: date with no appointments → `200` empty array.
- **Auth failures**: no token → `401`.

### `POST /api/appointments`
- **Happy path**: authed `{client_id, service_id, date, start_time}` → `201`/`200` with status `scheduled`; appears in `GET /api/appointments?date=`.
- **Idempotency / double-booking**: booking a second appointment on the **same `(date, start_time)`** while an existing non-cancelled appointment occupies it → `409` with a human-readable message in the body.
  - After **cancelling** the occupying appointment, the same slot becomes bookable again (→ success).
- **Validation failures**: missing `client_id`/`service_id`/`date`/`start_time` → `422`/`400`; non-existent `client_id` or `service_id` → `400`/`404`; malformed `date`/`start_time` → `422`/`400`.
- **Auth failures**: no token → `401`.

### `PATCH /api/appointments/:id/status`
- **Happy path**: authed transition to each of `scheduled | completed | cancelled | no-show` → `200`; `GET` reflects new status.
- **Validation failures**: invalid status value (e.g. `done`) → `422`/`400`.
- **Edge cases**: non-existent appointment id → `404`. Marking an appointment `cancelled` frees its slot for re-booking (cross-check with `POST /api/appointments`).
- **Auth failures**: no token → `401`.

### `GET /api/dashboard/today`
- **Happy path**: authed → `200` with today's appointments (time-ordered, each including client phone) **and** a count of tomorrow's appointments.
- **Correctness**: today's list contains only appointments whose `date == today`; tomorrow count equals number of appointments whose `date == tomorrow`.
- **Auth failures**: no token → `401`.

### `GET /api/revenue`
- **Happy path (admin)**: ADMIN token → `200` array of `{month: "YYYY-MM", total_cents}`.
- **Correctness (grouping math)**: `total_cents` for each month equals the **sum of linked service `price_cents`** over appointments with status `completed` whose `date` falls in that month. Non-completed (scheduled/cancelled/no-show) appointments are excluded. Verify against a known seeded/constructed dataset.
- **Auth failures**: USER token → `403`; no token → `401`.

### `GET /api/admin/settings`
- **Happy path (admin)**: ADMIN token → `200` list of service config keys (e.g. postgresql, minio) with **masked** values and a configured/unconfigured status flag per key.
- **Correctness**: secret values are masked (never returned in clear text).
- **Auth failures**: USER token → `403`; no token → `401`.

### `PATCH /api/admin/settings`
- **Happy path (admin)**: ADMIN token upserts one or more `{key, value}` pairs → `200`; a subsequent `GET /api/admin/settings` shows those keys as configured (value still masked).
- **Validation failures**: unknown/empty key or malformed body → `422`/`400`.
- **Auth failures**: USER token → `403`; no token → `401`.

### `GET /api/health`
- **Happy path (public)**: no auth → `200` (e.g. `{status: "ok"}`).

### `GET /api/health/deep`
- **Happy path (public)**: no auth → `200` after a successful DB ping.
- **Edge case**: if the DB is unreachable the endpoint returns a non-200 (e.g. `503`); happy-path assertion is `200` under normal test conditions.

## UI / journey tests

### Journey: First-signup becomes admin
- **Steps**: navigate to `/signup` on a fresh instance → fill email/password/name → submit.
- **Expected outcomes**: redirected into the authenticated app (`/today`); "BizBook" header visible; role-aware nav shows admin-only entries (Revenue, Admin Settings).
- **Negative path**: submitting with an already-registered email shows an inline error and no navigation.

### Journey: Login / logout
- **Steps**: at `/login`, enter valid seeded ADMIN credentials → submit.
- **Expected outcomes**: land on `/today`; JWT persisted; nav reflects admin role. Logging out returns to `/login` and protected routes redirect back to `/login`.
- **Negative path**: wrong password shows an inline auth error; stays on `/login`.

### Journey: Auth guard + 401 handling
- **Steps**: while unauthenticated, directly open `/today` (or any guarded route).
- **Expected outcomes**: redirected to `/login`. With an expired/invalid token, any API 401 triggers redirect to `/login`.
- **Negative path**: USER opening `/revenue` or `/admin/settings` directly is blocked by `RequireAdmin` (redirect or "not authorized").

### Journey: Today dashboard
- **Steps**: authed user opens `/today`.
- **Expected outcomes**: today's appointments listed in time order, each showing client phone; a "tomorrow" count is displayed.
- **Negative path**: empty day shows an empty-state message; API error shows an error state (not a blank crash); loading state renders before data.

### Journey: Client list, search, and create
- **Steps**: open `/clients`; type into search (updates `?q=`); open create modal (`?modal=new-client`); fill name+phone; submit.
- **Expected outcomes**: list filters by `?q=`; new client appears after creation and modal closes; `?q=` and `?modal=new-client` are deep-linkable (reload restores filtered list / open modal).
- **Negative path**: submitting the new-client form without name or phone shows inline validation and does not close the modal.

### Journey: Client detail + history (deep link)
- **Steps**: from `/clients`, click a client → `/clients/:id`; then reload the page directly at `/clients/:id`.
- **Expected outcomes**: client info plus ordered appointment history (past + upcoming) render; page restores fully on direct reload (deep-linkable).
- **Negative path**: unknown id shows a not-found state.

### Journey: Services catalog — admin controls
- **Steps**: ADMIN opens `/services`; opens `?modal=new-service`; creates a service with valid duration/price; edits an existing service.
- **Expected outcomes**: prices display formatted from cents (e.g. `$45.00` from `4500`); new/edited service appears; modal state is deep-linkable via `?modal=new-service`.
- **Negative path**: invalid duration (≤0) or negative price surfaces inline validation.

### Journey: Services catalog — USER read-only
- **Steps**: USER opens `/services`.
- **Expected outcomes**: catalog visible with formatted prices; **no** create/edit controls rendered; navigating to `?modal=new-service` does not allow a successful write (guarded / hidden).

### Journey: Book an appointment (day view + double-booking)
- **Steps**: open `/appointments?date=<today>`; open `?modal=new-appointment`; pick client, service, start_time; submit. Then attempt to book the **same** start_time again.
- **Expected outcomes**: first booking appears in the day list (time-ordered) with a `scheduled` StatusBadge; changing `?date=` loads a different day and is deep-linkable (reload restores the day). Second booking on the taken slot surfaces the server's **409 double-booking message inline** in the form.
- **Negative path**: submitting with a missing required field shows inline validation; server errors are surfaced, not swallowed.

### Journey: Appointment status transitions
- **Steps**: from the day view, change an appointment's status via its controls to `completed`, then to `cancelled`.
- **Expected outcomes**: StatusBadge updates to reflect each status; cancelling frees the slot (re-booking the same slot now succeeds).
- **Negative path**: a failed status update surfaces an error and leaves the prior status intact.

### Journey: Revenue (admin only)
- **Steps**: ADMIN opens `/revenue`.
- **Expected outcomes**: a monthly table of `month` + total formatted from cents; totals match completed-appointment sums. After booking + marking an appointment `completed`, the corresponding month total increases by that service's price.
- **Negative path**: USER has **no** Revenue nav entry and receives 403 / redirect when hitting `/revenue` directly.

### Journey: Admin settings
- **Steps**: ADMIN opens `/admin/settings`; views service (postgresql, minio) configured/unconfigured badges; submits a credential value for one service.
- **Expected outcomes**: value is saved and shown as configured with a masked value on reload; a banner appears when placeholder services need credentials.
- **Negative path**: USER cannot see the Admin Settings nav entry and is blocked from `/admin/settings`.

## Data integrity tests
- After `POST /api/clients`, exactly one new `Client` row exists with the submitted fields and a populated `created_at`.
- Passwords are stored only as bcrypt hashes; no plaintext password is ever persisted or returned.
- At most one **non-cancelled** `Appointment` can exist per `(date, start_time)` — enforced by the unique partial index and the code-level check (concurrent duplicate inserts must not both succeed).
- Cancelling (status → `cancelled`) an appointment releases its `(date, start_time)` slot so a new non-cancelled appointment can occupy it.
- `Service.price_cents` and `total_cents` are always integers (no floating-point drift); revenue sums equal exact integer addition of contributing `price_cents`.
- `Appointment.client_id` / `service_id` reference existing rows; creation with a dangling FK is rejected.
- Revenue aggregation counts only `status == completed` appointments, grouped by `YYYY-MM` of `Appointment.date`.
- Seed is idempotent: running startup seed twice does not duplicate demo users/clients/services/appointments, and always yields a demo ADMIN + demo USER (with `SEED_CREDS_JSON={...}` printed to stdout).

## Out of scope
- **Real postgresql / minio connectivity**: the spec's data model targets SQLite and declares no object storage usage. Admin-settings credential storage is tested, but actually connecting the backend to provisioned postgresql/minio is out of scope (open question in tasks.md — spec is SQLite-only for this demo).
- **Third-party integrations**: spec `## Integrations` is "None"; no external integration behavior is tested.
- **JWT expiry duration / refresh tokens**: token expiry value and refresh flow are not specified; only "invalid/expired token → 401" is asserted, not a specific TTL.
- **Password strength / rate limiting / lockout**: spec is silent; not tested.
- **Concurrency/load beyond single-container demo scale**: SQLite concurrency limits are acknowledged as acceptable; performance/stress testing is out of scope (only the single-slot race invariant is asserted logically).
- **Exact currency locale/format**: cents→currency formatting is asserted as "formatted from cents" (e.g. dollars with 2 decimals); specific locale/symbol rules are not pinned by the spec.
- **Timezone semantics for "today/tomorrow"**: assumed server-local date; cross-timezone edge behavior is not specified and not tested.

Wrote .pipeline/test_spec.md (78 cases across 20 endpoints / 12 journeys).
