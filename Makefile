.PHONY: bootstrap bootstrap-nginx bootstrap-no-pf destroy pf-argocd pf-grafana pf-all status good-release bad-release

bootstrap:
	@echo "Bootstrapping Progressive Delivery POC with Istio mesh and auto port-forwarding..."
	@./scripts/bootstrap.sh --mesh --port-forward

bootstrap-nginx:
	@echo "Bootstrapping Progressive Delivery POC with NGINX only and auto port-forwarding..."
	@./scripts/bootstrap.sh --port-forward

bootstrap-no-pf:
	@echo "Bootstrapping with Istio mesh without port-forwarding..."
	@./scripts/bootstrap.sh --mesh

destroy:
	@echo "Destroying kind cluster..."
	@kind delete cluster --name progressive-delivery

pf-argocd:
	@echo "Port-forwarding Argo CD..."
	@kubectl port-forward -n argocd svc/argocd-server 8080:80

pf-grafana:
	@echo "Port-forwarding Grafana..."
	@kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

pf-all:
	@echo "Starting all port forwards..."
	@./scripts/bootstrap.sh --port-forward-only

status:
	@echo "Argo CD Applications:"
	@kubectl get applications -n argocd
	@echo ""
	@echo "Rollout Status:"
	@kubectl argo rollouts status app -n dev || echo "No rollout found in dev namespace"

good-release:
	@./scripts/demo-good-release.sh

bad-release:
	@./scripts/demo-bad-release.sh