#!/usr/bin/env bash
set -euo pipefail

# Fixed settings (as requested)
NS_ARGOCD="argocd"
NS_MONITORING="monitoring"
NS_APP="nodejs-helm-template"
NS_ELK="elk"
KIBANA_SVC_NAME="kibana-kibana"
ELASTIC_SECRET_NAME="elasticsearch-master-credentials"
SINCE="5m"
TAIL_LINES="120"
LOKI_LIMIT="200"
LOKI_LOCAL_PORT="13100"

cpu_to_millicores() {
  local v="${1:-0}"
  if [[ "${v}" == *m ]]; then
    echo "${v%m}"
  else
    echo $((v * 1000))
  fi
}

mem_to_mib() {
  local v="${1:-0}"
  case "${v}" in
    *Ki) echo $(( ${v%Ki} / 1024 )) ;;
    *Mi) echo "${v%Mi}" ;;
    *Gi) echo $(( ${v%Gi} * 1024 )) ;;
    *Ti) echo $(( ${v%Ti} * 1024 * 1024 )) ;;
    *) echo 0 ;;
  esac
}

argocd_ip="$(kubectl get svc/argocd-server -n "${NS_ARGOCD}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
argocd_pwd="$(kubectl -n "${NS_ARGOCD}" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"

grafana_ip="$(kubectl get svc/kube-prometheus-grafana -n "${NS_MONITORING}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
grafana_pwd="$(kubectl -n "${NS_MONITORING}" get secret grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 --decode || true)"
if [[ -z "${grafana_pwd}" ]]; then
  grafana_pwd="$(kubectl -n "${NS_MONITORING}" get secret kube-prometheus-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 --decode || true)"
fi

elk_ip="${ELK_LB_IP:-}"
if [[ -z "${elk_ip}" ]]; then
  elk_ip="$(kubectl get svc "${KIBANA_SVC_NAME}" -n "${NS_ELK}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
fi
if [[ -z "${elk_ip}" ]]; then
  elk_ip="$(kubectl get svc "${KIBANA_SVC_NAME}" -n "${NS_ELK}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
fi

elk_pwd="$(kubectl -n "${NS_ELK}" get secret "${ELASTIC_SECRET_NAME}" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"
if [[ -z "${elk_pwd}" ]]; then
  elk_pwd="$(kubectl -n "${NS_ELK}" get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 -d || true)"
fi
if [[ -z "${elk_pwd}" ]]; then
  elk_pwd="$(kubectl -n "${NS_ELK}" get secret kibana-system -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"
fi

dns_ip="$(kubectl get gateway app-gateway -n default -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
if [[ -z "${dns_ip}" ]]; then
  dns_ip="$(kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.status.loadBalancer.ingress[0].ip}{"\n"}{end}' 2>/dev/null | awk 'NF{print; exit}' || true)"
fi

node_total="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
node_ready="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 ~ /Ready/ {c++} END{print c+0}')"
pod_total="$(kubectl get pods -A --no-headers 2>/dev/null | wc -l | tr -d ' ')"
pod_running="$(kubectl get pods -A --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"

alloc_cpu_m=0
alloc_mem_mi=0
while read -r cpu mem; do
  [[ -z "${cpu:-}" || -z "${mem:-}" ]] && continue
  alloc_cpu_m=$((alloc_cpu_m + $(cpu_to_millicores "${cpu}")))
  alloc_mem_mi=$((alloc_mem_mi + $(mem_to_mib "${mem}")))
done < <(kubectl get nodes -o jsonpath='{range .items[*]}{.status.allocatable.cpu}{" "}{.status.allocatable.memory}{"\n"}{end}' 2>/dev/null || true)

used_cpu_m=0
used_mem_mi=0
top_nodes_count=0
while read -r _ cpu _ mem _; do
  [[ -z "${cpu:-}" || -z "${mem:-}" ]] && continue
  top_nodes_count=$((top_nodes_count + 1))
  used_cpu_m=$((used_cpu_m + $(cpu_to_millicores "${cpu}")))
  used_mem_mi=$((used_mem_mi + $(mem_to_mib "${mem}")))
done < <(kubectl top nodes --no-headers 2>/dev/null || true)

cpu_summary="N/A"
mem_summary="N/A"
if [[ "${alloc_cpu_m}" -gt 0 && "${top_nodes_count}" -gt 0 ]]; then
  cpu_summary="$(awk -v u="${used_cpu_m}" -v a="${alloc_cpu_m}" 'BEGIN{printf "%.2f/%.2f cores (%.1f%%)", u/1000, a/1000, (u/a)*100}')"
