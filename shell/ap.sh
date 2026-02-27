#!/usr/bin/env bash
set -euo pipefail

info() { echo "[INFO] $*"; }
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
# nodejs-fn-template , nodejs-bn-template
# values.nodejs-fn-template.yaml , values.nodejs-bn-template.yaml

APP_NAME="${APP_NAME:-nodejs-fn-template}"
NAMESPACE="${NAMESPACE:-nodejs-fn-template}"
VALUES_FILE="${VALUES_FILE:-values.nodejs-fn-template.yaml}"
REPO_URL="${REPO_URL:-https://github.com/LinX9581/nodejs-helm-template}"
PATH_IN_REPO="${PATH_IN_REPO:-.}"

info "Step 1/4 建立並標記 namespace"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml \
  | kubectl label -f - observability=enabled --local -o yaml \
  | kubectl apply -f -

info "Step 2/4 建立或更新 ArgoCD App"
argocd app create "$APP_NAME" \
  --repo "$REPO_URL" \
  --path "$PATH_IN_REPO" \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace "$NAMESPACE" \
  --values "$VALUES_FILE" \
  --upsert

info "Step 3/4 同步並等待 ArgoCD App Healthy"
argocd app sync "$APP_NAME"
argocd app wait "$APP_NAME" --health --sync --timeout 600

info "Step 4/4 完成"
echo "App: ${APP_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "Values: ${VALUES_FILE}"
echo "Otel 設定請於 values 檔控制（otel.enabled / otel.instrumentation.enabled）"
