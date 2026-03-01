# nodejs-helm-template

Node.js Helm 基礎模板，預設支援：
- Gateway API (`HTTPRoute`)
- OpenTelemetry injector annotation + `Instrumentation`
- ConfigMap / Secret envFrom
- HPA / resources / scheduling 設定

## 1) 快速使用
保留一份 chart，為每個專案建立自己的 values 檔。

1. 複製範本：
```bash
cp values.project-template.yaml values-myapp.yaml
```
2. 修改 `values-myapp.yaml`：
- `image.repository`, `image.tag`
- `application.port`, `service.port`
- `gateway.routes`, `gateway.redirectRoutes`
- `configMap.data`, `envFrom.secretRefs`

敏感資訊（例如 `DB_PASSWORD`、API token）不要放在 `values*.yaml` / ConfigMap，請放到 Kubernetes Secret，再透過 `envFrom.secretRefs` 引入。

## 2) ArgoCD 佈署方式

### 2.1 建立 ArgoCD
bash ./shell/argocd.sh

### 2.2 建立 App
不同專案指定不同 values 檔
observability=enabled 標籤是為了讓 Alloy 收集日誌

佈署 nodejs-fn-template
```bash
kubectl create namespace nodejs-fn-template --dry-run=client -o yaml | kubectl label -f - observability=enabled --local -o yaml | kubectl apply -f -
argocd app create nodejs-fn-template \
  --repo https://github.com/LinX9581/nodejs-helm-template \
  --path . \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace nodejs-fn-template \
  --values values.nodejs-fn-template.yaml \
  --upsert
argocd app sync nodejs-fn-template
```

佈署 nodejs-bn-template 

```bash
kubectl create namespace nodejs-bn-template --dry-run=client -o yaml | kubectl label -f - observability=enabled --local -o yaml | kubectl apply -f -
argocd app create nodejs-bn-template \
  --repo https://github.com/LinX9581/nodejs-helm-template \
  --path . \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace nodejs-bn-template \
  --values values.nodejs-bn-template.yaml \
  --upsert
argocd app sync nodejs-bn-template
```
