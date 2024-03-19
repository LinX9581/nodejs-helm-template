# Step
1. [ArgoCD Install](#argocd-install) 
2. [ArgoCD CLI Install](#ArgoCD-CLI-Install) 
3. [ArgoCD CLI create demo app](#ArgoCD-CLI-create-demo-app)
4. [helm create project & push repo to github](#helm-create-project)
5. bind private repo  
7. ArgoCD CLI sync app  

## <a name="argocd-install"></a>ArgoCD Install
argoCD 會建立一個很大權限的service account 來管理 k8s cluster  
所以VM要有相對應的IAM權限 才能建立 ArgoCD  

```
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl get pods -n argocd
```

* Create argoCD web service  
kubectl port-forward svc/argocd-server --address 0.0.0.0 -n argocd 3007:443 &

* Get password  
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo  
```
127.0.0.1:3007
admin
password
```

* create ingress  
https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/  


## <a name="ArgoCD-CLI-Install"></a>ArgoCD CLI Install
```
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

## <a name="ArgoCD-CLI-create-app"></a>ArgoCD CLI create app

argocd login 127.0.0.1:3007

kubectl create namespace nginx-ingress
```
argocd app create nginx-ingress \
--repo https://github.com/LinX9581/nginx-ingress \
--path . \
--dest-server https://kubernetes.default.svc \
--dest-namespace nginx-ingress
```
kubectl get all -n ingress-nginx

kubectl create namespace nodejs-helm-template
```
argocd app create nodejs-helm-template \
--repo https://github.com/LinX9581/nodejs-helm-template \
--path . \
--dest-server https://kubernetes.default.svc \
--dest-namespace nodejs-helm-template
```

* get loadbalancer ip and bind dns
kubectl get all -n ingress-nginx

* bind ip to dns
ip -> nodejs-helm-template

## helm create your own project
kubectl create ns nodejs-helm-template  
helm create nodejs-helm-template  

* need to changed
image & ingress & port & configMap

values.yaml (改image & ingress & port)
```
image:
  repository: asia.gcr.io/nownews-analytics/nodejs-template
  pullPolicy: IfNotPresent
  tag: "4.2"

service:
  type: ClusterIP
  port: 3006

ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /
  hosts:
    - host: nodejs-helm-template.linx.website
      paths:
        - path: /(.*)
          pathType: Prefix
```

configMap.yaml
```
apiVersion: v1
kind: ConfigMap
metadata:
  name: nodejs-helm-template-env
  namespace: nodejs-helm-template
data:
  db_host: "172.16.2.10"
  db_user: "docker"
  db_password: "00000000"
```

deployment.yaml (改port & 綁定configMap)
```
image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
envFrom:
- configMapRef:
    name: nodejs-helm-template-env
imagePullPolicy: {{ .Values.image.pullPolicy }}
ports:
- name: http
    containerPort: 3006
    protocol: TCP
```

## bind private repo
```
public key to github  
argoui -> setting -> connect repo -> ssh  
argocd repo add git@github.com:LinX9581/nodejs2.git --ssh-private-key-path var/www/rsa_id  
```

## ArgoCD Connect to Github/Other
```
預設只有常見的 gitlab.com github.com  
只要確保公Key有在github上 私Key在ui 建立repo 有放上去即可

如果是自己的私網域要另外新增連線方式
可以從 ui -> setting -> Repository certificates and known hosts
新增的內容 把以下指令的內容全貼上
ssh-keyscan gitlab.test.com
```

## 基本原理
```
ArgoCD 是走 GitOps
根據 Repo 來生成整個環境
所以原先如果已經
helm install -n nodejs-template1 helm-release1 ./
那就會變兩個相同環境 導致像是 ingress 重複而出錯
```

## 部屬策略
* Recreate 直接砍掉舊 等新的佈署完畢

* Ramped 新舊 逐一替換

* Blue/Green 新的好 直接全換新

* Canary 新舊並行 流量慢慢導到新的

* A/B testing 新舊並行

* Shadow  
同時並行 確認完全無誤才移除舊版本

# ref
建立  
https://ithelp.ithome.com.tw/articles/10268662  

部屬策略  
https://ithelp.ithome.com.tw/articles/10245433  