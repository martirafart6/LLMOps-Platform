# Why You Need setup.sh, Makefile, AND GitHub Actions Pipeline

## The Complete Picture

```
┌────────────────────────────────────────────────────────────────┐
│ GitHub Actions Pipeline (CI/CD on servers)                    │
│                                                                │
│ Runs on: GitHub's cloud infrastructure                        │
│ When: Every PR and push to main                               │
│ Purpose: Validate code quality                                │
│                                                                │
│ ✓ terraform fmt (check formatting)                           │
│ ✓ terraform validate (catch syntax errors)                   │
│ ✓ tflint (best practices)                                    │
│ ✓ hadolint (Dockerfile validation)                           │
│                                                                │
│ Does NOT: Actually provision infrastructure                   │
└────────────────────────────────────────────────────────────────┘
                             ↓
         (Code passes validation and merges to main)
                             ↓
┌────────────────────────────────────────────────────────────────┐
│ Local Development (Your laptop)                               │
│                                                                │
│ 1. setup.sh (one-time bootstrap)                             │
│    • Check if Docker/kind/kubectl installed                   │
│    • Create Kind cluster locally                              │
│    • Extract kubeconfig                                       │
│                                                                │
│ 2. Makefile (developer convenience)                          │
│    • make setup → runs setup.sh                              │
│    • make apply → terraform apply                             │
│    • make destroy → clean up                                  │
│    • make status → check health                               │
│                                                                │
│ 3. terraform apply (actually provision)                       │
│    • Creates Docker network                                   │
│    • Starts registry container                                │
│    • Starts control-plane & worker nodes                      │
│    • Generates kubeconfig                                     │
│                                                                │
│ Result: Full cluster running on your laptop                   │
└────────────────────────────────────────────────────────────────┘
```

---

## Three Different Tools for Three Different Jobs

### GitHub Actions Pipeline

**What it does:**
- Runs on GitHub's servers (not your laptop)
- Validates code without running it
- Gives feedback on PRs
- Prevents bad code from merging

**Example:**
```yaml
# .github/workflows/ci.yaml
jobs:
  terraform:
    runs-on: ubuntu-latest  # ← On GitHub servers
    steps:
      - terraform fmt -check  # Validate formatting
      - terraform validate    # Check syntax
      - tflint               # Check best practices
      # Does NOT do: terraform apply (no provisioning)
```

### setup.sh (Local Bootstrap)

**What it does:**
```bash
bash terraform/setup.sh init
```

**Actual steps:**
1. Check if you have Docker, kind, kubectl, terraform installed
2. If not found → tells you what to install
3. Creates Kind cluster locally
4. Extracts kubeconfig to `terraform/generated/kubeconfig.yaml`

**Why needed:**
- GitHub pipeline can't bootstrap your local environment
- You need a working Kind cluster before running terraform
- Sets up prerequisites

### Makefile (Local Convenience)

**What it does:**
```bash
make setup     # Run setup.sh
make apply     # Terraform apply
make destroy   # Clean up
make status    # Show cluster health
```

**Why needed:**
- Avoids typing long commands
- Standardizes workflow
- One-command deployment

### terraform apply (Actual Provisioning)

**What it does:**
1. Creates Docker network (172.18.0.0/16)
2. Starts registry container on 172.18.0.2
3. Starts control-plane on 172.18.0.10
4. Starts workers on 172.18.0.20-21
5. Generates kubeconfig

**Why needed:**
- Actually creates the infrastructure
- Idempotent (safe to run multiple times)
- Manages resources as code

---

## Complete Workflow (How They All Work Together)

### Day 1: Initial Setup

```bash
# 1. Validate code (before merging)
# GitHub Actions runs automatically on PR
# You see: ✓ Terraform fmt OK, ✓ Validate OK, ✓ TFLint OK

# 2. Merge to main (GitHub displays status)

# 3. Clone locally and set up
git clone https://github.com/martirafart6/LLMOps-Platform
cd LLMOps-Platform

# 4. One-command bootstrap (setup.sh inside Makefile)
make setup

# 5. Deploy infrastructure (terraform apply)
cd terraform
terraform apply
export KUBECONFIG=$(pwd)/generated/kubeconfig.yaml

# 6. Verify
kubectl get nodes
```

### Day 2: Make Changes and Push

