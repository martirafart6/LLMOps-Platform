# IP & Networking Quick Reference

## The 4 Networks at a Glance

```
YOU (Laptop)                                                    THE CLUSTER
   ↓                                                              ↓
localhost:6443  ─────────┐                          172.18.0.10 (K8s API)
localhost:5001  ─────────┼─→ [Docker NAT] ────────→ 172.18.0.2  (Registry)
                          │                         172.18.0.20  (Worker-1)
                          │                         172.18.0.21  (Worker-2)
                          ↓
                   Docker Network
                   172.18.0.0/16
                         ↓
                  Kubernetes Cluster
                   (inside Docker)
                         ├─ Services: 10.96.0.0/12
                         └─ Pods: 10.244.0.0/16
```

## IP Address Cheat Sheet

### Docker Network (172.18.0.0/16)
- **What:** Bridge network connecting all containers
- **Gateway:** 172.18.0.1 (internal Docker router)
- **Registry:** 172.18.0.2 (exposed as localhost:5001)
- **Control-Plane:** 172.18.0.10 (Kubernetes API server)
- **Worker-1:** 172.18.0.20 (kubelet + container runtime)
- **Worker-2:** 172.18.0.21 (kubelet + container runtime)

### Kubernetes Service Network (10.96.0.0/12)
- **What:** Virtual IP space for Services
- **Kubernetes service:** 10.96.0.1 (API access)
- **CoreDNS service:** 10.96.0.10 (DNS resolution)
- **Your apps:** 10.96.x.x (assigned on deployment)
- **Scope:** Only inside cluster, not accessible from host

### Kubernetes Pod Network (10.244.0.0/16)
- **What:** Real IP addresses for running pods
- **Assigned dynamically** when pods are created
- **Ephemeral** - changes when pod restarts
- **From host:** Not directly accessible (by design)

### Host Ports
- **localhost:6443** → 172.18.0.10:6443 (Kubernetes API)
- **localhost:5001** → 172.18.0.2:5000 (Container Registry)

---

## Why These Specific IPs?

| IP Range | Reason |
|----------|--------|
| **172.18.0.0/16** | • Non-conflicting (RFC 1918 private range) • Large enough for infrastructure • Docker standard recommendation |
| **10.96.0.0/12** | • Kubernetes default for services • Very large (1M addresses) • Unlikely to conflict |
| **10.244.0.0/16** | • Kubernetes default for pods • Expandable with multiple subnets per node • RFC 1918 private |

---

## Common Network Troubleshooting

### Issue: Can't reach API from kubectl

**Check:** 
```bash
ping 127.0.0.1 -p 6443  # Should work
docker exec ai-llmops-control-plane curl 127.0.0.1:6443  # Inside container
```

**Solution:**
```bash
export KUBECONFIG=$(pwd)/terraform/generated/kubeconfig.yaml
kubectl cluster-info
```

---

### Issue: Pod can't pull images from registry

**Check:**
```bash
docker exec ai-llmops-worker-1 curl http://172.18.0.2:5000/v2/_catalog
```

**Solution:** Ensure registry is running
```bash
docker ps | grep registry
```

---

### Issue: Pod can't reach another pod

**Inside cluster pods:**
```bash
kubectl exec -it <pod-name> -- bash
ping 10.244.x.x  # Should work (other pod IP)
nslookup <service-name>  # Should resolve to 10.96.x.x
```

---

## Memory Aid: Remember the Pattern

```
172.18.0.X    ← Big containers (infrastructure)
              ├─ .2  = Registry
              ├─ .10 = Control-Plane  
              ├─ .20 = Workers (incremental)
              └─ .x  = Host-level routing
              
10.96.0.0/12   ← Kubernetes Services (virtual)
              └─ Created/deleted as you deploy
              
10.244.0.0/16 ← Kubernetes Pods (ephemeral)
              └─ Created/deleted as pods start/stop
```

---

## Network Flows (Copy-Paste Friendly)

