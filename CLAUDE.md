# CLAUDE.md - Project Context for AI Assistants

REMEMBER THAT IN THE DevOps-AI-Model-Automatization\README.md is the project description

> This file provides context for AI assistants (Claude, Copilot, etc.) working on this project.
> Read this file completely before starting any work.

---

## Project Overview

**Project Title:** "Application of DevOps Techniques in Implementing Automatic CI/CD Process for Training and Versioning AI Models"

**Type:** Bachelor's Thesis (Engineering Degree)

**Goal:** Compare manual vs. automated ML model deployment, demonstrating DevOps benefits for AI/ML workflows.

**Budget Constraint:** ~$50 USD total on AWS (one-time project - build, test, document, tear down)

---

## Repository Architecture

This project uses **three repositories** with **Git Submodules** for connection:

```
┌──────────────────────────────────────────┐
│  Water-Meters-Segmentation-Autimatization│  ◄── WORKING REPO (main)
│  github.com/Rafallost/...                │
├──────────────────────────────────────────┤
│  • ML code (WMS/)                        │
│  • Training data (DVC tracked)           │
│  • GitHub Actions workflows              │
│  • devops/ ← SUBMODULE                   │
└───────────────┬──────────────────────────┘
                │ git submodule
                ▼
┌─────────────────────────────────────────┐
│  DevOps-AI-Model-Automatization         │  ◄── THIS REPO (infrastructure)
│  github.com/Rafallost/...               │
├─────────────────────────────────────────┤
│  • Terraform modules                    │
│  • Helm charts                          │
│  • Automation scripts                   │
│  • Documentation & diagrams             │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  Water-Meters-Segmentation              │  ◄── REFERENCE (read-only)
│  github.com/Rafallost/...               │
├─────────────────────────────────────────┤
│  • Original U-Net model                 │
│  • Baseline: Dice 0.9275, IoU 0.8865    │
│  • DO NOT MODIFY                        │
└─────────────────────────────────────────┘
```

### Which Repository Am I In?

- **DevOps-AI-Model-Automatization** (this repo): Infrastructure, Terraform, Helm, scripts, documentation
- **Water-Meters-Segmentation-Autimatization**: ML code, training data, workflows, project-specific configs
- **Water-Meters-Segmentation**: Reference only - baseline metrics source

---

## Core System Flow

**This is the heart of the project.** Everything we build serves this flow:

```
USER uploads data → DATA QA → [FAIL: error message]
                           → [PASS: create branch + PR]
                                    ↓
                              TRAINING (up to 3 attempts)
                                    ↓
                              QUALITY GATE (vs baseline)
                                    ↓
                    [WORSE after 3 tries: reject PR with comment]
                    [BETTER: approve + merge → BUILD → DEPLOY]
```

### Detailed Steps:

1. **User provides new training data** (images + masks to `WMS/data/training/`)
2. **Data QA validates automatically:**
   - Image↔mask pairs match
   - Resolutions correct (512x512)
   - Masks are binary (0/255)
   - **FAIL:** PR comment with error list, label `invalid-data`
   - **PASS:** PR comment confirming data OK, proceed to training
3. **Training runs (up to 3 attempts):**
   - Each attempt uses different random seed
   - Logs to MLflow (metrics, model artifacts)
   - Model version = `{git_sha}-{data_version}`
4. **Quality Gate compares to baseline:**
   - Baseline: Dice ≥ 0.9075, IoU ≥ 0.8665 (with 2% tolerance)
   - **PASS:** Approve PR, ready for merge
   - **FAIL:** Retry with different seed (up to 3 times)
   - **FAIL after 3 attempts:** Reject PR with detailed comment
5. **After merge to main:**
   - Tag model version
   - Build Docker image → push to ECR
   - Helm deploy to k3s → smoke test
6. **Monitoring:** Prometheus + Grafana dashboards

---

## Tech Stack & Budget Decisions

