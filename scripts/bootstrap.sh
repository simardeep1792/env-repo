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

echo "Installing NGINX Ingress Controller..."
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --version 4.10.0 \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443 \
  --set controller.metrics.enabled=true \
  --set controller.metrics.serviceMonitor.enabled=true \
  --wait

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

echo "Applying Argo CD App of Apps..."
kubectl apply -f "${ROOT_DIR}/argocd/projects.yaml"
kubectl apply -f "${ROOT_DIR}/argocd/app-of-apps.yaml"

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
echo "- App: http://app.localtest.me:30080"
echo ""
echo "Run 'make status' to check application status."