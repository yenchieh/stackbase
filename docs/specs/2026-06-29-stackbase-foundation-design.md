# stackbase — design

A reusable, open-source **project foundation** for the author's stack:
Go (HTTP + middleware, gRPC later) · Vue · Postgres · Cloudflare R2 ·
umami analytics · MicroK8s local dev with hot reload · namespace-per-project ·
`*.test` local domains · **same manifests local → prod**.

Adopted via GitHub "Use this template" → rename → `tilt up`. The deliverable is
a **working minimal app**, not a generator. The boilerplate *is* the product.

---

## Goals

1. **Fast new-project spinup** — template → working local→prod skeleton in minutes.
2. **Consistency across projects** — one blessed pattern instead of per-repo drift.
3. **Near-zero per-service boilerplate** — adding a service is a small, obvious diff.
4. **Reliable local==prod parity** — identical kustomize manifests both ways.

## Non-goals / explicitly deferred

- **gRPC** (proto + `buf` codegen + a second service) — Phase 2.
- **Prod CI** (GHCR build/push, secret bootstrap automation) — Phase 2.
- **Full auth product** (users table, login, password reset) — out of scope; the
  template ships the *JWT-validation pattern*, not an auth system.
- **A scaffolding CLI / cookiecutter generator** — YAGNI until the plain-template
  rename proves painful.

---

## Why Tilt (the one build-vs-buy decision)

The author's current nursing-call local overlay hand-rolls hot reload with
`hostPath` mounts + CompileDaemon (Go) + a `node_modules` musl emptyDir dance
(Vue), plus `imagePullPolicy: Always` and NodePort coordination. The hardcoded
`/home/jay/code/...` paths make it **non-portable** — fatal for something others
adopt.

