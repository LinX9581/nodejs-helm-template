# nodejs-helm-template

Node.js Helm 基礎模板，預設支援：
- Gateway API (`HTTPRoute`)
- OpenTelemetry injector annotation
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
CLI 範例（佈署 `nodejs-helm-template`）：
```bash
argocd app create nodejs-helm-template \
  --repo https://github.com/LinX9581/nodejs-helm-template \
  --path . \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace nodejs-helm-template \
  --values values.project-template.yaml \
  --upsert
```

CLI 範例（第二個 App：`nodejs-helm-bn-template`，同 chart 不同 values）：
```bash
argocd app create nodejs-helm-bn-template \
  --repo https://github.com/LinX9581/nodejs-helm-template \
  --path . \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace nodejs-helm-bn-template \
  --values values.nodejs-helm-bn-template.yaml \
  --upsert
```

更新/同步：
```bash
argocd app sync nodejs-helm-template
argocd app sync nodejs-helm-bn-template
```
