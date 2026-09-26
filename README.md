# Autonomous AI-SOC & Security Data Platform

Copyright © Bibas Gautam. All rights reserved.
Third-party libraries retain their own licenses — see `THIRD_PARTY_LICENSES.md`.

> **Status: Complete (Parts 1–3).** Backend core (auth/RBAC/MFA, ingestion,
> detection-as-code, case management, approval-gated response actions, audit
> trail) + ML anomaly detection + correlation/risk-scoring + threat intel +
> Kubernetes manifests + CI, and a React/TypeScript SOC UI — all wired
> together behind Docker Compose and one-click Windows scripts.

A defensive security data platform for **authorized environments only**. It
ingests security events you point at it, evaluates them against
version-controlled detection rules *and* an ML anomaly model, correlates and
risk-scores the results, and lets analysts manage investigations as cases —
with every mutating action recorded in an append-only audit log and every
response action gated behind explicit human approval.

## What this is *not*
- Not an offensive security / exploitation tool.
- Not a scanner that probes systems on your behalf — it only processes data
  you ingest.
- Not something that executes response actions automatically — see
  "Response Action Execution" below.

## Architecture

See `docs/ARCHITECTURE.md` for the full requirements checklist, technology
justification, and data-flow diagram, and `docs/THREAT_MODEL.md` for the
STRIDE threat model of the platform itself.

```
autonomous-ai-soc/
├── backend/             FastAPI app, SQLAlchemy models, Alembic migrations,
│                        ML/detection/correlation/threat-intel services, tests
├── frontend/            React + TypeScript SOC UI (Vite, nginx in prod)
├── detection_rules/     YAML detection-as-code rules (demo set included)
├── k8s/                 Kubernetes manifests (reference deployment) + README
├── docs/                Architecture & threat model docs
├── .github/workflows/   CI (backend tests, frontend build, docker builds)
├── docker-compose.yml
├── .env.example
└── setup.bat / start.bat / seed-demo-data.bat / stop.bat / restart.bat / health-check.bat
```

## Quick start (Windows, Docker) — the whole system in 3 commands

1. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/).
2. From the project root:
   ```
   setup.bat
   start.bat
   seed-demo-data.bat
   ```
3. Open the SOC UI: **http://localhost:5173** — log in with
   `admin` / `ChangeMe123!` (seeded by `seed-demo-data.bat`; **change this
   password before using the instance for anything real**).
4. Interactive API docs: http://localhost:8000/docs
5. Check everything is healthy: `health-check.bat`
6. Stop with `stop.bat` (data is preserved) or restart with `restart.bat`.

The backend container runs `alembic upgrade head` automatically on startup,
so the schema is created for you — no manual migration step needed for a
fresh install. `seed-demo-data.bat` loads synthetic events, a demo admin
user, and demo IOCs, then trains the ML anomaly baseline on them — safe to
skip if you'd rather start from an empty system and ingest your own data.

## Quick start (without Docker)

Backend:
```
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy ..\.env.example ..\.env      REM then edit .env — at minimum set SECRET_KEY
REM Point DATABASE_URL in .env at a Postgres instance you control
alembic upgrade head
uvicorn app.main:app --reload
```

Frontend:
```
cd frontend
npm install
npm run dev
```
The Vite dev server proxies `/api` to `http://localhost:8000` (see
`vite.config.ts`) so no CORS configuration is needed beyond what's already
in `.env`.

## Configuration

All configuration is via environment variables — see `.env.example` for the
full list with comments. Key ones:

| Variable | Required | Notes |
|---|---|---|
| `SECRET_KEY` | Yes | JWT signing key. Generate with `python -c "import secrets; print(secrets.token_urlsafe(64))"` |
| `DATABASE_URL` | Yes | Postgres connection string |
| `REDIS_URL` | Yes | Reserved for the event-bus upgrade path (see Architecture doc) |
| `ML_MODEL_PATH` | No | Where the trained IsolationForest model is persisted. Defaults correctly for both Docker and local dev. |
| `ENABLE_EMBEDDED_CORRELATION_WORKER` | No | `true` (default) runs correlation in-process — fine for Compose's single backend instance. Set `false` and use the k8s CronJob when running multiple backend replicas. |
| `THREAT_INTEL_FEED_URL` / `THREAT_INTEL_API_KEY` | No | Only needed if you wire up a real external threat-intel feed. Leave blank otherwise — **no external integration is enabled by default.** |
| `AWS_*` | No | Only needed if you build S3 log archival yourself. This repo does not provision or call AWS. |

**No integration described in this README is "operational" unless you have
configured its corresponding environment variables.** Where a variable is
blank, that feature is simply inactive — this is a safety property, not a bug.

## Authentication & RBAC

