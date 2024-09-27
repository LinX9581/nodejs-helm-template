#!/bin/bash

# 創建 ArgoCD 命名空間
kubectl create namespace argocd

# 安裝 ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 等待所有 pod 運行
echo "等待 ArgoCD pods 運行..."
kubectl wait --for=condition=Ready pod --all -n argocd --timeout=300s

# 將 ArgoCD 服務類型更改為 LoadBalancer
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# 等待 LoadBalancer IP 分配
echo "等待 LoadBalancer IP 分配..."
while [ -z "$ARGOCD_IP" ]; do
  ARGOCD_IP=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  sleep 5
done

# 獲取 ArgoCD 密碼
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# 輸出結果
echo "ArgoCD 安裝完成！"
echo "ArgoCD LoadBalancer IP: $ARGOCD_IP"
echo "ArgoCD 初始密碼: $ARGOCD_PASSWORD"
echo "請使用以下資訊登入 ArgoCD:"
echo "URL: https://$ARGOCD_IP"
echo "用戶名: admin"
echo "密碼: $ARGOCD_PASSWORD"

# 登入 ArgoCD
argocd login $ARGOCD_IP --username admin --password $ARGOCD_PASSWORD --insecure

# 創建 nginx-ingress 應用
kubectl create namespace nginx-ingress
argocd app create nginx-ingress \
--repo https://github.com/LinX9581/nginx-ingress \
--path . \
--dest-server https://kubernetes.default.svc \
--dest-namespace nginx-ingress \
--sync-policy automated

echo "等待 nginx-ingress 部署完成..."
kubectl wait --for=condition=Available deployment --all -n ingress-nginx --timeout=300s

# 創建 nodejs-helm-template 應用
kubectl create namespace nodejs-helm-template
argocd app create nodejs-helm-template \
--repo https://github.com/LinX9581/nodejs-helm-template \
--path . \
--dest-server https://kubernetes.default.svc \
--dest-namespace nodejs-helm-template \
# --sync-policy automated

# echo "等待 nodejs-helm-template 部署完成..."
# kubectl wait --for=condition=Available deployment --all -n nodejs-helm-template --timeout=300s

# 獲取 ingress-nginx 的 LoadBalancer IP
INGRESS_IP=$(kubectl get svc -n ingress-nginx -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')

echo "部署完成！"
echo "nginx-ingress LoadBalancer IP: $INGRESS_IP"
echo "請將此 IP 綁定到您的 DNS 記錄中。"