#!/usr/bin/env bash
set -euo pipefail

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "缺少必要指令: $1"
    exit 1
  }
}

need_cmd kubectl
need_cmd argocd

# 常用的 NS 和 values
# nodejs-helm-template , nodejs-helm-bn-template
# values.nodejs-helm-fn-template.yaml , values.nodejs-helm-bn-template.yaml

APP_NAME="${APP_NAME:-nodejs-helm-fn-template}"
NAMESPACE="${NAMESPACE:-nodejs-helm-fn-template}"
VALUES_FILE="${VALUES_FILE:-values.nodejs-helm-fn-template.yaml}"
REPO_URL="${REPO_URL:-https://github.com/LinX9581/nodejs-helm-template}"
PATH_IN_REPO="${PATH_IN_REPO:-.}"
ENABLE_TEMPO="${ENABLE_TEMPO:-Y}"

info "Step 1/6 建立並標記 namespace"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml \
  | kubectl label -f - observability=enabled --local -o yaml \
  | kubectl apply -f -

info "Step 2/6 建立或更新 ArgoCD App"
argocd app create "$APP_NAME" \
  --repo "$REPO_URL" \
  --path "$PATH_IN_REPO" \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace "$NAMESPACE" \
  --values "$VALUES_FILE" \
  --upsert

info "Step 3/6 同步並等待 ArgoCD App Healthy"
argocd app sync "$APP_NAME"
argocd app wait "$APP_NAME" --health --sync --timeout 600

if [[ "$ENABLE_TEMPO" =~ ^[Yy]$ ]]; then
  info "Step 4/6 套用 OpenTelemetry Instrumentation"
  kubectl apply -n "$NAMESPACE" -f - <<EOF
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: otel-instrumentation
spec:
  exporter:
    endpoint: http://otel-collector-opentelemetry-collector.observability.svc.cluster.local:4318
  propagators:
    - tracecontext
    - baggage
  sampler:
    type: parentbased_traceidratio
    argument: "1"
  nodejs:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:latest
    env:
      - name: OTEL_EXPORTER_OTLP_PROTOCOL
        value: http/protobuf
      - name: OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
        value: http://otel-collector-opentelemetry-collector.observability.svc.cluster.local:4318/v1/traces
      - name: OTEL_SERVICE_NAME
        value: ${NAMESPACE}
      - name: OTEL_METRICS_EXPORTER
        value: otlp
      - name: OTEL_EXPORTER_OTLP_METRICS_ENDPOINT
        value: http://otel-collector-opentelemetry-collector.observability.svc.cluster.local:4318/v1/metrics
EOF

  DEPLOYMENT="$(kubectl -n "$NAMESPACE" get deploy -l app.kubernetes.io/instance="$APP_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -z "$DEPLOYMENT" ]]; then
    DEPLOYMENT="$(kubectl -n "$NAMESPACE" get deploy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  fi

  if [[ -z "$DEPLOYMENT" ]]; then
    warn "找不到 deployment，略過注入 patch/restart。"
  else
    info "Step 5/6 Patch deployment annotation + rollout restart: ${NAMESPACE}/${DEPLOYMENT}"
    kubectl -n "$NAMESPACE" patch deploy "$DEPLOYMENT" --type merge -p \
      '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-nodejs":"true"}}}}}'
    kubectl -n "$NAMESPACE" rollout restart "deploy/${DEPLOYMENT}"
    kubectl -n "$NAMESPACE" rollout status "deploy/${DEPLOYMENT}" --timeout=600s
  fi
else
  info "Step 4-5/6 已略過 Tempo 注入流程 (ENABLE_TEMPO=${ENABLE_TEMPO})"
fi

info "Step 6/6 完成"
echo "App: ${APP_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "Values: ${VALUES_FILE}"
echo "ENABLE_TEMPO: ${ENABLE_TEMPO}"
if [[ "$ENABLE_TEMPO" =~ ^[Yy]$ ]]; then
  echo "Tempo traces 應已開始進入 (通常需 1-3 分鐘可在 Grafana 查到)"
else
  echo "Tempo 注入未啟用"
fi
