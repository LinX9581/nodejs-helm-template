# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a shared Helm chart (`nodejs-helm-template`) for deploying Node.js applications on GKE. A single chart is maintained, and each project gets its own `values.<app-name>.yaml` file. Deployment is managed via GitHub + ArgoCD.

## Common Commands

### Helm lint / template rendering
```bash
helm lint . -f values.nodejs-fn-template.yaml
helm template my-release . -f values.nodejs-fn-template.yaml
```

### Deploy a new app via ArgoCD
```bash
APP_NAME=nodejs-fn-template NAMESPACE=nodejs-fn-template VALUES_FILE=values.nodejs-fn-template.yaml bash ./shell/ap.sh
```

### Manage Kubernetes Secrets

Secrets are out-of-band from GitOps (not committed to git). Create a `.env.<app>` file from the example, fill in values, then run the script. It applies the secret and triggers a rollout restart.

```bash
cp .env.fn.example .env.fn
# edit .env.fn with real values

NAMESPACE=nodejs-fn-template \
SECRET_NAME=nodejs-fn-template-secrets \
ENV_FILE=.env.fn \
DEPLOYMENT=nodejs-fn-template-nodejs-helm-template \
bash ./manage-nodejs-secrets.sh
```

`.env.*` files are gitignored. Only `.env.*.example` (empty values) are committed.

### Install / set up ArgoCD
```bash
bash ./shell/argocd.sh
```

## Architecture

### Chart Structure
- `values.project-template.yaml` — master template to copy when creating a new project
- `values.<app-name>.yaml` — per-project overrides
- `templates/`:
  - `deployment.yaml` — Deployment with configmap checksum annotation, OTel injection, `envFrom` (ConfigMap + Secrets)
  - `httproute.yaml` — Gateway API `HTTPRoute` resources (main routes + redirect routes)
  - `healthcheckpolicy.yaml` — GKE `HealthCheckPolicy` CRD (only when `healthCheckPolicy.enabled: true`)
  - `hpa.yaml` — HorizontalPodAutoscaler
  - `configmap.yaml` — non-sensitive env vars
  - `_helpers.tpl` — named template helpers (`fullname`, `labels`, `selectorLabels`, `configMapName`)

### Key Design Patterns

**Gateway API (not Ingress):** Traffic routing uses `gateway.networking.k8s.io/v1 HTTPRoute` attached to a Traefik gateway (`gatewayName: traefik-gateway`, `gatewayNamespace: traefik`). Configure routes in `gateway.routes`, path-level rules in `gateway.rules`, and domain redirects in `gateway.redirectRoutes`.

**Environment config split:**
- Non-sensitive vars → `configMap.data` → mounted via `envFrom.configMap`
- Sensitive vars → Kubernetes Secret (managed via `manage-nodejs-secrets.sh`) → referenced in `envFrom.secretRefs`

**OTel auto-instrumentation:** When `otel.enabled: true`, the deployment gets annotation `instrumentation.opentelemetry.io/inject-nodejs: "true"`, triggering the OpenTelemetry Operator to inject the SDK. The `Instrumentation` CR is managed by the platform team, not this chart.

**Health check endpoint:** Liveness and readiness probes both use `/pod-health`. The optional `HealthCheckPolicy` CRD (`healthCheckPolicy.enabled: true`) configures GKE's backend health check separately.

**Node scheduling:** App workloads target `nodeSelector: workload: app`. ArgoCD/system workloads use `workload: system` with a `dedicated=system:NoSchedule` toleration.

**Namespace observability label:** Namespaces must be labeled `observability=enabled` for Alloy log collection. Handled automatically by `shell/ap.sh`.

### Creating a New Project
1. `cp values.project-template.yaml values.<myapp>.yaml` and update `image`, `service.port`, `application.port`, `gateway.routes`, `configMap.data`, `envFrom.secretRefs`
2. Create `.env.<myapp>.example` with empty keys and `.env.<myapp>` with real values
3. Run `shell/ap.sh` to create the ArgoCD app
4. Run `manage-nodejs-secrets.sh` to apply the initial secret
