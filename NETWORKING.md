# Phase 1 Networking Architecture Explained

## Quick Overview

The Phase 1 setup creates a **layered network** with three distinct IP ranges:

```
┌─────────────────────────────────────────────────────────────────┐
│ Your Host Machine (macOS/Linux/Windows)                         │
│ • Docker Desktop or Native Docker                               │
│ • localhost = 127.0.0.1                                         │
└─────────────────────────────────────────────────────────────────┘
                          ↓
         ┌────────────────────────────────────┐
         │  Docker Bridge Network              │
         │  172.18.0.0/16                      │ ← LAYER 1: HOST NETWORK
         │  (Internal to Docker only)          │
         ├────────────────────────────────────┤
         │                                    │
         │  • Registry: 172.18.0.2:5000       │
         │  • Control-Plane: 172.18.0.10      │
         │  • Worker-1: 172.18.0.20           │
         │  • Worker-2: 172.18.0.21           │
         │                                    │
         └────────────────────────────────────┘
                          ↓
         ┌────────────────────────────────────┐
         │  Kubernetes Service Network        │
         │  10.96.0.0/12                      │ ← LAYER 2: K8S SERVICES
         │  (Kubernetes internal services)    │
         └────────────────────────────────────┘
                          ↓
         ┌────────────────────────────────────┐
         │  Kubernetes Pod Network            │
         │  10.244.0.0/16                     │ ← LAYER 3: K8S PODS
         │  (Pod-to-pod communication)        │
         └────────────────────────────────────┘
```

---

## IP Address Breakdown

### 1. Docker Network Layer (Host Network)

**Network:** `172.18.0.0/16`

**Why this range?**
- **Safe:** Not conflicting with common local networks (192.168.x.x, 10.x.x.x)
- **Large:** Contains 65,536 addresses (172.18.0.0 to 172.18.255.255)
- **Isolated:** Only accessible from your host; not routed to the internet
- **Standard:** Recommended by Docker for user-defined bridge networks

**Key IPs:**

| IP | Container | Role | Why This IP |
|----|-----------|------|------------|
| `172.18.0.2` | `ai-llmops-registry` | OCI Registry Service | `.2` = first data service (gateway is `.1`) |
| `172.18.0.10` | `ai-llmops-control-plane` | Kubernetes API Server | `.10` = primary control endpoint |
| `172.18.0.20` | `ai-llmops-worker-1` | Worker Node #1 | `.20` = worker pool starts here |
| `172.18.0.21` | `ai-llmops-worker-2` | Worker Node #2 | `.21` = sequential worker numbering |

---

## Why Each Component Gets Its Own IP

### Control-Plane (172.18.0.10)

```
Host localhost:6443  →  [Docker NAT]  →  172.18.0.10:6443  →  Inside Container
                                       
kubectl connects               Kubernetes API Server
to localhost:6443              (etcd, Scheduler, Controller Manager)
```

**Why static IP?**
- Kubernetes components inside the container need to reach each other on stable addresses
- etcd needs to know where other etcd nodes are
- Scheduler/Controller-Manager need API server address in kubeconfig

### Worker Nodes (172.18.0.20-21)

```
Control-Plane orchestrates via their stable IPs:
172.18.0.10  ──kubelet──→  172.18.0.20  (Worker-1)
             ──kubelet──→  172.18.0.21  (Worker-2)
             ──schedule pods on these nodes
```

**Why static IPs?**
- Control-plane uses node IPs to register them in etcd
- Pod networking needs consistent node identification
- Load balancing and scheduling depends on stable node addresses

### Registry (172.18.0.2)

```
Pod inside control-plane or worker:
http://ai-llmops-registry:5000/my-image:latest

DNS resolution (inside cluster):
ai-llmops-registry  →  172.18.0.2  →  Container port 5000
```

**Why this IP?**
- Kind cluster auto-discovers it on the same Docker network
- Containerd mirror config points to it by hostname (`ai-llmops-registry:5000`)
- All nodes on the Docker network can reach it

---

## Three Network Layers Explained

