# Implementation Plan

> **Budget:** ~$50 USD on AWS
> **Goal:** One-time project - build, test, tear down

---

## AWS Budget Safety Rules

> Follow these at every step. Ignoring them is the fastest way to blow past $50.

1. **Before any AWS spending — set up a billing alert.** AWS Console → Billing & Cost Management → Budgets → Create budget → Monthly cost budget → threshold **$40** → alert via email. This fires before you hit $50 and gives you time to stop resources. **Do this before Phase 5.**
2. **Never run `terraform apply` without first running `terraform plan`** and reading every line of the output.
3. **EC2 is the main cost driver** at $0.0208/h. Stop it when you are not actively testing. A stopped EC2 costs $0/h for compute, but see rule 4 for IP charges.
4. **Every public IPv4 address costs $0.005/h — always.** This applies to Elastic IPs and auto-assigned public IPs, whether the instance is running or stopped (AWS pricing change, 1 February 2024). The only way to stop paying is to release the address entirely. Release the EIP before stopping EC2 for an extended break; re-allocate when you restart.
5. **Phases 0–4 incur no AWS charges** as long as no one runs `terraform apply` or creates AWS resources manually before Phase 5. GitHub Actions free tier covers CI runs. Do not trigger any workflow step that touches AWS until Phase 5 infrastructure is live.
6. **Phase 5 is where the clock starts.** `terraform apply` is the moment EC2 boots and charges begin. See the pre-apply checklist in Phase 5 before running it.
7. **After each testing session, stop EC2:**
   ```bash
   aws ec2 stop-instances --instance-ids <INSTANCE_ID> --region eu-central-1
   ```
8. **Never create resources manually in the AWS Console.** Everything must go through Terraform. Anything created manually is invisible to `terraform destroy` and will keep charging.
9. **At project end:** run `cleanup-aws.sh`, then manually verify in AWS Console that zero resources remain in eu-central-1. Check the billing dashboard one final time.

---

## Tech Stack

### Core MLOps/DevOps

- **Repo/CI:** GitHub + GitHub Actions (free)
- **Data versioning:** DVC + S3 remote
- **Experiment tracking:** MLflow (SQLite backend + S3 artifacts)
- **Containerization:** Docker + Helm
- **Kubernetes:** k3s on EC2 (t3.small/medium)

### Serving + Observability

- **Model serving:** FastAPI + uvicorn
- **Monitoring:** Prometheus + Grafana (run only during testing)
- **EC2 metrics:** CloudWatch (backup)

### IaC

- **Terraform:** S3, IAM, EC2, ECR

### Budget Decisions

| Component       | Expensive Option           | Our Choice              | Savings  |
| --------------- | -------------------------- | ----------------------- | -------- |
| Kubernetes      | EKS ($0.10/h = ~$73/mo.)   | k3s on EC2              | ~$70/mo. |
| MLflow backend  | RDS MySQL (~$13/mo.)       | SQLite + S3             | ~$13/mo. |
| Networking      | NAT Gateway (~$32/mo.)     | Public subnet only      | ~$32/mo. |
| Model artifacts | DVC + MLflow (duplication) | MLflow as single source | Simpler  |

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

### Detailed Step Descriptions

#### Step 3.1 — User Provides Data

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
- Pairs: each image must have a corresponding mask (same filename)
- Masks: grayscale, binary (0 = background, 255 = water meter)

---

#### Step 3.2 — Data Validation (Data QA)

**Trigger:** PR with new data or changes in `WMS/data/training/`

**Automatic validation checks:**

- 3.2.1 Image↔mask pair matching (every image has a mask and vice versa)
- 3.2.2 Resolutions (images and masks have same dimensions)
- 3.2.3 File formats (JPG/PNG)
- 3.2.4 Empty masks (mask completely black)
- 3.2.5 Mask binarity (values only 0 and 255 — checked **after** pixel load, because JPG compression can silently introduce intermediate values)
- 3.2.6 Basic statistics (file count, size distribution)
- 3.2.7 Near-empty masks (fewer than a configurable minimum of foreground pixels; default 100)
- 3.2.8 Coverage and centroid outliers (masks whose foreground area or geometric centroid deviate significantly from the dataset median — flags likely mislabelled images)
- 3.2.9 Mask format advisory: masks stored as JPG risk compression artefacts that break binarity; **PNG is strongly preferred for masks**

**Results:**

##### 3.2.A — INVALID data:

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
│ ⚠️  Pipeline stopped. Fix data and try again.          │
└─────────────────────────────────────────────────────────┘
```

- Pipeline ends with **FAIL** status
- Bot adds comment to PR with error list
- PR is labeled `invalid-data`

##### 3.2.B — VALID data:

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
- Pipeline proceeds to training

---

#### Step 3.3 — Data Versioning and PR Creation

**Trigger:** Data QA PASSED

**Actions:**

- 3.3.1 Data is added to DVC (`dvc add`), `dvc.lock` is updated
- 3.3.2 If user didn't create PR, system automatically:
  - Creates branch `data/<batch-id>-<timestamp>`
  - Opens PR to `main` with updated `.dvc` files + Data QA report
- 3.3.3 PR is labeled `auto-training`

---

#### Step 3.4 — Model Training (up to 3 attempts)

**Trigger:** PR with `auto-training` label or changes in `WMS/src/`, `WMS/configs/`, `dvc.lock`

##### 3.4.1 Initialization

- `dvc pull` — download data from S3
- Environment setup (dependencies, GPU if available)
- Load configuration from `WMS/configs/train.yaml`

##### 3.4.2 Training (attempt N of 3)

```
┌─────────────────────────────────────────────────────────┐
│ TRAINING - Attempt 1/3                                  │
├─────────────────────────────────────────────────────────┤
│ Config: WMS/configs/train.yaml                          │
│ Data version: abc1234                                   │
│ Epochs: 50 | Batch: 4 | LR: 1e-4                        │
├─────────────────────────────────────────────────────────┤
│ Progress: [████████████████████] 100%                   │
│ Train Loss: 0.0055 | Val Loss: 0.0166                   │
│ Val Dice: 0.9066 | Val IoU: 0.8799                      │
├─────────────────────────────────────────────────────────┤
│ Duration: 45 min                                        │
│ MLflow Run: https://mlflow.../runs/xyz789               │
└─────────────────────────────────────────────────────────┘
```

##### 3.4.3 MLflow Logging

- Hyperparameters (LR, batch size, epochs)
- Metrics per epoch (train_loss, val_loss, val_dice, val_iou)
- Model artifact (`best.pth`)
- Version: `model_version = {git_sha}-{data_version}`

---

#### Step 3.5 — Quality Gate (evaluation vs baseline)

**Trigger:** Training completed

**PASS criteria:**

```python
PASS if:
    val_dice >= BASELINE_DICE - TOLERANCE  # e.g., 0.9275 - 0.02 = 0.9075
    AND val_iou >= BASELINE_IOU - TOLERANCE  # e.g., 0.8865 - 0.02 = 0.8665
    AND smoke_test_inference == PASS
