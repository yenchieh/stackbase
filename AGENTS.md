# AGENTS.md

Guidelines for coding agents (and humans) working in **stackbase**. The full,
locked design lives in [`CLAUDE.md`](CLAUDE.md) — read it first. This file is the
quick contract: commands, style, and what to flag in a PR.

## Commands

Per-service checks, no cluster needed:

```bash
cd services/api && go test ./... && go vet ./... && go build ./...
cd services/frontend && npx vitest run && npm run build
```

Cluster / ops (see `make help` for the full list):

```bash
make cluster-init     # once per machine: shared Traefik + the *.test DNS line
make secrets-apply    # build app-secrets from secrets.env (then `make restart`)
make up               # dev loop: tilt up — Go + Vue live-reload
make apply            # one-shot local deploy without Tilt (guards kube context)
make migrate          # (re)run DB migrations (ConfigMap from the db/migrations glob)
make seed             # idempotent demo data
make validate         # render an overlay + kubectl apply --dry-run=server
make prod-deploy      # build + push (:latest + :<sha>) then pinned apply
```

## Style

- **Go:** handlers return `respond.Error(w, status, msg)` (→ `{"error": msg}`), never
  `http.Error`. Any struct on the Go↔Vue JSON boundary needs explicit snake_case
  `json:` tags (Go's case-insensitive decode does NOT bridge `day_of_week`↔`DayOfWeek`).
  Guard boundary structs with a marshal round-trip test. TDD: stub so RED is an
  assertion failure, not a compile error.
- **Migrations:** append-only, idempotent (`CREATE … IF NOT EXISTS`). Never edit a
  shipped migration; add a new numbered file. The migrate Job globs `/migrations/*.sql`
  — never maintain an explicit file list (that footgun silently dropped migrations
  in the parent project).
- **kustomize:** `base/` uses bare image names; overlays retag (local →
  `localhost:32000/…:dev`, prod → GHCR). Change the base name, the overlay, and the
  Tiltfile `docker_build` target together.
- **Secrets:** one `app-secrets`. Optional integrations use `secretKeyRef … optional: true`
  so a blank value degrades gracefully instead of wedging the pod.
- Keep changes minimal and boring (see the `ponytail` house style). Prefer deleting
  over adding.

## Commit / PR conventions

- Commit prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, and `deploy(k8s):`
  for manifest/Makefile/infra changes.
- **In the PR description, explicitly call out any:**
  - **migration** (new `db/migrations/*.sql`) — reviewers need to know a `make migrate` runs;
  - **secret/config change** — reminder that it needs `make secrets-apply` + `make restart`
    (a secret change does NOT roll pods on its own);
  - **k8s manifest change** — which overlay(s), and whether it's been `make validate`'d.
- Roadmap: `docs/roadmap.html` is tracked in git — flip a task's status to `progress`
  when you start and `shipped` when done, editing BOTH the `TASKS` array entry and the
  `<section>`/`<span class="badge">` for that card. The commit-gate hook enforces here:
  every commit must touch `docs/roadmap.html` or carry a `[skip-roadmap]` token.

## Don't build these yet

gRPC · prod CI · full auth/user module · a generator CLI. See CLAUDE.md "Deferred to
Phase 2" and the recipes in [`docs/patterns.md`](docs/patterns.md) (backup alerting,
off-cluster GPU, multi-binary images, umami bootstrap) — add those only when a real
need appears.
