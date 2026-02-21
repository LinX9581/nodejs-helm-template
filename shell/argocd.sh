#!/bin/bash
set -e

# ============================================================
# ArgoCD 安裝 + 登入
# 這個腳本基本上不會變動
# ============================================================

info()  { echo "[INFO] $1"; }
warn()  { echo "[WAIT] $1" >&2; }
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.11.7}"

wait_for_ip() {
  local resource=$1 ns=$2 jsonpath=$3 ip=""
  warn "等待 $resource 取得外部 IP..."
  while [ -z "$ip" ]; do
    ip=$(kubectl get $resource -n "$ns" -o jsonpath="$jsonpath" 2>/dev/null)
    sleep 5
  done
  echo "$ip"
}

# ---------- 安裝 ArgoCD ----------
info "安裝 ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

warn "等待 ArgoCD pods 就緒..."
kubectl wait --for=condition=Ready pod --all -n argocd --timeout=300s

# ---------- 暴露 ArgoCD Server ----------
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

ARGOCD_IP=$(wait_for_ip "svc/argocd-server" "argocd" "{.status.loadBalancer.ingress[0].ip}")
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

info "ArgoCD 安裝完成！"
echo "  版本: ${ARGOCD_VERSION}"
echo "  URL:  https://$ARGOCD_IP"
echo "  帳號: admin"
echo "  密碼: $ARGOCD_PASSWORD"
echo "  CLI : argocd login $ARGOCD_IP --username admin --password '$ARGOCD_PASSWORD' --insecure"

# ---------- 登入 ArgoCD CLI ----------
argocd login "$ARGOCD_IP" --username admin --password "$ARGOCD_PASSWORD" --insecure

info "ArgoCD 就緒，接下來請執行: bash deploy.sh"
