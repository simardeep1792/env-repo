#!/bin/bash
set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default values
MESH_MODE=false
AUTO_PORT_FORWARD=false
PORT_FORWARD_ONLY=false
VERBOSE=false

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse command line arguments
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -m, --mesh              Bootstrap with Istio service mesh instead of NGINX"
    echo "  -p, --port-forward      Automatically start port forwards after bootstrap"
    echo "  -P, --port-forward-only Only start port forwards (skip bootstrap)"
    echo "  -v, --verbose           Enable verbose output"
    echo "  -h, --help              Display this help message"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mesh)
            MESH_MODE=true
            shift
            ;;
        -p|--port-forward)
            AUTO_PORT_FORWARD=true
            shift
            ;;
        -P|--port-forward-only)
            PORT_FORWARD_ONLY=true
            AUTO_PORT_FORWARD=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Cleanup function for port forwards
cleanup_port_forwards() {
    if [ "$AUTO_PORT_FORWARD" = true ]; then
        echo -e "\n${YELLOW}Cleaning up port forwards...${NC}"
        pkill -f "port-forward.*argocd-server" 2>/dev/null || true
        pkill -f "port-forward.*grafana" 2>/dev/null || true
        pkill -f "port-forward.*kiali" 2>/dev/null || true
    fi
}

# Set trap for cleanup on exit if auto port forwarding is enabled
if [ "$AUTO_PORT_FORWARD" = true ]; then
    trap cleanup_port_forwards EXIT
