# Network Architecture — Quick Reference

## The 4 Networks

```
localhost (127.0.0.1)          ← Your terminal
      ↓ [NAT port mapping]
172.18.0.0/16                  ← Docker network (containers)
      ↓ [Inside cluster]
10.96.0.0/12 (Services)        ← Kubernetes virtual IPs
10.244.0.0/16 (Pods)           ← Real pod IPs
```

---

## IP Cheat Sheet

### Docker Network (172.18.0.0/16)
```
172.18.0.2    → Registry (http://localhost:5001)
172.18.0.10   → Control-Plane (Kubernetes API)
172.18.0.20   → Worker-1 (kubelet + pods)
172.18.0.21   → Worker-2 (kubelet + pods)
```

### Kubernetes Internal
```
10.96.0.0/12  → Service IPs (virtual, not routable outside)
10.244.0.0/16 → Pod IPs (real, ephemeral)
```

### Port Mapping
```
localhost:6443    → 172.18.0.10:6443  (Kubernetes API)
localhost:5001    → 172.18.0.2:5000   (Image registry)
```

---

## Why Each IP Range?

| Range | Reason |
|-------|--------|
| **172.18.0.0/16** | Private, non-conflicting, Docker standard |
| **10.96.0.0/12** | Kubernetes standard for services (1M addresses) |
| **10.244.0.0/16** | Kubernetes standard for pods (RFC 1918) |

---

## One-Liner Verification

```bash
# Show container IPs
docker network inspect ai-llmops-kind | grep IPv4Address

# Show nodes (172.18.x.x IPs)
kubectl get nodes -o wide

# Show pods (10.244.x.x IPs)
kubectl get pods -A -o wide

# Show services (10.96.x.x IPs)
kubectl get svc -A

# Test registry  
curl http://localhost:5001/v2/_catalog

# Test API
curl -k https://localhost:6443
```

---

## Network Flows

### Flow 1: Your command → Kubernetes
```
kubectl on laptop
  ↓
localhost:6443
  ↓ [Docker NAT]
172.18.0.10:6443 (control-plane)
  ↓
kube-apiserver responds
```

### Flow 2: Docker push → Registry
```
docker push localhost:5001/image:tag
  ↓ [Docker daemon translates]
172.18.0.2:5000 (registry container)
  ↓
Image stored in /var/lib/registry
```

### Flow 3: Pod pull → Registry  
```
kubelet needs image
  ↓
curl http://172.18.0.2:5000/v2/image/manifests/tag
  ↓
Registry returns image
  ↓
Container created
```

---

## Troubleshooting

**Can't reach Kubernetes API?**
```bash
export KUBECONFIG=terraform/generated/kubeconfig.yaml
kubectl cluster-info
```

**Registry not accessible?**
```bash
docker inspect ai-llmops-registry | grep State
docker ps | grep registry
```

**Pod can't reach registry?**
```bash
kubectl exec -it <pod> -- curl http://172.18.0.2:5000/v2/_catalog
```

---

## Visual Diagram

```
┌────────────────────────────────────────────┐
│ Your Machine                               │
├────────────────────────────────────────────┤
│ localhost:6443  ──[NAT]──→ 172.18.0.10    │
│ localhost:5001  ──[NAT]──→ 172.18.0.2     │
└────────────────────────────────────────────┘
                       ↓
┌────────────────────────────────────────────┐
│ Docker Network (172.18.0.0/16)             │
│                                            │
│  172.18.0.10 (K8s API)                    │
│  172.18.0.20 (Worker-1)                   │
│  172.18.0.21 (Worker-2)                   │
│  172.18.0.2 (Registry)                    │
│                                            │
│  ↓ inside cluster                         │
│  Services: 10.96.0.0/12                   │
│  Pods: 10.244.0.0/16                      │
└────────────────────────────────────────────┘
```

---

**For detailed explanation, see [NETWORKING.md](NETWORKING.md)**
