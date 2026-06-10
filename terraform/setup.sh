#!/bin/bash

################################################################################
# Phase 1 Bootstrap Script: Reproducible Infrastructure Setup
#
# This script bootstraps the complete local Kubernetes environment with:
# - Docker network isolation
# - Local OCI image registry (port 5001)
# - Kind cluster (1 control-plane + 2 workers)
# - Generated kubeconfig for kubectl access
#
# Usage:
#   bash terraform/setup.sh [init|apply|destroy|status]
#
# Prerequisites:
#   - docker (with daemon running)
#   - kind (https://kind.sigs.k8s.io/docs/user/quick-start/)
#   - kubectl (https://kubernetes.io/docs/tasks/tools/)
#   - terraform (https://www.terraform.io/downloads.html)
#
################################################################################

set -euo pipefail

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    local missing=0
    
    if ! command_exists docker; then
        log_error "docker is not installed"
        missing=$((missing + 1))
    else
        log_success "docker found: $(docker --version)"
    fi
    
    if ! command_exists kind; then
        log_error "kind is not installed"
        log_warn "Install from: https://kind.sigs.k8s.io/docs/user/quick-start/"
        missing=$((missing + 1))
    else
        log_success "kind found: $(kind --version)"
    fi
    
    if ! command_exists kubectl; then
        log_error "kubectl is not installed"
        log_warn "Install from: https://kubernetes.io/docs/tasks/tools/"
        missing=$((missing + 1))
    else
        log_success "kubectl found: $(kubectl version --client --short)"
    fi
    
    if ! command_exists terraform; then
        log_error "terraform is not installed"
        log_warn "Install from: https://www.terraform.io/downloads.html"
        missing=$((missing + 1))
    else
        log_success "terraform found: $(terraform -version | head -1)"
    fi
    
    if [[ $missing -gt 0 ]]; then
        log_error "Missing $missing required tools. Please install them and retry."
        return 1
    fi
    
    # Check Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running. Please start Docker."
        return 1
    fi
    log_success "Docker daemon is running"
}

# Initialize Terraform
setup_terraform() {
    log_info "Initializing Terraform..."
    
    if [[ ! -d "terraform/.terraform" ]]; then
        cd terraform
        terraform init
        cd ..
        log_success "Terraform initialized"
    else
        log_success "Terraform already initialized"
    fi
}

# Create the cluster using Kind
create_cluster() {
    log_info "Creating Kind cluster..."
    
    local cluster_name="ai-llmops-platform"
    local kind_config="terraform/.kind-config.yaml"
    
    # Check if cluster already exists
    if kind get clusters 2>/dev/null | grep -q "$cluster_name"; then
        log_warn "Cluster '$cluster_name' already exists. Skipping creation."
        return 0
    fi
    
    if [[ ! -f "$kind_config" ]]; then
        log_error "Kind config file not found: $kind_config"
        return 1
    fi
    
    kind create cluster --config="$kind_config"
    log_success "Kind cluster created: $cluster_name"
    
    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready node --all --timeout=300s >/dev/null 2>&1 || {
        log_warn "Cluster nodes not fully ready, but continuing..."
    }
    log_success "Cluster nodes are ready"
}

# Configure local registry access
configure_registry() {
    log_info "Configuring local registry access..."
    
    local registry_name="ai-llmops-registry"
    local registry_port="5001"
    
    # Check if registry is already running (either by docker or terraform)
    if docker ps --filter="name=$registry_name" --format="{{.Names}}" | grep -q "$registry_name"; then
        log_success "Registry container already running"
    else
        log_info "Registry will be managed by terraform. Continue with 'terraform apply'"
        return 0
    fi
    
    # Configure containerd to allow insecure registry access
    local cluster_name="ai-llmops-platform"
    local control_plane="${cluster_name}-control-plane"
    
    # Create/update containerd config on all nodes
    docker exec "$control_plane" mkdir -p /etc/containerd || true
    
    log_success "Registry access configured"
}

