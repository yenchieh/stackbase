# stackbase roadmap

Local-only (gitignored — never pushed). Tracks build progress against the design at
`docs/specs/2026-06-29-stackbase-foundation-design.md`.

Status key: ✅ done · 🚧 in-progress · ⬜ todo

---

## Phase 1 — foundation core (skeleton + R2 + umami)

Build order is deliberate: the two **spikes** come first to de-risk the only parts
we haven't already shipped in nursing-call. If either spike fails, we adjust the
design before building on it.

- ✅ **0. Project scaffold** — repo, README, MIT license, .gitignore, this roadmap, design spec
- ✅ **1. SPIKE — Tilt live-reload on MicroK8s** — PROVEN in `spike/` (Tilt v0.37.4). A `.go` edit → Tilt `Will copy 1 file(s) to container` (live_update sync) → CompileDaemon `Build ok` + in-pod restart → same pod serves new body; image `localhost:32000/stackbase-spike:tilt-…` confirms the registry round-trip. CompileDaemon stays (no Tilt-native `run()` fallback needed). *De-risks the whole dev loop.*
  - **Findings for later tasks:**
    - **kubeconfig wiring (Task 3/12):** host `kubectl` had no current-context — MicroK8s ships its own config. `make cluster-init` / README must do `microk8s config >> ~/.kube/config` (or set `KUBECONFIG`) so Tilt targets the cluster. Not in the spec yet.
    - **host port conflicts:** `:80` and `:8080` are already taken on this box. Real apps route through the shared Traefik (`:80`), so the old per-project Traefik/Caddy must be freed before Task 2 (matches the spec risk note). Spike used port-forward `18080`.
    - `spike/` is throwaway — delete after the real `services/api` + Tiltfile land (Task 8).
