# Architecture

## Requested stack
`backend, web` (from pipeline `<stack>` input)

## Scaffolding outcome
**Neither platform was scaffolded from a template.** See rationale below.

| Platform | Requested | Template available | Scaffolded? |
|---|---|---|---|
| backend | yes | `template-backend` (NestJS + Prisma + PostgreSQL) | ❌ skipped — framework mismatch |
| web | yes | `template-web` (Angular 17 + NestJS) | ❌ skipped — framework mismatch |

### Why templates were skipped
The technical plan for this project (BizBook appointment CRM) is explicit
and deliberate about its stack:

- **Backend:** FastAPI (Python) + SQLAlchemy + SQLite, JWT auth via
  `python-jose`/`passlib`.
- **Frontend:** React + Vite + TypeScript, `react-router-dom`.
- **Deployment:** single Docker image — multi-stage build compiles the
  Vite frontend, copies `dist/` into the FastAPI image, and uvicorn serves
  both the `/api` routes and the static SPA (with client-side routing
  fallback) from one container/port.

The only templates available in `scaffold-templates/` for `backend` and
`web` are TypeScript/NestJS/Angular based (effectively the same stack as
the `enterprise` template). There is no FastAPI/Python template. Copying
the NestJS/Angular templates would have:
- Directly contradicted the plan's explicit, reasoned stack choice.
- Forced the coder agent to delete an entire framework's worth of
  scaffolding before writing a single real line of the plan.
- Produced a two-service (Angular+NestJS) shape when the plan calls for a
  single self-contained FastAPI+static-SPA service.

This mirrors the exception already granted to the `enterprise` template
("use unless the spec explicitly requests a different stack") — here the
plan explicitly requests a different stack, and no matching template
exists, so the correct action is to leave the workspace clean rather than
scaffold the wrong framework.

## Where things live (to be created by the coder agent, per the plan)
- `backend/` — FastAPI app (`app/main.py`, `app/models.py`, `app/routers/*`,
  `app/seed.py`, `requirements.txt`).
- `frontend/` — Vite + React + TypeScript app (`src/pages/*`,
  `src/auth/*`, `src/api/client.ts`).
- `Dockerfile` (repo root) — multi-stage build: Node builds
  `frontend/dist` → copied into the Python/uvicorn image; FastAPI mounts
  `/api` and serves the built frontend with SPA fallback on port 8080.

## Next steps for the developer / coder agent
1. Scaffold `backend/` and `frontend/` from scratch per the plan's file
   list (no template to diff against — this is a clean build).
2. `pip install -r backend/requirements.txt` and `npm install` in
   `frontend/`.
3. Implement models, auth, routers, and seed per the plan's steps 1–7.
4. Implement the frontend shell, routing, and pages per steps 8–9.
5. Write the multi-stage `Dockerfile` per step 10; verify
   `GET /api/health` and `/api/health/deep` return 200 after build.
6. No `.env.template`/`docker-compose` setup was run (nothing was
   scaffolded) — the coder agent owns environment/config setup
   (`DATABASE_URL`, `JWT_SECRET`) as part of implementation.

## Template sources considered (not used)
- `scaffold-templates/template-backend` — NestJS + Prisma + PostgreSQL.
- `scaffold-templates/template-web` — Angular 17 frontend + NestJS backend.
