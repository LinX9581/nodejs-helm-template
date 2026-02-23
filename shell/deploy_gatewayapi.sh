#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Gateway API + TLS + SSL + App 部署
# 前置條件: argocd.sh 已執行完成
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
need_cmd helm

SCRIPT_DIR="/etc/nginx/ssl"
EDGE_NAMESPACE="${EDGE_NAMESPACE:-default}"
EDGE_GATEWAY_NAME="${EDGE_GATEWAY_NAME:-app-gateway}"
EDGE_GATEWAY_CLASS="${EDGE_GATEWAY_CLASS:-gke-l7-global-external-managed}"
TRAEFIK_NAMESPACE="${TRAEFIK_NAMESPACE:-traefik}"
TRAEFIK_RELEASE="${TRAEFIK_RELEASE:-traefik}"
TRAEFIK_SVC_NAME="${TRAEFIK_SVC_NAME:-traefik}"
TRAEFIK_GATEWAY_NAME="${TRAEFIK_GATEWAY_NAME:-traefik-gateway}"
TRAEFIK_GATEWAY_CLASS="${TRAEFIK_GATEWAY_CLASS:-traefik}"
TRAEFIK_GATEWAY_PORT="${TRAEFIK_GATEWAY_PORT:-8000}"
EDGE_TO_TRAEFIK_HOSTNAMES="${EDGE_TO_TRAEFIK_HOSTNAMES:-}"

wait_for_ip() {
  local resource=$1 ns=$2 jsonpath=$3 ip=""
  warn "等待 $resource 取得外部 IP..."
  while [[ -z "$ip" ]]; do
    ip="$(kubectl get "$resource" -n "$ns" -o jsonpath="$jsonpath" 2>/dev/null || true)"
    sleep 5
  done
  echo "$ip"
}

# ============================================================
# 1. TLS Secret
# ============================================================
info "建立 TLS Secret..."
kubectl create secret tls linx-bar-tls \
  --cert="${SCRIPT_DIR}/linx-bar.crt" \
  --key="${SCRIPT_DIR}/linx-bar.key" \
  -n "$EDGE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ============================================================
# 2. 安裝 Traefik (中間層)
# ============================================================
info "安裝 Traefik (Gateway API provider)..."
helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install "$TRAEFIK_RELEASE" traefik/traefik \
  --namespace "$TRAEFIK_NAMESPACE" \
  --create-namespace \
  --set service.type=ClusterIP \
  --set providers.kubernetesGateway.enabled=true \
  --set providers.kubernetesCRD.enabled=true \
  --set providers.kubernetesIngress.enabled=false \
  --wait --timeout 600s

info "建立 Traefik GatewayClass/Gateway..."
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: ${TRAEFIK_GATEWAY_CLASS}
spec:
  controllerName: traefik.io/gateway-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ${TRAEFIK_GATEWAY_NAME}
  namespace: ${TRAEFIK_NAMESPACE}
spec:
  gatewayClassName: ${TRAEFIK_GATEWAY_CLASS}
  listeners:
    - name: http
      protocol: HTTP
      port: ${TRAEFIK_GATEWAY_PORT}
      allowedRoutes:
        namespaces:
          from: All
EOF

# ============================================================
# 3. 外層 GKE Gateway (HTTP + HTTPS)
# ============================================================
info "建立外層 GKE Gateway..."
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ${EDGE_GATEWAY_NAME}
  namespace: ${EDGE_NAMESPACE}
spec:
  gatewayClassName: ${EDGE_GATEWAY_CLASS}
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

# ============================================================
# 4. 外層 GKE Gateway 導流到 Traefik Service
# ============================================================
info "建立 edge route: GKE Gateway -> Traefik Service..."
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-default-httproute-to-traefik-svc
  namespace: ${TRAEFIK_NAMESPACE}
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: ${EDGE_NAMESPACE}
  to:
    - group: ""
      kind: Service
      name: ${TRAEFIK_SVC_NAME}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: edge-to-traefik
  namespace: ${EDGE_NAMESPACE}
spec:
  parentRefs:
    - name: ${EDGE_GATEWAY_NAME}
      namespace: ${EDGE_NAMESPACE}
  rules:
    - backendRefs:
        - name: ${TRAEFIK_SVC_NAME}
          namespace: ${TRAEFIK_NAMESPACE}
          port: 80
EOF

if [[ -n "$EDGE_TO_TRAEFIK_HOSTNAMES" ]]; then
  info "套用 edge route hostnames: ${EDGE_TO_TRAEFIK_HOSTNAMES}"
  HOST_JSON=""
  IFS=',' read -r -a _hosts <<< "$EDGE_TO_TRAEFIK_HOSTNAMES"
  for h in "${_hosts[@]}"; do
    h="$(echo "$h" | xargs)"
    [[ -z "$h" ]] && continue
    if [[ -z "$HOST_JSON" ]]; then
      HOST_JSON="\"${h}\""
    else
      HOST_JSON="${HOST_JSON},\"${h}\""
    fi
  done
  if [[ -n "$HOST_JSON" ]]; then
    kubectl patch httproute edge-to-traefik -n "$EDGE_NAMESPACE" --type merge -p "{\"spec\":{\"hostnames\":[${HOST_JSON}]}}"
  fi
fi

GATEWAY_IP="$(wait_for_ip "gateway/${EDGE_GATEWAY_NAME}" "$EDGE_NAMESPACE" "{.status.addresses[0].value}")"
info "Edge Gateway IP: $GATEWAY_IP"

# ============================================================
# 完成
# ============================================================
echo ""
info "========== 部署完成 =========="
echo "  外層 Gateway: http://$GATEWAY_IP (HTTP)"
echo "  外層 Gateway: https://$GATEWAY_IP (HTTPS)"
echo "  中間層 Traefik Gateway: ${TRAEFIK_NAMESPACE}/${TRAEFIK_GATEWAY_NAME} (port ${TRAEFIK_GATEWAY_PORT})"
echo "  請將網域 DNS 綁到外層 Gateway IP"
echo "  應用 values 應設定:"
echo "    gateway.gatewayName: ${TRAEFIK_GATEWAY_NAME}"
echo "    gateway.gatewayNamespace: ${TRAEFIK_NAMESPACE}"