- ✅ **2. SPIKE — shared Traefik ingress** — PROVEN in `spike/ingress.yaml`. ONE Traefik (ns `ingress-spike`, `--providers.kubernetescrd` with NO namespace restriction) routed `a.test`→ns `spike-a` and `b.test`→ns `spike-b`, unknown host → 404, all via one entrypoint. Existing per-project Traefiks left untouched. *De-risks the multi-project fix.*
  - **Findings for later tasks:**
    - **versions:** cluster CRDs are Traefik **v3** (`ingressroutes.traefik.io`); real shared Traefik = `traefik:v3.2`, IngressRoutes `traefik.io/v1alpha1`.
    - **the enabler is ClusterRole RBAC** (not Role): watch `services`/`endpointslices`/`secrets`/`traefik.io` cluster-wide — that's literally what "watch all namespaces" requires. Carry into `infra/cluster/traefik/` (Task 3).
    - **hostPort works** (proven on 18081). Real Traefik wants hostPort **80/443**, but `:80` is currently owned by an existing per-project Traefik. So `make cluster-init`'s *live apply against :80* is blocked until the Phase-2 cutover (retire komiic/manyi/nursing-call/diagramzu per-project Traefiks). Authoring the manifests + idempotent target (Task 3) is NOT blocked.
    - **MetalLB is enabled** → prod ingress can be a `LoadBalancer` Service (confirms the spec's "NodePort or LoadBalancer in prod" — LB is available here).
- ✅ **3. Cluster bootstrap** (authored + server-validated; live `:80` apply deferred to cutover) — `infra/cluster/traefik/` = `00-crds.yaml` (VENDORED pinned Traefik v3.2 CRDs, so a fresh box has them), `10-rbac.yaml` (ns `ingress` + SA + ClusterRole[official v3.2 rules] + Binding), `20-traefik.yaml` (Deployment, `kubernetescrd` watch-all, hostPort 80/443, tcpSocket probes). `infra/cluster/dnsmasq.md` (one-line `address=/test/127.0.0.1`, + kubeconfig-wiring note). `Makefile` with idempotent `cluster-init` (`kubectl apply -f infra/cluster/traefik/`, `KUBECTL ?=` override for `microk8s kubectl`).
  - **Validation:** `kubectl apply --dry-run=server` passed for all CRDs + RBAC + Deployment against the real cluster (temp empty `ingress` ns created then deleted — cluster left untouched, no pod, `:80` never bound). Runtime Traefik config already proven by Task 2.
  - **Deferred:** `make cluster-init`'s real apply needs `:80` free → blocked on retiring the existing per-project Traefiks (Phase-2 cutover). Prod variant swaps hostPort→LoadBalancer (MetalLB present).
- ✅ **4. Go `api` skeleton** — TDD, `services/api/` (module `github.com/yenchieh/stackbase`). `cmd/server` (`newRouter` + thin `main`, fail-fast if `JWT_SECRET` unset, `ReadHeaderTimeout`). `internal/middleware`: `RequestID` (X-Request-Id gen/propagate), `Logging` (slog, injected), `JWTValidate` (HS256, alg-pinned via `WithValidMethods`). `internal/handlers`: `Healthz` public, `Me` protected (echoes claims). `internal/respond` (`JSON`/`Error` → `{"error":msg}`). `Dockerfile` (distroless static nonroot) + `Dockerfile.dev` (CompileDaemon). 14 tests green, vet+gofmt clean; **prod image runtime-verified** (fail-fast on no secret; `/healthz`→ok; `/me` no-token→401).
  - **Decisions:** added `golang-jwt/jwt/v5` (security boundary — no hand-rolled crypto); jwt tests cover bad-signature / expired / `alg=none`. Package `internal/handlers` + `internal/respond` instead of spec's `internal/http` (a `package http` shadows stdlib). Module path per CLAUDE.md (`…/stackbase`, not `…/stackbase/api`).
- ✅ **5. Postgres + migrate Job** — live-validated. `infra/k8s/base/postgres.yaml` (Postgres 16 StatefulSet + headless Service, `microk8s-hostpath` PVC, `pg_isready` probes, password via `secretKeyRef`). `infra/k8s/base/migrate-job.yaml` (waits for pg, then `for f in /migrations/*.sql` with `ON_ERROR_STOP=1`). `db/migrations/0001_init.sql` (idempotent `demo_items`). `make migrate` regenerates the ConfigMap from the **GLOB** (`kubectl create configmap migrations --from-file=db/migrations`, never an explicit `files:` list) then delete+re-applies the immutable Job.
  - **Footgun designed out — proven live:** in a throwaway ns, run1 applied 0001; re-run was idempotent; then dropping a `0002_more.sql` into the dir and regenerating from the glob (NO list edited) auto-applied it → `demo_items|demo_more`. The exact failure mode that dropped nursing-call's 027–029 cannot recur.
  - **Note:** base manifests are raw YAML; `base/kustomization.yaml` + overlays come in Task 7. Storage class is `microk8s-hostpath` (local); prod overlay patches it.
- ✅ **6. Vue frontend** — `services/frontend/` (Vite 6 + Vue 3 + TS). `src/api.ts` (`getHealth`/`getMe`, TDD'd — 3 vitest cases: 200→claims, non-2xx→throw, bearer header sent). `src/App.vue` (health on mount + token→`/me`). `vite.config.ts` (`host:true`, `/api`→api proxy for standalone dev). `Dockerfile` (vite build → nginx + SPA fallback `nginx.conf`) + `Dockerfile.dev` (vite dev) + `.dockerignore`. Verified: `npm run build` compiles the SFC, vitest green, **prod image serves the SPA + fallback 200**. Prod deps: 0 audit vulns (warnings are dev-only tooling).
  - **Notes:** frontend calls `/api/*`; Traefik strips `/api` in the integrated path (Task 7) while the Vite proxy strips it standalone. Vite HMR-behind-Traefik tuning deferred to Task 8 (Tiltfile).
- ✅ **7. kustomize base + overlays/local** — live-validated end-to-end. `base/` = `namespace` + `api` (Deploy+Svc) + `frontend` (Deploy+Svc) + `ingressroute` (Middleware `strip-api` + IngressRoute: `/api`→api stripped, `/`→frontend) + the Task-5 postgres/migrate, tied by `base/kustomization.yaml`. `overlays/local` sets `namespace: stackbase` (knob #1) and rewrites images → `localhost:32000/stackbase-{api,frontend}:dev`. **Live deploy** (built+pushed :dev images, applied overlay to ns `stackbase`): postgres+api+frontend rolled out, migrate created `demo_items`, api Svc `/healthz`→ok & `/me`→401, frontend Svc `/`→200 `<title>stackbase</title>`. Torn down clean.
  - **Decisions:** unified one `app-secrets` Secret (`jwt-secret`, `postgres-password`) — repointed postgres/migrate to it. Frontend container port **5173 in both** images (nginx configured to `listen 5173`) → zero local↔prod port divergence, no overlay patch. Bare image names in base so the overlay (and Task-8 Tilt) retag. The two adopter knobs: `namespace:` (overlay) + ``Host(`…test`)`` (ingressroute).
- ✅ **8. Tiltfile** — live-validated full-stack hot-reload. `docker_build` for api (`live_update=sync(services/api→/app)`, CompileDaemon) + frontend (`sync(services/frontend/src→/app/src)`, Vite HMR); `k8s_yaml(kustomize(overlays/local))`; migrations ConfigMap via `local('kubectl create configmap … --from-file=db/migrations -n stackbase --dry-run=client -o yaml')` (the GLOB); `port_forwards` 18080(fe)/18081(api). Image refs = the overlay's `localhost:32000/…` names, so no `default_registry`. **Proven:** `tilt up` → edit `.go` flipped `/healthz` `ok`→`reloaded` (CompileDaemon in-pod) AND edit `.vue` synced into the SAME frontend pod (Tilt `Will copy 1 file(s) to container` for both, no restart). Torn down clean; source reverted; api tests still green.
- ⛔ **9. R2 object storage — DROPPED** (owner decision, 2026-06-29). Not built; `internal/r2`, `/uploads/presign`, and the Vue upload demo are out of scope. R2 scrubbed from CLAUDE.md / README / design spec.
- ✅ **10. umami** — live-validated. `src/analytics.ts`: `umamiAttrs()` env gate (TDD'd — 3 vitest cases: both unset→null, one set→null, both→attrs) + `initAnalytics()` DOM shim, wired into `main.ts` (`VITE_UMAMI_*` typed in vite-env.d.ts; unset → no-op). `infra/k8s/shared/umami/` (ns `umami`, its own Postgres 16, umami Deploy+Svc with `DATABASE_URL` built from the secret via `$(DB_PASSWORD)` interpolation, IngressRoute `umami.test`). **Live deploy** in ns `umami`: db + umami rolled out (umami self-migrates on boot), `/` and `/api/heartbeat` → 200. Torn down clean.
  - **Note:** umami image is `:postgresql-latest` (commented to pin for prod). Shared install applied via kustomize; a `make umami` convenience target can land in Task 12.
- ✅ **11. overlays/prod** — `overlays/prod/kustomization.yaml` over the same `base/`: images → `ghcr.io/yenchieh/stackbase-{api,frontend}:latest`, JSON6902 patch adding `imagePullPolicy: Always` to both app Deployments, same `app-secrets` refs. **Validated:** `kustomize build` renders; `kubectl apply --dry-run=server` accepted every resource (incl. IngressRoute/Middleware CRDs); `diff local↔prod` shows the delta is ONLY image refs + `imagePullPolicy` → parity guarantee holds.
  - **Left to the adopter (documented in the kustomization, not templated):** real Host() domain, TLS (websecure + certResolver), `make secrets-apply` + `make migrate` on the prod context. Image build/push is Phase-2 CI.
- ✅ **12. Makefile + README polish** — `Makefile` full target set (`cluster-init`, `up`, `down`, `secrets-apply`, `apply`, `deploy`, `migrate`, `umami`) with `KUBECTL`/`NS` overrides + `help`. `secrets.env.example` + `services/frontend/.env.example` templates. README: refined quick start, **the two knobs** table (namespace + Host), make-targets table, status. **Validated:** `make help` + dry-runs parse; **live `make secrets-apply`** created `app-secrets` with correctly-mapped `jwt-secret`/`postgres-password` keys (decoded values verified); `secrets.env` confirmed gitignored.

**Phase 1 done =** `make cluster-init` → use-template → `make up` → edit Go *and* Vue
live at `http://<name>.test`, prod overlay deploys by hand.

## Phase 1.5 — template unification (cross-project audit, 2026-07-07)

Source: parallel audits of **komiic** (`~/go/src/github.com/yenchieh/komiic`), **manyi**
(`~/code/manyi`), **diagramzu** (`~/code/mermaid`), **nursing-call** (`~/code/nursing-call`).
Ranked by how many projects independently carry the pattern — highest duplication first.
stackbase already fixed the big shared pains (per-project Traefik + NodePort/Caddy/MetalLB/
hostPort hacks, /etc/hosts edits, hostPath hot-reload, explicit migration `files:` lists,
build-time analytics baking) — these are the patterns it *missed*:

- ✅ **13 (U1). Prod Postgres backup + restore** — `infra/k8s/overlays/prod/backup/` = pinned+sha256 `mc` Dockerfile (postgres:16-alpine), `backup_script.sh` (pg_dump -Fc → MinIO, retention prune, Discord alert), `restore_script.sh` (operator kubectl-cp+pg_restore), `cronjob.yaml` (every 12h, `concurrencyPolicy: Forbid`). Script mounted via `configMapGenerator` (`disableNameSuffixHash`) so editing it needs no image rebuild. MinIO/Discord keys are OPTIONAL in `app-secrets` (secretKeyRef `optional:true`) — extended `secrets.env.example` + `make secrets-apply`. Backup image uses a **bare `stackbase-backup` name in the prod overlay `images:` list** (post-review fix) so `GH_OWNER` retags it like api/frontend. Rendered clean via `kubectl kustomize overlays/prod`. — the single most-duplicated asset: ALL FOUR
  projects ship a near-identical prod-only CronJob (pg_dump → MinIO/S3, `concurrencyPolicy:
  Forbid`, retention prune, **Discord webhook on failure**) + operator `restore_script.sh`.
  Add to `overlays/prod/backup/` with its own `backup.env` secretGenerator.
  Best copies: `manyi/infra/k8s/overlays/prod/backup/`, `nursing-call/infra/k8s/overlays/production/backup/`,
  diagramzu's has a pinned+sha256-verified `mc` binary (`mermaid/infra/k8s/overlays/prod/backup/Dockerfile`).
- ✅ **14 (U2). Pinned prod deploys + guard rails** — Makefile `prod-build`/`prod-push` (api+frontend+backup, `:latest`+`:<git-sha>` → `$(REGISTRY)`), `deploy` renders `overlays/prod`, **refuses on placeholder hits** (`change-me|replace-me|TODO|<[A-Z_]+>`), then applies at `:$(TAG)`. **Post-review fix:** `TAG` defaults to `latest` so a *standalone* `make deploy` ships the always-pullable tag (no more pinning to an unpushed/tarball SHA); `prod-deploy` = build+push then `deploy TAG=$(SHA)` for an immutable, rollback-able release. `PROD_KUBECONFIG ?=` knob (`--kubeconfig` on prod apply). `_guard-local-context` prereq on `apply` verifies the kube API server is this machine/a private address (escape: `GUARD_OK=1`). Verified: guard no-false-positive; `:latest` default + SHA pin both render correctly. **Owner decision (2026-07-08): keep `prod-build`/`prod-push`** — they're the manual pre-CI build/push path (isolated in `prod-deploy`); Phase-2 CI just automates them, it doesn't replace them. — manyi + diagramzu both: build/push
  `:latest`+`:<git-sha>`, then `make deploy` sed-rewrites the *rendered* kustomize output
  `:latest`→`:<sha>` (immutable deploys, `kubectl set image` rollback, no CI needed) and
  **refuses to apply if the render contains placeholders** (`replace-me|TODO|empty`).
  Add nursing-call's `_guard-local-context` (verify kube API endpoint is THIS machine before
  any local apply/destroy; `nursing-call/Makefile:422`) + `PROD_KUBECONFIG ?=` knob.
- ✅ **15 (U3). Day-2 ops make targets** — added `status` (pods/svc/ingressroute), `logs SERVICE=`, `shell SERVICE=`, `restart [SERVICE=]`, `port-forward SERVICE= LOCAL= REMOTE=`, `events`, `validate` (render + `apply --dry-run=server`, `OVERLAY=`), `diff` (`kubectl diff -k`), `health` (curl `$(HEALTH_URL)` expect 200; comment notes the 401-as-routing-proof trick). All show in `make help`. — komiic + nursing-call converged on the same kubectl
  wrapper vocabulary stackbase lacks: `k8s-status / logs SERVICE= / shell / restart /
  port-forward / events / validate / diff / health`. `validate` = render +
  `kubectl apply --dry-run=server` (currently only a CLAUDE.md convention — make it a target);
  `health` = post-deploy curl smoke (diagramzu's "no creds → assert 401 challenge" trick).
  References: `komiic/infra/k8s/production/Makefile`, `nursing-call/Makefile`, `mermaid/Makefile`.
- ✅ **16 (U4). Prod PVC data-loss insurance** — `overlays/prod/storageclass-retain.yaml` (`stackbase-hostpath-retain`, `provisioner: microk8s.io/hostpath`, `reclaimPolicy: Retain`) + JSON6902 patch repointing the postgres `volumeClaimTemplate` storageClassName in prod only (local stays `microk8s-hostpath`). Verified via render. Note baked into the manifest: storageClassName is immutable on an existing PVC, so it must be set on the FIRST prod deploy. — manyi's one-file `Retain` StorageClass +
  prod-overlay PVC patch (`manyi/infra/k8s/overlays/prod/storageclass-retain.yaml`) so
  `kubectl delete -k` can't wipe the DB. diagramzu documents the same gap unfixed ("consider
  a Retain PV"). stackbase prod currently inherits hostpath Delete reclaim.
- ✅ **17 (U5). Graceful-secrets convention** — demonstrated by the backup CronJob (`optional: true`
  MinIO/Discord refs) and documented adopter-facing: `secrets.env.example` (required vs optional keys),
  README "Secrets & config conventions" (optional-key rationale + the **secret/config change does NOT
  roll pods → `make restart`** gotcha), and a matching reminder printed by `make secrets-apply`.
  — diagramzu + nursing-call: `secretKeyRef.optional:
  true` for optional integrations so pods boot pre-provisioning and features degrade
  (vs `CreateContainerConfigError`). Document the shared gotcha (manyi + nursing-call):
  a secret/config-only change does NOT roll pods → either document `rollout restart` or add
  a checksum annotation.
- ✅ **18 (U6). Tiltfile hardening** — added `fall_back_on(['services/api/go.mod','go.sum'])` and
  `fall_back_on(['services/frontend/package.json','package-lock.json'])` so a dep change forces a real
  image rebuild instead of syncing a broken graph. Added a lean `resources` block to `base/api.yaml`
  (req cpu 50m/64Mi, **memory-only limit 512Mi — NO cpu limit**, post-review fix so a CPU cap can't
  throttle the local in-pod `go build`) and a **local-overlay patch raising the memory limit to 1Gi**
  so the CompileDaemon compile doesn't OOM (prod keeps 512Mi). Verified: local=1Gi, prod=512Mi, no cpu
  limit on api, Tiltfile passes `tilt alpha tiltfile-result`. — manyi's refinements: `fall_back_on(go.mod/go.sum/lockfiles)`
  → full image rebuild (sync alone can't handle dep changes), and a local-overlay resource
  bump for the api dev pod (in-pod `go build` OOMs at the 512Mi runtime limit — manyi needed
  2Gi; `manyi/infra/k8s/overlays/local/kustomization.yaml`).
- ✅ **19 (U7). Seed-data slot** — `services/api/cmd/seed/main.go`: idempotent Go CLI (`database/sql`
  + `lib/pq`, added as a direct dep), inserts a deterministic demo set into `demo_items` via
  `INSERT … WHERE NOT EXISTS` (re-runnable; name isn't UNIQUE so no ON CONFLICT). Reads `DATABASE_URL`
  (localhost dev fallback). `make seed` = host `go run ./cmd/seed`; `make k8s-seed` execs the api pod
  (`/seed` baked-binary, else `go run` in the dev image — so it's the local/dev path; prod seeds via
  host `make seed`). Verified: builds, vets, all api tests green, runs with a clean fatal on an
  unreachable DB. Idempotency check = run `make seed` twice (2nd run reports "0 inserted").
  — nursing-call: idempotent Go seed CLI (`cmd/seed*`, deterministic
  demo login) + `make seed` (host, against DATABASE_URL) and `make k8s-seed` (kubectl exec,
  baked-binary vs `go run` auto-detect). stackbase has migrations but no seed story.
- ✅ **20 (U8). Patterns doc + AGENTS.md** — `docs/patterns.md` (off-cluster GPU via Cloudflare Tunnel,
  multi-binary Go image reused by a CronJob, Alertmanager→chat-webhook paging, umami two-phase bootstrap
  — each as shape + where-to-copy, explicitly "don't pre-build") and `AGENTS.md` (vendor-neutral agent
  contract: per-service + ops commands, Go/migration/kustomize/secrets style, commit prefixes incl.
  `deploy(k8s):`, and the PR rule to flag migration/secret/k8s impacts). — capture the non-core recipes as docs, not code:
  off-cluster GPU service via Cloudflare Tunnel (manyi `deploy/cloudflared-config.yml.example`),
  multi-binary Go image reused by CronJobs (diagramzu `cancel-overdue`, nursing-call api/admin-api),
  Alertmanager→chat-webhook paging (komiic `infra/line-alert-webhook`), umami two-phase
  bootstrap runbook (manyi `deploy/README.md`). Plus an `AGENTS.md` in the nursing-call shape
  (commands, commit prefixes, "call out migration/secret/k8s impacts in PRs").

## Phase 2 — deferred (each its own small spec)

- ⬜ gRPC — proto + `buf` codegen + a second service (topology TBD: Go↔Go vs connect/grpc-web).
  *Audit input:* nursing-call's shared-module recipe works today — `go.work` + per-module
  `replace ../platform`, `GOWORK=off` in Docker, build context = `services/`; komiic scales
  the same idea to 26 modules.
- ⬜ Prod CI — **automate** the GHCR build/push + secret bootstrap. NOTE: the *manual*
  build/push path already landed in Task 14 (`make prod-build`/`prod-push`, `:latest`+`:<sha>`);
  CI's job is only to run it on push, not to invent it. Shape to copy: komiic is the only
  project with CI — a reusable `_go-service.yml` workflow + ~15-line per-service callers,
  path-filtered on `services/<name>/**` AND the shared lib, plus one workspace-wide vet/build
  safety net (`komiic/.github/workflows/`). CI builds+pushes images only; humans still apply
  manifests via `make deploy` / `prod-deploy` (pairs with U2's SHA pinning).
- ⬜ Full auth/user module — login, users table, password reset (the `platform`-style library).
- ⬜ Migrate existing projects onto the shared Traefik — now **four** cutovers, each retiring
  a different per-project hack: nursing-call (NodePort 31080 + host Caddy on :80),
  manyi (NodePort 31278 + host Caddy), diagramzu (MetalLB LoadBalancer + manual /etc/hosts),
  komiic (hostPort 80/443 + nodeSelector pin + interactive /etc/hosts script). Retiring these
  frees `:80` → unblocks the deferred live `make cluster-init` apply (Task 3).
