# stackbase Makefile — the only hands-on steps live here. Code + manifests apply
# automatically while `tilt up` runs; these targets wrap the kubectl-touching bits.
#
# KUBECTL override lets MicroK8s users skip wiring a kubeconfig:
#   make <target> KUBECTL="microk8s kubectl"
# NS must match `namespace:` in infra/k8s/overlays/{local,prod} (the project knob).
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

KUBECTL  ?= kubectl
NS       ?= stackbase
GH_OWNER ?= yenchieh
REGISTRY ?= ghcr.io/$(GH_OWNER)
# Immutable image tag = the current commit (falls back to :latest outside git).
SHA      := $(shell git rev-parse --short HEAD 2>/dev/null || echo latest)
# TAG is what `deploy` pins images to. Default `latest` = the always-pullable tag
# `prod-push` keeps current, so a standalone `make deploy` is safe. `prod-deploy`
# overrides it to the just-pushed SHA for an immutable, rollback-able release.
TAG      ?= latest
# Set PROD_KUBECONFIG to force prod targets at a specific cluster (a guard against
# deploying to the wrong context). Empty = use the current kube-context.
PROD_KUBECONFIG ?=
PROD_KUBECTL := $(KUBECTL)$(if $(PROD_KUBECONFIG), --kubeconfig=$(PROD_KUBECONFIG),)

OVERLAY ?= local
HEALTH_URL ?= http://stackbase.test/api/healthz

.DEFAULT_GOAL := help
.PHONY: help cluster-init up down secrets-apply apply deploy migrate umami \
        prod-build prod-push prod-deploy \
        status logs shell restart port-forward events validate diff health \
        seed k8s-seed _guard-local-context

help: ## list targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

## --- lifecycle -------------------------------------------------------------

cluster-init: ## one-time per machine: install shared Traefik (CRDs+RBAC+Deployment). Idempotent.
	$(KUBECTL) apply -f infra/cluster/traefik/
	@echo
	@echo ">> Shared Traefik applied (namespace 'ingress', owns hostPort 80/443)."
	@echo ">> Last step is wildcard DNS for *.test — one line, see infra/cluster/dnsmasq.md:"
	@echo "       address=/test/127.0.0.1"

up: ## dev loop: tilt up (build, deploy, live-reload Go + Vue)
	tilt up

down: ## stop the dev loop
	tilt down

secrets-apply: ## build the app-secrets Secret from secrets.env into the project namespace
	$(KUBECTL) create namespace $(NS) --dry-run=client -o yaml | $(KUBECTL) apply -f -
	set -a; . ./secrets.env; set +a; \
	$(KUBECTL) create secret generic app-secrets -n $(NS) \
	  --from-literal=jwt-secret="$$JWT_SECRET" \
	  --from-literal=postgres-password="$$POSTGRES_PASSWORD" \
	  --from-literal=minio-endpoint="$${MINIO_ENDPOINT:-}" \
	  --from-literal=minio-access-key="$${MINIO_ACCESS_KEY:-}" \
	  --from-literal=minio-secret-key="$${MINIO_SECRET_KEY:-}" \
	  --from-literal=discord-webhook="$${DISCORD_WEBHOOK:-}" \
	  --dry-run=client -o yaml | $(KUBECTL) apply -f -
	@echo ">> app-secrets updated. NOTE: a secret change does NOT roll running pods —"
	@echo ">> run 'make restart' (or 'make restart SERVICE=api') to pick up new values."

apply: _guard-local-context ## one-shot deploy of overlays/local without Tilt (pair with secrets-apply + migrate)
	$(KUBECTL) apply -k infra/k8s/overlays/local

migrate: ## (re)run migrations: regenerate ConfigMap from db/migrations GLOB, then delete + re-apply the immutable Job
	$(KUBECTL) create configmap migrations --from-file=db/migrations -n $(NS) --dry-run=client -o yaml | $(KUBECTL) apply -f -
	$(KUBECTL) delete job migrate -n $(NS) --ignore-not-found
	$(KUBECTL) apply -f infra/k8s/base/migrate-job.yaml -n $(NS)

umami: ## optional one-time: install the shared umami (create the 'umami' secret first — see README)
	$(KUBECTL) apply -k infra/k8s/shared/umami

## --- seed data -------------------------------------------------------------

# Postgres is a headless in-cluster StatefulSet (no host port), so host `make seed`
# needs a route to it: either run `make port-forward SERVICE=postgres LOCAL=5432
# REMOTE=5432` in another shell, or pass a reachable DATABASE_URL=... explicitly.
seed: ## seed demo data via host `go run` (needs a reachable DATABASE_URL — see comment)
	cd services/api && go run ./cmd/seed

# Dev/local convenience: runs the seed inside the api DEV pod (which has go + the
# synced source). The PROD api image is distroless (no shell/go) — seed prod from
# a workstation with `make seed` + a port-forward instead.
k8s-seed: ## seed demo data inside the (dev) api pod via `go run`
	@pw=$$($(KUBECTL) get secret app-secrets -n $(NS) -o jsonpath='{.data.postgres-password}' | base64 -d); \
	pod=$$($(KUBECTL) get pod -n $(NS) -l app=api -o name | head -1 || true); \
	url="postgres://stackbase:$$pw@postgres:5432/stackbase?sslmode=disable"; \
	echo ">> seeding via $$pod"; \
	$(KUBECTL) exec -n $(NS) $$pod -- sh -c "cd /app && DATABASE_URL='$$url' go run ./cmd/seed"

