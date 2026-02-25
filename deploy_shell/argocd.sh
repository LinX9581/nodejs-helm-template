#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# ArgoCD 安裝 + 登入
# ============================================================

info()  { echo "[INFO] $*"; }
warn()  { echo "[WAIT] $*" >&2; }
err()   { echo "[ERROR] $*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "缺少必要指令: $1"
    exit 1
  }
}

need_cmd kubectl
need_cmd gcloud
need_cmd argocd

ARGOCD_VERSION="${ARGOCD_VERSION:-v2.11.7}"
PROJECT_ID="${PROJECT_ID:-nownews-terraform}"
REGION="${REGION:-${GCP_REGION:-asia-east1}}"
STATIC_IP_NAME="${STATIC_IP_NAME:-argocd-server-ip}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_SERVER_SVC="${ARGOCD_SERVER_SVC:-argocd-server}"

if [[ -z "$PROJECT_ID" ]]; then
  err "找不到 PROJECT_ID。請設定環境變數 PROJECT_ID，或先執行: gcloud config set project <PROJECT_ID>"
  exit 1
fi

if [[ -z "$REGION" ]]; then
  err "找不到 REGION。請設定 REGION (例如: asia-east1)，或先執行: gcloud config set compute/region <REGION>"
  exit 1
fi

wait_for_endpoint() {
  local resource=$1 ns=$2 endpoint=""
  warn "等待 $resource 取得外部端點..."
  while [[ -z "$endpoint" ]]; do
    endpoint="$(kubectl get "$resource" -n "$ns" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [[ -z "$endpoint" ]]; then
      endpoint="$(kubectl get "$resource" -n "$ns" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    fi
    sleep 5
  done
  echo "$endpoint"
}

# ---------- 安裝 ArgoCD ----------
info "安裝 ArgoCD..."
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "$ARGOCD_NAMESPACE" --server-side --force-conflicts -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

warn "等待 ArgoCD pods 就緒..."
kubectl wait --for=condition=Ready pod --all -n "$ARGOCD_NAMESPACE" --timeout=300s

# ---------- 先建立/重用 GKE Static IP ----------
if gcloud compute addresses describe "$STATIC_IP_NAME" --region "$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; then
  info "重用既有 static IP resource: $STATIC_IP_NAME"
else
  info "建立 static IP resource: $STATIC_IP_NAME"
  gcloud compute addresses create "$STATIC_IP_NAME" \
    --region "$REGION" \
    --network-tier PREMIUM \
    --project "$PROJECT_ID"
fi

STATIC_IP="$(gcloud compute addresses describe "$STATIC_IP_NAME" --region "$REGION" --project "$PROJECT_ID" --format='value(address)')"

# ---------- 暴露 ArgoCD Server ----------
info "設定 ArgoCD Server Service 使用預留 static IP..."
kubectl patch svc "$ARGOCD_SERVER_SVC" -n "$ARGOCD_NAMESPACE" --type merge -p "{
  \"spec\": {\"type\": \"LoadBalancer\"},
  \"metadata\": {
    \"annotations\": {
      \"cloud.google.com/l4-rbs\": \"enabled\",
      \"networking.gke.io/load-balancer-ip-addresses\": \"${STATIC_IP_NAME}\"
    }
  }
}"

ARGOCD_ENDPOINT="$(wait_for_endpoint "svc/${ARGOCD_SERVER_SVC}" "$ARGOCD_NAMESPACE")"
ARGOCD_PASSWORD="$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"

info "ArgoCD 安裝完成！"
echo "  版本: ${ARGOCD_VERSION}"
echo "  預留IP資源: ${STATIC_IP_NAME}"
echo "  預留IP位址: ${STATIC_IP}"
echo "  URL:  https://${ARGOCD_ENDPOINT}"
echo "  帳號: admin"
echo "  密碼: $ARGOCD_PASSWORD"
echo "  CLI : argocd login ${ARGOCD_ENDPOINT} --username admin --password '$ARGOCD_PASSWORD' --insecure"

# ---------- 登入 ArgoCD CLI ----------
argocd login "$ARGOCD_ENDPOINT" --username admin --password "$ARGOCD_PASSWORD" --insecure

info "ArgoCD 就緒，接下來請執行: bash deploy.sh"
