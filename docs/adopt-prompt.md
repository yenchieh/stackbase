# Adoption prompt — paste into any sibling project's session

One reusable prompt. Open a Claude Code session **in the target repo**
(diagramzu, manyi, komiic, nursing-call, …) and paste the block below verbatim.
Each project's own Step-0 audit specializes it — no per-project edits needed.

Companion read-once guide (the mechanics this prompt drives): [ADOPTING.md](ADOPTING.md).

---

```
Refactor THIS project to follow the deployment + dev-loop structure of the template
repo at /home/jay/code/stackbase. This is a deployment/ops refactor only — do NOT
change app code or business logic.

## Read stackbase first — it is the reference standard
- CLAUDE.md and docs/specs/*-stackbase-foundation-design.md — the locked decisions
- infra/cluster/traefik/ + infra/cluster/dnsmasq.md — the ONE shared cluster Traefik + wildcard *.test DNS
- infra/k8s/base/ + overlays/{local,prod}/ — kustomize base + overlays pattern
- Tiltfile — the live-reload dev loop
- Makefile — the operational interface (build/push/deploy + day-2 ops + guards)
- docs/patterns.md — patterns adopted only when a real need shows up
- docs/ADOPTING.md — the read-once migration mechanics

## Step 0 — audit THIS project's current state (don't assume)
List every service (language, Dockerfile, build context, reload strategy), every
vendored/upstream image, the current ingress, the registry + tagging scheme, the
single-instance concerns (DB, migrations, backup, secrets), and the current
dev-loop pain. This audit drives the refactor.

## Adopt these stackbase patterns, adjusted to what the audit found
- ONE shared cluster Traefik as ingress infra; this project ships only an
  IngressRoute. Do the cutover LOCAL-first, keep prod working; prod ingress is a
  separate later step.
- kustomize base/ (bare image names) + overlays/{local,prod} (retag via `images:`).
  base + overlay + Tiltfile change together.
- Tilt dev loop: one scoped-src sync + in-pod reload per service (sync src/ only,
  never node_modules). No machine-specific hostPaths.
- Makefile as the single operational interface. Parameterize per-service work
  (build/push/restart) over ONE service-list knob rather than hardcoding names.
  Carry stackbase's guards verbatim: local-context guard, placeholder-grep before
  deploy, two-tag :latest+:<sha> pinning, day-2 targets.
- Single-instance concerns (DB, migrate Job, backup, secrets) stay single — do not
  multiply them per service.

## Constraints
- Incremental and reversible; keep prod deployable at every step.
- No machine-specific paths in manifests (that's why the dev loop is Tilt sync, not
  hostPath).
- Validate infra with `kustomize build overlays/<env>` + `kubectl apply
  --dry-run=server` (pre-create the namespace) before applying for real.

## Report back
Call out every place where stackbase's assumptions DON'T fit this project's shape
(e.g. single-service assumptions vs. a multi-service app, a different registry, an
off-cluster component). Those deltas are what we fold back into stackbase so every
project inherits them — surface them explicitly rather than silently working around.
```