- Roles: `admin`, `lead_analyst`, `analyst`, `viewer`.
- Register: `POST /api/auth/register`, login: `POST /api/auth/login` (returns
  access + refresh JWTs).
- Optional TOTP MFA: `POST /api/auth/mfa/enable` returns a secret and a
  `provisioning_uri` you can render as a QR code for an authenticator app;
  once enabled, `login` requires `mfa_code`.
- Every endpoint's role requirement is enforced **server-side** via a FastAPI
  dependency (`require_role`) — never inferred from anything the client sends.

## Ingestion, Detection-as-Code & ML Anomaly Detection

Push events to `POST /api/events/ingest`:
```json
{
  "source": "suricata",
  "source_ip": "10.0.0.9",
  "dest_ip": "10.0.0.1",
  "event_type": "port_scan",
  "raw_payload": {"ports_scanned": 40}
}
```
Each ingested event is, in order:
1. **Enriched** against the local threat-intel IOC store (`ioc_match` flag).
2. **Scored** by the ML anomaly detector (IsolationForest) — safe neutral
   score (0.0, not anomalous) if the model hasn't been trained yet.
3. **Evaluated** against every rule in `detection_rules/*.yaml`. A match
   creates an `Alert` with risk score = rule severity blended with the
   anomaly score.
4. If **no rule matched but the ML model flags it anomalous**, a separate
   `detection_source: "ml"` alert is created — ML is additive to rules, never
   a silent replacement for them.

Train (or retrain) the anomaly baseline on recently ingested events:
`POST /api/ml/train` (admin only, manual/on-demand by design — not an
unattended cron job, so a human reviews when the baseline changes).

Rules are plain YAML — add your own file to `detection_rules/` and restart
the backend to load it.

### Collector adapters (bring your own)
This platform does not bundle Suricata, Zeek, or agent binaries. To connect
real sources, run a small shipper that tails their output and POSTs it to
`/api/events/ingest` in the schema above:
- **Suricata**: tail `eve.json`, map `event_type`/`src_ip`/`dest_ip` fields.
- **Zeek**: tail `conn.log`/`notice.log` (TSV or JSON output mode).
- **Syslog**: point a syslog-to-HTTP forwarder (e.g. `rsyslog` omhttp module) at the endpoint.
- **Windows hosts**: a lightweight agent forwarding Sysmon/Event Log entries.

None of these adapters are implemented as running services in this repo —
implementing and running them against real infrastructure is the operator's
responsibility.

## Correlation & Risk Scoring

A background worker (`app/workers/correlation_worker.py`) periodically groups
recent `new` alerts by source IP; if a single IP has produced enough
distinct alerts within the correlation window, all of them are escalated
(`status=escalated`) and their risk score is boosted. This never contacts or
acts on any external system — it only raises status on the platform's own
alert records. See `ENABLE_EMBEDDED_CORRELATION_WORKER` above for the
multi-replica deployment note.

## Threat Intelligence

- Manage IOCs: `POST/GET /api/threat-intel/iocs`, check a value:
  `GET /api/threat-intel/iocs/check?value=...`.
- Optional external feed import: `POST /api/threat-intel/import` — a
  documented no-op unless `THREAT_INTEL_FEED_URL` and `THREAT_INTEL_API_KEY`
  are both set.

## Case Management & Response Actions

- Create a case from one or more alerts: `POST /api/cases`.
- Comment: `POST /api/cases/{id}/comments`.
- Request a response action: `POST /api/cases/{id}/actions` → created as
  `pending_approval`.
- Approve (requires `lead_analyst` or `admin`): `POST /api/cases/{id}/actions/{action_id}/approve`.
- Reject: `.../reject`. Revert an approved/executed action: `.../revert`.
- All of this is available in the SOC UI's Case detail page, not just the API.

### Response Action Execution
Approving an action **does not** call any external system in this build —
there is deliberately no firewall/EDR/IAM integration wired up out of the
box. Wiring `status=approved` to a real enforcement call (e.g. a firewall
API to block an IP) is a per-deployment integration you implement and enable
explicitly, so that this platform never takes irreversible action against
your infrastructure without you having reviewed and connected that specific
integration.

## Audit Trail

Every non-GET API call is recorded in `audit_log` (actor, method, path,
status code, client IP, SHA-256 hash of the request body, duration) by
`AuditMiddleware`. There is no update or delete route for this table. In
production, additionally revoke UPDATE/DELETE on `audit_log` at the database
role level — see the comment in
`backend/app/alembic/versions/0001_initial_schema.py`.

## SOC UI (frontend/)

React + TypeScript + Vite, served by nginx in Docker/Kubernetes. Pages:
Dashboard (alert/case stats), Alerts (filter, triage, spin up a case),
Cases (create, comment, approve/reject/revert response actions), Events
(raw ingested events with anomaly scores), Threat Intel (manage IOCs,
trigger feed import). JWTs are stored in `localStorage` with automatic
silent refresh on 401.

