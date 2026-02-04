# Implementation Plan (v5 - Budget Optimized + Repository Phases)

> **Budget:** ~$50 USD on AWS  
> **Goal:** One-time project - build, test, tear down

---

## Summary of Changes from Original Version

| Element         | Version v1 (expensive)     | Version v2 (budget)     | Savings  |
| --------------- | -------------------------- | ----------------------- | -------- |
| Kubernetes      | EKS ($0.10/h = ~$73/mo.)   | k3s on EC2              | ~$70/mo. |
| MLflow backend  | RDS MySQL (~$13/mo.)       | SQLite + S3             | ~$13/mo. |
| Networking      | NAT Gateway (~$32/mo.)     | Public subnet only      | ~$32/mo. |
| Model artifacts | DVC + MLflow (duplication) | MLflow as single source | Simpler  |

---

## Tech Stack

### Core MLOps/DevOps

- **Repo/CI:** GitHub + GitHub Actions (free)
- **Data versioning:** DVC + S3 remote
- **Experiment tracking:** MLflow (SQLite backend + S3 artifacts)
- **Containerization:** Docker + Helm
- **Kubernetes:** k3s on EC2 (t3.small/medium)

### Serving + Observability

- **Model serving:** FastAPI + uvicorn (simpler)
- **Monitoring:** Prometheus + Grafana (run only during testing)
- **EC2 metrics:** CloudWatch (backup)

### IaC

- **Terraform:** S3, IAM, EC2, ECR

---

## Core System Flow

### Flow Diagram (ASCII)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              CORE SYSTEM FLOW                                    │
└─────────────────────────────────────────────────────────────────────────────────┘

     ┌────────────┐
     │    USER    │
     └─────┬──────┘
           │
           ▼ (1) Provides new training data
     ┌─────────────┐      (images + masks)
     │   UPLOAD    │
     │    DATA     │
     └─────┬───────┘
           │
           ▼ (2) Automatic validation
     ┌─────────────┐
     │  DATA QA    │
     └─────┬───────┘
           │
     ┌─────┴─────┐
     │           │
     ▼           ▼
 ┌───────┐   ┌───────┐
 │ FAIL  │   │ PASS  │
 └───┬───┘   └───┬───┘
     │           │
     ▼           ▼ (3) Create branch + PR
 ┌─────────┐  ┌──────────────┐
 │  ERROR  │  │ AUTO BRANCH  │
 │ MESSAGE │  │ data/<id>    │
 └─────────┘  └──────┬───────┘
                     │
                     ▼ (4) Train model (up to 3 attempts)
               ┌─────────────┐
               │  TRAINING   │◄──────┐
               │  PIPELINE   │       │ (retry if fail)
               └─────┬───────┘       │
                     │               │
                     ▼ (5) Quality Gate
               ┌─────────────┐       │
               │ EVALUATION  │       │
               │ vs BASELINE │       │
               └─────┬───────┘       │
                     │               │
               ┌─────┴─────┐         │
               │           │         │
               ▼           ▼         │
           ┌───────┐   ┌───────┐     │
           │BETTER │   │WORSE  │     │
           └───┬───┘   └───┬───┘     │
               │           │         │
               │     ┌─────┴─────┐   │
               │     │attempt < 3│───┘
               │     └─────┬─────┘
               │           │ attempt = 3
               │           ▼
               │     ┌───────────┐
               │     │  REJECT   │
               │     │  PR +     │
               │     │  COMMENT  │
               │     └───────────┘
               │
               ▼ (6) Merge to main
         ┌───────────┐
         │  MERGE    │
         │  TO MAIN  │
         └─────┬─────┘
               │
               ▼ (7) Build + Deploy
         ┌───────────┐
         │  BUILD    │
         │  IMAGE    │
         └─────┬─────┘
               │
               ▼
         ┌───────────┐
         │  DEPLOY   │
         │  TO K3S   │
         └─────┬─────┘
               │
               ▼ (8) Smoke test + Monitoring
         ┌───────────┐
         │ MONITORING│
         │ PROMETHEUS│
         │ GRAFANA   │
         └───────────┘