### Why These Choices (Budget Optimization):

| Component     | Expensive Option      | Our Choice         | Savings  |
| ------------- | --------------------- | ------------------ | -------- |
| Kubernetes    | EKS ($73/mo.)         | k3s on EC2         | ~$70/mo. |
| ML Database   | RDS MySQL ($13/mo.)   | SQLite + S3        | ~$13/mo. |
| Networking    | NAT Gateway ($32/mo.) | Public subnet only | ~$32/mo. |
| Load Balancer | ALB ($16/mo.)         | NodePort           | ~$16/mo. |

### Stack Summary:

- **CI/CD:** GitHub Actions (free)
- **Data Versioning:** DVC + S3
- **Experiment Tracking:** MLflow (SQLite backend, S3 artifacts)
- **Containerization:** Docker + Helm
- **Kubernetes:** k3s on EC2 t3.small
- **Monitoring:** Prometheus + Grafana
- **IaC:** Terraform

---

## Directory Structure (This Repo)

```
DevOps-AI-Model-Automatization/
├── terraform/
│   └── modules/
│       ├── vpc/              # VPC with public subnet (NO NAT Gateway)
│       ├── ec2-k3s/          # EC2 instance with k3s + MLflow
│       ├── s3-mlops/         # S3 buckets for DVC + MLflow
│       ├── ecr/              # Docker registry
│       └── iam-github-oidc/  # GitHub Actions authentication
│
├── helm/
│   ├── ml-model/             # Generic ML model serving chart
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml  # NodePort (not LoadBalancer!)
│   │       └── servicemonitor.yaml
│   └── monitoring/           # Prometheus + Grafana config
│
├── scripts/
│   ├── data-qa.py            # Data validation script
│   ├── quality-gate.py       # Model evaluation vs baseline
│   ├── train-with-retry.py   # Training wrapper with retry logic
│   ├── setup-k3s.sh          # k3s installation script
│   ├── setup-mlflow.sh       # MLflow server setup
│   └── cleanup-aws.sh        # CRITICAL: Resource cleanup
│
├── docker/
│   ├── Dockerfile.serve.template
│   └── Dockerfile.train.template
│
├── docs/
│   ├── architecture.md
│   ├── repository-guide.md
│   ├── tech-stack.md
│   ├── aws-layout.md
│   ├── cost-analysis.md
│   ├── core-flow.md
│   └── diagrams/
│       ├── c4-context.mermaid
│       ├── c4-container.mermaid
│       ├── data-flow.mermaid
│       └── ci-cd-sequence.mermaid
│
├── CLAUDE.md                 # This file
├── Makefile
└── README.md
```

---

## Working Repo Structure (Water-Meters-Segmentation-Autimatization)

```
Water-Meters-Segmentation-Autimatization/
├── devops/                   # ← Git submodule (this repo)
│
├── .github/workflows/
│   ├── ci.yaml               # Code quality (flake8, black, pytest)
│   ├── data-qa.yaml          # Validates WMS/data/training/
│   ├── train-pr.yaml         # Training on PR (uses devops/scripts/)
│   └── release-deploy.yaml   # Build + deploy after merge
│
├── WMS/
│   ├── configs/
│   │   └── train.yaml        # Hyperparameters (epochs, LR, batch_size)
│   ├── data/
│   │   └── training/
│   │       ├── images/       # DVC tracked (1244 files, 512x512)
│   │       ├── masks/        # DVC tracked (1244 files, binary)
│   │       └── temp/         # Auto-generated splits (.gitignore)
│   ├── src/
│   │   ├── train.py          # Modified: + MLflow integration
│   │   ├── model.py          # U-Net architecture (unchanged)
│   │   ├── dataset.py        # PyTorch Dataset (unchanged)
│   │   ├── transforms.py     # Augmentations (unchanged)
│   │   ├── prepareDataset.py # 80/10/10 splits (unchanged)
│   │   └── serve/
│   │       └── app.py        # FastAPI serving
│   └── tests/
│
├── infrastructure/
│   ├── terraform.tfvars      # Project-specific Terraform values
│   └── helm-values.yaml      # Project-specific Helm overrides
│
├── comparison/
│   ├── manual/
│   │   └── instructions.md   # Manual deployment steps (for comparison)
│   └── results/
│
├── dvc.yaml                  # DVC pipeline definition
├── dvc.lock                  # Data version state
└── Makefile
```