```

**Baseline (from Water-Meters-Segmentation):**

- Dice: **0.9275**
- IoU: **0.8865**
- Tolerance: **0.02** (2% margin)

##### 3.5.A — Model BETTER or equal to baseline:

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
│ PR approved for merge                                   │
└─────────────────────────────────────────────────────────┘
```

##### 3.5.B — Model WORSE than baseline:

```
┌─────────────────────────────────────────────────────────┐
│ ⚠️  QUALITY GATE FAILED - Attempt 1/3                  │
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
│ Retrying with different seed... (2/3 remaining)         │
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

> **Note on retry effectiveness:** Changing only the random seed addresses
> non-deterministic variance (weight initialisation, augmentation sampling) but does
> **not** fix systematic issues such as noisy labels, distribution shift, or bad
> train/val splits. If all three attempts fail, investigate the **data quality first**
> before re-triggering. The retry budget is deliberately small (3) to avoid wasting CI
> minutes on a problem that seed changes alone cannot solve.

##### 3.5.C — After 3 failed attempts:

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
│ - New data may be of lower quality                      │
│ - Data distribution shift                               │
│ - Insufficient training data                            │
│                                                         │
│ PR marked as rejected                                   │
│ Please review data quality and try again                │
└─────────────────────────────────────────────────────────┘
```

- PR is labeled `training-failed`
- Bot adds detailed comment with all attempts
- PR is NOT auto-closed (user may want to investigate)

---

#### Step 3.6 — Merge to main (Model Release)

**Trigger:** Quality Gate PASSED + PR approved

**Actions:**

- 3.6.1 PR is merged to `main`
- 3.6.2 `release-deploy` pipeline runs:
  - Tags model version (`v1.2.3` or `model-abc1234`)
  - Promotes model in MLflow Registry to `Production`
  - Builds Docker image with new model
  - Pushes to ECR

---

#### Step 3.7 — Deploy to Kubernetes (k3s)

**Trigger:** New image in ECR after merge

**Actions:**

- 3.7.1 Helm deploy to namespace `model-<version>`
- 3.7.2 Smoke test:
  - `GET /health`
  - `POST /predict` with test image
  - `GET /metrics`
- 3.7.3 Smoke test FAIL → automatic rollback
- 3.7.4 Smoke test PASS → new version is active

---

#### Step 3.8 — Monitoring and Feedback Loop

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

## Repository Architecture

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
│  • Report_PL.pdf                        │
│  • DO NOT MODIFY                        │
└─────────────────────────────────────────┘
```

---

## Current Repository State

> **Legend:** `[EXISTS]` already in repo | `[PHASE N]` created during that phase | `[MODIFY]` existing file that gets changed
>
> Note: Windows `tree` without `/F` flag only shows directories. Files like `PLAN.md`, `CLAUDE.md`, `README.md` exist but are invisible without `/F`.

### DevOps-AI-Model-Automatization

```
DevOps-AI-Model-Automatization/
│
├── .claude/                             [EXISTS]  Claude Code settings
│   └── settings.local.json
├── .gitignore                           [EXISTS]
├── LICENSE                              [EXISTS]
├── CLAUDE.md                            [EXISTS]  AI assistant context
├── README.md                            [EXISTS]  Thesis description
├── PLAN.md                              [EXISTS]  This file
│
├── docs/                                [EXISTS]  Empty directory
│   ├── architecture.md                  [PHASE 9]
│   ├── repository-guide.md              [PHASE 9]
│   ├── tech-stack.md                    [PHASE 9]
│   ├── aws-layout.md                    [PHASE 9]
│   ├── cost-analysis.md                 [PHASE 9]
│   ├── core-flow.md                     [PHASE 9]
│   └── diagrams/                        [PHASE 9]
│       ├── c4-context.mermaid
│       ├── c4-container.mermaid
│       ├── data-flow.mermaid
│       └── ci-cd-sequence.mermaid
│
├── scripts/                             [PHASE 2]
│   ├── data-qa.py                       [PHASE 2]
│   ├── quality-gate.py                  [PHASE 2]
│   ├── train-with-retry.py              [PHASE 2]
│   ├── setup-k3s.sh                     [PHASE 5]
│   ├── setup-mlflow.sh                  [PHASE 5]
│   └── cleanup-aws.sh                   [PHASE 8]
│
├── terraform/                           [PHASE 5]
│   └── modules/
│       ├── vpc/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── ec2-k3s/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── user-data.sh
│       ├── s3-mlops/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── ecr/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── iam-github-oidc/
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
│
├── helm/                                [PHASE 6]
│   ├── ml-model/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       └── servicemonitor.yaml
│   └── monitoring/                      [PHASE 7]
│       ├── values.yaml
│       └── dashboards/
│           └── wms-model.json
│
├── docker/                              [PHASE 6]
│   ├── Dockerfile.serve.template
│   └── Dockerfile.train.template
│
└── Makefile                             [PHASE 9]
```

### Water-Meters-Segmentation-Autimatization (Working)

```
Water-Meters-Segmentation-Autimatization/
│
├── .idea/                               [EXISTS]  → gitignored in Phase 0
│
├── WMS/
│   ├── src/                             [EXISTS]
│   │   ├── model.py                     [EXISTS]  U-Net architecture (unchanged)
│   │   ├── dataset.py                   [EXISTS]  PyTorch Dataset (unchanged)
│   │   ├── transforms.py                [EXISTS]  Augmentations (unchanged)
│   │   ├── prepareDataset.py            [EXISTS]  80/10/10 splits (unchanged)
│   │   ├── predicts.py                  [EXISTS]  Inference (unchanged)
│   │   ├── train.py                     [EXISTS]  → [MODIFY] Phase 3: add MLflow
│   │   ├── __pycache__/                 [EXISTS]  → gitignored in Phase 0
│   │   └── serve/                       [PHASE 6]
│   │       ├── app.py                   FastAPI serving endpoint
│   │       └── __init__.py
│   │
│   ├── data/
│   │   ├── training/                    [EXISTS]
│   │   │   ├── images/                  [EXISTS]  9 images (id_1 .. id_9)
│   │   │   ├── masks/                   [EXISTS]  9 matching masks
│   │   │   └── temp/                    [EXISTS]  → gitignored in Phase 0
│   │   │       ├── train/               Auto-generated 80% split
│   │   │       ├── val/                 Auto-generated 10% split
│   │   │       └── test/                Auto-generated 10% split
│   │   └── predictions/                 [EXISTS]
│   │       ├── photos_to_predict/       10 test images for inference
│   │       └── predicted_masks/         [EXISTS]  → gitignored in Phase 0
│   │
│   ├── models/                          [EXISTS]  → gitignored in Phase 0
│   │   └── unet_epoch{1..31+}.pth       31+ checkpoint files (local only)
│   │
│   ├── Results/                         [EXISTS]  → gitignored in Phase 0
│   │   ├── plot_pixel_balance_train.png
│   │   ├── plot_pixel_balance_validation.png
│   │   ├── plot_pixel_balance_test.png
│   │   ├── plot_dataset_split.png
│   │   └── plot_samples.png
│   │
│   ├── configs/                         [PHASE 1]
│   │   └── train.yaml                   Hyperparameters config
│   │
│   └── tests/                           [PHASE 8]
│       ├── test_model.py
│       ├── test_dataset.py
│       └── test_inference.py
│
├── .github/                             [PHASE 4]
│   └── workflows/
│       ├── ci.yaml                      Code quality (lint, tests)
│       ├── data-qa.yaml                 Data validation on PR
│       ├── train-pr.yaml                Training trigger on PR
│       └── release-deploy.yaml          Build + deploy on merge
│
├── devops/                              [PHASE 4]  ← git submodule
│
├── infrastructure/                      [PHASE 5]
│   ├── terraform.tfvars                 [PHASE 5]  Project-specific AWS values
│   └── helm-values.yaml                 [PHASE 6]  Project-specific Helm overrides
│
├── docker/                              [PHASE 6]
│   └── Dockerfile.serve                 Docker image for serving
│
├── comparison/                          [PHASE 8]
│   ├── manual/
│   │   └── instructions.md              Step-by-step manual deployment
│   └── results/
│       └── .gitkeep
│
├── .gitmodules                          [PHASE 4]
├── .gitignore                           [PHASE 0]
├── requirements.txt                     [PHASE 0]
├── dvc.yaml                             [PHASE 1]
├── dvc.lock                             [PHASE 1]  (auto-generated by DVC)
├── .dvc/                                [PHASE 1]  (dvc init)
├── Makefile                             [PHASE 9]
└── README.md                            [PHASE 9]
```

### Water-Meters-Segmentation (Reference — READ ONLY)

```
Water-Meters-Segmentation/
│
├── Results/
│   └── Report_PL.pdf                    Thesis report (Polish)
│
└── WMS/
    ├── src/                             Same 6 source files as Working repo
    │   ├── model.py
    │   ├── dataset.py
    │   ├── transforms.py
    │   ├── train.py
    │   ├── prepareDataset.py
    │   └── predicts.py
    ├── data/
    │   ├── additional_training/
    │   │   └── collage/                 Extra training images from collages
    │   ├── predictions/
    │   │   ├── photos_to_predict/
    │   │   └── predicted_masks/
    │   └── training/
    │       ├── images/                  Full dataset (1244 files)
    │       ├── masks/
    │       └── temp/
    └── models/

