.PHONY: bootstrap bootstrap-mesh destroy pf-argocd pf-grafana status good-release bad-release

bootstrap:
	@echo "Bootstrapping Progressive Delivery POC with NGINX..."
	@./scripts/bootstrap.sh

bootstrap-mesh:
	@echo "Bootstrapping Progressive Delivery POC with Istio mesh..."
	@./scripts/bootstrap-mesh.sh

destroy:
	@echo "Destroying kind cluster..."
	@kind delete cluster --name progressive-delivery

pf-argocd:
	@echo "Port-forwarding Argo CD..."
	@kubectl port-forward -n argocd svc/argocd-server 8080:80

pf-grafana:
	@echo "Port-forwarding Grafana..."
	@kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

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