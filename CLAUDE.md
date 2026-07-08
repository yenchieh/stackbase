# CLAUDE.md

Guidance for Claude Code working in **stackbase**. These instructions are the
distilled output of a full brainstorming session — treat the decisions below as
**locked**; don't re-litigate them, build against them.

## What this is

stackbase = an opinionated, open-source **project foundation** (a GitHub "Use this
template" repo) for a **Go + Vue + MicroK8s** stack. Local dev and prod run the
**same kustomize manifests**; **both Go and Vue hot-reload on save**. Adopt →
change two values → `make up`.

- **Full design (read first):** `docs/specs/2026-06-29-stackbase-foundation-design.md`
- **Build progress / task list:** `ROADMAP.md` (tracked in git)
- **Status:** Phase 1 in progress. Nothing built yet beyond scaffold — **start at ROADMAP Task 1.**

## Prime directive: it must run on a STRANGER'S machine

This is open source. **Nothing may hardcode machine-specific paths** (no
`/home/jay/...` hostPaths). That is the #1 reason the dev loop is **Tilt**
(relative file-sync) rather than the hostPath + CompileDaemon overlay patches from
nursing-call. Optimize every choice for "a fresh adopter clones it and it works."

## Locked architecture decisions

- **Dev loop = Tilt**, not hand-rolled hostPath patches. Tilt syncs scoped source
  into the running pod and triggers an in-pod rebuild.
- **Both languages live-reload on save**, zero manual steps:
  - **Go**: Tilt `sync(services/api → /app)` → in-pod **CompileDaemon** `go build` +
    restart (seconds). This is real hot-reload, **not** rebuild-on-apply.
  - **Vue**: Tilt `sync(services/frontend/src → /app/src)` → **Vite HMR**. Sync is
    scoped to `src/`, so `node_modules` is never synced → **no musl emptyDir dance**.
- **Ingress = ONE shared Traefik as cluster infra** (this is the fix for the
  multi-project local pain). Namespace `ingress`, owns **hostPort 80/443**,
  kubernetescrd provider watches **all namespaces**. Lives in
  `infra/cluster/traefik/`, installed once via `make cluster-init` (idempotent —
  every repo ships an identical copy). Projects ship **only an `IngressRoute`**
  (``Host(`<name>.test`)``). **NO per-project Traefik, NO Service NodePort, NO host
  Caddy.**
- **DNS**: `*.test → 127.0.0.1` via a one-line dnsmasq wildcard
  (`address=/test/127.0.0.1`). A new project needs **zero** DNS edits.
- **Same manifests local↔prod**: kustomize `base/` + `overlays/{local,prod}`. Local =
  `:dev` images → `localhost:32000` MicroK8s registry; prod = GHCR `:latest` +
  `imagePullPolicy: Always` + secret refs.
- **umami (analytics)**: ONE shared install (`infra/k8s/shared/umami/`, its own small
  Postgres); Vue snippet env-gated on `VITE_UMAMI_*` (unset → no-op).
- **Auth**: JWT-**validate** middleware only — the *pattern*, not a product. No users
  table, no login, no password reset in Phase 1.
- **Manual steps live in the Makefile, nowhere else**: only **secrets**
  (`make secrets-apply`) and **prod deploy** (`make deploy`) are hands-on. Code *and*
  k8s manifests apply automatically while `tilt up` runs.

## Deferred to Phase 2 — do NOT build these yet

gRPC (proto + `buf` + a 2nd service) · prod CI (GHCR build/push, secret bootstrap) ·
full auth/user module · migrating nursecall/manyi/komiic onto the shared Traefik.
A scaffolding/generator CLI is **YAGNI** — this is a plain template, not a generator.

## Build order (ROADMAP.md is the source of truth)

**Spikes first** — they de-risk the only parts not already proven in nursing-call.
If a spike fails, fix the **design (and the spec)** before building on it.

1. **SPIKE — Tilt live-reload on MicroK8s**: hello-world Go pod; confirm a `.go` edit
   syncs in + CompileDaemon rebuilds in-pod, images via `localhost:32000`.
2. **SPIKE — shared Traefik**: route two `*.test` hosts living in two *different*
   namespaces through one Traefik on `:80`.

Then: cluster bootstrap → Go `api` → Postgres + migrate → Vue → kustomize
base+overlays/local → Tiltfile → umami → overlays/prod → Makefile + README.
(R2 object storage was **dropped** — owner decision, 2026-06-29.)

## Conventions (inherited from nursing-call where battle-tested)

- **Validate infra changes** with `kustomize build overlays/<env>` + `kubectl apply
  --dry-run=server` (pre-create the namespace it targets — base references it); for a
  live check, deploy to a **throwaway namespace** then delete it.
- **Image-name wiring**: `base/` uses bare image names; `overlays/local` rewrites to
  `localhost:32000/<svc>:dev` and the Tiltfile's `docker_build` targets that same full
  name (NO `default_registry`). Change all three together.
- **Go TDD here**: stub the impl so RED is an *assertion* failure, not a compile error —
  Go won't build a test with an undefined symbol, nor a stub with unused imports (drop
  them until the real impl).
- Go handlers return `writeJSONError(w, status, msg)` (→ `{"error": msg}`), not `http.Error`.
- **Go↔Vue JSON boundary needs explicit snake_case `json:` tags.** Go's
  case-insensitive decode does NOT bridge `day_of_week`↔`DayOfWeek`; an untagged
  struct silently 400s on PUT and returns unreadable keys on GET. Guard boundary
  structs with a marshal/unmarshal round-trip test.
- Migrations idempotent (`CREATE ... IF NOT EXISTS`). Migrate Job globs
  `/migrations/*.sql` — **generate the ConfigMap from a glob, never an explicit
  `files:` list** (the explicit-list footgun silently dropped nursing-call migrations
  027–029).
- kustomize calls that walk out of the tree need `--load-restrictor=LoadRestrictionsNone`.
- Go module path: `github.com/yenchieh/stackbase` (confirm your handle before `go mod init`).

## Roadmap mechanics

`ROADMAP.md` is **tracked in git** (pushed to GitHub). Plain markdown checklist;
status key **✅ done · 🚧 in-progress · ⬜ todo**. Standing rule: flip a task to 🚧
when you **start** it and ✅ when **done**. Because the roadmap is now tracked, the
global commit-gate hook **enforces** here — every commit must update `ROADMAP.md` or
carry a **`[skip-roadmap]`** (or `[no-task]`) token to bypass.

## Commands (target shape — exist after Phase 1 task 12)

- `make cluster-init` — once per machine: shared Traefik + dnsmasq `*.test`
- `make up` / `make down` — `tilt up` / `tilt down` (the dev loop)
- `make secrets-apply` — build the local Secret from `secrets.env`
- `make apply` — one-shot `kustomize build overlays/local | kubectl apply` (no-Tilt)
- `make deploy` — prod `kustomize build overlays/prod | kubectl apply`
- `make migrate` — delete + re-run the migrate Job (immutable Job footgun)

Per-service checks without the cluster: `cd services/api && go test ./... && go build ./...` ·
`cd services/frontend && npx vitest run && npm run build`.
