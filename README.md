# Masters Final Project — Full Specification

---

## Title

**"Designing and Evaluating a Production-Grade LLMOps Platform:
Infrastructure Automation, Multi-Agent Orchestration, and Dual-Layer
Observability on Kubernetes"**

---

## Subtitle

*A practical framework for operating multi-agent LLM workloads with
GitOps delivery, zero-trust security, and correlated system and LLM
observability on local Kubernetes infrastructure.*

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

---

## Central Research Question

> *What architectural patterns and tooling are required to operate
> multi-agent LLM workloads on Kubernetes with production-grade
> reliability, security, and observability — and what are their
> measurable performance trade-offs under concurrent load?*

### Derived Sub-Questions

Each thesis chapter answers one sub-question:

| Chapter | Sub-Question |
|---------|-------------|
| 1 | Can Infrastructure-as-Code eliminate environment drift and guarantee reproducibility for AI platform deployments? |
| 2 | What are the convergence time characteristics and reconciliation overhead of GitOps-driven delivery for LLM workloads compared to push-based deployment? |
| 3 | What latency overhead does a zero-trust LLM gateway introduce, and how does dynamic secret injection compare to static environment variable configuration? |
| 4 | What are the graph execution overheads, token costs, and retry dynamics of a supervisor/analyst multi-agent RAG system under real workloads? |
| 5 | What is the empirical relationship between system-layer resource contention and LLM-layer behavioral degradation under concurrent stress? |

---

## Tool Stack & Responsibilities

Every tool in this project has a single, well-defined responsibility.
There is no overlap.

```
┌─────────────────────────────────────────────────────────────┐
│                     TOOL RESPONSIBILITIES                    │
├──────────────────────┬──────────────────────────────────────┤
│ Terraform            │ Infrastructure provisioning (IaC)     │
│ Kind                 │ Local Kubernetes cluster runtime      │
│ GitHub Actions       │ CI pipeline (lint, build, push)       │
│ ArgoCD               │ GitOps continuous delivery            │
│ HashiCorp Vault      │ Secret management & injection         │
│ LiteLLM              │ LLM API gateway & routing             │
│ Ollama               │ Local model runtime (GPU)             │
│ LangGraph            │ Multi-agent orchestration framework   │
│ ChromaDB             │ Vector database for RAG               │
│ Langfuse             │ LLM-native tracing & observability    │
│ Prometheus           │ System metrics collection             │
│ Grafana              │ System metrics visualization          │
│ Locust               │ Load testing & stress simulation      │
└──────────────────────┴──────────────────────────────────────┘
```

---

## Repository Structure

```
ai-llmops-platform/
│
├── .github/
│   └── workflows/
│       ├── ci.yaml              # Lint, test, build, push on PR
│       └── release.yaml         # Tag-triggered image releases
│
├── terraform/
│   ├── main.tf                  # Kind cluster + local registry
│   ├── variables.tf
│   └── outputs.tf
│
├── gitops/
│   ├── root-application.yaml    # ArgoCD App-of-Apps entry point
│   ├── infrastructure/
│   │   ├── vault/               # Vault Helm chart values
│   │   ├── litellm/             # LiteLLM Helm chart values
│   │   └── chromadb/            # ChromaDB Helm chart values
│   └── applications/
│       ├── agent-service/       # Multi-agent app manifests
│       └── langfuse/            # Langfuse tracing manifests
│
├── src/
│   ├── agents/
│   │   ├── supervisor.py        # Supervisor agent (LangGraph)
│   │   ├── analyst.py           # Analyst agent + RAG logic
│   │   └── graph.py             # DAG state machine definition
│   ├── api/
│   │   └── main.py              # FastAPI entrypoint
│   └── Dockerfile
│
└── telemetry/
    ├── prometheus-values.yaml   # Scrape configs
    ├── grafana-dashboards/      # Pre-built dashboard JSONs
    └── locustfile.py            # Load test scenarios
```

---

## Phase 1 — Reproducible Infrastructure

### Academic Focus
*Can Infrastructure-as-Code eliminate environment drift and guarantee
reproducibility for AI platform deployments?*

