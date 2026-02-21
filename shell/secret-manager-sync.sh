  printf '你的新密碼' | gcloud secrets versions add nodejs-helm-template-db-password --project=nownews-terraform --data-file=-
  kubectl -n nodejs-helm-template create secret generic nodejs-helm-template-secrets --from-literal=DB_PASSWORD="$(gcloud secrets versions access latest --secret=nodejs-helm-template-db-password
  --project=nownews-terraform)" --dry-run=client -o yaml | kubectl apply -f -