### LAYER 1: Docker Network (172.18.0.0/16)

**Purpose:** Container-to-container communication at the host level

**Characteristics:**
- Created by Terraform: `resource "docker_network" "kind_network"`
- Bridge driver: containers can communicate directly
- Isolated from host networking (except exposed ports)

**What uses it?**
- All Kind containers (control-plane, workers)
- Registry container
- Any debugging containers you might launch

**Traffic flow:**
```
Your Docker commands  →  Docker daemon  →  172.18.0.0/16 bridge
                                            ↓
                                    Container network stack
                                            ↓
                                    Internal TCP/IP routing
```

### LAYER 2: Kubernetes Service Network (10.96.0.0/12)

**Purpose:** Virtual IPs for Kubernetes Services

**Characteristics:**
- Defined in `.kind-config.yaml`: `serviceSubnet: "10.96.0.0/12"`
- Not routable outside the cluster (internal to Kubernetes)
- Example: `kubernetes` service lives at `10.96.0.1`
- `kube-dns` service at `10.96.0.10`

**Example service creation:**
```bash
kubectl expose deployment my-app --port 8080
# Creates a virtual Service IP like 10.96.5.42
# All pods in cluster can reach it by DNS name
```

**Why separate from Docker network?**
- Kubernetes needs its own address space for services
- Service IPs are virtual (proxied by kube-proxy)
- Allows scaling without IP conflicts

### LAYER 3: Kubernetes Pod Network (10.244.0.0/16)

**Purpose:** Pod-to-pod communication within the cluster

**Characteristics:**
- Defined in `.kind-config.yaml`: `podSubnet: "10.244.0.0/16"`
- Each pod gets a real (but ephemeral) IP in this range
- CNI plugin (flannel/kindnet) manages this network

**Example pod networking:**
```bash
Pod A: 10.244.1.5 ──┐
                     │ (both on same Docker network bridge)
Pod B: 10.244.2.8 ──┘

Pod A can ping Pod B directly via 10.244.2.8
```

**Why separate from services?**
- Pod IPs are ephemeral (change when pod restarts)
- Service IPs are stable (persist even if pods change)
- CNI plugins manage pod routing separately from services

---

## How It All Works Together: Complete Flow

### Scenario: Deploy an application

```
1. kubectl apply -d deployment.yaml
   ↓
2. kubectl sends request to 172.18.0.10:6443 (control-plane)
   ↓
3. Control-plane receives request and schedules pod on 172.18.0.20 (worker-1)
   ↓
4. Kubelet on worker-1 (172.18.0.20) creates pod container
   ↓
5. Pod gets IP from 10.244.0.0/16 range, e.g., 10.244.1.5
   ↓
6. Pod-to-pod communication: other pods reach it at 10.244.1.5
   ↓
7. kubectl expose creates Service with IP from 10.96.0.0/12, e.g., 10.96.5.42
   ↓
8. Pods reach service by DNS: app.default.svc.cluster.local → 10.96.5.42
```

### Scenario: Push image to local registry

```
1. docker build -t myapp:latest .
   ↓
2. docker tag myapp:latest localhost:5001/myapp:latest
   ↓
3. docker push localhost:5001/myapp:latest
   Docker daemon translates: localhost:5001 → 172.18.0.2:5000
   ↓
4. Pod needs image: imagePullPolicy: Always
   ↓
5. kubectl asks kubelet on 172.18.0.20 or 172.18.0.21
   ↓
6. Kubelet connects to 172.18.0.2:5000 (registry on Docker network)
   ↓
7. Kubelet pulls image and creates pod
```

---

## Port Mapping (Why localhost:6443 and localhost:5001?)

### Kubernetes API (6443)

```
Host machine                    Docker Container
localhost:6443    ──[NAT]──→    172.18.0.10:6443
(exposed port)                  (internal port)

• Port 6443 = standard HTTPS for Kubernetes API
• Exposed to host so kubectl can connect from your terminal
• Inside cluster, pods reach it at 172.18.0.10:6443
```

**In terraform/main.tf:**
```hcl
ports {
  internal = 6443
  external = 6443
}
```