### What You Build

You will write Terraform scripts using the `kreuzwerker/docker` provider
to provision a complete local Kubernetes environment from scratch. A
single `terraform apply` command will:

1. Pull the Kind Docker image and instantiate three containers acting
   as cluster nodes: `kind-control-plane`, `kind-worker-1`,
   `kind-worker-2`.
2. Configure a local container image registry on port `5001`, pre-wired
   into the Kind cluster so images pushed locally are immediately
   pullable by pods.
3. Output a valid `kubeconfig` file consumed by all subsequent tooling.

A GitHub Actions CI pipeline runs on every pull request. It performs
static linting (`tflint` for Terraform, `hadolint` for Dockerfiles),
builds application Docker images, tags them by git SHA, and pushes them
to the local registry. No human runs `docker build` manually after this
is set up.

### Hardware Allocation
- 4 CPU cores and 4 GB RAM allocated to the WSL2/Docker network via
  `.wslconfig`.
- Container network operates independently from the host Ollama process.

### Key Files
- `terraform/main.tf` — cluster definition
- `terraform/variables.tf` — node count, resource limits, registry port
- `.github/workflows/ci.yaml` — full CI pipeline

### Thesis Chapter 1 Content

**Theoretical section:** Review of Infrastructure-as-Code principles,
idempotency guarantees, and state drift theory. Survey of existing
approaches to AI research environment reproducibility.

**Empirical contribution:** Measure bootstrap time from zero to a
fully running 3-node cluster across 10 independent `terraform destroy`
→ `terraform apply` cycles. Record variance. Demonstrate that the
environment is deterministic. Compare this against a manually
configured baseline documented as a runbook.

**Expected finding:** Automated bootstrap achieves sub-5-minute
reproducible cluster creation with near-zero configuration variance,
while manual approaches introduce measurable drift within 2–3
iterations.

---

## Phase 2 — Declarative Delivery Engine (GitOps)

### Academic Focus
*What are the convergence time characteristics and reconciliation
overhead of GitOps-driven delivery for LLM workloads?*

### What You Build

You will deploy ArgoCD into the cluster using its official Helm chart
and configure it using the **App-of-Apps** pattern. A single root
manifest — `gitops/root-application.yaml` — points ArgoCD at your
repository. ArgoCD's controller continuously polls Git, calculates the
diff between desired state (Git manifests) and actual state (running
cluster), and applies the delta automatically.

After this phase, you never run `kubectl apply` manually again. Every
platform component — Vault, LiteLLM, ChromaDB, the agent service,
Langfuse — is declared in Git and reconciled by ArgoCD.

The workflow becomes:

```
Developer edits manifest in Git
        ↓
GitHub Actions CI validates the change
        ↓
ArgoCD detects drift (polling interval: 3 minutes default)
        ↓
ArgoCD calculates diff and applies mutations to cluster
        ↓
Cluster state matches Git state
```

### Key Configuration Decisions
- **Sync policy:** Automated sync with self-heal enabled — if someone
  manually modifies a resource in the cluster, ArgoCD reverts it
  within the next reconciliation cycle.
- **Health checks:** Each application defines a custom health check so
  ArgoCD can report genuine readiness, not just pod running status.
- **Notifications:** ArgoCD Notifications sends sync success/failure
  alerts to a Slack webhook for observability of the delivery pipeline
  itself.

### Thesis Chapter 2 Content

**Theoretical section:** Formal definition of GitOps (Weaveworks
model), comparison of push-based vs. pull-based delivery mechanics,
analysis of the CAP theorem implications for declarative state
management.

**Empirical contribution:** Measure *convergence time* — from git
commit to running pod — across 30 deployments covering three change
types: config-only changes, new image deployments, and multi-resource
rollouts. Also measure *reconciliation overhead* by monitoring ArgoCD
controller CPU and memory consumption during active sync events.

**Expected finding:** Config-only changes converge in under 60 seconds.
Image-based deployments depend on image pull time but are deterministic.
Reconciliation overhead is consistently below 200MB RAM, confirming
suitability for resource-constrained local environments.