## --- prod build / deploy ---------------------------------------------------

prod-build: ## build prod images (api, frontend, backup) tagged :latest + :<git-sha>
	docker build -t $(REGISTRY)/stackbase-api:latest      -t $(REGISTRY)/stackbase-api:$(SHA)      services/api
	docker build -t $(REGISTRY)/stackbase-frontend:latest -t $(REGISTRY)/stackbase-frontend:$(SHA) services/frontend
	docker build -t $(REGISTRY)/stackbase-backup:latest   -t $(REGISTRY)/stackbase-backup:$(SHA)   infra/k8s/overlays/prod/backup

prod-push: ## push prod images (:latest + :<git-sha>) to $(REGISTRY)
	for img in stackbase-api stackbase-frontend stackbase-backup; do \
	  docker push $(REGISTRY)/$$img:latest; \
	  docker push $(REGISTRY)/$$img:$(SHA); \
	done

deploy: ## prod deploy: render overlays/prod, guard placeholders, apply at :$(TAG) (default latest)
	@render=$$($(KUBECTL) kustomize infra/k8s/overlays/prod); \
	if echo "$$render" | grep -Eq 'change-me|replace-me|TODO|<[A-Z_]+>'; then \
	  echo ">> refusing to deploy — placeholder value(s) in the rendered manifests:"; \
	  echo "$$render" | grep -En 'change-me|replace-me|TODO|<[A-Z_]+>'; \
	  exit 1; \
	fi; \
	echo "$$render" | sed 's|\(stackbase-[a-z]*\):latest|\1:$(TAG)|g' | $(PROD_KUBECTL) apply -f -
	@echo ">> deployed overlays/prod at :$(TAG)."
	@[ "$(TAG)" = "latest" ] && echo ">> (standalone deploy uses :latest — run 'make prod-deploy' to build, push, and pin to the git SHA)" || echo ">> pinned to :$(TAG) — rollback: 'make deploy TAG=<older-sha>'"

prod-deploy: prod-build prod-push ## full prod pipeline: build + push, then pin the deploy to this commit's SHA
	@$(MAKE) deploy TAG=$(SHA)

## --- day-2 ops -------------------------------------------------------------

status: ## pods / services / ingressroutes in the namespace
	$(KUBECTL) get pods,svc,ingressroute -n $(NS)

logs: ## tail a service's logs: make logs SERVICE=api
	$(KUBECTL) logs -n $(NS) -l app=$(SERVICE) --tail=200 -f

shell: ## exec a shell in a pod: make shell SERVICE=api
	$(KUBECTL) exec -it -n $(NS) $$($(KUBECTL) get pod -n $(NS) -l app=$(SERVICE) -o name | head -1) -- /bin/sh

restart: ## rollout restart (default api+frontend, or make restart SERVICE=api)
	@if [ -n "$(SERVICE)" ]; then \
	  $(KUBECTL) rollout restart deploy/$(SERVICE) -n $(NS); \
	else \
	  $(KUBECTL) rollout restart deploy/api deploy/frontend -n $(NS); \
	fi

port-forward: ## forward a service port: make port-forward SERVICE=api LOCAL=18081 REMOTE=8080
	$(KUBECTL) port-forward -n $(NS) svc/$(SERVICE) $(LOCAL):$(REMOTE)

events: ## recent namespace events (sorted)
	$(KUBECTL) get events -n $(NS) --sort-by=.lastTimestamp

validate: ## render overlays/$(OVERLAY) + server-side dry-run (needs the namespace to exist)
	$(KUBECTL) kustomize infra/k8s/overlays/$(OVERLAY) | $(KUBECTL) apply --dry-run=server -f -

diff: ## show what overlays/$(OVERLAY) would change against the live cluster
	$(KUBECTL) diff -k infra/k8s/overlays/$(OVERLAY) || true

health: ## smoke: GET $(HEALTH_URL) expect 200 (an unauth /me returning 401 also proves routing)
	@# `|| true` so a transport error (curl exit 7 on connection-refused) doesn't
	@# abort under .SHELLFLAGS set -e before we print the diagnostic line. curl still
	@# writes '000' via -w on failure, so $$code is meaningful either way.
	@code=$$(curl -s -o /dev/null -w '%{http_code}' "$(HEALTH_URL)" || true); \
	echo "GET $(HEALTH_URL) -> $$code"; \
	[ "$$code" = "200" ] || { echo ">> unhealthy"; exit 1; }

## --- guards ----------------------------------------------------------------

# Verify the current kube API server is THIS machine (or a private address)
# before applying local :dev images — cheap insurance against nuking a prod
# cluster with a local overlay. Escape hatch: make apply GUARD_OK=1
_guard-local-context:
	@server=$$($(KUBECTL) config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true); \
	host=$$(echo "$$server" | sed -E 's|https?://||; s|[:/].*||'); \
	case "$$host" in \
	  127.0.0.1|localhost|10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) : ;; \
	  *) if ! echo " $$(hostname -I 2>/dev/null) " | grep -q " $$host "; then \
	       echo ">> refusing local apply: kube API server '$$host' isn't this machine or a private address."; \
	       echo ">>   current context: $$($(KUBECTL) config current-context 2>/dev/null)"; \
	       echo ">>   if this really is your local cluster: make $(MAKECMDGOALS) GUARD_OK=1"; \
	       [ -n "$${GUARD_OK:-}" ] || exit 1; \
	     fi ;; \
	esac
