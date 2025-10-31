#!/bin/bash
set -euo pipefail

echo "Starting port forwards..."

# Kill any existing port-forward processes
pkill -f "kubectl port-forward" || true

echo ""
echo "Starting Argo CD port-forward..."
kubectl port-forward -n argocd svc/argocd-server 8080:80 > /dev/null 2>&1 &
echo "Argo CD: http://localhost:8080"
echo "Username: admin"
echo "Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"

echo ""
echo "Starting Grafana port-forward..."
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 > /dev/null 2>&1 &
echo "Grafana: http://localhost:3000"
echo "Username: admin"
echo "Password: admin"

echo ""
echo "Port forwards started. Press Ctrl+C to stop."
wait