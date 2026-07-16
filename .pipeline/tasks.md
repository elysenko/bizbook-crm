# Pipeline Task Decomposition

## Summary
BizBook is a full-stack appointment CRM for small service businesses: a FastAPI + SQLite backend and a React + Vite + TypeScript frontend served from a single Docker image with JWT auth. Staff manage clients, a service catalog, and day-scheduled appointments (with double-booking protection), see a "Today" dashboard, and — for admins only — a monthly revenue report. Auth is `full_auth`: the first signup becomes ADMIN, later signups are USER; all app state is URL-addressable (day view via `?date=`, modals via `?modal=`, client search via `?q=`).

## Surface contract

### Auth model: `full_auth` (roles: admin, user)
- First user to sign up becomes ADMIN; subsequent users become USER (`@default(USER)`).
- Public: `/login`, `/signup`, `GET /api/health`, `GET /api/health/deep`.
- All other app routes require auth; `/revenue` and revenue/service-write endpoints require admin.

### Backend routes (`/api`)
- `POST /api/auth/signup`, `POST /api/auth/login`, `GET /api/auth/me`
- `GET /api/clients?q=`, `POST /api/clients`, `GET /api/clients/:id`, `PUT /api/clients/:id`, `GET /api/clients/:id/appointments`
- `GET /api/services`, `POST /api/services` (admin), `PUT /api/services/:id` (admin)
- `GET /api/appointments?date=YYYY-MM-DD`, `POST /api/appointments` (409 on double-book), `PATCH /api/appointments/:id/status`
- `GET /api/dashboard/today`
- `GET /api/revenue` (admin)
- `GET /api/admin/settings` (admin), `PATCH /api/admin/settings` (admin)
- `GET /api/health`, `GET /api/health/deep`

### Frontend routes/screens
- `/login`, `/signup` (public)
- `/today` (dashboard; `/` redirects here), `/clients` (`?q=`, `?modal=new-client`), `/clients/:id`, `/services` (`?modal=new-service`, admin-only controls), `/appointments` (`?date=`, `?modal=new-appointment`) — all `RequireAuth`
- `/revenue`, `/admin/settings` — `RequireAdmin`

### Entities
- `User(id, email unique, password_hash, name, role[UserRole])`
- `Client(id, name, phone, email, notes, created_at)`
- `Service(id, name, duration_minutes, price_cents)`
- `Appointment(id, client_id FK, service_id FK, date, start_time, status, created_at)` — active unique `(date, start_time)`
- `SystemSetting(key, value, updatedAt)`

## db_agent tasks
- [ ] Configure `backend/app/db.py`: SQLAlchemy engine + session for SQLite via `DATABASE_URL` (default `./bizbook.db`); `create_all` on startup.
- [ ] Define `User` model in `backend/app/models.py` with `id`, `email` (unique), `password_hash`, `name`, and `role` field using `enum UserRole { ADMIN, USER }` with `role @default(USER)` (full_auth model).
- [ ] Define `Client` model: `id`, `name`, `phone`, `email`, `notes`, `created_at`.
- [ ] Define `Service` model: `id`, `name`, `duration_minutes`, `price_cents` (integer cents).
- [ ] Define `Appointment` model: `id`, `client_id` FK, `service_id` FK, `date` (ISO date), `start_time` (`HH:MM`), `status`, `created_at`; add a unique partial index on `(date, start_time)` for non-cancelled rows.
- [ ] Define `SystemSetting` model: `key String @id`, `value String`, `updatedAt DateTime @updatedAt` (admin settings support for provisioned deployments postgresql, minio).

