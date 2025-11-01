# Progressive Delivery Demo

A complete Progressive Delivery platform demonstrating canary deployments with automated rollbacks using Argo CD and Argo Rollouts.

## Overview

This demo showcases enterprise-grade progressive delivery patterns:

- **GitOps**: Argo CD manages all deployments from Git
- **Canary Deployments**: Gradual traffic shifting with Argo Rollouts
- **Automated Rollbacks**: Metric-based quality gates trigger automatic rollbacks
- **Full Observability**: Prometheus metrics and Grafana dashboards
- **Traffic Management**: NGINX Ingress or Istio service mesh
- **Zero CI/CD Complexity**: Uses public demo images for simplicity

## Prerequisites

Install the following tools:

```bash
# Docker Desktop or equivalent
docker --version

# kind for local Kubernetes
go install sigs.k8s.io/kind@v0.23.0

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/$(uname | tr '[:upper:]' '[:lower:]')/amd64/kubectl"

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# yq for YAML processing (optional)
go install github.com/mikefarah/yq/v4@latest
```

## Quick Start

### Default Setup (Full Stack with Istio)

```bash
# Clone and bootstrap with automatic port forwarding
git clone <env-repo-url>
cd env-repo
make bootstrap

# Services are automatically available at:
# - Argo CD: http://localhost:8080
# - Grafana: http://localhost:3000
# - Kiali: http://localhost:20001
# - Application: http://app.localtest.me:30080

# Credentials will be displayed after bootstrap
```

### Minimal Setup (NGINX Only)

```bash
# Bootstrap with NGINX only (no service mesh)
make bootstrap-nginx
```

### Port Forwarding

```bash
# If port forwards die or you closed the terminal:
make pf-all        # Start all port forwards
make pf-argocd     # Only Argo CD
make pf-grafana    # Only Grafana
```

## Access Credentials

### Argo CD
- URL: http://localhost:8080 (via port-forward)
- Username: `admin`
- Password: Run `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`

### Grafana
- URL: http://localhost:3000 (via port-forward)
- Username: `admin`
- Password: `admin`

### Application
- URL: http://app.localtest.me:30080
- Health: http://app.localtest.me:30080/healthz
- Metrics: http://app.localtest.me:30080/metrics

## Repository Structure

```
env-repo/
├── bootstrap/           # Kind cluster and initial setup
├── infra/              # Platform infrastructure
│   ├── nginx/          # NGINX Ingress configuration
│   ├── monitoring/     # Prometheus, Grafana, dashboards
│   └── rollouts/       # Argo Rollouts controller
├── envs/               # Application environments
│   ├── dev/            # Development (auto-sync)
│   └── prod/           # Production (manual sync)
├── argocd/             # Argo CD configuration
├── scripts/            # Automation and demo scripts
└── mesh/               # Optional Istio configuration
```

## Progressive Delivery Workflow

### Canary Strategy

Rollouts follow this progression:

1. **5% Canary** (2 min pause + analysis)
   - Routes 5% traffic to new version
   - Monitors error rate and latency
   - Runs synthetic health checks

2. **20% Canary** (3 min pause + analysis)
   - Increases to 20% traffic split
   - Continues monitoring

3. **50% Canary** (5 min pause + analysis)
   - Half traffic to new version
   - Final quality gate

4. **100% Stable**
   - Promotes to full rollout
   - Old version terminated

### Automated Rollback

Rollbacks trigger when:
- Error rate > 1% for 2 consecutive checks
- p95 latency > 500ms for 2 consecutive checks
- Synthetic health checks fail

## Monitoring and Observability

### Grafana Dashboards

1. **Argo Rollouts Dashboard**
   - Rollout progress and status
   - Canary vs stable replica counts
   - Analysis run status

2. **NGINX Ingress Dashboard**
   - Request rates and error rates
   - Response time percentiles
   - Status code distribution

3. **App SLO Dashboard**
   - Success rate (SLO: 99%)
   - Latency percentiles (SLO: p95 < 500ms)
   - Request volume by route

