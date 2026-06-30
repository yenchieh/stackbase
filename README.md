# stackbase

An opinionated, reusable **project foundation** for a Go + Vue + Kubernetes stack —
local development and production run the *same* manifests, and live-reload works for
**both** Go and Vue out of the box.

Adopt it via GitHub **"Use this template"**, change two values, `make up`.

## Stack

| Layer        | Choice                                                              |
|--------------|--------------------------------------------------------------------|
| Backend      | Go — HTTP + middleware (request-id, logging, JWT-validate); gRPC later |
| Frontend     | Vue 3 + Vite                                                        |
| Database     | PostgreSQL (StatefulSet + idempotent migrate Job)                  |
| Analytics    | umami (one shared install, env-gated snippet)                      |
| Cluster      | MicroK8s, kustomize `base` + `overlays/{local,prod}`               |
| Dev loop     | [Tilt](https://tilt.dev) — sync source into the pod, live-reload   |
| Ingress      | **One shared Traefik** for the whole cluster; projects ship only an `IngressRoute` |

## Why it exists

Running several projects on one local MicroK8s box usually means a Traefik *per
project* fighting over port 80, hand-coordinated NodePorts, and a reverse proxy
demuxing `*.test`. stackbase makes the ingress controller **shared cluster infra**:
one Traefik owns `:80/:443` and routes by host across all namespaces. Adding a
project is one `kubectl apply` — no port to claim, no proxy to edit, no `/etc/hosts`.

And the local dev loop is real hot-reload: edit a `.go` file or a `.vue` file and the
change is live in the running pod in seconds. Only secrets and prod deploys are
manual (and those are `make` targets).

## Quick start

```bash
# 1. one-time per machine: shared Traefik + *.test wildcard DNS
make cluster-init

# 2. set the two knobs (below): project namespace + <name>.test host

# 3. secrets, then optional analytics
cp secrets.env.example secrets.env                          # fill JWT_SECRET + POSTGRES_PASSWORD
make secrets-apply
cp services/frontend/.env.example services/frontend/.env    # optional: umami

# 4. dev loop
make up                   # tilt up — edit Go/Vue, live at http://<name>.test
```

MicroK8s users whose host `kubectl` isn't wired to the cluster: either
`microk8s config >> ~/.kube/config`, or run any target as
`make <target> KUBECTL="microk8s kubectl"`.

## The two knobs

A new project changes exactly two values:

| Knob      | Where                                                         | Default          |
|-----------|---------------------------------------------------------------|------------------|
| namespace | `infra/k8s/overlays/{local,prod}/kustomization.yaml` `namespace:` (+ `NS` in the Makefile) | `stackbase`      |
| host      | `infra/k8s/base/ingressroute.yaml` `` Host(`…test`) ``        | `stackbase.test` |

## Make targets

| Target               | What |
|----------------------|------|
| `make cluster-init`  | once per machine: shared Traefik + the `*.test` DNS line |
| `make secrets-apply` | build the `app-secrets` Secret from `secrets.env` |
| `make up` / `down`   | the dev loop (`tilt up`/`down`) — Go + Vue live-reload |
| `make apply`         | one-shot deploy of `overlays/local` without Tilt |
| `make migrate`       | (re)run DB migrations (ConfigMap from the `db/migrations` glob) |
| `make deploy`        | prod: apply `overlays/prod` |
| `make umami`         | optional: install the shared umami analytics |

Production: `make cluster-init` on the prod cluster once, fill `secrets.env`,
`make secrets-apply`, `make deploy`, `make migrate`.

## Status

✅ **Phase 1 complete** — Go api, Vue frontend, Postgres + glob migrations, kustomize
base + local/prod overlays, the Tilt dev loop (Go + Vue hot-reload verified), the shared
Traefik, and optional umami are all built and validated. Design spec:
[`docs/specs/2026-06-29-stackbase-foundation-design.md`](docs/specs/2026-06-29-stackbase-foundation-design.md).

> Note: on a box that already runs other projects, the shared Traefik can't take
> `:80` until those per-project Traefiks are retired (a separate cutover). Everything
> else — and the whole loop via Tilt port-forwards — works today.

Phase 2 (deferred): gRPC, prod CI (GHCR build/push), a full auth/user module.

## License

MIT