---

## Phase 3 — Zero-Trust AI Gateway

### Academic Focus
*What latency overhead does a zero-trust LLM gateway introduce, and
how does dynamic secret injection compare to static configuration?*

### What You Build

This phase establishes the security and model access layer of the
platform through three components working in concert.

**Ollama (model runtime):** Runs natively on the host system with
direct access to the RTX 5070 GPU. Serves `llama3.1:8b` (quantized)
on a local endpoint. This is intentionally outside the cluster to
maximize GPU throughput — containerized GPU access adds overhead that
is acceptable in cloud environments but measurable locally.

**LiteLLM (API gateway):** Deployed inside the cluster as a Kubernetes
service. It exposes an OpenAI-compatible API endpoint to all agent
pods. Behind the scenes it routes requests to Ollama, enforces per-key
rate limits, tracks token usage per API key, and logs every request.
Crucially, agent pods only ever talk to LiteLLM — they have no
knowledge of the underlying model or its location.

**HashiCorp Vault (secret management):** Deployed via the official Helm
chart with Kubernetes Auth Method enabled. When an agent pod starts,
a Vault sidecar (injected by the Vault Agent Injector) authenticates
using the pod's Kubernetes service account token, retrieves the
LiteLLM API key from Vault's KV secrets engine, and writes it as an
in-memory environment variable. The secret is never written to disk,
never present in a Kubernetes Secret manifest in Git, and rotatable
without pod restarts.

### The Zero-Trust Model

```
Agent Pod boots
      ↓
Vault sidecar authenticates via Kubernetes service account
      ↓
Vault validates pod identity against cluster API
      ↓
Vault injects LiteLLM API key as in-memory env var
      ↓
Agent calls LiteLLM gateway (no direct model access)
      ↓
LiteLLM routes to Ollama, enforces rate limits, logs usage
      ↓
Response returned to agent
```

No secret ever touches a file, a manifest, or a Git repository.

### Hardware Allocation
- RTX 5070 (8GB VRAM): `llama3.1:8b` quantized uses ~5.5GB VRAM,
  leaving ~2.5GB for active inference context windows.
- Vault and LiteLLM pods: ~400MB RAM combined.

### Thesis Chapter 3 Content

**Theoretical section:** Zero-trust security architecture principles,
analysis of secret management anti-patterns in containerized
environments (secrets in environment variables, secrets in ConfigMaps,
secrets in Git), formal description of Vault's Kubernetes Auth Method.

**Empirical contribution 1 — Gateway overhead:** Benchmark
end-to-end inference latency for 100 requests in three configurations:
direct Ollama call, Ollama via LiteLLM proxy, Ollama via LiteLLM with
rate limiting active. Measure and report the added latency per
configuration.

**Empirical contribution 2 — Secret injection cost:** Measure pod
startup time with and without the Vault sidecar injector. Quantify
the time cost of dynamic secret injection vs. static environment
variable configuration.

**Expected finding:** LiteLLM adds 15–40ms of gateway overhead under
normal load. Vault sidecar adds 2–5 seconds to pod cold-start time —
a one-time cost that is entirely acceptable for the security guarantees
provided.

---

## Phase 4 — Multi-Agent Orchestration & RAG Engine

### Academic Focus
*What are the graph execution overheads, token costs, and retry
dynamics of a supervisor/analyst multi-agent RAG system under real
workloads?*

### What You Build

A Python microservice implementing a two-agent system using LangGraph.
The system is designed around a state machine where each node represents
an agent action and edges represent conditional transitions.

**The Analyst Agent:**
- Receives a user query.
- Generates a vector embedding of the query.
- Executes a similarity search against ChromaDB (running as a
  Kubernetes deployment, pre-loaded with a document corpus).
- Constructs a prompt combining retrieved context and the original
  query.
- Calls the LiteLLM gateway to generate a response.
- Returns the response and retrieval metadata to the graph state.