### Prometheus Alerts

- `CanaryHighErrorRate`: Error rate above 1%
- `CanaryHighLatency`: p95 latency above 500ms
- `AnalysisRunFailed`: Analysis run failure

## Demo Scenarios

### Successful Rollout

```bash
make good-release
```

This demonstrates:
1. Update from `blue` to `yellow` version
2. Automated canary progression (5% → 20% → 50% → 100%)
3. Successful promotion based on metrics

### Failed Rollout with Auto-Rollback

```bash
make bad-release
```

This demonstrates:
1. Update to `red` version (returns errors)
2. Analysis detects high error rate at 5% canary
3. Automatic rollback to previous stable version
4. Prometheus alerts fire

## Environments

### Dev Environment
- **Namespace**: `dev`
- **Sync Policy**: Automated with prune and self-heal
- **Use Case**: Continuous deployment from main branch

### Prod Environment
- **Namespace**: `prod`
- **Sync Policy**: Manual sync required
- **Use Case**: Controlled releases with approval gates

## Customization

### Modifying Canary Steps

Edit `envs/dev/rollout.yaml`:

```yaml
steps:
  - setWeight: 10        # Custom percentage
  - pause: { duration: 5m }  # Custom pause duration
  - analysis: { ... }    # Custom analysis templates
```

### Adding Analysis Templates

Create templates in `envs/dev/analysis/`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: custom-check
spec:
  metrics:
    - name: custom-metric
      provider:
        prometheus:
          query: "custom_query"
```

### Custom Grafana Dashboards

Add JSON files to `infra/monitoring/grafana-dashboards/` and update the kustomization.

## Troubleshooting

### Cluster Not Starting
```bash
# Check Docker and resources
docker system df
docker system prune

# Recreate cluster
make destroy
make bootstrap
```

### Argo Applications Not Syncing
```bash
# Check application status
kubectl get applications -n argocd

# Manual sync
kubectl patch application env-dev -n argocd -p '{"operation":{"sync":{}}}' --type merge
```

### Rollout Stuck
```bash
# Check rollout status
kubectl argo rollouts get rollout app -n dev

# Check analysis runs
kubectl get analysisruns -n dev

# Abort rollout
kubectl argo rollouts abort app -n dev
```

### Missing Metrics
```bash
# Check ServiceMonitors
kubectl get servicemonitors -n monitoring

# Check Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090/targets
```

### No Traffic Routing
```bash
# Check ingress
kubectl get ingress -n dev

# Check NGINX controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

## Cleanup

```bash
# Destroy cluster and all resources
make destroy

# Clean up downloaded binaries
rm -f kubectl-argo-rollouts-*
```

## Demo Application

This demo uses the official Argo Rollouts demo images:
- `argoproj/rollouts-demo:blue` - Stable version
- `argoproj/rollouts-demo:yellow` - Good update 
- `argoproj/rollouts-demo:red` - Bad version (returns errors)

The demo app displays a colored square representing the version, making it easy to see which version is running during canary deployments.

## How It Works

1. **Make Changes**: Edit image tags in `envs/dev/rollout.yaml`
2. **Commit & Push**: Git push triggers ArgoCD sync
3. **Progressive Rollout**: Argo Rollouts manages the canary deployment
4. **Automatic Analysis**: Prometheus metrics determine success/failure
5. **Auto Rollback**: Failed deployments automatically revert

## Architecture Decisions

### Why App of Apps?
- Centralized management of all applications
- Dependency ordering for infrastructure
- Environment isolation

### Why NGINX + Optional Istio?
- NGINX: Simple, well-understood, sufficient for most use cases
- Istio: Advanced features like distributed tracing, security policies
- User choice based on complexity needs

### Why Analysis Templates?
- Objective quality gates
- Automated decision making
- Consistent rollback criteria
- Observable failure modes

This setup provides a complete progressive delivery platform suitable for production workloads with comprehensive monitoring, automated quality gates, and operational simplicity.