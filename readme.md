# nodejs-helm-template

Node.js Helm 基礎模板，預設支援：
- Gateway API (`HTTPRoute`)
- OpenTelemetry injector annotation
- ConfigMap / Secret envFrom
- HPA / resources / scheduling 設定

## 1) 快速使用（建議）
不要複製整個 repo。保留一份 chart，為每個專案建立自己的 values 檔。

1. 複製範本：
```bash
cp values.project-template.yaml values-myapp.yaml
```
2. 修改 `values-myapp.yaml`：
- `image.repository`, `image.tag`
- `application.port`, `service.port`
- `gateway.routes`, `gateway.redirectRoutes`
- `configMap.data`, `envFrom.secretRefs`
3. 安裝/更新：
```bash
helm upgrade --install myapp . \
  -n myapp-ns \
  --create-namespace \
  -f values-myapp.yaml
```

## 2) 移植到新專案（同一叢集）
每個新專案只要確保以下三項不同即可：
- `release name` 不同（例如 `myapp`, `newsapp`）
- `namespace` 不同（例如 `myapp-ns`, `newsapp-ns`）
- `gateway hostname/path` 不互相衝突

範例：
```bash
helm upgrade --install newsapp . \
  -n newsapp-ns \
  --create-namespace \
  -f values-newsapp.yaml
```

## 3) 你提到的「整包複製 repo」做法（可行，但不建議）
如果你一定要複製整個資料夾：
1. 複製目錄並改資料夾名。
2. 準備新 `values-<project>.yaml`（可由 `values.project-template.yaml` 複製）。
3. 用新 `release` + 新 `namespace` 部署。

注意：
- 只改資料夾名稱不代表資源名稱會變；資源名稱主要看 Helm `release name`。
- 若同 namespace + 同 release 安裝，才會衝突。

## 4) 常用指令
Render 檢查：
```bash
helm template myapp . -f values-myapp.yaml
```

套件檢查：
```bash
helm lint . -f values-myapp.yaml
```

## 5) ArgoCD 佈署方式
如果要用 ArgoCD 佈署這個 chart，重點是 `Application` 要指定 repo/path/namespace，並指定 values 檔。

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