⚠️ DO NOT MODIFY — reference only. Baseline: Dice 0.9275, IoU 0.8865
```

---

## Documentation Strategy: Now vs Later

**Recommendation: write documentation AFTER the code is verified working, not before.**

Reasons:

- Architecture details may shift during implementation
- Cost analysis requires actual AWS billing data
- Diagrams should reflect the final, tested system
- READMEs should document what was actually built

### Docs NOW (Phase 0 — already exist or needed immediately)

| File             | Location       | Status  | Why now                        |
| ---------------- | -------------- | ------- | ------------------------------ |
| PLAN.md          | DevOps         | EXISTS  | This is the roadmap            |
| CLAUDE.md        | DevOps         | EXISTS  | AI assistant context           |
| README.md        | DevOps         | EXISTS  | Thesis description             |
| .gitignore       | Automatization | PHASE 0 | Must exist before first commit |
| requirements.txt | Automatization | PHASE 0 | Needed for local dev setup     |

### Docs LATER (Phase 8–9 — after implementation is verified)

| File                              | Location       | Phase | Why later                                                    |
| --------------------------------- | -------------- | ----- | ------------------------------------------------------------ |
| docs/architecture.md              | DevOps         | 9     | Full picture clear only after everything works               |
| docs/repository-guide.md          | DevOps         | 9     | Submodule details finalized in Phase 4                       |
| docs/tech-stack.md                | DevOps         | 9     | Budget decisions may adjust during work                      |
| docs/aws-layout.md                | DevOps         | 9     | Terraform layout finalized in Phase 5                        |
| docs/cost-analysis.md             | DevOps         | 9     | Actual costs only known after provisioning                   |
| docs/core-flow.md                 | DevOps         | 9     | Flow validated through CI/CD testing                         |
| docs/diagrams/\*.mermaid          | DevOps         | 9     | Should reflect final tested architecture                     |
| README.md                         | Automatization | 9     | Final project summary                                        |
| Makefile                          | Both           | 9     | Shortcuts finalized after all scripts exist                  |
| comparison/manual/instructions.md | Automatization | 8     | Needed before running comparison, but after deployment works |

---

## Implementation Phases

---

### Phase 0: Working Repo Cleanup

**Target: Water-Meters-Segmentation-Autimatization**

**Goal:** Prepare the existing repo before any code changes. No new logic — just hygiene.

**New files:** `.gitignore`, `requirements.txt`

#### 0.1 Create .gitignore

```
# Python
__pycache__/
*.pyc
*.pyo

# IDE
.idea/

# Auto-generated data splits (created by prepareDataset.py)
# Note: DVC also declares this path as an output in dvc.yaml; this entry is a
# safety net so that running prepareDataset.py outside DVC does not commit splits.
WMS/data/training/temp/

# Local model checkpoints — MLflow is source of truth, not Git
WMS/models/

# Generated plots
WMS/Results/

# Prediction outputs
WMS/data/predictions/predicted_masks/

