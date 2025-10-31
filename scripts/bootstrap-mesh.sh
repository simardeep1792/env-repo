#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Creating kind cluster..."
kind create cluster --config="${ROOT_DIR}/bootstrap/kind-cluster.yaml" --wait=120s

echo "Installing kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack kube-prometheus-stack \
  --repo https://prometheus-community.github.io/helm-charts \
  --namespace monitoring \
  --create-namespace \
  --version 66.0.0 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin \
  --wait

echo "Installing Istio base..."
helm upgrade --install istio-base base \
  --repo https://istio-release.storage.googleapis.com/charts \
  --namespace istio-system \
  --create-namespace \
  --version 1.22.0 \
  --wait

echo "Installing Istio control plane..."
helm upgrade --install istiod istiod \
  --repo https://istio-release.storage.googleapis.com/charts \
  --namespace istio-system \
  --version 1.22.0 \
  --set global.proxy.resources.requests.cpu=100m \
  --set global.proxy.resources.requests.memory=128Mi \
  --wait

echo "Installing Istio ingress gateway..."
helm upgrade --install istio-ingressgateway gateway \
  --repo https://istio-release.storage.googleapis.com/charts \
  --namespace istio-ingress \
  --create-namespace \
  --version 1.22.0 \
  --set service.type=NodePort \
  --set service.ports[0].port=80 \
  --set service.ports[0].targetPort=8080 \
  --set service.ports[0].name=http \
  --set service.ports[0].nodePort=30080 \
  --wait

echo "Installing Kiali Operator..."
helm upgrade --install kiali-operator kiali-operator \
  --repo https://kiali.org/helm-charts \
  --namespace kiali-operator \
  --create-namespace \
  --version 1.86.0 \
  --wait

echo "Creating Kiali instance..."
kubectl apply -f - <<EOF
apiVersion: kiali.io/v1alpha1
kind: Kiali
metadata:
  name: kiali
  namespace: istio-system
spec:
  auth:
    strategy: anonymous
  deployment:
    accessible_namespaces:
      - "**"
  external_services:
    prometheus:
      url: http://kube-prometheus-stack-prometheus.monitoring:9090
    grafana:
      url: http://kube-prometheus-stack-grafana.monitoring:80
EOF

echo "Installing Argo CD..."
kubectl apply -f "${ROOT_DIR}/bootstrap/install-argocd.yaml"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.12.0/manifests/install.yaml
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

echo "Installing Argo Rollouts..."
kubectl create namespace argo-rollouts || true
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/download/v1.7.0/install.yaml
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argo-rollouts -n argo-rollouts --timeout=300s

echo "Installing Argo Rollouts kubectl plugin..."
if ! command -v kubectl-argo-rollouts &> /dev/null; then
  curl -LO https://github.com/argoproj/argo-rollouts/releases/download/v1.7.0/kubectl-argo-rollouts-$(uname | tr '[:upper:]' '[:lower:]')-amd64
  chmod +x kubectl-argo-rollouts-$(uname | tr '[:upper:]' '[:lower:]')-amd64
  sudo mv kubectl-argo-rollouts-$(uname | tr '[:upper:]' '[:lower:]')-amd64 /usr/local/bin/kubectl-argo-rollouts
fi

echo "Creating mesh App of Apps..."
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps-mesh
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/example/env-repo
    targetRevision: HEAD
    path: argocd
    directory:
      recurse: false
      include: "{projects.yaml}"
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: env-dev-mesh
  namespace: argocd
spec:
  project: apps
  source:
    repoURL: https://github.com/example/env-repo
    targetRevision: HEAD
    path: envs/dev-mesh
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

echo "Bootstrap complete!"
echo ""
echo "Access points:"
echo "- Argo CD: kubectl port-forward -n argocd svc/argocd-server 8080:80"
echo "  Username: admin"
echo "  Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
echo ""
echo "- Grafana: kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "  Username: admin"
echo "  Password: admin"
echo ""
echo "- Kiali: kubectl port-forward -n istio-system svc/kiali 20001:20001"
echo "  Or http://kiali.localtest.me:30080"
echo ""
echo "- App: http://app.localtest.me:30080"