### Flow 1: kubectl → Kubernetes API
```
kubectl on your laptop
  ↓
localhost:6443 (your terminal)
  ↓
[Docker NAT]
  ↓
172.18.0.10:6443 (inside control-plane container)
  ↓
/etc/kubernetes/manifests/kube-apiserver.yaml
```

### Flow 2: docker push → Registry
```
docker push localhost:5001/myapp:latest
  ↓
[Docker daemon translates]
  ↓
172.18.0.2:5000
  ↓
/var/lib/registry (inside registry container)
```

### Flow 3: Kubelet → Image Pull
```
Kubelet on 172.18.0.20 (worker)
  ↓
image_name=myapp:latest
  ↓
Asks registry: http://172.18.0.2:5000/v2/myapp/manifests/latest
  ↓
Registry returns image layers
  ↓
Kubelet stores in container filesystem
  ↓
Creates container with image
```

---

## Verification Commands (One-Liners)

```bash
# See all IPs in use
docker network inspect ai-llmops-kind | grep IPv4Address

# Check what's listening on ports
lsof -i :6443
lsof -i :5001

# See cluster nodes and their IPs
kubectl get nodes -o wide

# See pods and their IPs
kubectl get pods -A -o wide

# Check service IPs
kubectl get svc -A

# Test registry connectivity
curl http://localhost:5001/v2/_catalog

# Test API connectivity
curl -k https://localhost:6443  # Ignore cert warning
```

---

## Network Diagram (ASCII Art)

```
┌─────────────────────────────────────────────────────────────────┐
│ Your Machine (Host OS)                                          │
│                                                                 │
│  $ kubectl get nodes           $ docker push localhost:5001/img │
│  $ kubectl get pods            $ docker pull localhost:5001/img │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                  ↓                              ↓
            EXPOSED PORTS                  EXPOSED PORTS
          localhost:6443                  localhost:5001
                  ↓                              ↓
        ┌─────────────────────────────────────────────────────┐
        │ Docker NAT/Routing Layer                            │
        │ (Translation between host and container)            │
        └─────────────────────────────────────────────────────┘
                  ↓                              ↓
            172.18.0.10:6443                172.18.0.2:5000
        ┌─────────────────────────────────────────────────────┐
        │ Docker Bridge Network (172.18.0.0/16)               │
        │                                                      │
        │  ┌─────────────────────────────────────────────┐   │
        │  │ K8s Cluster                                 │   │
        │  │                                             │   │
        │  │  Control-Plane (172.18.0.10)                │   │
        │  │  ├─ API Server (listens on :6443)          │   │
        │  │  ├─ etcd (cluster state)                    │   │
        │  │  └─ Scheduler (assigns pods)                │   │
        │  │                                             │   │
        │  │  Worker-1 (172.18.0.20)                     │   │
        │  │  ├─ kubelet (talks to 172.18.0.10)         │   │
        │  │  └─ Pods assigned here                      │   │
        │  │                                             │   │
        │  │  Worker-2 (172.18.0.21)                     │   │
        │  │  ├─ kubelet (talks to 172.18.0.10)         │   │
        │  │  └─ Pods assigned here                      │   │
        │  │                                             │   │
        │  │  Registry (172.18.0.2)                      │   │
        │  │  └─ Stores container images                 │   │
        │  │                                             │   │
        │  └─ Service Network (10.96.0.0/12)             │   │
        │  │  └─ Virtual IPs for Services              │   │
        │  │                                             │   │
        │  └─ Pod Network (10.244.0.0/16)               │   │
        │     └─ Real IPs for running containers         │   │
        │                                                      │
        └─────────────────────────────────────────────────────┘
```

---

## Key Points to Remember

1. **172.18 = Docker Network** (where containers live)
2. **10.96 = Service IPs** (virtual, internal to K8s)
3. **10.244 = Pod IPs** (real IPs of running containers)
4. **localhost:6443 & localhost:5001 = Entry points** (your access to the cluster)

---

*Reference: Phase 1 Networking Architecture*