## Kubernetes (k8s/)

A reference deployment — namespace/config, Postgres/Redis/Elasticsearch,
backend Deployment+HPA, a correlation CronJob (for multi-replica setups),
frontend Deployment + Ingress. **Read `k8s/README.md` before applying this
to a real cluster** — it documents what you must change (image references,
secrets, TLS, the multi-replica correlation-worker setting, persistent ML
model storage).

## CI/CD

`.github/workflows/ci.yml` runs backend tests + lint, frontend type-check +
build, and builds (but does not push) both Docker images. Push-to-registry
and deploy stages are left as commented-out placeholders — wiring them up
needs your own registry/cluster credentials, which this template does not
assume.

## Testing

```
cd backend
pip install -r requirements.txt
pytest -v
```
Tests use an in-memory SQLite database (no Postgres required) and cover:
auth/registration/RBAC, event ingestion → threat-intel enrichment → ML
scoring → detection → alert creation, case and response-action approval
workflow, the correlation worker, risk-scoring math, the ML anomaly
detector, and the detection-rule engine in isolation. See `backend/tests/`.

```
cd frontend
npm install
npm run typecheck
npm run build
```

**Honesty note on verification:** this codebase was built and reviewed in a
sandboxed environment without package-registry access, so while every piece
of pure-Python/ML logic (detection engine, risk scoring, anomaly detector)
was directly executed and confirmed correct, the full FastAPI+SQLAlchemy
test suite and the frontend build could not be executed end-to-end here.
Run `pytest -v` and `npm run build` yourself after unzipping and report back
anything that fails.

## API Documentation

Interactive OpenAPI docs are auto-generated by FastAPI at `/docs` (Swagger
UI) and `/redoc` once the backend is running.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `docker compose build` fails | Ensure Docker Desktop is running and you have network access to pull base images |
| Backend container restarts in a loop | Check `docker compose logs backend` — usually a bad `DATABASE_URL` or missing `SECRET_KEY` in `.env` |
| `/readyz` reports database error | Postgres container may still be starting; wait a few seconds, or check `docker compose logs postgres` |
| 403 on an endpoint you expect to access | Check your account's `role` via `GET /api/auth/me` — RBAC is enforced server-side |
| Alerts not appearing after ingesting an event | Confirm your event's `event_type` / payload fields actually match a rule in `detection_rules/*.yaml`, or that the ML model is trained (`GET /api/ml/status`) — no match and no anomaly means no alert, by design |
| Frontend loads but API calls fail | Check the backend is healthy (`health-check.bat`) and that `frontend/nginx.conf`'s `/api` proxy target matches your compose service name |
| `seed-demo-data.bat` can't get a token | Run `docker compose logs backend` to check the seed script itself succeeded; you can always log in via the UI and call `/api/ml/train` manually |

## Known Limitations

- Rate limiting on the ingestion endpoint is not yet enabled by default
  (hook noted in `docs/THREAT_MODEL.md`; add `slowapi` for production).
- The embedded correlation worker is per-process — see the
  `ENABLE_EMBEDDED_CORRELATION_WORKER` note for multi-replica deployments.
- The trained ML model is stored on a local volume/emptyDir, not shared
  storage — see `k8s/README.md` point 4 for the production fix.
- Elasticsearch is included in `docker-compose.yml`/`k8s/` for future
  full-text/correlation search but is not yet queried by the backend.
- No NetworkPolicies, PodDisruptionBudgets, or service mesh config in `k8s/`.

## Final Verification Checklist

- [x] Multi-source ingestion endpoint accepts arbitrary JSON events
- [x] Detection-as-code: YAML rules, hot-loadable, unit-tested
- [x] ML anomaly detection (IsolationForest): train/persist/reload/score — executed and verified
- [x] Threat-intel local IOC store + optional external feed importer (documented no-op if unconfigured)
- [x] Correlation/risk-scoring worker with multi-replica-safe CronJob alternative
- [x] RBAC enforced server-side on every privileged route
- [x] MFA (TOTP) scaffold: enable + enforce-at-login
- [x] Audit trail: append-only, covers all mutating routes
- [x] Case management: create/update/comment
- [x] Response actions: request → approve/reject → revert, all audited
- [x] React/TypeScript SOC UI covering every major workflow
- [x] Docker Compose stack (Postgres/Redis/ES/backend/frontend) with health checks
- [x] Kubernetes manifests + README documenting production-readiness gaps
- [x] GitHub Actions CI (tests, lint, type-check, docker build)
- [x] Windows setup/start/seed-demo-data/stop/restart/health-check scripts
- [x] `.env.example` with no real secrets
- [x] Automated tests for auth, ingestion/detection/ML/correlation, case/action workflow