## backend_agent tasks
- [ ] Implement `backend/app/auth.py`: bcrypt password hashing (passlib), JWT create/verify (HS256, `JWT_SECRET` env), `get_current_user` and `require_admin` dependencies.
- [ ] Implement `backend/app/routers/auth.py`: `POST /api/auth/signup` (first user → ADMIN, else USER), `POST /api/auth/login` → JWT token, `GET /api/auth/me`.
- [ ] Implement `backend/app/routers/clients.py`: `GET /api/clients?q=`, `POST /api/clients` (name+phone required), `GET /api/clients/:id`, `PUT /api/clients/:id`, `GET /api/clients/:id/appointments` (past + upcoming, ordered) — all require auth.
- [ ] Implement `backend/app/routers/services.py`: `GET /api/services` (any auth), `POST /api/services` and `PUT /api/services/:id` (`require_admin`); validate `duration_minutes > 0`, `price_cents >= 0`.
- [ ] Implement `backend/app/routers/appointments.py`: `GET /api/appointments?date=YYYY-MM-DD` (time-ordered, joins client+service), `POST /api/appointments` → status `scheduled` with 409 + message when a non-cancelled appt occupies the `(date, start_time)` slot, `PATCH /api/appointments/:id/status` (scheduled|completed|cancelled|no-show).
- [ ] Implement `backend/app/routers/dashboard.py`: `GET /api/dashboard/today` → today's appts (time order, client phone) + tomorrow's count.
- [ ] Implement `backend/app/routers/revenue.py`: `GET /api/revenue` (`require_admin`) → `[{month, total_cents}]` summing completed appts' service `price_cents` grouped by `YYYY-MM`.
- [ ] Implement `backend/app/routers/health.py`: `GET /api/health` and `GET /api/health/deep` (DB ping); both public.
- [ ] Generate admin route protection: ensure the `/api/admin/*` group and admin-guarded writes enforce `require_admin`; USER receives 403 on revenue and service writes.
- [ ] Implement `backend/app/seed.py`: idempotent seed creating demo ADMIN + demo USER, 5 clients, 4 services, ~10 appointments (yesterday/today/tomorrow, mixed statuses incl. some completed); print `SEED_CREDS_JSON={"admin":{...},"user":{...}}` to stdout.
- [ ] Implement `backend/app/lib/config.py` (`resolveConfig(key)` equivalent): read `process.env`/`os.environ[key]` first; if value is absent or equals `PLACEHOLDER_CONFIGURE_IN_SETTINGS`, read the `SystemSetting` DB row; return null if neither is set.
- [ ] Implement `backend/app/routers/admin_settings.py`: `GET /api/admin/settings` (list service keys for postgresql + minio with masked values + configured status) and `PATCH /api/admin/settings` (upsert key/value pairs, `require_admin`).
- [ ] Wire `backend/app/main.py`: FastAPI app mounting `/api` router, `StaticFiles` for built frontend with SPA `index.html` fallback, run seed on startup, expose port 8080.
- [ ] Author `backend/requirements.txt`: fastapi, uvicorn[standard], sqlalchemy, pydantic, passlib[bcrypt], python-jose[cryptography], python-multipart.
- [ ] Implement `backend/app/schemas.py`: Pydantic request/response models for all entities and endpoints above.

