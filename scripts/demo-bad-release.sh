#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "======================================"
echo "Demo: Progressive Delivery - Bad Release with Rollback"
echo "======================================"
echo ""
echo "This demo shows automatic rollback when metrics fail"
echo "We'll try to update to a 'bad' version that returns errors"
echo ""

echo "Step 1: Current state"
echo "--------------------"
kubectl get rollout app -n dev
echo ""

echo "Step 2: Updating to Red (bad) version"
echo "------------------------------------"
# The red version of the demo app returns 500 errors occasionally
sed -i.bak 's|image: argoproj/rollouts-demo:[a-z]*|image: argoproj/rollouts-demo:red|' "${ROOT_DIR}/envs/dev/rollout.yaml"
rm -f "${ROOT_DIR}/envs/dev/rollout.yaml.bak"

echo "Committing change to Git..."
cd "${ROOT_DIR}"
git add envs/dev/rollout.yaml
git commit -m "demo: update app to red version (will fail)" || echo "No changes to commit"
git push

echo ""
echo "Step 3: ArgoCD will detect the change and start rollout"
echo "-------------------------------------------------------"
echo "Waiting for ArgoCD to sync..."
sleep 10

echo ""
echo "Step 4: Watching Progressive Rollout with Automatic Rollback"
echo "-----------------------------------------------------------"
echo "The rollout will:"
echo "  ⚠️  Start 5% canary"
echo "  ❌ Detect high error rate (>1%)"
echo "  🔄 Automatically rollback to previous stable version"
echo ""
echo "You can access the app at: http://app.localtest.me:30080"
echo "Watch the Grafana dashboards to see error rates spike!"
echo ""
echo "Starting rollout watch (press Ctrl+C to stop watching)..."
kubectl argo rollouts get rollout app -n dev --watch