#!/usr/bin/env bash
set -euo pipefail

# 用法：
#   NAMESPACE=nodejs-fn-template \
#   SECRET_NAME=nodejs-fn-template-secrets \
#   ENV_FILE=.env.fn \
#   DEPLOYMENT=nodejs-fn-template-nodejs-helm-template \
#   bash ./manage-nodejs-secrets.sh

: "${NAMESPACE:?請設定 NAMESPACE}"
: "${SECRET_NAME:?請設定 SECRET_NAME}"
: "${ENV_FILE:?請設定 ENV_FILE}"
: "${DEPLOYMENT:?請設定 DEPLOYMENT}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERROR] 找不到 env 檔: ${ENV_FILE}" >&2
  exit 1
fi

echo "[INFO] apply secret: ${NAMESPACE}/${SECRET_NAME} from ${ENV_FILE}"
kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-env-file="$ENV_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[INFO] rollout restart: ${NAMESPACE}/${DEPLOYMENT}"
kubectl -n "$NAMESPACE" rollout restart deployment "$DEPLOYMENT"
kubectl -n "$NAMESPACE" rollout status deployment "$DEPLOYMENT" --timeout=300s

echo "[INFO] 完成"