```

### 3. Core Flow - Detailed Step Description

#### 3.1 User Provides Data

**Trigger:** User wants to add new training data (water meter images + segmentation masks)

**Actions:**

- 3.1.1 User adds a new batch of data:
  - Images: `WMS/data/training/images/id_*_value_*_*.jpg`
  - Masks: `WMS/data/training/masks/id_*_value_*_*.jpg`
- 3.1.2 User creates PR with new data (or pushes to `data/*` branch)
- 3.1.3 Optionally: upload directly to S3 (DVC remote) + update `.dvc` files

**Data requirements:**

- Format: JPG
- Resolution: 512x512 (or to be rescaled)
- Pairs: each image must have a corresponding mask (same name)
- Masks: grayscale, binary (0 = background, 255 = water meter)

---

#### 3.2 Data Validation (Data QA)

**Trigger:** PR with new data or changes in `WMS/data/training/`

**Automatic validation checks:**

- 3.2.1 Image↔mask pair matching (does every image have a mask and vice versa)
- 3.2.2 Resolutions (do images and masks have the same dimensions)
- 3.2.3 File formats (JPG/PNG)
- 3.2.4 Empty masks (e.g., if mask is completely black)
- 3.2.5 Mask binarity (are values only 0 and 255)
- 3.2.6 Basic statistics (file count, size distribution)

**Results:**

##### 3.2.A - For INVALID data:

```
┌─────────────────────────────────────────────────────────┐
│ ❌ DATA QA FAILED                                      │
├─────────────────────────────────────────────────────────┤
│ Status: FAIL                                            │
│ Images: 50 | Masks: 48                                  │
│                                                         │
│ Errors:                                                 │
│ - Missing masks for 2 images: [id_101, id_102]          │
│ - Different resolutions: id_103 (512x512 vs 256x256)    │
│                                                         │
│ ⚠️ Pipeline stopped. Fix data and try again.           │
└─────────────────────────────────────────────────────────┘
```

- Pipeline ends with **FAIL** status
- Bot adds comment to PR with list of errors
- PR is labeled `invalid-data`
- **User receives clear message about what to fix**

##### 3.2.B - For VALID data:

```
┌─────────────────────────────────────────────────────────┐
│ ✅ DATA QA PASSED                                      │
├─────────────────────────────────────────────────────────┤
│ Status: PASS                                            │
│ Images: 50 | Masks: 50 | Valid pairs: 50                │
│                                                         │
│ Stats:                                                  │
│ - Resolution: 512x512 (100%)                            │
│ - Empty masks: 0                                        │
│                                                         │
│ ✅ Data valid. Starting training...                    │
└─────────────────────────────────────────────────────────┘
```

- Bot publishes Data QA report as PR comment
- Pipeline proceeds to next step (training)
- **User receives confirmation that data is OK**

---

#### 3.3 Data Versioning and PR Creation

**Trigger:** Data QA PASSED

**Actions:**

- 3.3.1 Data is added to DVC (`dvc add`), `dvc.lock` is updated
- 3.3.2 If user didn't create PR, system automatically:
  - Creates branch `data/<batch-id>-<timestamp>`
  - Opens PR to `main` with:
    - Updated `.dvc` files
    - `dvc.lock`
    - Data QA report
- 3.3.3 PR is labeled `auto-training`

---

#### 3.4 Model Training (up to 3 attempts)

**Trigger:** PR with `auto-training` label or changes in `WMS/src/`, `WMS/configs/`, `dvc.lock`

**Training process:**

##### 3.4.1 Initialization

- `dvc pull` - download data from S3
- Environment setup (dependencies, GPU if available)
- Load configuration from `WMS/configs/train.yaml`

##### 3.4.2 Training (attempt N of 3)

```
┌─────────────────────────────────────────────────────────┐
│ 🏋️ TRAINING - Attempt 1/3                              │
├─────────────────────────────────────────────────────────┤
│ Config: WMS/configs/train.yaml                          │
│ Data version: abc1234                                   │
│ Epochs: 50 | Batch: 4 | LR: 1e-4                        │
├─────────────────────────────────────────────────────────┤
│ Progress: [████████████████████] 100%                   │
│ Train Loss: 0.0055 | Val Loss: 0.0166                   │
│ Val Dice: 0.9066 | Val IoU: 0.8799                      │
├─────────────────────────────────────────────────────────┤
│ ⏱️ Duration: 45 min                                    │
│ 📊 MLflow Run: https://mlflow.../runs/xyz789           │
└─────────────────────────────────────────────────────────┘
```

##### 3.4.3 MLflow Logging

- Hyperparameters (LR, batch size, epochs)
- Metrics per epoch (train_loss, val_loss, val_dice, val_iou)
- Training time (for comparison in Phase 7)
- Model artifact (`best.pth`)
- Version: `model_version = {git_sha}-{data_version}`

---

#### 3.5 Quality Gate (evaluation vs baseline)

**Trigger:** Training completed

**PASS criteria:**

```python
PASS if:
    val_dice >= BASELINE_DICE - TOLERANCE  # e.g., 0.9275 - 0.02 = 0.9075
    AND val_iou >= BASELINE_IOU - TOLERANCE  # e.g., 0.8865 - 0.02 = 0.8665
    AND smoke_test_inference == PASS
```

**Baseline (from original repo):**

- Dice: **0.9275**
- IoU: **0.8865**
- Tolerance: **0.02** (2% margin)

##### 3.5.A - Model BETTER or equal to baseline:

```
┌─────────────────────────────────────────────────────────┐
│ ✅ QUALITY GATE PASSED                                 │
├─────────────────────────────────────────────────────────┤
│ Model Version: abc1234-def5678                          │
│                                                         │
│ Results vs Baseline:                                    │
│ ┌─────────┬──────────┬──────────┬──────────┐            │
│ │ Metric  │ Baseline │ Current  │ Status   │            │
│ ├─────────┼──────────┼──────────┼──────────┤            │
│ │ Dice    │ 0.9275   │ 0.9301   │ ✅ +0.3% │           │
│ │ IoU     │ 0.8865   │ 0.8890   │ ✅ +0.3% │           │
│ └─────────┴──────────┴──────────┴──────────┘            │
│                                                         │
│ ✅ Model ready for deployment                          │
│ 🔀 PR approved for merge                               │
└─────────────────────────────────────────────────────────┘
```

- PR is marked as **approved**
- Bot adds comment with results
- PR can be merged (automatically or manually)

##### 3.5.B - Model WORSE than baseline:

```
┌─────────────────────────────────────────────────────────┐
│ ⚠️ QUALITY GATE FAILED - Attempt 1/3                   │
├─────────────────────────────────────────────────────────┤
│ Model Version: abc1234-def5678                          │
│                                                         │
│ Results vs Baseline:                                    │
│ ┌─────────┬──────────┬──────────┬─────────┐             │
│ │ Metric  │ Baseline │ Current  │ Status  │             │
│ ├─────────┼──────────┼──────────┼─────────┤             │
│ │ Dice    │ 0.9275   │ 0.8950   │ ❌ -3.5%│            │
│ │ IoU     │ 0.8865   │ 0.8600   │ ❌ -3.0%│            │
│ └─────────┴──────────┴──────────┴─────────┘             │
│                                                         │
│ 🔄 Retrying with different seed... (2/3 remaining)     │
└─────────────────────────────────────────────────────────┘
```

**Retry logic:**

```
attempt = 1
while attempt <= 3:
    train_model(seed=attempt)
    if quality_gate_passed():
        approve_pr()
        break
    attempt += 1

if attempt > 3:
    reject_pr_with_comment()
```

##### 3.5.C - After 3 failed attempts:

```
┌─────────────────────────────────────────────────────────┐
│ ❌ QUALITY GATE FAILED - All 3 attempts exhausted      │
├─────────────────────────────────────────────────────────┤
│ All attempts:                                           │
│ ┌─────────┬──────────┬──────────┬──────────┐           │
│ │ Attempt │ Dice     │ IoU      │ Status   │           │
│ ├─────────┼──────────┼──────────┼──────────┤           │
│ │ 1       │ 0.8950   │ 0.8600   │ ❌ FAIL  │           │
│ │ 2       │ 0.9010   │ 0.8650   │ ❌ FAIL  │           │
│ │ 3       │ 0.8980   │ 0.8620   │ ❌ FAIL  │           │
│ └─────────┴──────────┴──────────┴──────────┘           │
│                                                         │
│ Possible reasons:                                       │
│ - New data may be of lower quality                     │
│ - Data distribution shift                              │
│ - Insufficient training data                           │
│                                                         │
│ 🚫 PR marked as rejected                               │
│ 💬 Please review data quality and try again            │
└─────────────────────────────────────────────────────────┘
```

- PR is labeled `training-failed`
- Bot adds detailed comment with results from all attempts
- PR is NOT automatically closed (user may want to investigate)
- Suggestions for possible causes

---

#### 3.6 Merge to main (Model Release)

**Trigger:** Quality Gate PASSED + PR approved

**Actions:**

- 3.6.1 PR is merged to `main`
- 3.6.2 `release-deploy` pipeline runs automatically:
  - Tags model version (`v1.2.3` or `model-abc1234`)
  - "Promotes" model in MLflow Registry to `Production` stage
  - Builds Docker image with new model
  - Pushes to ECR

---

#### 3.7 Deploy to Kubernetes (k3s)

**Trigger:** New image in ECR after merge

**Actions:**

- 3.7.1 Helm deploy to namespace `model-<version>`
- 3.7.2 Smoke test:
  - Request to `/health`
  - Request to `/predict` with test image
  - Check `/metrics`
- 3.7.3 If smoke test FAIL → automatic rollback
- 3.7.4 If PASS → new version is active

---

#### 3.8 Monitoring and feedback loop

**Continuous:**

- Prometheus collects metrics (latency, errors, CPU/RAM)
- Grafana dashboards show performance per version
- Alerts on anomalies (optional)

---

### Core Flow Summary

| Step | Trigger       | Output            | User Message                            |
| ---- | ------------- | ----------------- | --------------------------------------- |
| 3.1  | User upload   | New files in repo | -                                       |
| 3.2  | PR/push       | QA report         | ✅ Data OK / ❌ Error list              |
| 3.3  | QA pass       | Branch + PR       | "Created PR, starting training"         |
| 3.4  | PR ready      | MLflow runs       | "Training in progress... (attempt N/3)" |
| 3.5  | Training done | Pass/Fail         | ✅ Model better / ❌ Results + reasons  |
| 3.6  | QA pass       | Merge + tag       | "Model v1.2.3 released"                 |
| 3.7  | Merge         | Deploy            | "Deployed to production"                |
| 3.8  | Always        | Metrics           | Dashboard link                          |

---

## Repository Structure

> **Separation of concerns** - three repositories with clearly defined roles
> **Connection:** Git Submodules (simpler and more universal)

### Repository Dependencies Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         REPOSITORY ARCHITECTURE                              │
│                            (Git Submodules)                                  │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│  Water-Meters-Segmentation-Autimatization│  ◄── WORKING REPO (main)
│  (GitHub: Rafallost/...)                 │
├──────────────────────────────────────────┤
│  • ML code (WMS/)                        │
│  • Training data (DVC tracked)           │
│  • Project configuration                 │
│  • GitHub Actions workflows              │
│  • devops/ ← SUBMODULE                   │
└───────────────┬──────────────────────────┘
                │
                │ git submodule
                ▼
┌─────────────────────────────────────────┐
│  DevOps-AI-Model-Automatization         │  ◄── SUBMODULE (infrastructure)
│  (GitHub: Rafallost/...)                │
├─────────────────────────────────────────┤
│  • Terraform modules                    │
│  • Helm charts                          │
│  • Scripts (data-qa.py, setup-k3s.sh)   │
│  • Dockerfile templates                 │
│  • DevOps documentation                 │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  Water-Meters-Segmentation              │  ◄── REFERENCE (read-only)
│  (GitHub: Rafallost/...)                │
├─────────────────────────────────────────┤
│  • Original U-Net model                 │
│  • Baseline results (Dice 0.9275)       │
│  • DO NOT MODIFY                        │
└─────────────────────────────────────────┘
```

---

### Repo 1: DevOps-AI-Model-Automatization (Submodule)

**URL:** `https://github.com/Rafallost/DevOps-AI-Model-Automatization`

**Purpose:** Reusable infrastructure - Terraform, Helm, scripts (can be used for different ML projects)

**Structure with explanations:**

```
DevOps-AI-Model-Automatization/
│
├── terraform/                            # 🏗️ INFRASTRUCTURE AS CODE
│   ├── modules/                          # Terraform modules (reusable)
│   │   │
│   │   ├── vpc/                          # 🌐 Virtual Private Cloud
│   │   │   ├── main.tf                   #    VPC definition, subnet, routing
│   │   │   ├── variables.tf              #    Input variables (CIDR, region)
│   │   │   └── outputs.tf                #    Output values (VPC ID, subnet ID)
│   │   │   # EXPLANATION: Creates isolated network in AWS.
│   │   │   # Budget version: only PUBLIC subnet (no NAT Gateway).
│   │   │
│   │   ├── ec2-k3s/                      # 🖥️ EC2 Server with Kubernetes (k3s)
│   │   │   ├── main.tf                   #    EC2 instance definition
│   │   │   ├── variables.tf              #    Instance type, SSH key, etc.
│   │   │   ├── outputs.tf                #    Public IP, instance ID
│   │   │   └── user-data.sh              #    Script run at EC2 startup
│   │   │   # EXPLANATION: Instead of EKS ($73/mo.) we use EC2 with k3s (~$15/mo.).
│   │   │   # user-data.sh installs: k3s, Helm, MLflow, Docker.
│   │   │
│   │   ├── s3-mlops/                     # 🗄️ Storage for ML
│   │   │   ├── main.tf                   #    S3 buckets
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │   # EXPLANATION: Two buckets:
│   │   │   # 1. wms-dvc-data - training data (DVC remote)
│   │   │   # 2. wms-mlflow-artifacts - models and MLflow artifacts
│   │   │
│   │   ├── ecr/                          # 🐳 Docker Registry
│   │   │   ├── main.tf                   #    ECR repository
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │   # EXPLANATION: Private registry for Docker images.
│   │   │   # Stores images wms-model:v1, wms-model:v2, etc.
│   │   │
│   │   └── iam-github-oidc/              # 🔐 Permissions for GitHub Actions
│   │       ├── main.tf                   #    IAM roles, policies
│   │       ├── variables.tf
│   │       └── outputs.tf
│   │       # EXPLANATION: Allows GitHub Actions to log into AWS
│   │       # without long-lived credentials (OIDC federation).
│   │
│   └── README.md                         # Terraform documentation
│
├── helm/                                 # ☸️ KUBERNETES DEPLOYMENT
│   │
│   ├── ml-model/                         # Chart for ML model
│   │   ├── Chart.yaml                    #    Chart metadata (name, version)
│   │   ├── values.yaml                   #    Default values (replicas, resources)
│   │   └── templates/                    #    YAML templates
│   │       ├── deployment.yaml           #    Pod with model
│   │       ├── service.yaml              #    Expose as NodePort
│   │       └── servicemonitor.yaml       #    Prometheus integration
│   │   # EXPLANATION: Defines HOW to run model in Kubernetes.
│   │   # Helm enables easy versioning and deployment rollback.
│   │
│   └── monitoring/                       # Monitoring stack
│       └── values.yaml                   #    Prometheus + Grafana configuration
│       # EXPLANATION: Minimal monitoring configuration.
│       # Run only during testing (resource savings).
│
├── scripts/                              # 🔧 AUTOMATION SCRIPTS
│   │
│   ├── setup-k3s.sh                      # k3s installation on EC2
│   │   # EXPLANATION: Run manually or via Terraform.
│   │   # Installs: k3s, kubectl, helm.
│   │
│   ├── setup-mlflow.sh                   # MLflow configuration
│   │   # EXPLANATION: Starts MLflow server with SQLite backend.
│   │   # Artifacts go to S3.
│   │
│   ├── data-qa.py                        # 📊 Data validation
│   │   # EXPLANATION: Checks:
│   │   # - Does every image have a mask
│   │   # - Do resolutions match
│   │   # - Are masks binary (0/255)
│   │   # Returns JSON report + exit code.
│   │
│   ├── quality-gate.py                   # 🚦 Model evaluation vs baseline
│   │   # EXPLANATION: Compares new model metrics with baseline.
│   │   # Decides: PASS (merge PR) or FAIL (retry/reject).
│   │
│   ├── train-with-retry.py               # 🔄 Training with retry logic
│   │   # EXPLANATION: Wrapper for train.py from original repo.
│   │   # Adds: max 3 attempts, different seeds, reporting.
│   │
│   └── cleanup-aws.sh                    # 🧹 AWS resource cleanup
│       # EXPLANATION: CRITICAL! Deletes all AWS resources.
│       # Run after project completion to stop charges.
│
├── docker/                               # 🐳 DOCKERFILE TEMPLATES
│   │
│   ├── Dockerfile.serve.template         # Template for serving
│   │   # EXPLANATION: Base Dockerfile for FastAPI.
│   │   # Working repo copies and customizes.
│   │
│   └── Dockerfile.train.template         # Template for training
│       # EXPLANATION: Optional - for containerized training.
│
├── docs/                                 # 📚 DOCUMENTATION
│   ├── architecture.md                   # Overall system architecture
│   ├── setup-guide.md                    # How to use in a new project
│   └── diagrams/                         # Mermaid diagrams
│       ├── c4-context.mermaid            #    Context diagram (actors, systems)
│       ├── c4-container.mermaid          #    Container diagram (components)
│       ├── data-flow.mermaid             #    Data flow
│       └── ci-cd-sequence.mermaid        #    CI/CD sequence
│
├── Makefile                              # Command shortcuts
└── README.md                             # Main documentation
```

---

### Repo 2: Water-Meters-Segmentation-Autimatization (Working)

**URL:** `https://github.com/Rafallost/Water-Meters-Segmentation-Autimatization`

**Purpose:** Main working repository - ML model + data + pipeline

**Structure with explanations:**

```
Water-Meters-Segmentation-Autimatization/
│
├── .gitmodules                           # 🔗 Git Submodule configuration
│   # EXPLANATION: Defines connection to DevOps repo.
│   # Contains: path=devops, url=https://github.com/.../DevOps-AI-Model-Automatization.git
│
├── devops/                               # ← GIT SUBMODULE
│   │   # EXPLANATION: This is NOT a copy - it's a LINK to DevOps repo.
│   │   # Git stores only commit hash, not files.
│   │   # Cloning: git clone --recurse-submodules ...
│   │
│   ├── terraform/                        # Available via devops/terraform/
│   ├── helm/                             # Available via devops/helm/
│   ├── scripts/                          # Available via devops/scripts/
│   └── ...
│
├── .github/                              # 🤖 GITHUB ACTIONS
│   └── workflows/
│       │
│       ├── ci.yaml                       # Code quality + tests
│       │   # TRIGGER: push/PR to main
│       │   # DOES: flake8, black, mypy, pytest
│       │
│       ├── data-qa.yaml                  # Data validation
│       │   # TRIGGER: PR with changes in WMS/data/training/
│       │   # DOES: python devops/scripts/data-qa.py
│       │   # OUTPUT: Comment in PR with report
│       │
│       ├── train-pr.yaml                 # Training on PR
│       │   # TRIGGER: PR with changes in src/, configs/, dvc.lock
│       │   # DOES: python devops/scripts/train-with-retry.py
│       │   # OUTPUT: Comment in PR with results, PASS/FAIL
│       │
│       └── release-deploy.yaml           # Deploy after merge
│           # TRIGGER: push to main
│           # DOES: build Docker → push ECR → helm deploy
│           # OUTPUT: New version in k3s
│
├── WMS/                                  # 🧠 ML CODE (from original repo)
│   │
│   ├── configs/                          # ⚙️ CONFIGURATION (NEW)
│   │   └── train.yaml                    # Hyperparameters
│   │   # EXPLANATION: Extracted from hardcoded values in train.py.
│   │   # Changes here trigger retraining.
│   │   # Contains: epochs, batch_size, learning_rate, augmentations, baseline.
│   │
│   ├── data/
│   │   └── training/                     # 📸 TRAINING DATA
│   │       │
│   │       ├── images/                   # Water meter images (DVC tracked)
│   │       │   └── id_*_value_*_*.jpg    # 1244 files, 512x512
│   │       │   # EXPLANATION: Original water meter photos.
│   │       │   # Tracked by DVC (not Git) - too large.
│   │       │
│   │       ├── masks/                    # Segmentation masks (DVC tracked)
│   │       │   └── id_*_value_*_*.jpg    # 1244 files, 512x512, binary
│   │       │   # EXPLANATION: Ground truth - what model should predict.
│   │       │   # White (255) = water meter, black (0) = background.
│   │       │
│   │       └── temp/                     # ⚠️ AUTO-GENERATED (.gitignore)
│   │           ├── train/                # 80% of data (images/ + masks/)
│   │           ├── val/                  # 10% of data
│   │           └── test/                 # 10% of data
│   │           # EXPLANATION: Created by prepareDataset.py.
│   │           # DO NOT COMMIT - generated automatically.
│   │
│   ├── models/                           # 🎯 MODELS
│   │   └── .gitkeep                      # Empty file (folder in Git)
│   │   # EXPLANATION: Models are NOT in Git or DVC.
│   │   # MLflow is SINGLE SOURCE OF TRUTH for models.
│   │   # This folder is only for local development.
│   │
│   ├── src/                              # 💻 SOURCE CODE
│   │   │
│   │   ├── train.py                      # 🏋️ Training script (MODIFIED)
│   │   │   # EXPLANATION: Original + added:
│   │   │   # - MLflow integration (logging metrics, models)
│   │   │   # - Config loading from YAML
│   │   │   # - Versioning: git_sha + data_version
│   │   │
│   │   ├── model.py                      # U-Net architecture (UNCHANGED)
│   │   │   # EXPLANATION: 1.97M parameters, 512x512 input.
│   │   │   # Encoder: 16→32→64→128→256 channels.
│   │   │
│   │   ├── dataset.py                    # PyTorch Dataset (UNCHANGED)
│   │   │   # EXPLANATION: Loads image+mask pairs.
│   │   │
│   │   ├── transforms.py                 # Augmentations (UNCHANGED)
│   │   │   # EXPLANATION: flip, rotate, color jitter.
│   │   │
│   │   ├── prepareDataset.py             # Creating splits (UNCHANGED)
│   │   │   # EXPLANATION: Copies 80/10/10 to temp/.
│   │   │
│   │   ├── predicts.py                   # Inference (UNCHANGED)
│   │   │   # EXPLANATION: Prediction on new images.
│   │   │
│   │   └── serve/                        # 🌐 API SERVING (NEW)
│   │       ├── app.py                    # FastAPI application
│   │       │   # EXPLANATION: REST API for model.
│   │       │   # Endpoints: /health, /predict, /metrics
│   │       │   # Prometheus metrics: latency, count, errors.
│   │       │
│   │       └── __init__.py
│   │
│   └── tests/                            # 🧪 TESTS (NEW)
│       ├── test_model.py                 # Architecture tests
│       ├── test_dataset.py               # Data loading tests
│       └── test_inference.py             # Inference tests
│       # EXPLANATION: Run in CI (ci.yaml).
│       # Verify code works before merge.
│
├── infrastructure/                       # 🏗️ CONFIGURATION FOR THIS PROJECT
│   │
│   ├── terraform.tfvars                  # Terraform variables
│   │   # EXPLANATION: Values SPECIFIC to WMS:
│   │   # - region, instance_type, bucket names
│   │   # - Your IP for Security Group
│   │   # Used: terraform apply -var-file=terraform.tfvars
│   │
│   └── helm-values.yaml                  # Helm overrides
│       # EXPLANATION: Values SPECIFIC to WMS:
│       # - ECR repository URL
│       # - MLflow URI
│       # - Resource limits
│       # Used: helm install -f helm-values.yaml
│
├── docker/                               # 🐳 DOCKERFILE FOR WMS
│   └── Dockerfile.serve                  # Dockerfile for serving
│   # EXPLANATION: Based on template from devops/, but:
│   # - Copies WMS/src/serve/
│   # - Sets MODEL_VERSION
│
├── comparison/                           # 📊 MANUAL vs AUTO COMPARISON (NEW)
│   │
│   ├── manual/
│   │   └── instructions.md               # Manual deployment instructions
│   │   # EXPLANATION: Step by step what to do manually.
│   │   # Form to record time for each step.
│   │
│   └── results/                          # Comparison results
│       └── .gitkeep
│   # EXPLANATION: Main deliverable for engineering thesis.
│   # Comparison of times, errors, reproducibility.
│
├── dvc.yaml                              # 📦 DVC Pipeline
│   # EXPLANATION: Defines stages:
│   # 1. prepare - prepareDataset.py
│   # 2. train - train.py
│   # Run: dvc repro
│
├── dvc.lock                              # DVC pipeline state
│   # EXPLANATION: Hash of all dependencies and outputs.
│   # Change = potential retraining.
│
├── .dvc/
│   └── config                            # DVC remote configuration
│   # EXPLANATION: Points to S3 bucket.
│   # dvc remote add -d s3remote s3://wms-dvc-data/
│
├── requirements.txt                      # Python dependencies
│   # EXPLANATION: torch, torchvision, mlflow, fastapi, etc.
│
├── Makefile                              # 🔧 Command shortcuts
│   # EXPLANATION: make train-local, make deploy, make clean
│   # Uses scripts from devops/ submodule.
│
└── README.md                             # Project documentation
```

---

### Repo 3: Water-Meters-Segmentation (Reference)

**URL:** `https://github.com/Rafallost/Water-Meters-Segmentation`

**Purpose:** Original project - source of baseline metrics

**Status:** ⚠️ READ-ONLY - do not modify

**Used as:**

- Source of baseline metrics (Dice 0.9275, IoU 0.8865)
- U-Net architecture documentation
- Results comparison for engineering thesis

---

### How to Use Submodule

**Cloning repository (with submodule):**

```bash
# Option 1: Clone with submodules immediately
git clone --recurse-submodules https://github.com/Rafallost/Water-Meters-Segmentation-Autimatization.git

# Option 2: If already cloned without submodules
cd Water-Meters-Segmentation-Autimatization
git submodule update --init --recursive
```

**Updating submodule to latest version:**

```bash
cd devops
git pull origin main
cd ..
git add devops
git commit -m "chore: update devops submodule"
```

---

### Repository Summary

| Repository                                   | Role           | Connection             | Main Content                      |
| -------------------------------------------- | -------------- | ---------------------- | --------------------------------- |
| **Water-Meters-Segmentation-Autimatization** | Working (main) | -                      | ML code, data, workflows, configs |
| **DevOps-AI-Model-Automatization**           | Infrastructure | Submodule in `devops/` | Terraform, Helm, scripts          |
| **Water-Meters-Segmentation**                | Reference      | None (docs only)       | Baseline metrics                  |

---

## Implementation Phases

### Phase 0: Repository Setup (NEW)

**Status:** PENDING

**Goal:** Prepare repository structure before starting actual work.

**Tasks:**

#### 0.1 Create DevOps-AI-Model-Automatization Repository

```bash
# On GitHub: Create new repository "DevOps-AI-Model-Automatization"
# Locally:
mkdir DevOps-AI-Model-Automatization
cd DevOps-AI-Model-Automatization
git init

# Create basic structure
mkdir -p terraform/modules/{vpc,ec2-k3s,s3-mlops,ecr,iam-github-oidc}
mkdir -p helm/{ml-model/templates,monitoring}
mkdir -p scripts
mkdir -p docker
mkdir -p docs/diagrams

# Placeholder files
touch terraform/modules/vpc/{main.tf,variables.tf,outputs.tf}
touch terraform/modules/ec2-k3s/{main.tf,variables.tf,outputs.tf,user-data.sh}
touch terraform/modules/s3-mlops/{main.tf,variables.tf,outputs.tf}
touch terraform/modules/ecr/{main.tf,variables.tf,outputs.tf}
touch terraform/modules/iam-github-oidc/{main.tf,variables.tf,outputs.tf}
touch terraform/README.md

touch helm/ml-model/{Chart.yaml,values.yaml}
touch helm/ml-model/templates/{deployment.yaml,service.yaml,servicemonitor.yaml}
touch helm/monitoring/values.yaml

touch scripts/{setup-k3s.sh,setup-mlflow.sh,data-qa.py,quality-gate.py,train-with-retry.py,cleanup-aws.sh}

touch docker/{Dockerfile.serve.template,Dockerfile.train.template}

touch docs/{architecture.md,setup-guide.md}
touch docs/diagrams/{c4-context.mermaid,c4-container.mermaid,data-flow.mermaid,ci-cd-sequence.mermaid}

touch Makefile README.md

# Initial commit
git add .
git commit -m "chore: initial repository structure"
git remote add origin https://github.com/Rafallost/DevOps-AI-Model-Automatization.git
git push -u origin main
```

#### 0.2 Prepare Water-Meters-Segmentation-Autimatization

```bash
cd Water-Meters-Segmentation-Autimatization

# Add submodule
git submodule add https://github.com/Rafallost/DevOps-AI-Model-Automatization.git devops

# Create new folders (not in original repo)
mkdir -p .github/workflows
mkdir -p WMS/configs
mkdir -p WMS/src/serve
mkdir -p WMS/tests
mkdir -p infrastructure
mkdir -p docker
mkdir -p comparison/manual
mkdir -p comparison/results

# Create placeholder files
touch .github/workflows/{ci.yaml,data-qa.yaml,train-pr.yaml,release-deploy.yaml}
touch WMS/configs/train.yaml
touch WMS/src/serve/{app.py,__init__.py}
touch WMS/tests/{test_model.py,test_dataset.py,test_inference.py}
touch infrastructure/{terraform.tfvars,helm-values.yaml}
touch docker/Dockerfile.serve
touch comparison/manual/instructions.md
touch comparison/results/.gitkeep

# Create .gitignore for temp/
echo "temp/" >> WMS/data/training/.gitignore

# Commit
git add .
git commit -m "chore: add DevOps submodule and new folder structure"
git push
```

#### 0.3 Verification

- [ ] DevOps repo created with full folder structure
- [ ] Submodule added to Working repo
- [ ] `git submodule update --init --recursive` works
- [ ] All folders visible after `git clone --recurse-submodules`

---

### Phase 1: Architecture Documentation

**Status:** PENDING

**Deliverables:**

- [ ] `docs/architecture.md` - High level architecture documentation
- [ ] `docs/repository-guide.md` - Description of 3 repositories and their connection
- [ ] `docs/tech-stack.md` - Tech stack specification (with budget justification)
- [ ] `docs/aws-layout.md` - AWS infrastructure layout (budget version)
- [ ] `docs/cost-analysis.md` - AWS cost analysis
- [ ] `docs/core-flow.md` - Detailed Core System Flow description

**Where to create files:**

| File                | Repository                     | Location |
| ------------------- | ------------------------------ | -------- |
| architecture.md     | DevOps-AI-Model-Automatization | `docs/`  |
| repository-guide.md | DevOps-AI-Model-Automatization | `docs/`  |
| tech-stack.md       | DevOps-AI-Model-Automatization | `docs/`  |
| aws-layout.md       | DevOps-AI-Model-Automatization | `docs/`  |
| cost-analysis.md    | DevOps-AI-Model-Automatization | `docs/`  |
| core-flow.md        | DevOps-AI-Model-Automatization | `docs/`  |

**Existing repo context:**

> Repo `Water-Meters-Segmentation-Autimatization` already has `WMS/` folder copied from original project.
> Data structure is `WMS/data/training/images/` and `WMS/data/training/masks/`.

**Existing files in WMS/src/ (from original repo):**

- `train.py` - Training with early stopping, 50 epochs, Adam optimizer
- `model.py` - U-Net (1.97M parameters, 512x512 input)
- `dataset.py` - PyTorch Dataset class
- `transforms.py` - Augmentations (flip, rotate, color jitter)
- `prepareDataset.py` - 80/10/10 splits to temp/
- `predicts.py` - Inference on new images

**Model specs (from original repo):**

- Test Dice: **0.9275**
- Test IoU: **0.8865**
- Epochs: 51 (best at 46)
- LR: 1e-4 with ReduceLROnPlateau
- Batch size: 4
- Loss: BCEWithLogitsLoss

---

### Phase 2: Mermaid Diagrams

**Status:** PENDING

**Deliverables:**

- [ ] `docs/diagrams/diagrams.md` - All diagrams in Mermaid format:
  - C4 Context diagram - System overview with actors
  - Data Flow diagram - Training and deployment pipeline
  - Deployment diagram - AWS infrastructure layout **(k3s version)**
  - CI/CD Sequence diagram - Step-by-step pipeline flow
  - Model Versioning flow - How models are versioned and deployed
  - Cost comparison diagram - EKS vs k3s

**Where to create files:**

| File                   | Repository                     | Location         |
| ---------------------- | ------------------------------ | ---------------- |
| c4-context.mermaid     | DevOps-AI-Model-Automatization | `docs/diagrams/` |
| c4-container.mermaid   | DevOps-AI-Model-Automatization | `docs/diagrams/` |
| data-flow.mermaid      | DevOps-AI-Model-Automatization | `docs/diagrams/` |
| ci-cd-sequence.mermaid | DevOps-AI-Model-Automatization | `docs/diagrams/` |

---

### Phase 3: Foundation Setup

**Status:** PENDING

**Objectives:**

- Set up version control for data and models
- Provision AWS infrastructure **(budget version)**
- Configure remote storage

**Where to create files:**

| File                    | Repository | Location                             | Description             |
| ----------------------- | ---------- | ------------------------------------ | ----------------------- |
| vpc/main.tf             | DevOps     | `terraform/modules/vpc/`             | VPC module              |
| ec2-k3s/main.tf         | DevOps     | `terraform/modules/ec2-k3s/`         | EC2 + k3s module        |
| s3-mlops/main.tf        | DevOps     | `terraform/modules/s3-mlops/`        | S3 buckets module       |
| ecr/main.tf             | DevOps     | `terraform/modules/ecr/`             | ECR module              |
| iam-github-oidc/main.tf | DevOps     | `terraform/modules/iam-github-oidc/` | IAM module              |
| terraform.tfvars        | Working    | `infrastructure/`                    | Project-specific values |
| dvc.yaml                | Working    | `/`                                  | DVC pipeline            |
| train.yaml              | Working    | `WMS/configs/`                       | Hyperparameters         |
| Makefile                | Working    | `/`                                  | Command shortcuts       |

**Tasks:**

#### 3.1 DVC Initialization (in Working repo)

```bash
cd Water-Meters-Segmentation-Autimatization

# Initialize DVC
dvc init

# Configure S3 remote
dvc remote add -d s3remote s3://wms-dvc-data/dvc
dvc remote modify s3remote region eu-central-1

# Track training data
# PATH: WMS/data/training/ (NOT data/raw/)
dvc add WMS/data/training/images/
dvc add WMS/data/training/masks/

git add WMS/data/training/images.dvc WMS/data/training/masks.dvc .dvc/ dvc.yaml
git commit -m "chore: initialize DVC with training data"
```

#### 3.2 Create DVC Pipeline (in Working repo)

Create `dvc.yaml`:

```yaml
stages:
  prepare:
    cmd: python WMS/src/prepareDataset.py
    deps:
      - WMS/data/training/images
      - WMS/data/training/masks
      - WMS/src/prepareDataset.py
    outs:
      - WMS/data/training/temp/train
      - WMS/data/training/temp/val
      - WMS/data/training/temp/test

  train:
    cmd: python WMS/src/train.py --config WMS/configs/train.yaml
    deps:
      - WMS/data/training/temp/train
      - WMS/data/training/temp/val
      - WMS/data/training/temp/test
      - WMS/src/train.py
      - WMS/src/model.py
      - WMS/src/dataset.py
      - WMS/src/transforms.py
      - WMS/configs/train.yaml
    metrics:
      - WMS/models/metrics.json:
          cache: false
```

#### 3.3 Training Config (NEW - in Working repo)

Create `WMS/configs/train.yaml`:

```yaml
# Hyperparameters extracted from original train.py

model:
  architecture: "unet"
  input_channels: 3
  output_channels: 1
  input_size: 512

training:
  epochs: 50
  batch_size: 4
  learning_rate: 0.0001
  weight_decay: 0.0001
  early_stopping_patience: 5

  scheduler:
    factor: 0.5
    patience: 3
    min_lr: 0.000001

data:
  train_split: 0.8
  val_split: 0.1
  test_split: 0.1

augmentation:
  horizontal_flip: 0.5
  vertical_flip: 0.3
  rotation_degrees: 10
  rotation_prob: 0.5
  color_jitter_prob: 0.3

# Baseline metrics (for quality gate)
baseline:
  min_dice: 0.90
  min_iou: 0.85
```

#### 3.4 Terraform Infrastructure (in DevOps repo)

**Fill in Terraform module files** in `DevOps-AI-Model-Automatization/terraform/modules/`:

- `vpc/main.tf` - VPC with public subnet (no NAT Gateway)
- `ec2-k3s/main.tf` - EC2 t3.small with k3s, MLflow
- `s3-mlops/main.tf` - S3 buckets
- `ecr/main.tf` - ECR repository
- `iam-github-oidc/main.tf` - IAM for GitHub Actions

**Create terraform.tfvars in Working repo** `infrastructure/terraform.tfvars`:

```hcl
aws_region    = "eu-central-1"
instance_type = "t3.small"
my_ip         = "YOUR_IP/32"  # Your IP
key_name      = "your-key"
mlflow_bucket = "wms-mlflow-artifacts"
dvc_bucket    = "wms-dvc-data"
```

#### 3.5 Verification

- [ ] DVC tracking working locally (`dvc status`)
- [ ] Terraform plan shows expected resources
- [ ] **No NAT Gateway in Terraform plan**
- [ ] **No RDS in Terraform plan**
- [ ] S3 buckets created

---

### Phase 4: ML Pipeline Setup

**Status:** PENDING

**Objectives:**

- Configure MLflow for experiment tracking
- Create GitHub Actions CI pipeline
- Implement training workflow with auto-trigger

**Where to create files:**

| File                | Repository | Location             | Description         |
| ------------------- | ---------- | -------------------- | ------------------- |
| data-qa.py          | DevOps     | `scripts/`           | Data validation     |
| quality-gate.py     | DevOps     | `scripts/`           | Baseline evaluation |
| train-with-retry.py | DevOps     | `scripts/`           | Training with retry |
| ci.yaml             | Working    | `.github/workflows/` | Code quality        |
| data-qa.yaml        | Working    | `.github/workflows/` | Data validation     |
| train-pr.yaml       | Working    | `.github/workflows/` | Training on PR      |
| release-deploy.yaml | Working    | `.github/workflows/` | Deploy on merge     |
| train.py (modify)   | Working    | `WMS/src/`           | Add MLflow          |

**Tasks:**

#### 4.1 Scripts in DevOps repo

**scripts/data-qa.py:**

```python
#!/usr/bin/env python3
"""
Training data validation.
Checks: image↔mask pairs, resolutions, formats, mask binarity.

Usage:
    python data-qa.py WMS/data/training/ --output report.json
"""
# ... (full implementation in previous plan version)
```

**scripts/quality-gate.py:**

```python
#!/usr/bin/env python3
"""
Compares new model metrics with baseline.
Returns exit code 0 (PASS) or 1 (FAIL).

Usage:
    python quality-gate.py --report training-report.json --baseline-dice 0.9275 --baseline-iou 0.8865
"""
# ... implementation
```

**scripts/train-with-retry.py:**

```python
#!/usr/bin/env python3
"""
Wrapper for training script with retry logic (max 3 attempts).
Each attempt uses a different seed.

Usage:
    python train-with-retry.py --config WMS/configs/train.yaml --max-retries 3
"""
# ... implementation
```

#### 4.2 Modify train.py in Working repo

Add to `WMS/src/train.py`:

```python
import mlflow
import mlflow.pytorch
import yaml
import hashlib
from pathlib import Path

# At the beginning of file - load config
def load_config(config_path: str = "WMS/configs/train.yaml"):
    with open(config_path) as f:
        return yaml.safe_load(f)

# Versioning
def get_data_version():
    dvc_lock = Path("dvc.lock")
    if dvc_lock.exists():
        return hashlib.md5(dvc_lock.read_bytes()).hexdigest()[:8]
    return "unknown"

def get_model_version():
    git_sha = os.environ.get("GITHUB_SHA", "local")[:7]
    return f"{git_sha}-{get_data_version()}"

# In main training function
config = load_config()
mlflow.set_tracking_uri(os.environ.get("MLFLOW_TRACKING_URI", "http://localhost:5000"))
mlflow.set_experiment("water-meter-segmentation")

with mlflow.start_run(run_name=get_model_version()):
    mlflow.log_params(config["training"])

    # Training loop...
    for epoch in range(config["training"]["epochs"]):
        # ... existing training code ...
        mlflow.log_metrics({"train_loss": train_loss, "val_dice": val_dice}, step=epoch)

    # Log model
    mlflow.pytorch.log_model(model, "model", registered_model_name="water-meter-segmentation")
```

#### 4.3 GitHub Actions Workflows in Working repo

**`.github/workflows/ci.yaml`:**

```yaml
name: CI Pipeline
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
# ... (full implementation as in previous plan version)
```

**`.github/workflows/data-qa.yaml`:**

```yaml
name: Data Quality Assurance
on:
  pull_request:
    paths:
      - "WMS/data/training/**"
# ... uses: python devops/scripts/data-qa.py WMS/data/training/
```

**`.github/workflows/train-pr.yaml`:**

```yaml
name: Train & Evaluate (PR)
on:
  pull_request:
    paths:
      - "WMS/src/**"
      - "WMS/configs/**"
# ... uses: python devops/scripts/train-with-retry.py
```

**`.github/workflows/release-deploy.yaml`:**

```yaml
name: Release & Deploy
on:
  push:
    branches: [main]
# ... build Docker, push ECR, helm deploy
```

#### 4.4 Verification

- [ ] MLflow server accessible
- [ ] Data QA passes on PR with data changes
- [ ] Training triggers on PR
- [ ] Experiments logged in MLflow

---

### Phase 5: Kubernetes & Deployment

**Status:** PENDING

**Where to create files:**

| File             | Repository | Location                   | Description         |
| ---------------- | ---------- | -------------------------- | ------------------- |
| Chart.yaml       | DevOps     | `helm/ml-model/`           | Helm chart metadata |
| values.yaml      | DevOps     | `helm/ml-model/`           | Default values      |
| deployment.yaml  | DevOps     | `helm/ml-model/templates/` | K8s Deployment      |
| service.yaml     | DevOps     | `helm/ml-model/templates/` | K8s Service         |
| helm-values.yaml | Working    | `infrastructure/`          | Overrides           |
| Dockerfile.serve | Working    | `docker/`                  | Docker image        |
| app.py           | Working    | `WMS/src/serve/`           | FastAPI app         |

**Tasks:**

#### 5.1 FastAPI Serving (in Working repo)

Create `WMS/src/serve/app.py`:

```python
from fastapi import FastAPI, File, UploadFile
from prometheus_client import Counter, Histogram
# ... (implementation as in previous plan version)
```

Create `docker/Dockerfile.serve`:

```dockerfile
FROM python:3.10-slim
# ... (implementation as in previous plan version)
```

#### 5.2 Helm Chart (in DevOps repo)

Create `helm/ml-model/Chart.yaml`:

```yaml
apiVersion: v2
name: ml-model
version: 1.0.0
description: Generic ML Model Serving Chart
```

Create `helm/ml-model/values.yaml`:

```yaml
replicaCount: 1
image:
  repository: ""
  tag: "latest"
service:
  type: NodePort
  port: 8000
# ... (full implementation)
```

#### 5.3 Verification

- [ ] Docker image builds
- [ ] Helm deployment works
- [ ] `/health` returns 200
- [ ] `/metrics` returns Prometheus format

---

### Phase 6: Monitoring & Observability

**Status:** PENDING

**Where to create files:**

| File           | Repository | Location                      |
| -------------- | ---------- | ----------------------------- |
| values.yaml    | DevOps     | `helm/monitoring/`            |
| wms-model.json | DevOps     | `helm/monitoring/dashboards/` |

---

### Phase 7: Comparison Framework

**Status:** PENDING

**Where to create files:**

| File                 | Repository | Location             |
| -------------------- | ---------- | -------------------- |
| instructions.md      | Working    | `comparison/manual/` |
| metrics_collector.py | DevOps     | `scripts/`           |

---

### Phase 8: Testing & Documentation

**Status:** PENDING

**Where to create files:**

| File           | Repository | Location     |
| -------------- | ---------- | ------------ |
| test\_\*.py    | Working    | `WMS/tests/` |
| cleanup-aws.sh | DevOps     | `scripts/`   |
| README.md      | Working    | `/`          |
| SETUP.md       | Working    | `/`          |

---

## Summary: Where to Create Files

### DevOps-AI-Model-Automatization (Infrastructure)

```
CREATE:
├── terraform/modules/       # All AWS infrastructure
├── helm/                    # Charts for K8s
├── scripts/                 # data-qa.py, quality-gate.py, train-with-retry.py, cleanup-aws.sh
├── docker/                  # Dockerfile templates
└── docs/                    # Architecture documentation, diagrams
```

### Water-Meters-Segmentation-Autimatization (Working)

```
ALREADY EXISTS (from original repo):
├── WMS/src/                 # train.py, model.py, dataset.py, transforms.py, prepareDataset.py, predicts.py
└── WMS/data/training/       # images/, masks/

CREATE:
├── .github/workflows/       # CI/CD pipelines
├── WMS/configs/train.yaml   # Hyperparameters
├── WMS/src/serve/           # FastAPI app
├── WMS/tests/               # Unit tests
├── infrastructure/          # terraform.tfvars, helm-values.yaml
├── docker/Dockerfile.serve  # Docker for serving
├── comparison/              # Manual vs auto comparison
├── dvc.yaml                 # DVC pipeline
└── Makefile                 # Command shortcuts
```

### Water-Meters-Segmentation (Reference)

```
DO NOT MODIFY - only reference for baseline metrics
```

---

## Timeline Summary

| Phase | Description                        | Est. Time | Main Repo |
| ----- | ---------------------------------- | --------- | --------- |
| 0     | Repository Setup                   | 0.5 day   | Both      |
| 1     | Architecture Documentation         | 1 day     | DevOps    |
| 2     | Mermaid Diagrams                   | 0.5 day   | DevOps    |
| 3     | Foundation Setup (Terraform + DVC) | 2-3 days  | Both      |
| 4     | ML Pipeline Setup (GitHub Actions) | 2-3 days  | Both      |
| 5     | Kubernetes & Deployment            | 2 days    | Both      |
| 6     | Monitoring & Observability         | 1 day     | DevOps    |
| 7     | Comparison Framework               | 2 days    | Working   |
| 8     | Testing & Documentation            | 2 days    | Both      |

**Total: ~12-15 working days**

---

## Cost Estimation (Budget: $50)

| Resource                      | Cost/Hour | Est. Hours | Total  |
| ----------------------------- | --------- | ---------- | ------ |
| EC2 t3.small                  | $0.0208   | 100h       | $2.08  |
| S3 (5GB)                      | -         | -          | ~$0.12 |
| ECR (1GB images)              | -         | -          | ~$0.10 |
| Data transfer                 | ~$0.09/GB | 5GB        | ~$0.45 |
| Elastic IP (when EC2 stopped) | $0.005/h  | 100h       | $0.50  |
| Buffer for mistakes           | -         | -          | $10.00 |

**Estimated Total: ~$15-25**

---

## Success Criteria

- [ ] CI/CD pipeline triggers automatically on changes
- [ ] Models versioned and tracked in MLflow
- [ ] Kubernetes namespaces isolate model versions
- [ ] Monitoring dashboards operational
- [ ] Comparison report shows improvements
- [ ] All tests passing
- [ ] **Total AWS cost < $50**
- [ ] **All resources cleaned up after project**
