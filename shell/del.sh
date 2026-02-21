#!/bin/bash

kubectl delete namespace nodejs-helm-template
kubectl delete namespace nodejs-helm-bn-template
kubectl delete namespace argocd
kubectl delete secret linx-bar-tls -n default