### Registry (5001)

```
Host machine                    Docker Container
localhost:5001    ──[NAT]──→    172.18.0.2:5000
(exposed port)                  (internal port)

• Port 5001 = host-accessible registry
• Port 5000 = container internal registry service
• Inside cluster, pods reach it at http://ai-llmops-registry:5000
• From host, you use: docker push localhost:5001/image:tag
```

**In terraform/main.tf:**
```hcl
ports {
  internal = 5000
  external = var.registry_port  # default: 5001
}
```

---

## Network Flow Diagram: Complete Picture

```
┌─────────────────────────────────────────────────────────────────────┐
│ YOUR TERMINAL / DOCKER CLI                                          │
│                                                                     │
│  $ kubectl cluster-info                                            │
│  $ docker push localhost:5001/image:tag                            │
└─────────────────────────────────────────────────────────────────────┘
        ↓                                    ↓
        │                                    │
   [NAT Router]                         [NAT Router]
        ↓                                    ↓
   localhost:6443  ────────────────→  172.18.0.10:6443
   (Exposed)                          (Kubernetes API)
                                      
        
   localhost:5001  ────────────────→  172.18.0.2:5000
   (Exposed)                          (Registry Service)


═══════════════════════════════════════════════════════════════════════════

INSIDE DOCKER NETWORK (172.18.0.0/16 - Container Bridge)

┌────────────────────────────────────────────────────────────────────┐
│                   Docker Bridge Network                             │
│                   172.18.0.0/16                                    │
│                                                                    │
│  ┌──────────────────────┐                                         │
│  │ Registry Container   │                                         │
│  │ 172.18.0.2:5000      │  (pulls images for all pods)           │
│  └──────────────────────┘                                         │
│           ↑ (image pulls)                                         │
│           │                                                       │
│  ┌────────┴──────────────────────────────────────────────────┐   │
│  │         Control-Plane Container                          │   │
│  │         172.18.0.10:6443                                 │   │
│  │  • API Server (receives kubectl commands)                │   │
│  │  • etcd (cluster state database)                         │   │
│  │  • Scheduler (assigns pods to nodes)                     │   │
│  │  • Controller-Manager (reconciliation loop)              │   │
│  └────────┬──────────────────────────────────────────────────┘   │
│           │ (orchestrates via kubelet API)                       │
│           │                                                       │
│  ┌────────┴────────┐                    ┌────────────────────┐   │
│  │ Worker-1        │                    │ Worker-2           │   │
│  │ 172.18.0.20     │                    │ 172.18.0.21        │   │
│  │ • kubelet       │ (connects to       │ • kubelet          │   │
│  │ • container     │  172.18.0.10)      │ • container        │   │
│  │   runtime       │                    │   runtime          │   │
│  │ • kube-proxy    │                    │ • kube-proxy       │   │
│  └────────┬────────┘                    └────────┬───────────┘   │
│           │                                      │                │
│           └──────────────┬───────────────────────┘                │
│                          ↓                                        │
│             ALL PODS connect to registry                          │
│             at 172.18.0.2:5000 for image pulls                   │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════

INSIDE KUBERNETES (Pod Communication)

┌────────────────────────────────────────────────────────────────────┐
│            Kubernetes Service Network (10.96.0.0/12)               │
│  kubernetes service: 10.96.0.1    (connect to API server)          │
│  kube-dns service: 10.96.0.10     (resolve DNS names)             │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│            Kubernetes Pod Network (10.244.0.0/16)                  │
│                                                                    │
│  Pod A: 10.244.1.5  ───┐                  Pod B: 10.244.2.8       │
│  (app container)        │ (can reach via   (another app)          │
│                         │  direct IP or    (gets IP from          │
│                         │  DNS name)       pool on startup)       │
│                         └─────────────────                        │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Why This Design?

### Security ✓

```
Host Machine (Your laptop)
├── Only ports 6443 and 5001 exposed to localhost
├── Everything else isolated in Docker network
└── No direct access to pod network from host

