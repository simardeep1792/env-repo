#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_REPO_DIR="$(cd "${ROOT_DIR}/../app-repo" && pwd)"

echo "Demo: Good Release"
echo "=================="

echo ""
echo "Step 1: Making a harmless change to the application..."
cd "${APP_REPO_DIR}"

# Update version in the app
sed -i.bak 's/VERSION", value: "1.0.0"/VERSION", value: "1.1.0"/' "${ROOT_DIR}/envs/dev/rollout.yaml"
rm -f "${ROOT_DIR}/envs/dev/rollout.yaml.bak"

echo "Changed version to 1.1.0"

echo ""
echo "Step 2: Simulating CI/CD pipeline..."
echo "Building and pushing new image..."
NEW_TAG="demo-$(date +%s)"
echo "New image tag: ${NEW_TAG}"

# Update the rollout with new image
sed -i.bak "s|image: ghcr.io/example/progressive-delivery-app:.*|image: ghcr.io/example/progressive-delivery-app:${NEW_TAG}|" "${ROOT_DIR}/envs/dev/rollout.yaml"
rm -f "${ROOT_DIR}/envs/dev/rollout.yaml.bak"

echo ""
echo "Step 3: Applying changes (simulating PR merge)..."
kubectl apply -f "${ROOT_DIR}/envs/dev/rollout.yaml"

echo ""
echo "Step 4: Watching rollout progress..."
echo "The rollout will progress through:"
echo "  - 5% canary (2 min pause + analysis)"
echo "  - 20% canary (3 min pause + analysis)"
echo "  - 50% canary (5 min pause + analysis)"
echo "  - 100% stable"
echo ""
echo "Starting rollout watch (press Ctrl+C to stop watching)..."
kubectl argo rollouts get rollout app -n dev --watch