## ui_agent tasks
- [ ] Build `frontend/src/App.tsx` + `src/main.tsx`: router root with `AppShell` ("BizBook" header + role-aware nav); `/` → `/today` redirect; wire modal (`?modal=`), day view (`?date=`), search (`?q=`) URL state.
- [ ] Build auth screens `src/pages/Login.tsx` and `src/pages/Signup.tsx` as part of the main app (full_auth model); public routes.
- [ ] Build `src/auth/AuthContext.tsx`, `src/auth/RequireAuth.tsx`, `src/auth/RequireAdmin.tsx`; admin nav entries (Revenue, Admin Settings) visible only to admins.
- [ ] Build `src/pages/Today.tsx`: today's appointment list (time order, client phone) + tomorrow's count, with empty/loading/error states.
- [ ] Build `src/pages/Clients.tsx` (list + search `?q=` + `?modal=new-client`) and `src/pages/ClientDetail.tsx` (info + appointment history, deep-linkable at `/clients/:id`).
- [ ] Build `src/pages/Services.tsx`: catalog with prices formatted from cents; admin-only create/edit controls (`?modal=new-service`) hidden for USER.
- [ ] Build `src/pages/Appointments.tsx`: day view bound to `?date=`, booking form (`?modal=new-appointment`) surfacing the 409 double-booking message inline, status controls.
- [ ] Build `src/pages/Revenue.tsx`: admin-only monthly revenue table (month + total formatted from cents), guarded by `RequireAdmin`.
- [ ] Build `src/pages/AdminSettings.tsx` at `/admin/settings`: list each service in postgresql, minio with configured/unconfigured badge and per-service credential form; show a prominent banner when placeholder services/integrations need credentials (none currently flagged).
- [ ] Build shared `src/components/`: `Nav.tsx` (role-aware), `StatusBadge.tsx`, and form dialog components used by the pages above.

## service_agent tasks
- [ ] Implement `frontend/src/api/client.ts`: fetch wrapper attaching the JWT, JSON handling, and 401 → redirect `/login`.
- [ ] Wire auth flows (signup/login/me/logout) through `api/client.ts` into `AuthContext`.
- [ ] Wire clients data layer: list (with `?q=`), create, get, update, and appointment history calls to the `/api/clients` endpoints.
- [ ] Wire services data layer: list plus admin create/update calls to `/api/services`.
- [ ] Wire appointments data layer: day list (`?date=`), create (surfacing 409 errors), and status update to `/api/appointments`.
- [ ] Wire dashboard (`/api/dashboard/today`) and revenue (`/api/revenue`) data calls to their pages.
- [ ] Wire admin settings data layer: `GET`/`PATCH /api/admin/settings` to the `/admin/settings` page.
- [ ] Author frontend scaffolding config as needed for the client layer: `vite.config.ts` dev proxy `/api` → backend (coordinate with existing scaffold).

## tester tasks
- [ ] Backend pytest: signup first-user-becomes-admin, login/JWT issuance, `GET /api/auth/me`.
- [ ] Backend pytest: client CRUD + `/clients/:id/appointments` history ordering; auth required.
- [ ] Backend pytest: admin-only guards — USER gets 403 on service writes and `GET /api/revenue`; admin succeeds.
- [ ] Backend pytest: appointment booking success, double-booking 409, and status transitions (scheduled|completed|cancelled|no-show).
- [ ] Backend pytest: dashboard today summary counts and revenue grouping math (`YYYY-MM`, completed appts, price_cents sum).
- [ ] Backend pytest: `GET /api/health` and `GET /api/health/deep` return 200; admin settings `GET`/`PATCH` behavior + masking.
- [ ] Frontend: verify deep-linkability/state restore on reload for `/clients/:id`, `/appointments?date=`, and `?modal=` params.
- [ ] Frontend: verify USER sees no Revenue nav entry and no service edit controls; admin sees both.
- [ ] E2E smoke: seed → login as admin → book appointment → mark completed → revenue reflects price; login as USER → revenue blocked (403).

## Open questions
- Spec `## Integrations` says "None (no third-party external services)", but `<spec_deployments>` provisioned `postgresql` and `minio`. The spec's data model targets SQLite and declares no object storage usage. Admin settings tasks were added per pipeline rules to expose credentials for the provisioned services, but downstream agents should confirm whether the backend should actually connect to postgresql/minio or remain SQLite-only for this demo.
- The `<spec_integrations>` entry is a null marker ("None…"), so no integration client module was scheduled. Confirm no real third-party integration is expected.
- Docker/deployment files (`Dockerfile`, `.dockerignore`, `README.md`) are in the spec but not clearly owned by db/backend/ui/service agents; confirm which agent finalizes the multi-stage build and static-serve wiring (assumed backend_agent via `main.py`).
