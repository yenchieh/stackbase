# stackbase Makefile — the only hands-on steps live here. Code + manifests apply
# automatically while `tilt up` runs; these targets wrap the kubectl-touching bits.
#
# KUBECTL override lets MicroK8s users skip wiring a kubeconfig:
#   make <target> KUBECTL="microk8s kubectl"
# NS must match `namespace:` in infra/k8s/overlays/{local,prod} (the project knob).
KUBECTL ?= kubectl
NS      ?= stackbase

.DEFAULT_GOAL := help

.PHONY: help cluster-init up down secrets-apply apply deploy migrate umami

help: ## list targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

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
	  --dry-run=client -o yaml | $(KUBECTL) apply -f -

apply: ## one-shot deploy of overlays/local without Tilt (pair with secrets-apply + migrate)
	$(KUBECTL) apply -k infra/k8s/overlays/local

deploy: ## prod deploy: apply overlays/prod (run secrets-apply + migrate against the prod context)
	$(KUBECTL) apply -k infra/k8s/overlays/prod

migrate: ## (re)run migrations: regenerate ConfigMap from db/migrations GLOB, then delete + re-apply the immutable Job
	$(KUBECTL) create configmap migrations --from-file=db/migrations -n $(NS) --dry-run=client -o yaml | $(KUBECTL) apply -f -
	$(KUBECTL) delete job migrate -n $(NS) --ignore-not-found
	$(KUBECTL) apply -f infra/k8s/base/migrate-job.yaml -n $(NS)

umami: ## optional one-time: install the shared umami (create the 'umami' secret first — see README)
	$(KUBECTL) apply -k infra/k8s/shared/umami