```bash
# 1. Edit terraform/main.tf or terraform/variables.tf
vim terraform/variables.tf

# 2. Test locally
make plan

# 3. Commit and push
git add .
git commit -m "Change worker count"
git push origin feature-branch

# 4. GitHub Actions automatically validates:
#    ✓ terraform fmt -check
#    ✓ terraform validate
#    ✓ tflint
#    (You see results in PR)

# 5. If tests pass, create PR and merge
# GitHub shows: "All checks passed" ✓

# 6. Pull changes locally and redeploy
git pull origin main
make apply  # Terraform updates your local cluster
```

---

## Why You Need ALL THREE (Not Just Pipeline)

### ❌ If you ONLY had GitHub Actions:
```
✗ Pipeline validates code on GitHub
✗ But it doesn't create your local cluster
✗ You have no way to test locally
✗ You can't develop without pushing to GitHub repeatedly
✗ Workflow is: edit → push → wait for GitHub → read errors → repeat
```

### ❌ If you ONLY had setup.sh + Makefile:
```
✗ No code validation before pushing
✗ Bad Terraform code can merge to main
✗ No automated checks on team PRs
✗ Everyone writes Terraform differently
✗ No idempotency guarantees
```

### ✅ With ALL THREE (Correct Approach):
```
✓ GitHub Actions validates code (catches bugs early)
✓ setup.sh + Makefile let you bootstrap locally (fast dev cycle)
✓ terraform apply provisions infrastructure (idempotent)
✓ Workflow is: edit → validate-locally → push → auto-validated → merge
```

---

## Comparison Table

| Tool | Runs Where | When | Purpose | Provisions? |
|------|-----------|------|---------|------------|
| **GitHub Actions** | GitHub servers | Every PR/push | Code validation | No |
| **setup.sh** | Your laptop | First-time setup | Prerequisites check | No |
| **Makefile** | Your laptop | On-demand | Developer convenience | No (wrapper) |
| **terraform apply** | Your laptop | On-demand | Infrastructure creation | YES |

---

## Practical Example: Why Each is Needed

### Scenario: You want to add a 3rd worker node

#### Step 1: Edit code (local development)
```hcl
# terraform/variables.tf
variable "worker_count" {
  default = 3  # Changed from 2
}
```

#### Step 2: Test locally (setup.sh + Makefile needed)
```bash
make plan
# Shows: 1 resource to add (docker_container.worker[2])
make apply
# Actually creates the 3rd node
kubectl get nodes  # Verify 3 workers exist
```

#### Step 3: Commit and push
```bash
git add terraform/variables.tf
git commit -m "Add 3rd worker node"
git push origin feature/add-worker
```

#### Step 4: GitHub validates (Pipeline needed)
```
GitHub Actions runs:
✓ terraform fmt -check  (formatting verified)
✓ terraform validate    (syntax verified)
✓ tflint               (best practices verified)

Displays in PR: "All checks passed ✓"
```

#### Step 5: Merge to main
```
GitHub shows green checkmark
You merge PR
Code is now in main branch
```

#### step 6: Team member pulls and deploys
```bash
git pull origin main
make apply
# Teammate's laptop now has 3 workers too
```

**Notice:** Without setup.sh + Makefile, teammate couldn't easily test locally.  
**Notice:** Without GitHub Actions, bad code could merge to main.

---

## When to Use Each

| Situation | Use |
|-----------|-----|
| **First-time setup** | `bash terraform/setup.sh init` |
| **Fix formatting issues** | `make fmt` (in Makefile) |
| **Deploy cluster** | `make apply` |
| **Check cluster health** | `make status` |
| **Clean up** | `make destroy` |
| **Before pushing** | Wait for GitHub Actions in PR |
| **Before merging** | Check GitHub Actions status |

---

## The DevOps Truth

```
Pipeline + Local Tools ≠ Redundant
They're complementary:

Pipeline    = "Did you write good code?" (automated code review)
Local Tools = "Does it actually work?" (manual testing + provisioning)

Both needed = confident code + working infrastructure
```

---

## Simple Rule of Thumb

```
GitHub Actions = Speed bump between main branch and bad code
setup.sh       = Onboarding script for new developers  
Makefile       = Convenience layer for developers
terraform      = Actual infrastructure provisioning

Remove ANY ONE = Workflow breaks somewhere
```

---

*Recommendation: Keep all three. They serve different purposes and together create a professional DevOps workflow.*