fi
if [[ "${alloc_mem_mi}" -gt 0 && "${top_nodes_count}" -gt 0 ]]; then
  mem_summary="$(awk -v u="${used_mem_mi}" -v a="${alloc_mem_mi}" 'BEGIN{printf "%.1f/%.1f GiB (%.1f%%)", u/1024, a/1024, (u/a)*100}')"
fi

declare -A node_has_monitor
declare -A node_has_app
while read -r node ns; do
  [[ -z "${node:-}" || -z "${ns:-}" ]] && continue
  if [[ "${ns}" == "monitoring" ]]; then
    node_has_monitor["${node}"]=1
  elif [[ "${ns}" == "nodejs-helm-template" ]]; then
    node_has_app["${node}"]=1
  fi
done < <(
  kubectl get pods -A \
    -o custom-columns='NS:.metadata.namespace,NODE:.spec.nodeName' \
    --no-headers 2>/dev/null | awk 'NF && $2 != "<none>" {print $2 " " $1}'
)

echo "==================== Access ===================="
echo "ArgoCD IP       : ${argocd_ip:-N/A}"
echo "ArgoCD Password : ${argocd_pwd:-N/A}"
echo "ArgoCD CLI Login: argocd login ${argocd_ip:-<IP>} --username admin --password '${argocd_pwd:-<PWD>}' --insecure"
echo "Grafana IP      : ${grafana_ip:-N/A}"
echo "Grafana Password: ${grafana_pwd:-N/A}"
echo "ELK (Kibana) IP : ${elk_ip:-N/A}"
echo "ELK Password    : ${elk_pwd:-N/A}"
echo "DNS Bind IP     : ${dns_ip:-N/A}"

echo
echo "==================== Cluster Summary ===================="
echo "Nodes (Ready/Total): ${node_ready:-0}/${node_total:-0}"
echo "Pods  (Running/All): ${pod_running:-0}/${pod_total:-0}"
echo "CPU Usage          : ${cpu_summary}"
echo "Memory Usage       : ${mem_summary}"

echo
echo "==================== Pod Placement (monitoring / nodejs-helm-template) ===================="
kubectl get pods -A -o wide 2>/dev/null | egrep 'monitoring|nodejs-helm-template' || true

echo
echo "==================== Node CPU/Memory (per node) ===================="
while read -r node cpu cpu_pct mem mem_pct; do
  [[ -z "${node:-}" ]] && continue
  role="other"
  if [[ -n "${node_has_monitor[${node}]:-}" && -n "${node_has_app[${node}]:-}" ]]; then
    role="monitor+ap"
  elif [[ -n "${node_has_monitor[${node}]:-}" ]]; then
    role="monitor"
  elif [[ -n "${node_has_app[${node}]:-}" ]]; then
    role="ap"
  fi
  printf "%-45s role:%-11s CPU: %-12s (%-4s)  MEM: %-12s (%-4s)\n" "${node}" "${role}" "${cpu}" "${cpu_pct}" "${mem}" "${mem_pct}"
done < <(kubectl top nodes --no-headers 2>/dev/null || true)

echo
echo "==================== Namespace CPU Requests (millicores) ===================="
if command -v jq >/dev/null 2>&1; then
  kubectl get pods -A -o json 2>/dev/null | jq -r '
    [ .items[]
      | {ns: .metadata.namespace, reqs: [ .spec.containers[]?.resources.requests.cpu // "0" ] }
      | .cpu_m = ((.reqs | map(
          if test("m$") then sub("m$";"")|tonumber
          elif .=="0" then 0
          else (tonumber*1000)
          end
        ) | add))
      | {ns, cpu_m: .cpu_m}
    ]
    | group_by(.ns)
    | map({ns: .[0].ns, cpu_m: (map(.cpu_m)|add)})
    | sort_by(-.cpu_m)
    | .[] | "\(.ns)\t\(.cpu_m)m"
  ' || true
else
  echo "jq not found, skip namespace CPU request summary."
fi

echo
echo "==================== nodejs-helm-template Pod Logs (${SINCE}) ===================="
kubectl logs -n "${NS_APP}" -l app.kubernetes.io/name=nodejs-helm-template \
  -c nodejs-helm-template --since="${SINCE}" --tail="${TAIL_LINES}" --prefix=true || true