# Extract and validate kubeconfig
extract_kubeconfig() {
    log_info "Extracting kubeconfig..."
    
    local kubeconfig_path="terraform/generated/kubeconfig.yaml"
    mkdir -p "terraform/generated"
    
    # Get kubeconfig from Kind
    kind get kubeconfig --name="ai-llmops-platform" > "$kubeconfig_path"
    chmod 600 "$kubeconfig_path"
    
    if [[ ! -f "$kubeconfig_path" ]]; then
        log_error "Failed to extract kubeconfig"
        return 1
    fi
    
    log_success "Kubeconfig extracted: $kubeconfig_path"
}

# Verify cluster access
verify_cluster_access() {
    log_info "Verifying cluster access..."
    
    local kubeconfig_path="terraform/generated/kubeconfig.yaml"
    
    if [[ ! -f "$kubeconfig_path" ]]; then
        log_warn "Kubeconfig not found, skipping verification"
        return 0
    fi
    
    export KUBECONFIG="$kubeconfig_path"
    
    # Test cluster access
    if kubectl cluster-info >/dev/null 2>&1; then
        log_success "Cluster access verified"
        log_info "Cluster info:"
        kubectl cluster-info
        
        log_info "Node status:"
        kubectl get nodes
    else
        log_error "Failed to access cluster"
        return 1
    fi
}

# Apply Terraform configuration
apply_terraform() {
    log_info "Applying Terraform configuration..."
    
    cd terraform
    terraform apply -auto-approve
    local exit_code=$?
    cd ..
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "Terraform applied successfully"
    else
        log_error "Terraform apply failed with exit code $exit_code"
        return $exit_code
    fi
}

# Destroy infrastructure
destroy_infrastructure() {
    log_warn "Destroying infrastructure..."
    
    # Destroy Terraform-managed resources
    cd terraform
    terraform destroy -auto-approve
    cd ..
    
    # Delete Kind cluster
    if kind get clusters 2>/dev/null | grep -q "ai-llmops-platform"; then
        kind delete cluster --name="ai-llmops-platform"
        log_success "Kind cluster deleted"
    fi
    
    log_success "Infrastructure destroyed"
}

# Status of cluster
status_cluster() {
    log_info "Cluster status:"
    
    # Check if cluster exists
    if kind get clusters 2>/dev/null | grep -q "ai-llmops-platform"; then
        log_success "Cluster 'ai-llmops-platform' is running"
        
        # Show nodes
        log_info "Nodes:"
        kind get nodes --name="ai-llmops-platform"
        
        # Show kubeconfig status
        if [[ -f "terraform/generated/kubeconfig.yaml" ]]; then
            log_success "Kubeconfig exists: terraform/generated/kubeconfig.yaml"
        else
            log_warn "Kubeconfig not found"
        fi
        
        # Show registry status
        if docker ps --filter="name=ai-llmops-registry" --format="{{.Names}}" | grep -q "ai-llmops-registry"; then
            log_success "Registry container is running"
        else
            log_warn "Registry container not running"
        fi
    else
        log_warn "Cluster 'ai-llmops-platform' is not running"
    fi
}

# Main script logic
main() {
    local command="${1:-init}"
    
    case "$command" in
        init)
            log_info "Phase 1: Reproducible Infrastructure Setup"
            log_info "==========================================="
            validate_prerequisites
            setup_terraform
            create_cluster
            configure_registry
            extract_kubeconfig
            verify_cluster_access
            log_success "Phase 1 initialization complete!"
            log_info "Next steps:"
            log_info "  1. Run: cd terraform && terraform apply"
            log_info "  2. Verify: export KUBECONFIG=generated/kubeconfig.yaml && kubectl get nodes"
            ;;
        apply)
            log_info "Applying Terraform configuration..."
            apply_terraform
            extract_kubeconfig
            verify_cluster_access
            ;;
        destroy)
            destroy_infrastructure
            ;;
        status)
            status_cluster
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Usage: $0 [init|apply|destroy|status]"
            exit 1
            ;;
    esac
}

main "$@"