**The Supervisor Agent:**
- Receives the Analyst's response and the original query.
- Evaluates response quality using a structured rubric prompt (relevance,
  completeness, groundedness in retrieved context).
- Makes a binary decision: ACCEPT (return to user) or RETRY (send back
  to Analyst with a refined query strategy).
- Enforces a maximum retry budget (default: 2 retries) to prevent
  infinite loops.

**The LangGraph State Machine:**

```
User Query
    ↓
[Analyst Node] — RAG retrieval + generation
    ↓
[Supervisor Node] — quality evaluation
    ↓
ACCEPT ──→ Return response to user
    │
RETRY ──→ Back to [Analyst Node] (max 2 iterations)
```

All agent steps, prompts, retrieved chunks, token counts, and
evaluation decisions are logged to Langfuse as structured traces.

The microservice is packaged as a Docker image, pushed to the local
registry, and its Kubernetes manifest is committed to Git. ArgoCD
automatically deploys it to the cluster. A FastAPI wrapper exposes a
`/query` endpoint for load testing in Phase 5.

### Thesis Chapter 4 Content

**Theoretical section:** Survey of multi-agent architectures (reactive
vs. deliberative), formal description of directed acyclic graph
execution models in LLM systems, analysis of RAG pipeline design
patterns (naive RAG vs. advanced RAG).

**Empirical contribution:** Using Langfuse traces collected from 200
queries across the test corpus, measure and report:

- End-to-end latency distribution (p50, p95, p99) for single-pass
  queries vs. queries requiring supervisor retry.
- Token consumption per graph node (Analyst retrieval prompt, Analyst
  generation, Supervisor evaluation).
- Retry rate distribution — what percentage of queries require 0, 1,
  or 2 supervisor iterations.
- ChromaDB retrieval latency vs. corpus size (tested at 1K, 10K,
  50K document chunks).

**Expected finding:** Supervisor retries increase end-to-end latency by
60–120% but measurably improve response quality scores. Retrieval
latency scales sub-linearly with corpus size due to HNSW indexing.
Supervisor token spend represents ~30% of total query cost.

---

## Phase 5 — Dual-Layer Observability & Empirical Evaluation

### Academic Focus
*What is the empirical relationship between system-layer resource
contention and LLM-layer behavioral degradation under concurrent
stress?*

### What You Build

This is the chapter that makes your thesis novel. You operate two
complete observability stacks simultaneously and correlate their data.

**System Layer — Prometheus + Grafana:**

Prometheus scrapes metrics from:
- Kubernetes node exporters (CPU, memory, disk I/O per node)
- cAdvisor (per-pod CPU throttling, memory limits, OOM events)
- Ollama metrics endpoint (GPU utilization, VRAM consumption,
  inference queue depth)
- LiteLLM metrics endpoint (request rate, error rate, latency
  histogram)
- ArgoCD metrics (sync duration, application health counts)

Grafana dashboards provide real-time visualization of the full system
during load tests.

**LLM Layer — Langfuse:**

Langfuse captures LLM-native telemetry:
- Per-trace latency for every agent step
- Token counts (prompt tokens, completion tokens, total cost)
- Retrieval quality scores (logged by the Supervisor agent)
- Retry rates per time window
- Error types (context length exceeded, timeout, model overload)

**The Dual-Layer Dashboard:**

```
┌─────────────────────────────────────────────────────┐
│              SYSTEM LAYER (Grafana)                  │
│  GPU Utilization ████████░░  78%                    │
│  CPU Throttle Events         12 in last 60s         │
│  Ollama Queue Depth          8 pending requests     │
│  Pod Memory Pressure         Worker-1 at 94%        │
├─────────────────────────────────────────────────────┤
│              LLM LAYER (Langfuse)                    │
│  p95 Trace Latency           4,200ms  ↑ (+180%)     │
│  Retry Rate                  34%      ↑ (+22pp)     │
│  Token Cost / Query          1,840    ↑ (+41%)      │
│  Supervisor ACCEPT Rate      61%      ↓ (-18pp)     │
└─────────────────────────────────────────────────────┘
```

