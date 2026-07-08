# stackbase dev loop — `make up` runs this. Both Go and Vue live-reload on save.
# Prereqs (once): `make cluster-init` (shared Traefik), `make secrets-apply` (app-secrets).
#
# Image names match overlays/local's localhost:32000 refs, so Tilt builds, pushes
# to the MicroK8s registry, and substitutes them — no default_registry needed.

docker_build(
    'localhost:32000/stackbase-api', 'services/api',
    dockerfile='services/api/Dockerfile.dev',
    live_update=[
        # A dep change can't be hot-synced (go.sum drives the build) — force a full
        # image rebuild instead of syncing a broken module graph into the pod.
        fall_back_on(['services/api/go.mod', 'services/api/go.sum']),
        sync('services/api', '/app'),                     # edit .go -> CompileDaemon rebuilds in-pod
    ],
)

docker_build(
    'localhost:32000/stackbase-frontend', 'services/frontend',
    dockerfile='services/frontend/Dockerfile.dev',
    live_update=[
        # Same rule for JS deps: a package.json/lock change needs a real npm install.
        fall_back_on(['services/frontend/package.json', 'services/frontend/package-lock.json']),
        sync('services/frontend/src', '/app/src'),        # edit src/ -> Vite HMR; node_modules untouched
    ],
)

# The same overlay `make apply` uses — local==prod manifests.
k8s_yaml(kustomize('infra/k8s/overlays/local'))

# Migrations ConfigMap generated from the GLOB over db/migrations (never a static
# file list — that's the inherited footgun). Mirrors `make migrate`.
k8s_yaml(local(
    'kubectl create configmap migrations --from-file=db/migrations -n stackbase --dry-run=client -o yaml',
    quiet=True,
))

# Until the shared Traefik owns :80, reach the services directly.
# (Integrated routing is http://<name>.test via the IngressRoute.)
k8s_resource('frontend', port_forwards='18080:5173')
k8s_resource('api', port_forwards='18081:8080')
