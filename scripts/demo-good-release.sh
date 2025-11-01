#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "======================================"
echo "Demo: Progressive Delivery - Good Release"
echo "======================================"
echo ""
echo "This demo shows a successful canary deployment"
echo "We'll update from 'blue' to 'yellow' version"
echo ""

echo "Step 1: Current state - Blue version"
echo "------------------------------------"
kubectl get rollout app -n dev
echo ""

echo "Step 2: Updating to Yellow version"
echo "----------------------------------"
sed -i.bak 's|image: argoproj/rollouts-demo:blue|image: argoproj/rollouts-demo:yellow|' "${ROOT_DIR}/envs/dev/rollout.yaml"
rm -f "${ROOT_DIR}/envs/dev/rollout.yaml.bak"

echo "Committing change to Git..."
cd "${ROOT_DIR}"
git add envs/dev/rollout.yaml
git commit -m "demo: update app to yellow version" || echo "No changes to commit"
git push

echo ""
echo "Step 3: ArgoCD will detect the change and start rollout"
echo "-------------------------------------------------------"
echo "Waiting for ArgoCD to sync..."
sleep 10

echo ""
echo "Step 4: Watching Progressive Rollout"
echo "-----------------------------------"
echo "The rollout will progress through:"
echo "  ✓ 5% canary (2 min pause + analysis)"
echo "  ✓ 20% canary (3 min pause + analysis)"
echo "  ✓ 50% canary (5 min pause + analysis)"
echo "  ✓ 100% stable"
echo ""
echo "You can access the app at: http://app.localtest.me:30080"
echo ""
echo "Starting rollout watch (press Ctrl+C to stop watching)..."
kubectl argo rollouts get rollout app -n dev --watch