[Tilt](https://tilt.dev) does this generically: it **syncs scoped source paths
into the running pod** (no hostPath, relative paths → portable) and runs an
in-pod rebuild. It owns build → cluster-load → live-update with a UI.

**Tilt replaces only build + sync + deploy, not routing.** Routing is handled by a
single **shared** cluster Traefik (see the Ingress section) — not Tilt port-forwards,
and not the old per-project Traefik + Caddy setup, which this design retires.

---

## Repo layout

```
stackbase/
  services/
    api/                      # Go module github.com/yenchieh/stackbase/api (or per-adopter)
      cmd/server/main.go
      internal/middleware/    # requestid, logging, jwt
      internal/r2/            # S3-compatible client + presign
      internal/http/          # handlers: /healthz, /me, /uploads/presign
      Dockerfile              # prod: multi-stage static binary
      Dockerfile.dev          # CompileDaemon
    frontend/                 # Vue 3 + Vite
      src/                    # page that calls /healthz + /me; upload demo
      src/analytics.ts        # env-gated umami snippet
      Dockerfile              # prod: vite build -> nginx
      Dockerfile.dev          # vite dev server
  infra/
    cluster/                  # ONE-TIME per machine/cluster (make cluster-init):
      traefik/                #   ONE shared Traefik (ns=ingress, hostPort 80/443,
                              #   kubernetescrd watching ALL namespaces)
      dnsmasq.md              #   *.test -> 127.0.0.1 wildcard (one line)
    k8s/
      base/                   # namespace, api, frontend, postgres (StatefulSet),
                              #   migrate Job, IngressRoute  (NO Traefik Deployment —
                              #   the controller is shared cluster infra, above)
      overlays/
        local/                # :dev images -> localhost:32000
        prod/                 # :latest GHCR images, imagePullPolicy Always, secret refs
      shared/umami/           # OPTIONAL one-per-machine umami install (its own Postgres)
  db/migrations/0001_init.sql
  Tiltfile
  Makefile
  .env.example
  README.md                   # "adopt this" instructions
```

**Conventions inherited from nursing-call** (battle-tested, keep them): kustomize
`base/` + `overlays/`; migrate Job that globs `/migrations/*.sql`; idempotent
migrations (`CREATE ... IF NOT EXISTS`); Traefik `IngressRoute`; Go handlers
return `writeJSONError(w, status, msg)`.

---

## Local dev loop (Tiltfile)

Per service, three moves:

```python
docker_build('stackbase/api', 'services/api',
    dockerfile='services/api/Dockerfile.dev',
    live_update=[ sync('services/api', '/app') ])        # CompileDaemon rebuilds in-pod

docker_build('stackbase/frontend', 'services/frontend',
    dockerfile='services/frontend/Dockerfile.dev',
    live_update=[ sync('services/frontend/src', '/app/src') ])  # Vite HMR; node_modules untouched

k8s_yaml(kustomize('infra/k8s/overlays/local'))
```

- **Go hot-reloads like Vue does** (not "rebuild on apply"): edit `.go` → Tilt
  syncs → in-pod CompileDaemon `go build` + restart (seconds). This is a hard
  requirement — both languages live-reload on save with zero manual steps.
- **Vue**: edit `src/` → Tilt syncs `src/` only → Vite HMR (~1s). Because the sync
  is path-scoped to `src/`, `node_modules` is never synced → **no musl emptyDir
  workaround, no hostPath**.
- Tilt pushes images to the MicroK8s registry (`default_registry('localhost:32000')`).
- `*.test` routing via the **shared** cluster Traefik (see Ingress section); Tilt does
  not own routing. No Caddy, no NodePort.

### Dev-loop boundary — what's automatic vs a `make` target

| Change                          | How it applies                                  |
|---------------------------------|-------------------------------------------------|
| Go source / Vue source          | **Automatic** live-reload (Tilt sync, no apply) |
| k8s manifests / ConfigMaps      | **Automatic** re-apply by Tilt while `tilt up` runs (`k8s_yaml` is watched) |
| Secrets (out-of-band)           | **Manual** → `make secrets-apply`               |
| Prod deploy                     | **Manual** → `make deploy`                       |

Secrets are the only routinely-manual local step: they're built from a gitignored
`secrets.env` and never live in the git manifests, so Tilt can't watch them.

> Decision knob: keeping `k8s_yaml` **watched** means manifest edits also apply
> automatically during dev (less manual than the original "config needs apply"
> ask). If explicit control over manifest applies is preferred, mark `k8s_yaml`
> non-watched and use `make apply` for every manifest change. Default: watched.

## Prod path

`overlays/prod` over the same `base/`: GHCR `:latest` + `imagePullPolicy: Always`
+ secret refs (single `*-secrets` Secret created out-of-band, gitignored
`secrets.env`, template committed). `make deploy` =
`kustomize build infra/k8s/overlays/prod | kubectl apply -f -`. Identical base
manifests local↔prod is the parity guarantee. (Building/pushing images in CI is
Phase 2; the overlay is hand-deployable now.)

## Makefile (the manual steps live here, nowhere else)

Code never needs a `make` target — Tilt handles it. The Makefile wraps only the
`kubectl`-touching steps so adopters never type raw `kubectl`:

| Target              | Does                                                              |
|---------------------|------------------------------------------------------------------|
| `make cluster-init` | **one-time per machine**: install the shared Traefik (`infra/cluster`) + print the dnsmasq `*.test` line. Idempotent. |
| `make up`           | `tilt up` (the dev loop: build, deploy, live-reload Go + Vue)     |
| `make down`         | `tilt down`                                                       |
| `make secrets-apply`| build the local Secret from `secrets.env` (`kubectl create secret … --dry-run \| apply`) |
| `make apply`        | one-shot `kustomize build overlays/local \| kubectl apply` (no-Tilt case) |
| `make deploy`       | `kustomize build overlays/prod \| kubectl apply` + prod secrets   |
| `make migrate`      | delete + re-run the migrate Job (immutable Job footgun)           |

## App skeleton (Go `api`)

Middleware chain: `requestid → logging (structured) → jwt-validate`. Endpoints:

- `GET /healthz` — public, no middleware. Liveness/readiness target.
- `GET /me` — behind jwt-validate; echoes the validated claims. Proves the
  middleware + the protected-route pattern.
- `POST /uploads/presign` — see R2.

JWT middleware **validates** a bearer token against `JWT_SECRET` and puts claims
in context; it does **not** issue tokens or manage users. That is the deliberate
"pattern not product" line.

Vue frontend: one page that calls `/healthz` and `/me`, renders the result, and a
file-picker demoing the R2 presigned upload. This is the end-to-end proof that
`tilt up` works.

## R2 (object storage)

`aws-sdk-go-v2` S3 client, `BaseEndpoint = R2_ENDPOINT`, path-style, creds from
`R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`. Sample path = **presigned
PUT**: `POST /uploads/presign {filename}` → `{url, key}`; the browser `PUT`s the
file straight to R2 (no bytes through Go). ~30 lines. Env in `.env.example`.

## umami (analytics)

**One shared install per machine/cluster** in `infra/k8s/shared/umami/` (umami +
its own small Postgres), serving every project as a distinct "website". *Not*
one-per-project. The Vue snippet (`src/analytics.ts`) is **env-gated** on
`VITE_UMAMI_SRC` + `VITE_UMAMI_WEBSITE_ID`: unset → no-op, so the template runs
before umami exists. Standing umami up is an optional one-time step in the README.

## Database & migrations

Postgres 16 StatefulSet, hostpath PVC (`microk8s-hostpath`). A migrate Job globs
`/migrations/*.sql` (mounted from a ConfigMap). `db/migrations/0001_init.sql`
seeds one demo table. Migrations idempotent.

> ⚠️ Inherited gotcha to design out: nursing-call's migrate ConfigMap uses an
> **explicit `files:` list**, so new migrations were silently dropped. stackbase
> should generate the ConfigMap from a **glob** (or document the list-append loudly)
> so adopters don't hit the same trap.

## Ingress — one shared Traefik, not one per project

The recurring multi-project pain (NodePort collisions, N Traefik pods fighting for
hostPort 80, a host Caddy demuxing `*.test`) comes from running a Traefik **per
project**. stackbase fixes it at the root: **the ingress controller is shared
cluster infra, installed once; projects ship only an `IngressRoute` + a hostname.**

- **`infra/cluster/traefik/`** — a SINGLE Traefik in namespace `ingress`, owning
  **hostPort 80/443** directly, kubernetescrd provider watching **all namespaces**.
  Applied once per machine via `make cluster-init`. Idempotent — every stackbase repo
  ships an identical copy so any project can bootstrap the cluster; re-running is a
  no-op re-apply.
- **Per project**: `base/` contains only an `IngressRoute`
  (``Host(`<name>.test`)``: `/` → frontend, `/api` → api). **No Traefik Deployment,
  no Service NodePort, no Caddy.** The shared Traefik picks it up cross-namespace.
- **DNS**: `*.test → 127.0.0.1` via a one-line dnsmasq wildcard
  (`address=/test/127.0.0.1`). A new project needs **zero** DNS edits, ever.
- **Subdomains** (`admin.<name>.test`) = one more match rule in the same IngressRoute.

Net effect: adding a project = `kubectl apply` of its manifests (Tilt does this) —
no port to claim, no Caddy to edit, no `/etc/hosts` line.

**One namespace per project** (`namespace:` in the kustomization) and the
`<name>.test` host are the **only two values** an adopter changes.

**Prod** uses the same model — `make cluster-init` installs the shared Traefik on the
prod cluster too. The single environment difference is entrypoint binding: hostPort
80/443 locally; a NodePort or LoadBalancer in prod, per the cluster's front.

## Adoption flow (README)

1. **One-time per machine**: `make cluster-init` (shared Traefik + `*.test` dnsmasq).
   Only the first stackbase project on the box needs it; later projects skip it.
2. "Use this template" → new repo → `cd`.
3. Set the two knobs: **project name/namespace** and **`<name>.test` host**. One
   find-replace, documented. (No NodePort, no Caddy edit, no `/etc/hosts`.)
4. `cp .env.example .env`, fill R2 (+ optional umami) creds.
5. `make up` → open `http://<name>.test`.
6. Prod: `make cluster-init` on the prod cluster once, fill `secrets.env`, `make deploy`.

---

## Risks / open questions

- **Tilt + MicroK8s registry**: confirm `default_registry('localhost:32000')`
  round-trips on the author's cluster (it does for plain `docker_build`; verify
  with `live_update`). First implementation task should be a spike: `tilt up` on a
  hello-world Go pod and confirm a `.go` edit reloads in-pod.
- **CompileDaemon vs Tilt-native `run()`**: we keep CompileDaemon (author knows it,
  Dockerfile exists). If in-pod rebuild proves flaky under Tilt sync, fall back to
  Tilt-native `run('go build')` + container restart. Decide during the spike.
- **Shared Traefik must watch all namespaces and own hostPort 80/443** — verify the
  kubernetescrd provider has no namespace restriction, and that nothing else holds
  `:80` (the old per-project Traefiks + Caddy must be gone first).
- **Migrating existing projects** (nursecall 31080 / manyi 31278 / komiic 30080) off
  their per-project Traefik+NodePort+Caddy setup onto the shared Traefik is a separate
  cutover (free `:80`, stand up the shared Traefik, move each to IngressRoute-only,
  retire the old Traefiks + Caddy). Out of scope for the Phase-1 template, but the
  reason the template must model the shared pattern correctly from day one.
- **gRPC topology** (Phase 2): Go↔Go internal vs connect/grpc-web to the browser —
  resolve when Phase 2 is specced.
