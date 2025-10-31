# Progressive Delivery Environment Repository

GitOps repository for managing Progressive Delivery infrastructure and application deployments using Argo CD, Argo Rollouts, and comprehensive monitoring.

## Overview

This repository contains all Kubernetes manifests and automation for a complete Progressive Delivery platform:

- **GitOps**: Argo CD with App of Apps pattern
- **Progressive Rollouts**: Argo Rollouts with canary deployments
- **Traffic Management**: NGINX Ingress (default) or Istio service mesh (optional)
- **Monitoring**: Prometheus and Grafana with custom dashboards
- **Automated Quality Gates**: AnalysisTemplates with rollback on failure
- **Environments**: Dev (automated) and Prod (manual approval)

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

# yq for YAML processing
go install github.com/mikefarah/yq/v4@latest

# GitHub CLI (for CI integration)
brew install gh  # macOS
```

## Quick Start

### Default Profile (NGINX Ingress)

```bash
# Clone and bootstrap
git clone <env-repo-url>
cd env-repo
make bootstrap

# Wait for all components to be ready (5-10 minutes)
make status

# Access services
make pf-argocd    # Argo CD at http://localhost:8080
make pf-grafana   # Grafana at http://localhost:3000
```

### Mesh Profile (Istio + Kiali)

```bash
# Bootstrap with service mesh
make bootstrap-mesh

# Additional access
kubectl port-forward -n istio-system svc/kiali 20001:20001
# Kiali at http://localhost:20001
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
1. Harmless application change
2. Automated canary progression
3. Successful promotion to 100%

### Failed Rollout with Auto-Rollback

```bash
make bad-release
```

This demonstrates:
1. Application with failure injection
2. Analysis detecting high error rate
3. Automatic rollback to stable version
4. Alert notifications

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

## CI/CD Integration

This repository integrates with the app-repo CI/CD pipeline:

1. App repo pushes trigger image builds
2. CI opens PRs to this repo with new image tags
3. Merging PRs triggers Argo CD sync
4. Rollouts begin automatically in dev
5. Manual promotion required for prod

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