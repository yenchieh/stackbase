# Patterns — recipes stackbase deliberately does NOT ship as code

stackbase is a lean template. These are patterns proven in the sibling projects
(komiic, manyi, diagramzu, nursing-call) that you'll want *eventually* but that
would be dead weight in a fresh clone. Each entry is the shape + where to copy it
from, so you add it only when a real need shows up. Don't pre-build these.

---

## Off-cluster service via Cloudflare Tunnel (GPU / heavyweight / can't-be-in-k8s)

When one component can't live in the cluster — a GPU box, a huge ML model, a
license-locked binary — run it on its own host and expose it to the cluster
through a Cloudflare Tunnel instead of poking a hole in the firewall.

- Component runs under docker-compose on the host; `cloudflared` publishes it at
  `https://<svc>.<domain>` (a Named Tunnel, no inbound ports).
- In-cluster services call that hostname like any other upstream.
- **Trap (manyi):** if the same container serves both local dev and prod through
  one tunnel, rebuilding it for dev *is* a prod deploy. Give dev and prod separate
  tunnels/hostnames, or accept that rebuild = deploy and document it loudly.
- Copy from: `manyi/deploy/cloudflared-config.yml.example`, `manyi/deploy/cloudflared.service`,
  `manyi/scripts/translator.sh` (up/down/health wrapper).

## Multi-binary Go image reused by a CronJob / second workload

One image, one build, several entrypoints — cheaper than a second service when the
extra workload shares the app's code and deps.

- Build several `cmd/<x>` binaries into one image (or a distroless image with the
  main binary + a small command override).
- A CronJob (or a second Deployment) runs the same image with a different
  `command:`/args. One `images:` entry in kustomize covers both.
- Examples: diagramzu's `cancel-overdue` CronJob reuses the go-api image; nursing-call
  runs `api` and `admin-api` from one image (different binary at runtime).
- stackbase already leans this way: `services/api/cmd/{server,seed}` are two binaries
  in one module — a CronJob could run `cmd/seed` or a future `cmd/reaper` off the
  same image with a command override.

## Alertmanager → chat-webhook paging

Cheap paging without a paging vendor: a tiny receiver that forwards Prometheus
Alertmanager alerts to Discord/Slack/LINE.

- MicroK8s `observability` addon gives you Prometheus + Alertmanager.
- An `AlertmanagerConfig` (prometheus-operator CRD) routes to a webhook receiver:
  either a ~30-line Go service (komiic's `infra/line-alert-webhook`) or, for
  Discord/Slack, a direct webhook receiver.
- The backup CronJob (U1) already uses the same idea inline — `DISCORD_WEBHOOK` on
  failure. Reuse that env for a shared alert sink.
- Copy from: `komiic/infra/line-alert-webhook/`, `nursing-call` observability notes.

## umami analytics — two-phase bootstrap

`make umami` installs the shared analytics stack, but the website ID that the Vue
snippet needs doesn't exist until umami is up. So it's inherently two-phase:

1. `make umami` (deploy umami + its Postgres), log in, **create the website** in the
   umami UI → get its UUID.
2. Set `VITE_UMAMI_WEBSITE_ID` (+ `VITE_UMAMI_SRC`) in the frontend env and redeploy
   the frontend. stackbase reads these **at runtime** (env-gated in `src/analytics.ts`),
   so it's a config change + `make restart SERVICE=frontend`, NOT an image rebuild.
- Contrast (manyi): manyi bakes the UUID at image build time (`--build-arg`), which
  forces a rebuild+redeploy to change it. stackbase's runtime gating is the fix — keep it.
- Copy the runbook prose from: `manyi/deploy/README.md`.

---

Anything here graduates to real code the day you actually need it — at which point
add it to `ROADMAP.md` as its own task and delete its entry from this file.
