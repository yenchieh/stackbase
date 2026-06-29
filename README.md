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
| Object store | Cloudflare R2 (S3-compatible, presigned uploads)                   |
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

# 2. set two values: project namespace + <name>.test host (find-replace, documented)

# 3. creds
cp .env.example .env      # fill R2 (+ optional umami)

# 4. dev
make up                   # tilt up — edit Go/Vue, see it live at http://<name>.test
```

Production: `make cluster-init` on the prod cluster once, fill `secrets.env`, `make deploy`.

## Status

🚧 **Phase 1 in progress** — see the design spec at
[`docs/specs/2026-06-29-stackbase-foundation-design.md`](docs/specs/2026-06-29-stackbase-foundation-design.md).

## License

MIT