# DVC internals
.dvc/tmp/
```

#### 0.2 Create requirements.txt

```
torch
torchvision
Pillow
PyYAML
numpy
tqdm
mlflow
fastapi
uvicorn
prometheus-client
pytest
```

#### 0.3 Verification

- [ ] `__pycache__/` excluded from git tracking
- [ ] `.idea/` excluded
- [ ] `WMS/models/*.pth` (31+ checkpoints) excluded — stays local only
- [ ] `WMS/data/training/temp/` excluded
- [ ] `WMS/Results/*.png` excluded
- [ ] `requirements.txt` covers all imports in current source files

---

### Phase 1: Data Foundation

**Target: Water-Meters-Segmentation-Autimatization**

**Goal:** DVC data versioning + training configuration file.

**New directories:** `WMS/configs/`, `.dvc/`
**New files:** `WMS/configs/train.yaml`, `dvc.yaml`, `dvc.lock` (auto-generated)

#### 1.1 DVC Initialization

```bash
cd Water-Meters-Segmentation-Autimatization

dvc init

# S3 remote — the URL is written to .dvc/config and committed (standard DVC practice;
# only credentials must stay local, and those come from the IAM role at runtime).
# The bucket does not exist yet — created in Phase 5 (terraform apply).
# dvc push/pull will fail until then — that is expected and normal.
# IMPORTANT: replace <ACCOUNT_ID> with your AWS account ID to make the bucket name globally unique.
dvc remote add -d s3remote s3://wms-dvc-data-<ACCOUNT_ID>/dvc
dvc remote modify s3remote region eu-central-1

# Track existing training data
dvc add WMS/data/training/images/
dvc add WMS/data/training/masks/

git add WMS/data/training/images.dvc WMS/data/training/masks.dvc .dvc/ .gitignore
git commit -m "chore: initialize DVC with training data"
```

#### 1.2 Training Config

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

# Baseline metrics from Water-Meters-Segmentation (for quality gate)
baseline:
  min_dice: 0.90
  min_iou: 0.85
```

#### 1.3 DVC Pipeline

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

#### 1.4 Verification

- [ ] `dvc status` works locally
- [ ] Training images and masks tracked by DVC
- [ ] `train.yaml` loads in Python without errors
- [ ] `dvc push` **fails** — S3 bucket does not exist yet. This is expected. First successful push happens after Phase 5 (`terraform apply`).

---

### Phase 2: DevOps Core Scripts

**Target: DevOps-AI-Model-Automatization**

**Goal:** The three automation scripts that CI/CD pipelines will call. These must work before Phase 4.

**New directories:** `scripts/`
**New files:** `scripts/data-qa.py`, `scripts/quality-gate.py`, `scripts/train-with-retry.py`

#### 2.1 scripts/data-qa.py

```python
#!/usr/bin/env python3
"""
Training data validation.
Checks: image↔mask pair matching, resolutions, file formats, mask binarity,
        near-empty masks, coverage/centroid outliers,
        JPG compression artefacts in masks (non-binary pixel values after load).

Usage:
    python data-qa.py WMS/data/training/ --output report.json

Exit codes: 0 = PASS, 1 = FAIL
Output: JSON report with errors list + statistics

Notes:
- Masks should be PNG. JPG compression introduces non-binary values even for
  visually binary images; flag any mask with pixels outside {0, 255} after load.
- A mask with fewer than MIN_MASK_PIXELS (default 100) foreground pixels is
  treated as effectively empty and reported as an error.
- Coverage outliers are detected by comparing each mask's foreground area and
  centroid to the dataset median; masks far outside the expected range are flagged.
"""
# ... full implementation
```

#### 2.2 scripts/quality-gate.py

```python
#!/usr/bin/env python3
"""
Compares new model metrics with baseline.

Usage:
    python quality-gate.py --report training-report.json \
        --baseline-dice 0.9275 --baseline-iou 0.8865 --tolerance 0.02

Exit codes: 0 = PASS (model >= baseline - tolerance), 1 = FAIL
"""
# ... implementation
```

#### 2.3 scripts/train-with-retry.py

```python
#!/usr/bin/env python3
"""
Training wrapper with retry logic. Each attempt uses a different random seed.

Usage:
    python train-with-retry.py --config WMS/configs/train.yaml --max-retries 3

Calls train.py internally, runs quality-gate.py after each attempt.
Writes training-report.json with all attempt results.
"""
# ... implementation
```

#### 2.4 Verification

- [ ] `data-qa.py` runs against Automatization's `WMS/data/training/` → produces valid JSON
- [ ] `quality-gate.py` returns exit code 0 for scores above threshold, 1 below
- [ ] `train-with-retry.py` correctly chains attempts with different seeds

---

### Phase 3: MLflow Training Integration

**Target: Water-Meters-Segmentation-Autimatization**

**Goal:** Add experiment tracking to the existing `train.py`. No new files — only modification.

**Modified files:** `WMS/src/train.py`

#### 3.1 Changes to train.py

Add at the top:

```python
import mlflow
import mlflow.pytorch
import yaml
import hashlib
from pathlib import Path

def load_config(config_path: str = "WMS/configs/train.yaml"):
    with open(config_path) as f:
        return yaml.safe_load(f)

def get_data_version():
    dvc_lock = Path("dvc.lock")
    if dvc_lock.exists():
        return hashlib.md5(dvc_lock.read_bytes()).hexdigest()[:8]
    return "unknown"

def get_model_version():
    git_sha = os.environ.get("GITHUB_SHA", "local")[:7]
    return f"{git_sha}-{get_data_version()}"
```

Wrap the training loop:

```python
config = load_config()
mlflow.set_tracking_uri(os.environ.get("MLFLOW_TRACKING_URI", "http://localhost:5000"))
mlflow.set_experiment("water-meter-segmentation")

with mlflow.start_run(run_name=get_model_version()):
    mlflow.log_params(config["training"])

    for epoch in range(config["training"]["epochs"]):
        # ... existing training code unchanged ...
        mlflow.log_metrics({"train_loss": train_loss, "val_dice": val_dice}, step=epoch)

    # Log the best model artifact
    mlflow.pytorch.log_model(model, "model", registered_model_name="water-meter-segmentation")
```

#### 3.2 Verification

- [ ] `python WMS/src/train.py --config WMS/configs/train.yaml` runs locally
- [ ] MLflow UI (localhost:5000) shows experiment with params and metrics
- [ ] Model artifact saved and registered in MLflow

---

### Phase 4: CI/CD Pipelines + Submodule

**Target: Water-Meters-Segmentation-Autimatization**

**Goal:** Connect DevOps repo as submodule + create all GitHub Actions workflows.

> No AWS cost in this phase. The workflows are written here but they do not touch AWS yet — `dvc pull` in `train-pr.yaml` and ECR push in `release-deploy.yaml` will only actually hit AWS once Phase 5 infrastructure is live. Once it is, every workflow run that reads from S3 or pushes to ECR counts toward the budget. `dvc pull` transfers data **out** of S3 to the internet (egress); large datasets + frequent training runs will accumulate egress costs.
>
> **GH Actions ↔ EC2 connectivity — architectural decision.** GitHub Actions runners
> have ephemeral, dynamic IPs; you cannot whitelist them in a security group. Two
> consequences for this plan:
>
> 1. **Training jobs cannot reach MLflow on EC2.** Solution: each training job starts
>    MLflow **locally** (SQLite backend) and pushes artifacts directly to S3. The
>    EC2-hosted MLflow instance stays the authoritative registry; after a successful
>    merge the release pipeline (which runs on EC2) syncs the run data from S3 into
>    the local MLflow DB.
> 2. **Deploy jobs cannot reach the k3s API on EC2.** Solution: `release-deploy.yaml`
>    runs on a **self-hosted runner installed on EC2** (see Phase 5.8). That runner has
>    localhost access to both the k3s API (6443) and MLflow (5000).
>
> Security implication: MLflow (5000) and the k3s API (6443) never need to be open to
> 0.0.0.0/0. Only SSH (22) must be reachable from `my_ip`.

**New directories:** `.github/workflows/`, `devops/` (submodule link)
**New files:** `.gitmodules`, `ci.yaml`, `data-qa.yaml`, `train-pr.yaml`, `release-deploy.yaml`

#### 4.1 Add DevOps Submodule

```bash
cd Water-Meters-Segmentation-Autimatization

git submodule add https://github.com/Rafallost/DevOps-AI-Model-Automatization.git devops

git commit -m "chore: add DevOps submodule"
git push
```

#### 4.2 Workflows

**`.github/workflows/ci.yaml`** — Code quality on every PR:

```yaml
name: CI Pipeline
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Install
        run: pip install -r requirements.txt && pip install flake8 black mypy pytest
      - name: Lint
        run: flake8 WMS/src/ --max-line-length 120
      - name: Format check
        run: black WMS/src/ --check
      - name: Tests
        run: pytest WMS/tests/
```

**`.github/workflows/data-qa.yaml`** — Validates data on PR touching training data:

````yaml
name: Data Quality Assurance
on:
  pull_request:
    paths:
      - "WMS/data/training/**"

jobs:
  data-qa:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Install dependencies
        run: pip install Pillow PyYAML
      - name: Run Data QA
        run: python devops/scripts/data-qa.py WMS/data/training/ --output report.json
      - name: Post report as PR comment
        uses: actions/github-script@v7
        with:
          script: |
            const report = require('fs').readFileSync('report.json', 'utf8');
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.payload.pull_request.number,
              body: '```json\n' + report + '\n```'
            });
````

**`.github/workflows/train-pr.yaml`** — Trains model on PR touching code or config:

```yaml
name: Train & Evaluate (PR)
on:
  pull_request:
    paths:
      - "WMS/src/**"
      - "WMS/configs/**"
      - "dvc.lock"

jobs:
  train:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Install
        run: pip install -r requirements.txt
      - name: Configure AWS (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::ACCOUNT:role/github-actions-role
          aws-region: eu-central-1
      - name: Pull DVC data
        run: dvc pull
      - name: Train with retry
        run: python devops/scripts/train-with-retry.py --config WMS/configs/train.yaml --max-retries 3
        env:
          MLFLOW_TRACKING_URI: sqlite:///mlruns.db
          MLFLOW_ARTIFACT_ROOT: s3://wms-mlflow-artifacts-<ACCOUNT_ID>/ci-runs/
      - name: Upload MLflow run data to S3
        run: aws s3 sync mlruns/ s3://wms-mlflow-artifacts-<ACCOUNT_ID>/ci-runs/
      - name: Post results as PR comment
        uses: actions/github-script@v7
        with:
          script: |
            const report = require('fs').readFileSync('training-report.json', 'utf8');
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.payload.pull_request.number,
              body: report
            });
```

**`.github/workflows/release-deploy.yaml`** — Builds and deploys after merge:

```yaml
name: Release & Deploy
on:
  push:
    branches: [main]

jobs:
  build-and-deploy:
    runs-on: self-hosted  # Must run on EC2 — see Phase 5.8 (self-hosted runner setup)
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Configure AWS (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::ACCOUNT:role/github-actions-role
          aws-region: eu-central-1
      - name: Login to ECR
        uses: aws-actions/amazon-ecr-login@v2
      - name: Build + Push Docker
        run: |
          docker build -f docker/Dockerfile.serve -t $ECR_REPO:latest .
          docker push $ECR_REPO:latest
        env:
          ECR_REPO: ACCOUNT.dkr.ecr.eu-central-1.amazonaws.com/wms-model
      - name: Deploy via Helm
        run: |
          helm upgrade --install wms-model devops/helm/ml-model/ \
            -f infrastructure/helm-values.yaml \
            --namespace model-$(git rev-parse --short HEAD)
```

#### 4.3 Verification

- [ ] `git clone --recurse-submodules` pulls `devops/` correctly
- [ ] `git submodule update --init --recursive` works
- [ ] CI workflow triggers on push to main
- [ ] `devops/scripts/` paths resolve inside workflow runners

---

### Phase 5: AWS Infrastructure (Terraform) — MONEY STARTS HERE

**Target: DevOps-AI-Model-Automatization + Automatization (tfvars)**

**Goal:** Define and provision all AWS resources.

> **This is the first phase that spends real money.** `terraform apply` boots EC2 and creates S3 + ECR. From the moment EC2 is running, the account is charged $0.0208/h.
>
> **Pre-apply checklist — do not run `terraform apply` until every box is checked:**
>
> - [ ] Billing budget alert is set at $40 (AWS Console → Billing → Budgets)
> - [ ] You have run `terraform plan` and read every resource in the output
> - [ ] The plan lists exactly: 1 VPC, 1 subnet, 1 security group, 1 EC2 (t3.small), 1 Elastic IP, 2 S3 buckets, 1 ECR repo, 1 IAM role + OIDC provider, 1 EC2 instance profile (for S3 access)
> - [ ] **NO NAT Gateway** anywhere in the plan
> - [ ] **NO RDS** anywhere in the plan
> - [ ] Security group: ports 5000 and 6443 are **not** open to 0.0.0.0/0
> - [ ] You have your AWS account ID and SSH key name ready
> - [ ] You know the EC2 instance ID will appear in the output — write it down

**New directories (DevOps):** `terraform/modules/{vpc,ec2-k3s,s3-mlops,ecr,iam-github-oidc}`
**New files (DevOps):** All `.tf` files + `scripts/setup-k3s.sh` + `scripts/setup-mlflow.sh`
**New directories (Automatization):** `infrastructure/`
**New files (Automatization):** `infrastructure/terraform.tfvars`

#### 5.1 VPC Module — `terraform/modules/vpc/`

**main.tf:**

```hcl
# VPC + single public subnet (NO NAT Gateway — budget constraint)
# Security group:
#   SSH (22)       — source: my_ip only
#   k3s API (6443) — source: CLOSED to public (self-hosted runner uses localhost)
#   MLflow (5000)  — source: CLOSED to public (self-hosted runner uses localhost)
#   HTTP (8000)    — source: my_ip only (for manual smoke tests from developer machine)
# Route table: internet gateway only
```

#### 5.2 EC2 + k3s Module — `terraform/modules/ec2-k3s/`

**main.tf:**

```hcl
# EC2 t3.small in public subnet
# Elastic IP for stable address
# EC2 instance profile — grants the instance S3 read/write on both buckets
#   (MLflow needs this to push/pull artifacts without static credentials)
# user-data.sh runs at startup (installs k3s, MLflow, Docker)
# NOTE: AMI must be Amazon Linux 2 (verify ami-ID for eu-central-1 before apply)
```

**user-data.sh:**

```bash
#!/bin/bash
# Prerequisites: AMI must be Amazon Linux 2 (e.g. ami-0e2df48e8441df418 in eu-central-1)
set -euo pipefail

yum update -y

# ── Docker ──
yum install -y docker
systemctl start docker
systemctl enable docker

# ── Python 3 + pip ──
yum install -y python3 python3-pip

# ── k3s ──
curl -sfL https://get.k3s.io | sh
# Make kubeconfig readable by non-root users
chmod 644 /etc/rancher/k3s/k3s.yaml

# ── Helm ──
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ── MLflow (runs as a systemd service so it survives reboot) ──
pip3 install mlflow boto3
mkdir -p /opt/mlflow

cat > /etc/systemd/system/mlflow.service <<EOF
[Unit]
Description=MLflow Tracking Server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/mlflow server \
  --backend-store-uri sqlite:////opt/mlflow/mlflow.db \
  --default-artifact-root s3://wms-mlflow-artifacts-<ACCOUNT_ID>/ \
  --host 0.0.0.0
WorkingDirectory=/opt/mlflow
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start mlflow
systemctl enable mlflow
```

#### 5.3 S3 Buckets — `terraform/modules/s3-mlops/`

```hcl
# Bucket 1: wms-dvc-data-<ACCOUNT_ID>       — DVC remote (training data)
# Bucket 2: wms-mlflow-artifacts-<ACCOUNT_ID> — MLflow artifacts (models, logs)
# Both: eu-central-1, versioning enabled
# S3 bucket names are globally unique — appending the account ID avoids collisions.
# Actual names come from the dvc_bucket / mlflow_bucket variables in tfvars.
```

#### 5.4 ECR — `terraform/modules/ecr/`

```hcl
# Repository: wms-model
# Lifecycle policy: keep latest 5 images, expire older
# Set force_delete = true so that terraform destroy can remove a non-empty repo
```

#### 5.5 IAM + OIDC — `terraform/modules/iam-github-oidc/`

```hcl
# OIDC provider: github.com (allows GitHub Actions to assume role)
# IAM role trust policy: allows Rafallost/Water-Meters-Segmentation-Autimatization
# Permissions: S3 read/write on both buckets, ECR push
```

#### 5.6 terraform.tfvars (Automatization)

Create `infrastructure/terraform.tfvars`:

```hcl
aws_region    = "eu-central-1"
instance_type = "t3.small"
my_ip         = "YOUR_IP/32"
key_name      = "your-key"
# S3 bucket names must be globally unique — append your AWS account ID.
mlflow_bucket = "wms-mlflow-artifacts-<ACCOUNT_ID>"
dvc_bucket    = "wms-dvc-data-<ACCOUNT_ID>"
```

#### 5.7 Setup Scripts (DevOps)

**scripts/setup-k3s.sh** — standalone script (also embedded in user-data.sh):

```bash
#!/bin/bash
# Install k3s, helm, copy kubeconfig to ~/.kube/config
```

**scripts/setup-mlflow.sh** — can be run manually if user-data fails:

```bash
#!/bin/bash
# pip3 install mlflow boto3
# sudo systemctl start mlflow   ← if the systemd unit from user-data is present
# --- or manually ---
# mkdir -p /opt/mlflow
# mlflow server \
#   --backend-store-uri sqlite:////opt/mlflow/mlflow.db \
#   --default-artifact-root s3://wms-mlflow-artifacts-<ACCOUNT_ID>/ \
#   --host 0.0.0.0
```

#### 5.8 Self-Hosted GitHub Actions Runner

`release-deploy.yaml` must run on EC2 so it has localhost access to the k3s API and MLflow. Set this up **after** EC2 is running and k3s is healthy:

```bash
# SSH into EC2
ssh -i <key.pem> ec2-user@<EC2_PUBLIC_IP>

# Create runner directory
mkdir -p /opt/runner && cd /opt/runner

# Download the runner — get the URL from:
#   GitHub repo → Settings → Actions → Runners → New runner → Linux → x64
curl -O <DOWNLOAD_URL>
tar xzf actions-runner-*.tar.gz

# Configure (use the token from the same GitHub UI page — it is single-use)
./config.sh --url https://github.com/Rafallost/Water-Meters-Segmentation-Autimatization \
            --token <TOKEN>

# Install and start as a persistent service
sudo ./svc.sh install
sudo ./svc.sh start
```

> The runner token is single-use; generate a fresh one from the GitHub UI each time
> you need to re-register. Once started, the runner stays alive and picks up jobs
> labelled `self-hosted`.

#### 5.9 Verification

- [ ] `terraform plan` shows: 1 VPC, 1 EC2, 1 EIP, 2 S3 buckets, 1 ECR, 1 IAM role, 1 EC2 instance profile
- [ ] Self-hosted runner is registered and shows as "online" in GitHub → Settings → Actions → Runners
- [ ] **NO NAT Gateway** in plan
- [ ] **NO RDS** in plan
- [ ] After `terraform apply`: S3 buckets accessible, EC2 running, MLflow reachable at `http://<EC2_PUBLIC_IP>:5000`
- [ ] `dvc push` works — this is the **first real S3 write**, costs ~$0.09/GB for transfer
- [ ] Go to **AWS Console → Billing → Bills** and confirm charges are appearing and match expectations
- [ ] **Write down the EC2 instance ID** — you need it to stop/start the instance between sessions

> When you are done testing for today, **stop EC2 immediately:**
>
> ```bash
> aws ec2 stop-instances --instance-ids <INSTANCE_ID> --region eu-central-1
> ```
>
> A stopped EC2 costs $0/h for compute. The public IPv4 / EIP still charges $0.005/h while allocated — release it if EC2 will stay stopped for more than a day (see budget rule 4).

---

### Phase 6: Deployment Stack

**Target: Both repos**

**Goal:** Docker image + Helm chart + FastAPI serving layer.

> **AWS cost in this phase:** `docker push` writes ~0.1 GB to ECR (negligible storage cost). `helm install` starts a pod on EC2 — **EC2 must be running** for this to work. Start it before deploying, stop it again after you finish testing:
>
> ```bash
> # Before deploying:
> aws ec2 start-instances --instance-ids <INSTANCE_ID> --region eu-central-1
>
> # After testing is done for today:
> aws ec2 stop-instances --instance-ids <INSTANCE_ID> --region eu-central-1
> ```

**New directories (DevOps):** `helm/ml-model/templates/`, `docker/`
**New files (DevOps):** Helm chart (5 files), Dockerfile templates (2 files)
**New directories (Automatization):** `WMS/src/serve/`, `docker/`
**New files (Automatization):** `WMS/src/serve/app.py`, `WMS/src/serve/__init__.py`, `docker/Dockerfile.serve`, `infrastructure/helm-values.yaml`

#### 6.1 FastAPI App — `WMS/src/serve/app.py`

```python
from fastapi import FastAPI, File, UploadFile
from fastapi.responses import Response
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import torch
from PIL import Image
import io
import base64

app = FastAPI()

# Prometheus metrics
predict_count   = Counter("wms_predictions_total", "Total predictions made")
predict_latency = Histogram("wms_predict_latency_seconds", "Prediction latency")
predict_errors  = Counter("wms_predict_errors_total", "Prediction errors")

# Model loaded at startup (path from env or MLflow)
model = None  # ... load_model()

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.post("/predict")
async def predict(image: UploadFile = File(...)):
    with predict_latency.time():
        try:
            # image → tensor → model inference → binary mask → base64
            predict_count.inc()
            ...
            return {"mask_base64": encoded_mask}
        except Exception:
            predict_errors.inc()
            raise

@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
```

#### 6.2 Dockerfile — `docker/Dockerfile.serve`

```dockerfile
FROM python:3.12-slim
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY WMS/src/ ./WMS/src/

# Model downloaded from MLflow at container startup via entrypoint
EXPOSE 8000
CMD ["uvicorn", "WMS.src.serve.app:app", "--host", "0.0.0.0", "--port", "8000"]
```

#### 6.3 Helm Chart — `helm/ml-model/` (DevOps)

**Chart.yaml:**

```yaml
apiVersion: v2
name: ml-model
version: 1.0.0
description: Generic ML Model Serving Chart
```

**values.yaml:**

```yaml
replicaCount: 1
image:
  repository: ""
  tag: "latest"
service:
  type: NodePort # NOT LoadBalancer — budget constraint
  port: 8000
resources:
  limits:
    memory: "512Mi"
    cpu: "500m"
  requests:
    memory: "256Mi"
    cpu: "250m"
```

**templates/deployment.yaml** — standard K8s Deployment using `{{ .Values.image }}`
**templates/service.yaml** — NodePort Service (container port 8000; actual NodePort is auto-assigned in the 30000–32767 range). For stable external access, route through Traefik Ingress (bundled with k3s by default) instead of relying on the NodePort directly.
**templates/servicemonitor.yaml** — Prometheus scrape on `/metrics`

#### 6.4 Dockerfile Templates (DevOps)

**docker/Dockerfile.serve.template** — generic base that Working repo copies and customizes
**docker/Dockerfile.train.template** — optional containerized training

#### 6.5 Helm Values Override — `infrastructure/helm-values.yaml`

```yaml
image:
  repository: "ACCOUNT.dkr.ecr.eu-central-1.amazonaws.com/wms-model"
  tag: "latest"
env:
  MLFLOW_TRACKING_URI: "http://<EC2_IP>:5000"
  MODEL_VERSION: "production"
```

#### 6.6 Verification

- [ ] `docker build -f docker/Dockerfile.serve .` succeeds
- [ ] `helm install wms devops/helm/ml-model/ -f infrastructure/helm-values.yaml` deploys to k3s
- [ ] `GET /health` → 200 OK
- [ ] `POST /predict` with test image → returns mask
- [ ] `GET /metrics` → Prometheus exposition format

---

### Phase 7: Monitoring & Observability

**Target: DevOps-AI-Model-Automatization**

**Goal:** Prometheus + Grafana dashboard for the deployed model.

**New directories:** `helm/monitoring/dashboards/`
**New files:** `helm/monitoring/values.yaml`, `helm/monitoring/dashboards/wms-model.json`

#### 7.1 Monitoring Stack

- Deploy `kube-prometheus-stack` via Helm (community chart) on k3s
- Prometheus auto-discovers ServiceMonitor → scrapes FastAPI `/metrics`
- Grafana dashboard panels:
  - Requests per second
  - Latency: p50, p95, p99
  - Error rate
  - Pod CPU / Memory

> **Resource warning:** Prometheus + Grafana add significant CPU and memory load.
> A t3.small (2 GiB RAM) is tight — k3s + the application + kube-prometheus-stack
> may trigger OOM kills or pod evictions. **Consider upgrading to t3.medium (4 GiB,
> $0.0416/h) before deploying the monitoring stack** — the cost difference over 100 h
> of total testing is ~$2, well within budget. If you stay on t3.small, be prepared
> for instability. Run the monitoring stack only during active testing — not overnight,
> not over weekends. After you have collected the data you need, tear it down before stopping EC2:
>
> ```bash
> helm uninstall kube-prometheus-stack --namespace monitoring
> aws ec2 stop-instances --instance-ids <INSTANCE_ID> --region eu-central-1
> ```

#### 7.2 Verification

- [ ] Prometheus `targets` page shows FastAPI endpoint as UP
- [ ] Grafana dashboard renders latency histogram
- [ ] Sending requests to `/predict` updates the dashboard in real time

---

### Phase 8: Comparison & Testing

**Target: Both repos**

**Goal:** Unit tests + manual comparison instructions + AWS cleanup script.

**New directories (Automatization):** `WMS/tests/`, `comparison/manual/`, `comparison/results/`
**New files (Automatization):** 3 test files, `instructions.md`, `.gitkeep`
**New files (DevOps):** `scripts/cleanup-aws.sh`, `scripts/metrics_collector.py`

#### 8.1 Unit Tests — `WMS/tests/`

**test_model.py:**

```python
# Test U-Net: correct output shape (B,1,512,512), parameter count ~1.97M
```

**test_dataset.py:**

```python
# Test WMSDataset: loads image+mask pair, correct dimensions, augmentation applied
```

**test_inference.py:**

```python
# Test prediction pipeline: single 512x512 image → binary mask, values only 0/1
```

#### 8.2 Manual Comparison Instructions — `comparison/manual/instructions.md`

Document the exact steps a developer must perform manually to achieve what the CI/CD pipeline does automatically. Include a timer field for each step. This is the **key thesis deliverable** — comparison of automated vs manual.

Structure:

1. Pull latest code
2. Run data validation manually
3. Run training manually
4. Evaluate metrics vs baseline
5. Build Docker image
6. Deploy to k3s
7. Verify deployment

Each step: description + expected output + `Time taken: ___`

#### 8.3 Metrics Collector — `scripts/metrics_collector.py` (DevOps)

```python
# Collects timing and event data for thesis comparison:
# - CI/CD pipeline total duration
# - Training duration per attempt
# - Deployment duration
# - Number of errors encountered
# Outputs: comparison/results/automated_metrics.json
```

#### 8.4 AWS Cleanup — `scripts/cleanup-aws.sh` (DevOps) — CRITICAL

```bash
#!/bin/bash
# ⚠️  DELETES ALL AWS RESOURCES for this project ⚠️
# Run ONLY after project testing and thesis submission is complete

set -e

# ── Step 1: Empty S3 buckets (required before terraform destroy) ──
# Buckets with versioning enabled cannot be deleted while they contain objects.
echo "=== Emptying S3 buckets (all versions + delete markers) ==="
for bucket in $(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'wms-')].Name" --output text); do
  echo "  Emptying $bucket ..."
  # Remove all object versions
  aws s3api list-object-versions --bucket "$bucket" \
    --output json --query "Versions[].{Key:Key,Id:VersionId}" 2>/dev/null | \
    jq -r '.[]? | .Key + "\t" + .Id' | while IFS=$'\t' read -r key id; do
      aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$id"
    done
  # Remove all delete markers
  aws s3api list-object-versions --bucket "$bucket" \
    --output json --query "DeleteMarkers[].{Key:Key,Id:VersionId}" 2>/dev/null | \
    jq -r '.[]? | .Key + "\t" + .Id' | while IFS=$'\t' read -r key id; do
      aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$id"
    done
done

# ── Step 2: Destroy all Terraform-managed resources (EC2, S3, ECR, VPC, IAM) ──
echo "Destroying Terraform resources..."
cd devops/terraform
terraform destroy -var-file=../../infrastructure/terraform.tfvars -auto-approve
# NOTE: ECR is managed by Terraform (force_delete = true); no manual delete needed.

echo "Done. Verify in AWS Console that no resources remain."
echo ""
echo "=== POST-CLEANUP CHECKLIST ==="
echo "  1. EC2 → Instances:   zero instances in eu-central-1"
echo "  2. EC2 → Elastic IPs: zero addresses"
echo "  3. S3:                 no wms-* buckets"
echo "  4. ECR:                no wms-model repository"
echo "  5. VPC:                no project VPCs (besides default)"
echo "  6. Billing:            open the dashboard, confirm no ongoing charges"
```

#### 8.5 Verification

- [ ] `pytest WMS/tests/` — all tests pass
- [ ] `comparison/manual/instructions.md` is clear and followable by someone unfamiliar with the project
- [ ] `cleanup-aws.sh` script reviewed (do not run until project is complete)

---

### Phase 9: Documentation & Diagrams

**Target: DevOps-AI-Model-Automatization (main docs) + Automatization (README, Makefile)**

**Goal:** Write all documentation NOW that the system is verified, tested, and working.

**New directories:** `docs/diagrams/`
**New files:** 6 documentation files, 4 Mermaid diagrams, 2 Makefiles, 1 README

#### 9.1 Architecture Documentation — `docs/` (DevOps)

Write these after the system is fully working. They should describe **what was actually built**, not what was planned.

- **architecture.md** — high-level system overview: 3 repos, their roles, how data flows end-to-end
- **repository-guide.md** — how to clone, how submodules work, which repo to edit for what
- **tech-stack.md** — each technology + why it was chosen (budget justification table)
- **aws-layout.md** — diagram of AWS resources and how they connect
- **cost-analysis.md** — actual AWS costs incurred during the project (from billing dashboard)
- **core-flow.md** — detailed walkthrough of the full user→data→train→deploy→monitor flow

#### 9.2 Mermaid Diagrams — `docs/diagrams/` (DevOps)

- **c4-context.mermaid** — actors (developer, CI/CD bot), external systems (GitHub, AWS)
- **c4-container.mermaid** — internal components: repos, pipelines, S3, ECR, k3s, MLflow
- **data-flow.mermaid** — data path: user → GitHub → DVC/S3 → training → MLflow → ECR → k3s
- **ci-cd-sequence.mermaid** — sequence diagram: PR opened → Data QA → Train → Quality Gate → Merge → Deploy

#### 9.3 Makefiles

**DevOps Makefile:**

```makefile
.PHONY: docs lint

docs:
	# Validate markdown, check mermaid syntax
	echo "Docs check passed"

lint:
	# Lint Python scripts
	flake8 scripts/ --max-line-length 120
	# Validate Terraform
	terraform fmt -check terraform/modules/
```

**Automatization Makefile:**

```makefile
.PHONY: train-local data-qa deploy clean submodule-init infra-plan

submodule-init:
	git submodule update --init --recursive

train-local:
	python WMS/src/train.py --config WMS/configs/train.yaml

data-qa:
	python devops/scripts/data-qa.py WMS/data/training/ --output report.json

deploy:
	helm upgrade --install wms-model devops/helm/ml-model/ \
		-f infrastructure/helm-values.yaml

infra-plan:
	cd devops/terraform && terraform init && terraform plan \
		-var-file=../../infrastructure/terraform.tfvars

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null; true
	rm -rf WMS/data/training/temp/
```

#### 9.4 README (Automatization)

Cover: project overview, quick start (clone with submodules, install, run locally), how CI/CD works, links to thesis docs.

#### 9.5 Verification

- [ ] All docs render correctly on GitHub (markdown + Mermaid)
- [ ] Mermaid diagrams render on mermaid.live
- [ ] Makefile commands work from repo root
- [ ] README gives a complete picture of how to get started

---

## File Creation Summary by Phase

| Phase | Target Repo             | New Directories                                | New / Modified Files                                                      |
| ----- | ----------------------- | ---------------------------------------------- | ------------------------------------------------------------------------- |
| 0     | Automatization          | —                                              | `.gitignore`, `requirements.txt`                                          |
| 1     | Automatization          | `WMS/configs/`, `.dvc/`                        | `train.yaml`, `dvc.yaml`                                                  |
| 2     | DevOps                  | `scripts/`                                     | `data-qa.py`, `quality-gate.py`, `train-with-retry.py`                    |
| 3     | Automatization          | —                                              | `train.py` (modified)                                                     |
| 4     | Automatization          | `.github/workflows/`, `devops/`                | `.gitmodules`, 4 workflow YAMLs                                           |
| 5     | DevOps + Automatization | `terraform/modules/*`, `infrastructure/`       | 15 Terraform files, `terraform.tfvars`, 2 setup scripts                   |
| 6     | DevOps + Automatization | `helm/ml-model/*`, `docker/`, `WMS/src/serve/` | 5 Helm files, 2 Dockerfiles, `app.py`, `helm-values.yaml`                 |
| 7     | DevOps                  | `helm/monitoring/dashboards/`                  | `values.yaml`, `wms-model.json`                                           |
| 8     | Both                    | `WMS/tests/`, `comparison/*`                   | 3 test files, `instructions.md`, `cleanup-aws.sh`, `metrics_collector.py` |
| 9     | DevOps + Automatization | `docs/diagrams/`                               | 6 docs, 4 diagrams, 2 Makefiles, 1 README                                 |

### AWS Spend by Phase

| Phase | Cost                        | What actually runs on AWS                                                                 |
| ----- | --------------------------- | ----------------------------------------------------------------------------------------- |
| 0–4   | **$0.00**                   | Everything is local or on GitHub Actions (free tier). No AWS resources exist.             |
| 5     | **First charges**           | `terraform apply` — EC2 boots ($0.0208/h), S3 buckets created, ECR created, EIP allocated |
| 6     | **Ongoing while EC2 is up** | ECR image push (~0.1 GB storage), model pod running on EC2                                |
| 7     | **Ongoing while EC2 is up** | Same EC2, higher load from Prometheus + Grafana                                           |
| 8     | **Charges stop**            | `cleanup-aws.sh` destroys everything. Verify in Console afterward.                        |
| 9     | **$0.00**                   | Documentation only. No infrastructure.                                                    |

---

## Cost Estimation (Budget: $50)

> **Do this first:** AWS Console → Billing & Cost Management → Budgets → Create budget → Monthly cost → threshold $40 → alert via email. Takes 2 minutes. Without it you have no early warning if something goes wrong.

| Resource                          | Cost/Hour  | Est. Hours | Total  | Notes                                          |
| --------------------------------- | ---------- | ---------- | ------ | ---------------------------------------------- |
| EC2 t3.small                      | $0.0208    | 100h       | $2.08  | Stop when not actively testing                 |
| Public IPv4 / EIP                 | $0.005     | 200h       | $1.00  | Charged always while allocated — see rule 4    |
| S3 (5 GB, two buckets)            | —          | —          | ~$0.12 | Versioning enabled                             |
| ECR (1 GB images)                 | —          | —          | ~$0.10 | Latest 5 images kept                           |
| Data transfer OUT (S3 → internet) | ~$0.09/GB  | 5 GB       | ~$0.45 | GH Actions `dvc pull` is egress from AWS        |
| Buffer for mistakes               | —          | —          | $10.00 |                                                |

> Optional: upgrading to t3.medium for Phase 7 (monitoring) adds ~$2 over 100 h but
> significantly reduces OOM risk. Still well within the $50 budget.

**Estimated Total: ~$15–25**

---

## Success Criteria

- [ ] CI/CD pipeline triggers automatically on data or code changes
- [ ] Models versioned and tracked in MLflow (single source of truth)
- [ ] Kubernetes namespaces isolate model versions
- [ ] Monitoring dashboards operational during testing
- [ ] Comparison report (manual vs automated) documents real results
- [ ] All unit tests passing
- [ ] **Total AWS cost < $50**
- [ ] **All AWS resources cleaned up after project** (`cleanup-aws.sh`)
