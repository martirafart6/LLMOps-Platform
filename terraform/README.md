# Phase 1 — Reproducible Infrastructure

## Overview

This folder contains the Terraform configuration for the first deliverable: **Complete reproducible Kubernetes infrastructure provisioning from scratch.**

A single `terraform apply` command provisions:
- Local Docker network isolating all cluster components
- Local OCI-compliant container registry on port 5001
- Kind cluster with 1 control-plane and 2 worker nodes
- Generated kubeconfig for kubectl, helm, and ArgoCD access

## Prerequisites

### Required Tools

| Tool | Version | Install |
|------|---------|---------|
| **Docker** | 20.10+ | [Docker Desktop](https://www.docker.com/products/docker-desktop) or Linux native |
| **Kind** | 0.20+ | `brew install kind` or [releases](https://kind.sigs.k8s.io/docs/user/quick-start/) |
| **kubectl** | 1.28+ | `brew install kubectl` or [official docs](https://kubernetes.io/docs/tasks/tools/) |
| **Terraform** | 1.7+ | `brew install terraform` or [official docs](https://www.terraform.io/downloads.html) |

### System Resources

- **CPU:** 4 cores minimum (8 cores recommended)
- **RAM:** 8 GB minimum (16 GB recommended)
- **Disk:** 50 GB free space for cluster and registry data
- **Docker resources** configured via Docker Desktop settings or `.wslconfig` on WSL2

## Quick Start

### Option 1: Automated Setup (Recommended)

```bash
# Make setup script executable
chmod +x terraform/setup.sh

# Initialize cluster, Kind, registry, and apply Terraform
bash terraform/setup.sh init

# After initialization completes
cd terraform
terraform apply

# Verify
export KUBECONFIG=$(pwd)/generated/kubeconfig.yaml
kubectl get nodes
```

### Option 2: Manual Step-by-Step

```bash
# 1. Initialize Terraform
cd terraform
terraform init

# 2. Create Kind cluster
kind create cluster --config=.kind-config.yaml --name ai-llmops-platform

# 3. Extract kubeconfig
mkdir -p generated
kind get kubeconfig --name=ai-llmops-platform > generated/kubeconfig.yaml
chmod 600 generated/kubeconfig.yaml

# 4. Apply Terraform for registry and networking
terraform apply

# 5. Verify
export KUBECONFIG=$(pwd)/generated/kubeconfig.yaml
kubectl get nodes
```

## Architecture

### Docker Network (`ai-llmops-kind`)

```
┌─────────────────────────────────────────────────────────────┐
│                   Docker Network (Bridge)                    │
│                   Subnet: 172.18.0.0/16                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  172.18.0.10 (Control-Plane)          172.18.0.2 (Registry) │
│  ┌─────────────────────────────┐     ┌──────────────────┐   │
│  │  ai-llmops-control-plane    │     │  Registry:5000   │   │
│  │  - API Server: 6443         │     │  ↓               │   │
│  │  - etcd                     │     │  Exposed as      │   │
│  │  - Controller-Manager       │     │  localhost:5001  │   │
│  │  - Scheduler                │     └──────────────────┘   │
│  └─────────────────────────────┘                             │
│           ↓                                                   │
│  172.18.0.20 (Worker-1)    172.18.0.21 (Worker-2)           │
│  ┌──────────────────────┐   ┌──────────────────────┐        │
│  │ ai-llmops-worker-1   │   │ ai-llmops-worker-2   │        │
│  │ - kubelet            │   │ - kubelet            │        │
│  │ - container runtime  │   │ - container runtime  │        │
│  └──────────────────────┘   └──────────────────────┘        │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Key Files

| File | Purpose |
|------|---------|
| `main.tf` | Infrastructure definitions (network, registry, nodes, kubeconfig) |
| `variables.tf` | Input variables (cluster name, node image, registry port) |
| `outputs.tf` | Output values (cluster endpoint, registry endpoint) |
| `versions.tf` | Required provider versions (terraform, docker, local) |
| `.kind-config.yaml` | Kind cluster configuration (topology, networking, containerd patches) |
| `setup.sh` | Bootstrap script for prerequisites validation and cluster creation |
| `generated/kubeconfig.yaml` | Generated kubeconfig (created after `kind create cluster`) |

## Configuration

### Variables

```hcl
variable "project_name" {
  default = "ai-llmops-platform"
  # Used as prefix for all resources
}

variable "kind_image" {
  default = "kindest/node:v1.30.0"
  # Kubernetes version to deploy
}

variable "worker_count" {
  default = 2
  # Number of worker nodes (control-plane is separate)
}

variable "registry_port" {
  default = 5001
  # Host port for local registry (internal: 5000)
}

variable "docker_network_name" {
  default = "ai-llmops-kind"
  # Docker network name isolating cluster
}
```

Override defaults with `-var`:

```bash
terraform apply \
  -var="kind_image=kindest/node:v1.29.0" \
  -var="worker_count=3"
```

### Customization

**Change Kubernetes version:**
```bash
# Edit terraform/variables.tf or use -var flag
terraform apply -var="kind_image=kindest/node:v1.29.0"
```

**Scale worker nodes:**
```bash
terraform apply -var="worker_count=4"
```

**Custom registry port:**
```bash
terraform apply -var="registry_port=5050"
```

## Operations

### Initial Deployment

```bash
# From project root
bash terraform/setup.sh init

cd terraform
terraform apply
export KUBECONFIG=$(pwd)/generated/kubeconfig.yaml
kubectl get nodes
```

### Verify Cluster Health

```bash
export KUBECONFIG=terraform/generated/kubeconfig.yaml

# Node status
kubectl get nodes
kubectl describe nodes

# System pods
kubectl -n kube-system get pods

# API server connectivity
kubectl cluster-info
```

### Registry Access

The local registry is auto-configured in the Kind cluster. To push images:

```bash
# Build image
docker build -t myclient:latest .

# Tag for local registry
docker tag myclient:latest localhost:5001/myclient:latest

# Push to local registry
docker push localhost:5001/myclient:latest

# Use in Kubernetes
# Image: localhost:5001/myclient:latest (from inside cluster)
```

### Cluster Status

```bash
# All nodes and their status
kind get nodes --name=ai-llmops-platform

# Registry container
docker ps --filter="name=ai-llmops-registry"

# Network details
docker network inspect ai-llmops-kind

# Kubeconfig location
echo $KUBECONFIG
```

### Scale down / Destroy

**Temporary pause (keep cluster state):**
```bash
# Stop Kind containers
kind export logs --name=ai-llmops-platform
docker pause ai-llmops-control-plane
docker pause ai-llmops-worker-1
docker pause ai-llmops-worker-2
```

**Complete destruction:**
```bash
# Option 1: Use setup script
bash terraform/setup.sh destroy

# Option 2: Manual cleanup
cd terraform
terraform destroy -auto-approve

kind delete cluster --name=ai-llmops-platform

# Clean up registry volume (optional)
docker volume rm ai-llmops-platform-registry-data
```

## Output & Access

After `terraform apply`, you can access:

```bash
# Set kubeconfig
export KUBECONFIG=$(pwd)/terraform/generated/kubeconfig.yaml

# Kubernetes API
kubectl cluster-info

# Nodes
kubectl get nodes -o wide

# System components
kubectl -n kube-system get all

# Registry endpoint
# Inside cluster: http://ai-llmops-registry:5000
# From host: http://localhost:5001
```

## Troubleshooting

### Docker daemon not running

```bash
# Linux: start Docker service
sudo systemctl start docker

# macOS: start Docker Desktop
open /Applications/Docker.app
```

### Kind image not found

```bash
# Pull image manually
docker pull kindest/node:v1.30.0
```

### Disk space issues

```bash
# Clean up unused Docker resources
docker system prune -a --volumes

# Check reserved space
docker system df
```

### Kubeconfig not generated

```bash
# Extract manually
kind get kubeconfig --name=ai-llmops-platform > terraform/generated/kubeconfig.yaml
chmod 600 terraform/generated/kubeconfig.yaml

# Verify
export KUBECONFIG=terraform/generated/kubeconfig.yaml
kubectl cluster-info
```

### Registry not accessible from pods

```bash
# Verify registry container is running
docker ps | grep registry

# Check containerd mirror config
docker exec ai-llmops-control-plane cat /etc/containerd/config.toml | grep registry
```

## Phase 1 Deliverables Checklist

- [x] Docker network provisioning (terraform)
- [x] Local registry deployment (terraform + docker provider)
- [x] Kind control-plane node (terraform)
- [x] Kind worker nodes (terraform, count)
- [x] Kubeconfig auto-generation (terraform local provider)
- [x] Setup/bootstrap script (bash)
- [x] CI validation (GitHub Actions - tflint, terraform validate)
- [x] Documentation (this README)
- [x] Reproducibility validation (idempotent terraform)

## Next Steps (Phase 2)

Phase 2 adds the **GitOps delivery engine** (ArgoCD):

- Deploy ArgoCD to the cluster
- Configure App-of-Apps pattern
- Set up automatic syncing of manifests from Git
- Measure convergence time and reconciliation overhead

For Phase 2, the infrastructure provisioned here remains unchanged.

## Best Practices Applied

| Practice | Implementation |
|----------|-----------------|
| **IaC Principles** | Declarative Terraform; no manual `kubectl apply` |
| **Idempotency** | All operations are repeatable without side effects |
| **Separation of Concerns** | main.tf (infrastructure), variables.tf (config), outputs.tf (results) |
| **Security** | Private Docker network, RBAC-ready kubeconfig |
| **Reproducibility** | Single `terraform apply` creates identical environments |
| **Documentation** | Inline comments in code and this comprehensive README |
| **Automation** | setup.sh eliminates manual steps |

## References

- [Terraform Docker Provider Docs](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs)
- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Kubernetes Networking](https://kubernetes.io/docs/concepts/services-networking/)
- [Terraform Best Practices](https://developer.hashicorp.com/terraform/cloud-docs/best-practices)

---

*Phase 1 of "Designing and Evaluating a Production-Grade LLMOps Platform"*