---

## Key Files to Know

### Scripts (in this repo: `scripts/`)

| Script                | Purpose                                              | Usage                                                                 |
| --------------------- | ---------------------------------------------------- | --------------------------------------------------------------------- |
| `data-qa.py`          | Validate image↔mask pairs, resolutions, binary masks | `python data-qa.py WMS/data/training/ --output report.json`           |
| `quality-gate.py`     | Compare model metrics vs baseline                    | `python quality-gate.py --report results.json --baseline-dice 0.9275` |
| `train-with-retry.py` | Run training up to 3 times with different seeds      | `python train-with-retry.py --config train.yaml --max-retries 3`      |
| `cleanup-aws.sh`      | Delete ALL AWS resources                             | Run after project completion!                                         |

### Workflows (in Working repo: `.github/workflows/`)

| Workflow              | Trigger                                                   | Does                                      |
| --------------------- | --------------------------------------------------------- | ----------------------------------------- |
| `ci.yaml`             | Push/PR to main                                           | flake8, black, mypy, pytest               |
| `data-qa.yaml`        | PR with changes in `WMS/data/training/`                   | Validates data, posts PR comment          |
| `train-pr.yaml`       | PR with changes in `WMS/src/`, `WMS/configs/`, `dvc.lock` | Trains model (up to 3x), posts results    |
| `release-deploy.yaml` | Push to main                                              | Builds Docker, pushes ECR, deploys to k3s |

### Configuration Files

| File               | Location          | Purpose                                          |
| ------------------ | ----------------- | ------------------------------------------------ |
| `train.yaml`       | `WMS/configs/`    | Hyperparameters (epochs: 50, batch: 4, LR: 1e-4) |
| `terraform.tfvars` | `infrastructure/` | AWS region, instance type, your IP, bucket names |
| `helm-values.yaml` | `infrastructure/` | ECR URL, MLflow URI, resource limits             |
| `dvc.yaml`         | Root              | DVC pipeline stages (prepare, train)             |

---

## Baseline Metrics (From Original Repo)

**These are our targets for Quality Gate:**

| Metric | Baseline Value | Tolerance | Minimum Required |
| ------ | -------------- | --------- | ---------------- |
| Dice   | 0.9275         | 2%        | 0.9075           |
| IoU    | 0.8865         | 2%        | 0.8665           |

**Model Architecture:**

- U-Net with 1.97M parameters
- Input: 512x512 RGB images
- Output: 512x512 binary mask
- Encoder channels: 16→32→64→128→256

---

## Important Constraints

### Budget Constraints (CRITICAL):

- Total AWS budget: ~$50
- **DO NOT** use: EKS, RDS, NAT Gateway, Load Balancer
- **DO** use: k3s on EC2, SQLite, public subnet, NodePort
- **ALWAYS** run `cleanup-aws.sh` after testing

### Data Path:

- Correct: `WMS/data/training/images/` and `WMS/data/training/masks/`
- Wrong: `WMS/data/raw/` (does not exist)

### Model Storage:

- Models are stored in **MLflow only** (single source of truth)
- Do NOT store models in Git or DVC
- `WMS/models/` folder is for local development only

### Submodule Usage:

```bash
# Clone with submodule
git clone --recurse-submodules <repo-url>

# If already cloned without submodule
git submodule update --init --recursive

# Update submodule to latest
cd devops && git pull origin main && cd ..
git add devops && git commit -m "chore: update devops submodule"
```

