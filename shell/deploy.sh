#!/bin/bash
set -e

# ============================================================
# Gateway API + TLS + SSL + App 部署
# 前置條件: argocd.sh 已執行完成
# ============================================================

info()  { echo "[INFO] $1"; }
warn()  { echo "[WAIT] $1" >&2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

wait_for_ip() {
  local resource=$1 ns=$2 jsonpath=$3 ip=""
  warn "等待 $resource 取得外部 IP..."
  while [ -z "$ip" ]; do
    ip=$(kubectl get $resource -n "$ns" -o jsonpath="$jsonpath" 2>/dev/null)
    sleep 5
  done
  echo "$ip"
}

# ============================================================
# 1. TLS Secret
# ============================================================
info "建立 TLS Secret..."
kubectl create secret tls linx-bar-tls \
  --cert="$SCRIPT_DIR/ssl/linx-bar.crt" \
  --key="$SCRIPT_DIR/ssl/linx-bar.key" \
  -n default --dry-run=client -o yaml | kubectl apply -f -

# ============================================================
# 2. Gateway (HTTP + HTTPS)
# ============================================================
info "建立 GKE Gateway..."
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: app-gateway
  namespace: default
spec:
  gatewayClassName: gke-l7-global-external-managed
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - name: linx-bar-tls
      allowedRoutes:
        namespaces:
          from: All
EOF

GATEWAY_IP=$(wait_for_ip "gateway/app-gateway" "default" "{.status.addresses[0].value}")
info "Gateway IP: $GATEWAY_IP"

# ============================================================
# 完成
# ============================================================
echo ""
info "========== 部署完成 =========="
echo "  Gateway: http://$GATEWAY_IP (HTTP)"
echo "  Gateway: https://$GATEWAY_IP (HTTPS)"
echo "  請將 Gateway IP 綁定到您的 DNS 記錄"