When system pressure rises (GPU queue depth, CPU throttle), you
observe *correlated degradation* in LLM behavior (higher retry rates,
lower accept rates, increased token spend). This correlation is your
central empirical finding.

### Load Testing with Locust

Three test scenarios:

| Scenario | Concurrent Users | Duration | Purpose |
|----------|-----------------|----------|---------|
| Baseline | 1 | 10 min | Establish nominal latency and token spend |
| Moderate | 10 | 15 min | Identify first contention points |
| Stress | 25 | 20 min | Drive system to observable degradation |

During each scenario, both Prometheus and Langfuse data are collected.
After each run, you extract and align the time-series data and compute
correlation coefficients between system metrics and LLM behavioral
metrics.

### Thesis Chapter 5 Content

**Theoretical section:** Survey of LLMOps observability literature.
Distinguish system observability (traditional SRE domain) from LLM
observability (emerging LLMOps domain). Argue that neither is
sufficient alone for operating multi-agent systems.

**Empirical contribution — Correlation analysis:**

For each load scenario, present:
- Time-series plots of GPU utilization alongside p95 trace latency
- Scatter plots of CPU throttle events vs. Supervisor retry rate
- Token cost per query as a function of concurrent user count
- Identification of the critical load threshold — the inflection
  point where LLM behavioral quality degradation begins

**Expected finding:** At moderate load (10 users), system metrics
remain stable but LLM-layer retry rates begin increasing (+8–12pp),
suggesting that LLM behavioral degradation is an earlier signal of
platform stress than traditional system metrics. This would be a
practically significant finding for production platform teams.

---

## Academic Novelty Summary

This project makes three distinct contributions to the literature:

**Contribution 1 — Architecture:** A fully reproducible, open-source
LLMOps reference architecture combining GitOps delivery, zero-trust
secret management, and multi-agent orchestration in a single deployable
platform. No equivalent exists in the academic literature as a
validated, tested system.

**Contribution 2 — Empirical benchmarks:** Quantified overhead
measurements for LiteLLM gateway proxying, Vault sidecar injection
cost, and LangGraph multi-agent graph execution — data that practitioners
currently estimate from intuition.

**Contribution 3 — Dual-layer observability correlation:** The
empirical demonstration that LLM behavioral metrics (retry rate,
supervisor accept rate) degrade before system metrics reach conventional
alert thresholds under increasing concurrent load. This has direct
implications for how production teams should define SLOs for multi-agent
systems.

---

## Professional Value (AI Platform Engineer Alignment)

Every component of this project maps to a real skill domain sought in
AI Platform Engineering roles:

| Project Component | Professional Skill Domain |
|-------------------|--------------------------|
| Terraform + Kind | IaC, environment reproducibility |
| GitHub Actions | CI/CD pipeline design |
| ArgoCD GitOps | Platform delivery, declarative operations |
| Vault + LiteLLM | Enterprise security, LLM gateway management |
| LangGraph + RAG | AI application architecture |
| Langfuse | LLM observability, cost management |
| Prometheus + Grafana | SRE, system observability |
| Locust | Performance engineering, load testing |

The repository itself — structured, documented, reproducible from a
single clone — is the portfolio artifact that demonstrates operational
maturity to hiring teams.

---

## Suggested Timeline (6 months)

| Month | Deliverable |
|-------|------------|
| 1 | Phase 1 complete. Cluster boots from `terraform apply`. CI pipeline green. Chapter 1 draft. |
| 2 | Phase 2 complete. All components deploy via ArgoCD. No manual `kubectl apply`. Chapter 2 draft. |
| 3 | Phase 3 complete. Vault injecting secrets. LiteLLM gateway benchmarked. Chapter 3 draft. |
| 4 | Phase 4 complete. Multi-agent system running end-to-end. Langfuse traces collecting. Chapter 4 draft. |
| 5 | Phase 5 complete. Load tests run. Dual-layer correlation analysis done. Chapter 5 draft. |
| 6 | Full thesis write-up, revision, submission. |

---

*Project by Martí — MERIT Master Program, EPSEM, Universitat Politècnica de Catalunya*