fi

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Port forward only mode - skip bootstrap and just start port forwards
if [ "$PORT_FORWARD_ONLY" = true ]; then
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}Port Forward Mode${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo ""
    
    # Get Argo CD password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
    
    # Check if Istio is installed to determine if we need Kiali port forward
    ISTIO_INSTALLED=$(kubectl get namespace istio-system 2>/dev/null | grep -c istio-system || true)
    
    log_info "Starting port forwards..."
    kubectl port-forward -n argocd svc/argocd-server 8080:80 >/dev/null 2>&1 &
    kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 >/dev/null 2>&1 &
    
    if [ "$ISTIO_INSTALLED" -gt 0 ]; then
        kubectl port-forward -n istio-system svc/kiali 20001:20001 >/dev/null 2>&1 &
    fi
    
    sleep 3  # Give port forwards time to establish
    
    echo ""
    echo -e "${YELLOW}Access Information:${NC}"
    echo -e "${YELLOW}------------------${NC}"
    echo ""
    echo -e "${GREEN}Argo CD:${NC} http://localhost:8080"
    echo -e "  Username: admin"
    echo -e "  Password: ${ARGOCD_PASSWORD}"
    echo ""
    echo -e "${GREEN}Grafana:${NC} http://localhost:3000"
    echo -e "  Username: admin"
    echo -e "  Password: admin"
    
    if [ "$ISTIO_INSTALLED" -gt 0 ]; then
        echo ""
        echo -e "${GREEN}Kiali:${NC} http://localhost:20001"
    fi
    
    echo ""
    echo -e "${YELLOW}Press Ctrl+C to stop port forwards and exit.${NC}"
    wait
    exit 0
fi

# Header
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Progressive Delivery POC Bootstrap${NC}"
echo -e "${BLUE}Mode: $([ "$MESH_MODE" = true ] && echo "Istio Service Mesh" || echo "NGINX Ingress")${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Create kind cluster
log_info "Creating kind cluster..."
kind create cluster --config="${ROOT_DIR}/bootstrap/kind-cluster.yaml" --wait=120s

# Install kube-prometheus-stack
log_info "Installing kube-prometheus-stack..."
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

# Install ingress controller based on mode
if [ "$MESH_MODE" = true ]; then
    # Istio installation
    log_info "Installing Istio base..."
    helm upgrade --install istio-base base \
      --repo https://istio-release.storage.googleapis.com/charts \
      --namespace istio-system \
      --create-namespace \
      --version 1.22.0 \
      --wait

    log_info "Installing Istio control plane..."
    helm upgrade --install istiod istiod \
      --repo https://istio-release.storage.googleapis.com/charts \
      --namespace istio-system \
      --version 1.22.0 \
      --set global.proxy.resources.requests.cpu=100m \
      --set global.proxy.resources.requests.memory=128Mi \
      --wait

    log_info "Installing Istio ingress gateway..."
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

    log_info "Installing Kiali Operator..."
    helm upgrade --install kiali-operator kiali-operator \
      --repo https://kiali.org/helm-charts \
      --namespace kiali-operator \
      --create-namespace \
      --version 1.86.0 \
      --wait

    log_info "Creating Kiali instance..."
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
else
    # NGINX installation
    log_info "Installing NGINX Ingress Controller..."
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
fi

# Install Argo CD
log_info "Installing Argo CD..."
kubectl apply -f "${ROOT_DIR}/bootstrap/install-argocd.yaml"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.12.0/manifests/install.yaml
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Install Argo Rollouts
log_info "Installing Argo Rollouts..."
kubectl create namespace argo-rollouts || true
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/download/v1.7.0/install.yaml
kubectl wait --for=condition=available deployment/argo-rollouts -n argo-rollouts --timeout=300s

# Install Argo Rollouts kubectl plugin if not already installed
log_info "Installing Argo Rollouts kubectl plugin..."
if ! command -v kubectl-argo-rollouts &> /dev/null; then
    curl -LO https://github.com/argoproj/argo-rollouts/releases/download/v1.7.0/kubectl-argo-rollouts-$(uname | tr '[:upper:]' '[:lower:]')-amd64
    chmod +x kubectl-argo-rollouts-$(uname | tr '[:upper:]' '[:lower:]')-amd64
    sudo mv kubectl-argo-rollouts-$(uname | tr '[:upper:]' '[:lower:]')-amd64 /usr/local/bin/kubectl-argo-rollouts 2>/dev/null || \
        mv kubectl-argo-rollouts-$(uname | tr '[:upper:]' '[:lower:]')-amd64 /usr/local/bin/kubectl-argo-rollouts
fi

# Apply Argo CD App of Apps
log_info "Applying Argo CD App of Apps..."
kubectl apply -f "${ROOT_DIR}/argocd/projects.yaml"

if [ "$MESH_MODE" = true ]; then
    # For mesh mode, we might need different app configurations
    log_warn "Mesh mode App of Apps configuration may need customization"
fi

kubectl apply -f "${ROOT_DIR}/argocd/app-of-apps.yaml"

# Get credentials
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Start port forwards if requested
if [ "$AUTO_PORT_FORWARD" = true ]; then
    log_info "Starting port forwards..."
    kubectl port-forward -n argocd svc/argocd-server 8080:80 >/dev/null 2>&1 &
    kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 >/dev/null 2>&1 &
    
    if [ "$MESH_MODE" = true ]; then
        kubectl port-forward -n istio-system svc/kiali 20001:20001 >/dev/null 2>&1 &
    fi
    
    sleep 5  # Give port forwards time to establish
fi

# Wait for applications to sync
log_info "Waiting for applications to sync..."
for i in {1..30}; do
    if kubectl get applications -n argocd 2>/dev/null | grep -q "Synced"; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    else
        echo -n "."
        sleep 10
    fi
done

# Display summary
echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Bootstrap Complete!${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Display access information
echo -e "${YELLOW}Access Credentials:${NC}"
echo -e "${YELLOW}------------------${NC}"
echo ""

echo -e "${GREEN}Argo CD:${NC}"
if [ "$AUTO_PORT_FORWARD" = true ]; then
    echo -e "  URL:      ${BLUE}http://localhost:8080${NC}"
else
    echo -e "  Command:  ${BLUE}kubectl port-forward -n argocd svc/argocd-server 8080:80${NC}"
fi
echo -e "  Username: ${BLUE}admin${NC}"
echo -e "  Password: ${BLUE}${ARGOCD_PASSWORD}${NC}"
echo ""

echo -e "${GREEN}Grafana:${NC}"
if [ "$AUTO_PORT_FORWARD" = true ]; then
    echo -e "  URL:      ${BLUE}http://localhost:3000${NC}"
else
    echo -e "  Command:  ${BLUE}kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80${NC}"
fi
echo -e "  Username: ${BLUE}admin${NC}"
echo -e "  Password: ${BLUE}admin${NC}"
echo ""

if [ "$MESH_MODE" = true ]; then
    echo -e "${GREEN}Kiali:${NC}"
    if [ "$AUTO_PORT_FORWARD" = true ]; then
        echo -e "  URL:      ${BLUE}http://localhost:20001${NC}"
    else
        echo -e "  Command:  ${BLUE}kubectl port-forward -n istio-system svc/kiali 20001:20001${NC}"
    fi
    echo ""
fi

echo -e "${GREEN}Application:${NC}"
echo -e "  URL:      ${BLUE}http://app.localtest.me:30080${NC}"
echo ""

echo -e "${YELLOW}Useful Commands:${NC}"
echo -e "${YELLOW}---------------${NC}"
echo -e "Check status:     ${BLUE}make status${NC}"
echo -e "Good release:     ${BLUE}make good-release${NC}"
echo -e "Bad release:      ${BLUE}make bad-release${NC}"
echo -e "Destroy cluster:  ${BLUE}make destroy${NC}"

if [ "$AUTO_PORT_FORWARD" = true ]; then
    echo ""
    echo -e "${YELLOW}Note:${NC} Port forwards are running in the background."
    echo "Press Ctrl+C to stop them and exit."
    echo ""
    # Keep script running to maintain port forwards
    wait
else
    echo ""
    echo -e "${YELLOW}Note:${NC} Use the commands above to start port forwards when needed."
fi