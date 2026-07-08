# Adopting stackbase's architecture in an existing project

Self-contained migration guide. A Claude Code session running **in the target
repo** should read *only this file* — it has everything needed and avoids
exploring the whole stackbase tree.

> Load it into another session cheaply:
> ```
> @/home/jay/code/stackbase/docs/ADOPTING.md
> ```
> (or `claude --add-dir /home/jay/code/stackbase` if you also need to grep the
> real files live.)
>
> Prefer to just drive it? Paste the reusable prompt in
> [adopt-prompt.md](adopt-prompt.md) into a session in the target repo.

The win you're adopting: **one shared Traefik + `*.test` DNS for the whole
machine.** Per-project ingress controllers, NodePorts, and host Caddy all go
away. Each project ships only an `IngressRoute`.

---

## Tier 1 — route the project through the shared ingress (the common case)

### 0. One-time per machine (skip if already done for any project)

From a checkout of stackbase:

```bash
make cluster-init          # installs shared Traefik into ns 'ingress', owns :80/:443
```

Then add the wildcard DNS line **once** (covers every `*.test` project forever):

```bash
echo 'address=/test/127.0.0.1' | sudo tee /etc/dnsmasq.d/test.conf
sudo systemctl restart dnsmasq      # see stackbase infra/cluster/dnsmasq.md for NM/resolved/macOS
```

Verify: `getent hosts foo.test` → `127.0.0.1`.

### In the target project

1. **Delete** whatever the project uses for ingress today: its own Traefik/nginx
   install, any `type: NodePort` Services, a host-level Caddy/reverse proxy. The
   shared Traefik replaces all of it.
2. Make sure each app the project exposes is a plain **`ClusterIP` Service**
   (the default) — the IngressRoute references these by name + port.
3. **Add one IngressRoute** (template below). Change two things:
   - the `Host(...)` → `<your-project>.test`
   - the service names/ports → your project's Services
4. Apply it into the project's namespace and browse `http://<your-project>.test`.

That's the whole migration. The shared Traefik (kubernetescrd provider, no
namespace restriction) picks up the IngressRoute cross-namespace automatically.

### IngressRoute template

Canonical copy lives at stackbase `infra/k8s/base/ingressroute.yaml`. Inlined
here so this doc stands alone — adjust the `# <-- change` lines:

```yaml
# /api/* -> the api service (prefix stripped); /* -> the frontend.
# Drop the api route + middleware if the project is frontend-only.
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: strip-api
spec:
  stripPrefix:
    prefixes:
      - /api
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myproject                      # <-- change
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`myproject.test`) && PathPrefix(`/api`)   # <-- change host
      kind: Rule
      middlewares:
        - name: strip-api
      services:
        - name: api                    # <-- your backend Service name
          port: 8080                   # <-- its port
    - match: Host(`myproject.test`)    # <-- change host
      kind: Rule
      services:
        - name: frontend               # <-- your frontend Service name
          port: 80
```

> Routing through one host with a `/api` prefix lets the browser hit a single
> origin — no CORS, no second hostname. If the project already splits front/back
> across hostnames, you can instead give each its own `Host()` rule.

---

## Tier 2 / 3 — deeper structure (only if the project needs it)

Not required for Tier 1. Adopt per-repo where it pulls its weight; read the
named stackbase files when you get there.

- **Same manifests local↔prod** — kustomize `base/` + `overlays/{local,prod}`.
  Env diff (image registry, tags, secrets, pull policy) lives only in overlays.
  Template: stackbase `infra/k8s/{base,overlays}/`. Two adopter knobs:
  `namespace:` in `overlays/local/kustomization.yaml`, and the `Host()` above.
- **Tilt dev loop** — relative file-sync + in-pod rebuild, no machine-specific
  hostPaths. Template: stackbase `Tiltfile`.
- **Makefile as the only runbook** — manual steps (secrets, deploy, migrate)
  live in one place. Template: stackbase `Makefile`.
- **Migrations** — ConfigMap generated from a `db/migrations/*.sql` glob, never a
  static file list. Template: stackbase `infra/k8s/base/migrate-job.yaml` +
  the `migrate` Make target.

For a full Tier 2 restructure, brainstorm it against the specific repo rather
than copying blindly — the file layout transfers, the service shapes don't.
