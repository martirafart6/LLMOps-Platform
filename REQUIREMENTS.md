# Development Environment Setup

Complete setup guide for the LLMOps Platform development environment.

## System Requirements

### Hardware Minimum (Development)
- **CPU:** 4 cores (Intel/AMD x86-64)
- **RAM:** 8 GB
- **Storage:** 50 GB free space
- **GPU:** Optional (required for Phase 3: Ollama model inference)

### Hardware Recommended (Comfortable Development)
- **CPU:** 8+ cores
- **RAM:** 16+ GB  
- **Storage:** 100+ GB free space
- **GPU:** RTX 3060 or better with 6GB+ VRAM (for Phase 3)

## Platform Support

| OS | Status | Notes |
|----|--------|-------|
| **macOS 12+** | ✓ Fully Supported | Intel and Apple Silicon (M1/M2/M3) via Docker Desktop |
| **Linux (Ubuntu 20.04+)** | ✓ Fully Supported | Native Docker, no overhead |
| **Windows 11 + WSL2** | ✓ Fully Supported | Docker Desktop with WSL2 backend, configure resource limits in `.wslconfig` |

## Tool Installation

### Phase 1: Infrastructure (Terraform + Kind + Kubernetes)

Required for bringing up the cluster.

#### macOS (Homebrew)

```bash
# Install package manager if not present
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Terraform
brew install terraform

# Install Kind
brew install kind

# Install kubectl
brew install kubectl

# Install Docker Desktop
brew install --cask docker
# Then start Docker from Applications
```

#### Linux (Ubuntu 20.04+)

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# Install Terraform
wget https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip
unzip terraform_1.7.5_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform --version

# Install Kind
go install sigs.k8s.io/kind@latest
# Ensure $HOME/go/bin is in PATH

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

#### Windows (WSL2 + PowerShell)

```powershell
# From PowerShell as Administrator

# Install Terraform
choco install terraform

# Install Kind
choco install kind

# Install kubectl
choco install kubernetes-cli

# Install Docker Desktop
choco install docker-desktop
# Then start Docker Desktop
```

Then configure WSL2 resource limits in `~/.wslconfig`:
```ini
[wsl2]
memory=8GB
processors=4
swap=2GB
localhostForwarding=true
```

#### Windows (WSL2 + Bash)

```bash
# From WSL2 Ubuntu terminal

# Install Docker client (daemon runs on Windows Docker Desktop)
sudo apt-get update
sudo apt-get install -y docker.io

# Install Terraform
curl -o terraform.zip https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip
unzip terraform.zip
sudo mv terraform /usr/local/bin/

# Install Kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

### Phase 2: GitOps (ArgoCD)

Required after Phase 1 infrastructure is up.

```bash
# Helm is needed for ArgoCD deployment
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Windows
choco install kubernetes-helm
```

### Phase 3: AI Gateway (Ollama + Vault + LiteLLM)

Required for LLM model access and secret management.

#### Ollama (Host-based, for GPU access)

```bash
# macOS: Download from https://ollama.ai/download
# Or via Homebrew
brew install ollama

# Linux: Download from https://ollama.ai/download
# Or via package manager
curl -fsSL https://ollama.ai/install.sh | sh

# Windows: Download exe from https://ollama.ai/download
# Or via Homebrew
winget install Ollama.Ollama

# After install, start Ollama daemon
# The service will be available at http://localhost:11434
```

#### Vault CLI (for Phase 3 secret management)

```bash
# macOS
brew install vault

# Linux
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install vault

# Windows
choco install vault
```

### Phase 4: Application Development (Python)

Required for multi-agent system development.

#### Python Environment (Recommended: pyenv or Conda)

```bash
# Using pyenv (macOS/Linux)
brew install pyenv
pyenv install 3.11.5
pyenv local 3.11.5

# Using Conda (All platforms)
# Download from https://www.anaconda.com/download
conda create -n llmops python=3.11
conda activate llmops

# Using venv (Python 3.11+)
python3.11 -m venv venv
source venv/bin/activate  # macOS/Linux
# or
venv\Scripts\activate  # Windows
```

#### Python Dependencies

```bash
# Install from src/requirements.txt (when ready in Phase 4)
pip install --upgrade pip
pip install -r src/requirements.txt

# Development dependencies
pip install pytest pytest-cov black pylint mypy
```

### Phase 5: Observability (Prometheus + Grafana + Locust)

Required for monitoring and load testing.

```bash
# Locust (Python-based load testing)
pip install locust

# Prometheus & Grafana are deployed via Helm chart
# No local installation needed
```

## Verification

After installation, verify all tools are present and working:

```bash
# Phase 1: Infrastructure
terraform -version       # Should be >= 1.7.0
kind version            # Should be >= 0.20.0
kubectl version --client # Should be >= 1.28
docker --version        # Should be >= 20.10

# Phase 2: GitOps
helm version            # Should be >= 3.12

# Phase 3: AI Gateway (optional at this stage)
ollama --version        # Should be present
vault version           # Should be present

# Phase 4: Python (if ready)
python --version        # Should be >= 3.11
pip --version
```

## Quick Verification Script

```bash
#!/bin/bash

echo "Verifying LLMOps Platform dependencies..."

commands=(
    "terraform:>= 1.7.0"
    "kind:>= 0.20.0"
    "kubectl:>= 1.28"
    "docker:>= 20.10"
    "git:>= 2.30"
)

missing=0
for cmd_spec in "${commands[@]}"; do
    cmd="${cmd_spec%:*}"
    req="${cmd_spec#*:}"
    if command -v "$cmd" &> /dev/null; then
        version=$("$cmd" --version 2>&1 | head -1)
        echo "✓ $cmd: $version"
    else
        echo "✗ $cmd: NOT FOUND (required: $req)"
        missing=$((missing+1))
    fi
done

if [[ $missing -eq 0 ]]; then
    echo ""
    echo "✓ All dependencies installed!"
else
    echo ""
    echo "✗ Missing $missing tools. Install them before proceeding."
    exit 1
fi
```

Save as `verify-deps.sh` and run:
```bash
chmod +x verify-deps.sh
./verify-deps.sh
```

## Next Steps

1. **Phase 1 Infrastructure:** `bash terraform/setup.sh init`
2. **Verify:** `kubectl get nodes` (should show 3 nodes)
3. **Phase 2 GitOps:** Follow `gitops/README.md`
4. **Later phases:** Follow individual phase documentation

## Troubleshooting

### Docker is consuming too much disk space

```bash
# Check disk usage
docker system df

# Clean up unused resources
docker system prune -a --volumes
```

### WSL2 is too slow or consuming too much memory

Edit `~/.wslconfig`:
```ini
[wsl2]
memory=8GB              # Adjust based on your RAM
processors=4            # Adjust based on your CPU cores
swap=2GB
localhostForwarding=true
```

Then restart WSL2:
```powershell
# From PowerShell as Administrator
wsl --shutdown
```

### Port conflicts (5001 registry, 6443 API, etc.)

```bash
# Check which ports are in use
lsof -i :5001
lsof -i :6443

# If conflicts, update terraform/variables.tf
# and re-apply
```

### Terraform lock file conflicts

```bash
# Remove lock file and re-initialize
rm terraform/.terraform.lock.hcl
cd terraform
terraform init
```

## References

- [Terraform Documentation](https://www.terraform.io/docs)
- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Docker Documentation](https://docs.docker.com/)
- [Helm Documentation](https://helm.sh/docs/)
- [Ollama Documentation](https://ollama.ai/)
- [Vault Documentation](https://www.vaultproject.io/docs)
