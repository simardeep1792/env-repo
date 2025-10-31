#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_REPO_DIR="$(cd "${ROOT_DIR}/../app-repo" && pwd)"

echo "Demo: Bad Release (Auto-Rollback)"
echo "================================="

echo ""
echo "Step 1: Enabling failure injection in the application..."

# Enable failure injection in the rollout
sed -i.bak 's/INJECT_FAILURE", value: "false"/INJECT_FAILURE", value: "true"/' "${ROOT_DIR}/envs/dev/rollout.yaml"
rm -f "${ROOT_DIR}/envs/dev/rollout.yaml.bak"

echo "Failure injection enabled (10% of requests will return 500)"

echo ""
echo "Step 2: Simulating CI/CD pipeline..."
echo "Building and pushing bad image..."
BAD_TAG="demo-bad-$(date +%s)"
echo "New image tag: ${BAD_TAG}"

# Update the rollout with new image
sed -i.bak "s|image: ghcr.io/example/progressive-delivery-app:.*|image: ghcr.io/example/progressive-delivery-app:${BAD_TAG}|" "${ROOT_DIR}/envs/dev/rollout.yaml"
rm -f "${ROOT_DIR}/envs/dev/rollout.yaml.bak"

echo ""
echo "Step 3: Applying changes (simulating PR merge)..."
kubectl apply -f "${ROOT_DIR}/envs/dev/rollout.yaml"

echo ""
echo "Step 4: Watching rollout fail and auto-rollback..."
echo "The rollout will:"
echo "  - Start at 5% canary"
echo "  - Detect high error rate (>1%)"
echo "  - Fail analysis after 2 consecutive checks"
echo "  - Automatically rollback to stable version"
echo ""
echo "You should also see alerts firing in Prometheus/Grafana"
echo ""
echo "Starting rollout watch (press Ctrl+C to stop watching)..."
kubectl argo rollouts get rollout app -n dev --watch

echo ""
echo "Restoring good configuration for next demo..."
sed -i.bak 's/INJECT_FAILURE", value: "true"/INJECT_FAILURE", value: "false"/' "${ROOT_DIR}/envs/dev/rollout.yaml"
rm -f "${ROOT_DIR}/envs/dev/rollout.yaml.bak"