172.18.0.0/16 (Container isolation)
├── Only containers on this network can communicate
├── Host machine cannot directly access pod IPs (10.244.x.x)
└── Prevents accidental exposure
```

### Scalability ✓

```
Docker Network:    172.18.0.0/16  (256 - Enough for cluster infrastructure)
Service Network:   10.96.0.0/12   (1,048,576 services - Very large!)
Pod Network:       10.244.0.0/16  (65,536 pods - Expandable with subnets)
```

### Kubernetes Standard ✓

```
Service Subnet:  10.96.0.0/12   (RFC 1918, unused in most networks)
Pod Subnet:      10.244.0.0/16  (RFC 1918, unused in most networks)
```

These are the Kubernetes default ranges because they're unlikely to conflict with real networks.

---

## Verification Commands

### Check Docker Network

```bash
# Show the bridge network
docker network inspect ai-llmops-kind

# Expected output shows:
# "Name": "ai-llmops-kind",
# "IPAM": { "Config": [{ "Subnet": "172.18.0.0/16" }] },
# "Containers": {
#   "<id>": { "Name": "ai-llmops-control-plane", "IPv4Address": "172.18.0.10/16" },
#   "<id>": { "Name": "ai-llmops-worker-1", "IPv4Address": "172.18.0.20/16" },
#   "<id>": { "Name": "ai-llmops-worker-2", "IPv4Address": "172.18.0.21/16" },
#   "<id>": { "Name": "ai-llmops-registry", "IPv4Address": "172.18.0.2/16" }
# }
```

### Check Kubernetes Service Network

```bash
export KUBECONFIG=terraform/generated/kubeconfig.yaml

# Show service subnets
kubectl cluster-info dump | grep -A5 "service-cluster-ip-range"

# Expected: service-cluster-ip-range=10.96.0.0/12
```

### Check Kubernetes Pod Network

```bash
# Show pod IPs
kubectl get pods -A -o wide

# Expected output shows pods with IPs like:
# NAME                  READY   STATUS    IP              NODE
# coredns-...           1/1     Running   10.244.0.2      ai-llmops-control-plane
# etcd-...              1/1     Running   10.244.0.3      ai-llmops-control-plane
```

### Check Node IPs

```bash
# Show node IPs
kubectl get nodes -o wide

# Expected output:
# NAME                          STATUS   ROLES           IP            
# ai-llmops-control-plane       Ready    control-plane   172.18.0.10   (Docker network)
# ai-llmops-worker-1            Ready    <none>          172.18.0.20   
# ai-llmops-worker-2            Ready    <none>          172.18.0.21   
```

---

## Summary Table

| Layer | Network | Purpose | Scope |
|-------|---------|---------|-------|
| **Host** | localhost (127.0.0.1) | Your terminal | Your machine only |
| **Docker** | 172.18.0.0/16 | Container communication | Docker bridge network |
| **K8s Service** | 10.96.0.0/12 | Stable service IPs | Inside cluster only |
| **K8s Pod** | 10.244.0.0/16 | Pod-to-pod IPs | Inside cluster only |

---

## Key Takeaways

1. **Three layers exist for different purposes:**
   - Host (localhost) = your machine
   - Docker (172.18.x.x) = containers talking to each other
   - Kubernetes internal (10.x.x.x) = pod and service networking

2. **Static IPs are used for infrastructure components:**
   - 172.18.0.10 = control-plane (API server, etcd)
   - 172.18.0.20-21 = workers (kubelet, runtime)
   - 172.18.0.2 = registry (image storage)

3. **Dynamic IPs are used for workloads:**
   - 10.96.x.x = services (created/destroyed as you deploy apps)
   - 10.244.x.x = pods (created/destroyed as you scale)

4. **Port mapping connects host to containers:**
   - localhost:6443 → 172.18.0.10:6443 (API access)
   - localhost:5001 → 172.18.0.2:5000 (image push)

5. **Isolation provides security:**
   - Host cannot access pod network directly
   - Only exposed ports are accessible
   - Container network is isolated from internet

---

*This architecture is production-grade and follows Kubernetes best practices.*