---

## Writing Guidelines

### Documentation Style:

- **Academic tone** for thesis documentation
- Use proper citations where applicable
- Include diagrams (Mermaid format preferred)
- Structure: Introduction → Methodology → Implementation → Results → Conclusion

### Code Style:

- Python: Follow PEP 8, use type hints
- Terraform: Use modules, consistent naming (`wms-*`)
- YAML: 2-space indentation
- Comments: Explain WHY, not WHAT

### Commit Messages:

```
type: short description

Types: feat, fix, docs, chore, refactor, test
Examples:
- feat: add data-qa validation script
- fix: correct data path in dvc.yaml
- docs: update architecture diagram
- chore: update devops submodule
```

---

## Implementation Phases

| Phase | Description                | Main Deliverables                         |
| ----- | -------------------------- | ----------------------------------------- |
| 0     | Repository Setup           | Folder structure, submodule connection    |
| 1     | Architecture Documentation | docs/\*.md files                          |
| 2     | Mermaid Diagrams           | docs/diagrams/\*.mermaid                  |
| 3     | Foundation Setup           | Terraform modules, DVC config, train.yaml |
| 4     | ML Pipeline Setup          | Scripts, GitHub Actions workflows         |
| 5     | Kubernetes & Deployment    | Helm charts, Dockerfile, FastAPI app      |
| 6     | Monitoring                 | Prometheus + Grafana config               |
| 7     | Comparison Framework       | Manual instructions, metrics collector    |
| 8     | Testing & Documentation    | Tests, README, cleanup scripts            |

**Current Phase:** Check README.md or ask user

---

## Common Tasks

### Adding a New Terraform Module:

```bash
cd terraform/modules
mkdir new-module
touch new-module/{main.tf,variables.tf,outputs.tf}
```

### Creating a New Script:

```bash
cd scripts
touch new-script.py
chmod +x new-script.py
# Add shebang: #!/usr/bin/env python3
# Add docstring explaining purpose and usage
```

### Updating Documentation:

```bash
cd docs
# Edit relevant .md file
# If adding diagrams, put .mermaid files in docs/diagrams/
```

### Testing Locally:

```bash
# In Working repo
make submodule-init      # Get devops submodule
make data-qa             # Run data validation
make train-local         # Run training locally
make infra-plan          # Preview Terraform changes
```

---

## Troubleshooting

### "Submodule not found":

```bash
git submodule update --init --recursive
```

### "DVC data not found":

```bash
dvc pull  # Requires AWS credentials configured
```

### "MLflow connection refused":

- Check if EC2 is running
- Check Security Group allows port 5000
- Verify: `http://<EC2_IP>:5000`

### "Terraform state lock":

```bash
terraform force-unlock <lock-id>
```

### "AWS costs accumulating":

```bash
# IMMEDIATELY run:
bash scripts/cleanup-aws.sh
# Then verify in AWS Console
```

---

## Contact & Resources

- **Thesis Supervisor:** [Name]
- **Original Model Repo:** github.com/Rafallost/Water-Meters-Segmentation
- **Working Repo:** github.com/Rafallost/Water-Meters-Segmentation-Autimatization
- **This Repo:** github.com/Rafallost/DevOps-AI-Model-Automatization

---

## Quick Reference

```bash
# Clone everything
git clone --recurse-submodules https://github.com/Rafallost/Water-Meters-Segmentation-Autimatization.git

# Data validation
python devops/scripts/data-qa.py WMS/data/training/

# Training with retry
python devops/scripts/train-with-retry.py --config WMS/configs/train.yaml --max-retries 3

# Infrastructure
cd devops/terraform/modules && terraform init && terraform plan

# Deploy
helm upgrade --install wms-model devops/helm/ml-model/ -f infrastructure/helm-values.yaml

# CLEANUP (IMPORTANT!)
bash devops/scripts/cleanup-aws.sh
```
