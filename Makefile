.PHONY: help setup apply destroy status clean logs kubeconfig verify

TERRAFORM_DIR := terraform
KUBECONFIG := $(TERRAFORM_DIR)/generated/kubeconfig.yaml
CLUSTER_NAME := ai-llmops-platform

help:
	@echo "LLMOps Platform — Phase 1: Reproducible Infrastructure"
	@echo ""
	@echo "Available targets:"
	@echo "  setup              Initialize cluster with Kind and set up environment"
	@echo "  apply              Apply Terraform configuration (after setup)"
	@echo "  destroy            Destroy all infrastructure"
	@echo "  status             Show cluster status and component info"
	@echo "  verify             Verify all prerequisites are installed"
	@echo "  logs <pod>         Show logs from a pod (requires kubeconfig)"
	@echo "  clean              Remove generated files and temporary artifacts"
	@echo "  kubeconfig         Set KUBECONFIG environment variable"
	@echo ""

# Initialize cluster, registry, and environment
setup: verify
	@echo "Setting up Phase 1 infrastructure..."
	@bash $(TERRAFORM_DIR)/setup.sh init
	@echo ""
	@echo "Next step: make apply"

# Apply Terraform configuration
apply:
	@echo "Applying Terraform configuration..."
	@cd $(TERRAFORM_DIR) && terraform apply -auto-approve
	@echo ""
	@echo "Extracting kubeconfig..."
	@mkdir -p $(TERRAFORM_DIR)/generated
	@kind get kubeconfig --name=$(CLUSTER_NAME) > $(KUBECONFIG)
	@chmod 600 $(KUBECONFIG)
	@echo ""
	@echo "Verifying cluster access..."
	@KUBECONFIG=$(KUBECONFIG) kubectl cluster-info
	@echo ""
	@make status

# Destroy all infrastructure
destroy:
	@echo "⚠️  Destroying Phase 1 infrastructure..."
	@bash $(TERRAFORM_DIR)/setup.sh destroy
	@echo ""
	@echo "Infrastructure destroyed."

# Show cluster status
status:
	@echo "=== Cluster Status ==="
	@bash $(TERRAFORM_DIR)/setup.sh status
	@echo ""
	@if [ -f "$(KUBECONFIG)" ]; then \
		echo "=== Kubernetes Nodes ==="; \
		KUBECONFIG=$(KUBECONFIG) kubectl get nodes -o wide; \
		echo ""; \
		echo "=== System Pods ==="; \
		KUBECONFIG=$(KUBECONFIG) kubectl -n kube-system get pods --sort-by=.metadata.creationTimestamp; \
	fi

# Verify prerequisites
verify:
	@echo "Verifying prerequisites..."
	@command -v terraform >/dev/null 2>&1 || { echo "❌ terraform not found"; exit 1; }
	@command -v kind >/dev/null 2>&1 || { echo "❌ kind not found"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl not found"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "❌ docker not found"; exit 1; }
	@echo "✓ All prerequisites found"

# Show logs from pod/deployment
logs:
	@[ -f "$(KUBECONFIG)" ] || { echo "❌ kubeconfig not found"; exit 1; }
	@POD=$${POD:-}; \
	if [ -z "$$POD" ]; then \
		echo "Usage: make logs POD=<pod-name> [NAMESPACE=kube-system]"; \
		exit 1; \
	fi; \
	NAMESPACE=$${NAMESPACE:-default}; \
	KUBECONFIG=$(KUBECONFIG) kubectl -n $$NAMESPACE logs $$POD -f

# Set KUBECONFIG for shell session
kubeconfig:
	@if [ -f "$(KUBECONFIG)" ]; then \
		echo "export KUBECONFIG=$(KUBECONFIG)"; \
	else \
		echo "❌ kubeconfig not found. Run 'make setup' first."; \
		exit 1; \
	fi

# Clean up generated files
clean:
	@echo "Cleaning generated files..."
	@rm -rf $(TERRAFORM_DIR)/.terraform
	@rm -rf $(TERRAFORM_DIR)/.terraform.lock.hcl
	@rm -rf $(TERRAFORM_DIR)/terraform.tfstate*
	@rm -rf $(TERRAFORM_DIR)/generated
	@rm -rf $(TERRAFORM_DIR)/crash.log
	@echo "✓ Cleaned"

# Terraform init
init:
	@cd $(TERRAFORM_DIR) && terraform init

# Terraform fmt
fmt:
	@cd $(TERRAFORM_DIR) && terraform fmt -recursive

# Terraform validate
validate:
	@cd $(TERRAFORM_DIR) && terraform validate

# Terraform plan
plan:
	@cd $(TERRAFORM_DIR) && terraform plan

# Refresh terraform state
refresh:
	@cd $(TERRAFORM_DIR) && terraform refresh

# Show available nodes
nodes:
	@if [ -f "$(KUBECONFIG)" ]; then \
		echo "=== Kubernetes Nodes ==="; \
		KUBECONFIG=$(KUBECONFIG) kubectl get nodes -o wide; \
		echo ""; \
		echo "=== Node Details ==="; \
		KUBECONFIG=$(KUBECONFIG) kubectl describe nodes; \
	else \
		echo "❌ kubeconfig not found"; \
		exit 1; \
	fi

# Show registry status
registry:
	@echo "=== Local Registry Status ==="
	@docker ps --filter="name=$(CLUSTER_NAME)-registry" --format="table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@if docker ps --filter="name=$(CLUSTER_NAME)-registry" --format="{{.Names}}" | grep -q registry; then \
		echo "Registry endpoint: localhost:5001"; \
		echo "Inside cluster: http://$(CLUSTER_NAME)-registry:5000"; \
	else \
		echo "⚠️  Registry container not running"; \
	fi

# Push image to local registry
push-image:
	@[ -z "$(IMAGE)" ] && { echo "Usage: make push-image IMAGE=name:tag"; exit 1; } || true
	@echo "Pushing $(IMAGE) to local registry..."
	@docker tag $(IMAGE) localhost:5001/$(IMAGE)
	@docker push localhost:5001/$(IMAGE)
	@echo "✓ Pushed to localhost:5001/$(IMAGE)"
	@echo "Inside cluster, reference as: localhost:5001/$(IMAGE)"

# Show all resources in cluster
all-resources:
	@if [ -f "$(KUBECONFIG)" ]; then \
		echo "=== All Kubernetes Resources ==="; \
		KUBECONFIG=$(KUBECONFIG) kubectl get all --all-namespaces; \
	else \
		echo "❌ kubeconfig not found"; \
		exit 1; \
	fi

# Shell into control-plane node
shell-cp:
	@docker exec -it $(CLUSTER_NAME)-control-plane bash

# Shell into first worker node
shell-worker:
	@docker exec -it $(CLUSTER_NAME)-worker-1 bash

.DEFAULT_GOAL := help
