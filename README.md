# LLMOps Platform — Phase 1: Reproducible Infrastructure

**"Designing and Evaluating a Production-Grade LLMOps Platform:
Infrastructure Automation, Multi-Agent Orchestration, and Dual-Layer
Observability on Kubernetes"**

*A practical framework for operating multi-agent LLM workloads with
GitOps delivery, zero-trust security, and correlated system and LLM
observability on local Kubernetes infrastructure.*

---

## Current Status

| Phase | Component | Status |
|-------|-----------|--------|
| **1** | Reproducible Infrastructure (Terraform + Kind + local registry) | ✅ **Implemented** |
| **2** | GitOps Delivery (ArgoCD) | 📋 Planned |
| **3** | Zero-Trust AI Gateway (Vault + LiteLLM + Ollama) | 📋 Planned |
| **4** | Multi-Agent Orchestration & RAG (LangGraph + ChromaDB) | 📋 Planned |
| **5** | Dual-Layer Observability (Prometheus + Grafana + Langfuse) | 📋 Planned |

---

## Quick Start

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| **Docker** | 20.10+ | [Docker Desktop](https://www.docker.com/products/docker-desktop) or Linux native |
| **Kind** | 0.20+ | `brew install kind` or [releases](https://kind.sigs.k8s.io/docs/user/quick-start/) |
| **kubectl** | 1.28+ | `brew install kubectl` or [official docs](https://kubernetes.io/docs/tasks/tools/) |
| **Terraform** | 1.7+ | `brew install terraform` or [official docs](https://www.terraform.io/downloads.html) |

### Build & Run

```bash
# 1. Verify all prerequisites are installed
make verify

# 2. Initialize and create the Kind cluster
make setup

# 3. Apply Terraform configuration (registry, networking, kubeconfig)
make apply

# 4. Verify the cluster is running
make status
```

After these commands, you have:
- A local Kubernetes cluster with 1 control-plane + 2 worker nodes
- A local OCI-compliant container registry on `localhost:5001`
- Auto-generated kubeconfig at `terraform/generated/kubeconfig.yaml`

### Destroy Everything

```bash
make destroy
```

---

## Abstract

The rapid adoption of Large Language Models (LLMs) in enterprise
environments has exposed a critical operational gap: while model
capabilities have advanced significantly, the infrastructure patterns
required to operate LLM workloads reliably, securely, and reproducibly
remain immature and poorly studied. This project designs, implements,
and empirically evaluates a production-grade LLMOps platform that
addresses this gap.

The platform is built on five architectural layers: reproducible
infrastructure provisioned via Terraform and orchestrated by Kubernetes;
declarative continuous delivery via GitOps using ArgoCD; a zero-trust
AI gateway enforcing secret injection and model routing through LiteLLM
and HashiCorp Vault; a multi-agent reasoning system built with LangGraph
and a retrieval-augmented generation (RAG) pipeline over ChromaDB; and
a dual-layer observability stack combining system-level telemetry
(Prometheus, Grafana) with LLM-native tracing (Langfuse).

The central research contribution is the empirical characterization of
the relationship between system-level resource contention and LLM-layer
behavioral degradation under concurrent workloads — a correlation that
existing literature treats independently. The platform is designed to be
fully reproducible from a single repository, making it directly
applicable to enterprise AI Platform Engineering teams.

> **Phase 1** (this release) implements the first architectural layer:
> reproducible infrastructure via Terraform on Kind.

---

## Repository Structure

```
LLMOps-Platform/
│
├── Makefile                    # Developer workflow commands
├── REQUIREMENTS.md             # System setup guide for all platforms
├── README.md                   # This file
│
├── terraform/                  # Phase 1: Reproducible Infrastructure
│   ├── main.tf                 # Docker network, registry, Kind nodes, kubeconfig
│   ├── variables.tf            # Input variables (cluster name, image, ports)
│   ├── outputs.tf              # Output values (cluster endpoint, registry)
│   ├── versions.tf             # Provider version constraints
│   ├── .kind-config.yaml       # Kind cluster topology configuration
│   ├── setup.sh                # Bootstrap script for prerequisites + cluster
│   └── README.md               # Phase 1 documentation
│
├── gitops/                     # Phase 2 (planned)
│   └── README.md
│
├── src/                        # Phase 4 (planned)
│   └── README.md
│
└── telemetry/                  # Phase 5 (planned)
    └── README.md
```

---

## Phase 1 — Reproducible Infrastructure

### What's Built

A single `terraform apply` command (or `make setup && make apply`) provisions:

1. **Docker network** (`ai-llmops-kind`) — isolated bridge network (172.18.0.0/16)
2. **Local container registry** — OCI-compliant on port 5001, pre-wired into Kind
3. **Kind cluster** — 1 control-plane + 2 worker nodes (Kubernetes v1.30)
4. **Kubeconfig** — auto-generated for `kubectl`, Helm, and ArgoCD access

### Architecture

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
| `terraform/main.tf` | Infrastructure definitions (network, registry, nodes, kubeconfig) |
| `terraform/variables.tf` | Input variables (cluster name, node image, registry port) |
| `terraform/outputs.tf` | Output values (cluster endpoint, registry endpoint) |
| `terraform/versions.tf` | Required provider versions (terraform, docker, local) |
| `terraform/.kind-config.yaml` | Kind cluster configuration (topology, networking, containerd patches) |
| `terraform/setup.sh` | Bootstrap script for prerequisites validation and cluster creation |
| `Makefile` | Developer convenience targets (`setup`, `apply`, `destroy`, `status`, etc.) |

### Deliverables Checklist

- [x] Docker network provisioning (Terraform)
- [x] Local container registry deployment (Terraform + Docker provider)
- [x] Kind control-plane node (Terraform)
- [x] Kind worker nodes (Terraform, count)
- [x] Kubeconfig auto-generation (Terraform local provider)
- [x] Setup/bootstrap script (`terraform/setup.sh`)
- [x] Developer workflow (`Makefile`)
- [x] Documentation (`terraform/README.md`, `REQUIREMENTS.md`)

### Build Metrics

| Metric | Value |
|--------|-------|
| **Infrastructure Bootstrap Time** | 2-3 minutes |
| **Memory Usage** | 3-4 GB (3 nodes) |
| **Disk Usage** | 15-20 GB |
| **Code Idempotency** | 100% (apply is safe to repeat) |

### Operations

```bash
# Cluster status
make status

# Registry status
make registry

# All Kubernetes resources
make all-resources

# Show kubeconfig path
make kubeconfig

# Terraform plan
make plan

# Destroy everything
make destroy
```

### Registry Access

```bash
# Build and push an image to the local registry
docker build -t myapp:latest .
docker tag myapp:latest localhost:5001/myapp:latest
docker push localhost:5001/myapp:latest

# Use in Kubernetes manifests as: localhost:5001/myapp:latest
```

---

## Next Steps (Future Phases)

Future phases will add GitOps delivery (ArgoCD), zero-trust AI gateway
(Vault + LiteLLM + Ollama), multi-agent orchestration (LangGraph), and
dual-layer observability (Prometheus + Grafana + Langfuse). Each phase
will be documented in its respective directory as it is implemented.

---

## Project Context

This repository is the artifact of a Master's Final Project at the
**Universitat Politècnica de Catalunya — MERIT Master Program, EPSEM**.

*Project by Martí*