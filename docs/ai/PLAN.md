# Implementation Plan

## Overview

This document outlines the implementation plan for the MLOps platform that automates the CI/CD process for training and deploying AI models.

**Source Repository:** [github.com/Rafallost/Water-Meters-Segmentation](https://github.com/Rafallost/Water-Meters-Segmentation)

## Source Model Structure (Existing)

```
Rafallost/Water-Meters-Segmentation/
└── WMS/
    ├── src/
    │   ├── model.py          # U-Net architecture
    │   ├── train.py          # Training script
    │   ├── dataset.py        # Dataset class
    │   ├── predicts.py       # Inference/predictions
    │   ├── prepareDataset.py # Data preparation
    │   └── transforms.py     # Data augmentations
    ├── models/
    │   ├── best.pth          # Best model (~990KB)
    │   └── unet_epoch*.pth   # 50 epoch checkpoints
    └── data/
```

## MLOps Infrastructure Structure (To Create)

```
DevOps-AI-Model-Automatization/
├── WMS/                              # (git submodule or copy from source repo)
├── infrastructure/
│   ├── terraform/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── vpc.tf
│   │   ├── eks.tf
│   │   ├── ecr.tf
│   │   ├── s3.tf
│   │   ├── rds.tf
│   │   ├── iam.tf
│   │   └── terraform.tfvars.example
│   └── helm/
│       ├── wms-model/
│       │   ├── Chart.yaml
│       │   ├── values.yaml
│       │   └── templates/
│       │       ├── deployment.yaml
│       │       ├── service.yaml
│       │       ├── configmap.yaml
│       │       └── namespace.yaml
│       └── monitoring/
│           ├── prometheus-values.yaml
│           ├── grafana-values.yaml
│           └── dashboards/
│               └── ml-metrics.json
│
├── docker/
│   ├── Dockerfile.train
│   ├── Dockerfile.serve
│   └── torchserve/
│       └── config.properties
│
├── .github/
│   └── workflows/
│       ├── ci.yaml
│       ├── train.yaml
│       └── deploy.yaml
│
├── comparison/
│   ├── manual/
│   │   ├── instructions.md
│   │   └── time_tracker.py
│   ├── automated/
│   │   └── metrics_collector.py
│   └── reports/
│       └── template.md
│
├── docs/
│   ├── plan.md
│   ├── architecture.md
│   └── diagrams/
│       └── diagrams.md
│
├── scripts/
│   ├── setup_dvc.sh
│   ├── setup_mlflow.sh
│   └── deploy_model.sh
│
├── dvc.yaml
├── .dvc/config
├── .gitignore
├── .env.example
├── README.md
├── architecture.md
└── claude.md
```

## Implementation Phases

### Phase 1: Architecture Documentation

**Status:** IN PROGRESS

**Deliverables:**
- [ ] `docs/architecture.md` - Full architecture documentation
- [ ] Tech stack specifications
- [ ] AWS infrastructure layout
- [ ] Component descriptions

---

### Phase 2: Mermaid Diagrams

**Status:** IN PROGRESS

**Deliverables:**
- [ ] `docs/diagrams/diagrams.md` - All diagrams in Mermaid format:
  - C4 Context diagram - System overview with actors
  - Data Flow diagram - Training and deployment pipeline
  - Deployment diagram - AWS infrastructure layout
  - CI/CD Sequence diagram - Step-by-step pipeline flow
  - Model Versioning flow - How models are versioned and deployed

---

### Phase 3: Foundation Setup

**Status:** PENDING

**Objectives:**
- Set up version control for data and models
- Provision AWS infrastructure
- Configure remote storage

**Tasks:**

#### 3.1 DVC Initialization
```bash
# Initialize DVC
dvc init

# Configure S3 remote
dvc remote add -d s3remote s3://mlops-dvc-data/wms
dvc remote modify s3remote region eu-central-1

# Track data directory
dvc add WMS/data/
```

#### 3.2 Create DVC Pipeline
Create `dvc.yaml`:
```yaml
stages:
  prepare:
    cmd: python WMS/src/prepareDataset.py
    deps:
      - WMS/data/raw
      - WMS/src/prepareDataset.py
    outs:
      - WMS/data/processed

  train:
    cmd: python WMS/src/train.py
    deps:
      - WMS/data/processed
      - WMS/src/train.py
      - WMS/src/model.py
      - WMS/src/dataset.py
      - WMS/src/transforms.py
    outs:
      - WMS/models/best.pth
    metrics:
      - WMS/models/metrics.json:
          cache: false
```

#### 3.3 Terraform Infrastructure
Create AWS resources:
- VPC with public/private subnets
- EKS cluster with managed node group
- ECR repository for Docker images
- S3 buckets for DVC and MLflow
- RDS MySQL for MLflow backend
- IAM roles and policies

**Key Files:**
- `infrastructure/terraform/main.tf`
- `infrastructure/terraform/vpc.tf`
- `infrastructure/terraform/eks.tf`
- `infrastructure/terraform/ecr.tf`
- `infrastructure/terraform/s3.tf`
- `infrastructure/terraform/rds.tf`
- `infrastructure/terraform/iam.tf`

#### 3.4 Verification
- [ ] DVC tracking working locally
- [ ] Terraform plan shows expected resources
- [ ] AWS credentials configured
- [ ] S3 buckets accessible

---

### Phase 4: ML Pipeline Setup

**Status:** PENDING

**Objectives:**
- Configure MLflow for experiment tracking
- Create GitHub Actions CI pipeline
- Implement training workflow with auto-trigger

**Tasks:**

#### 4.1 MLflow Server Setup
Deploy MLflow on EKS:
```yaml
# infrastructure/helm/mlflow/values.yaml
replicaCount: 1
backend:
  type: mysql
  host: <rds-endpoint>
  database: mlflow
artifactStore:
  type: s3
  bucket: mlops-mlflow-artifacts
```

#### 4.2 Training Script with MLflow
Modify existing `WMS/src/train.py` to integrate MLflow:
```python
# Add to existing train.py from Rafallost/Water-Meters-Segmentation
import mlflow
import mlflow.pytorch
import os

mlflow.set_tracking_uri(os.environ.get("MLFLOW_TRACKING_URI", "http://localhost:5000"))
mlflow.set_experiment("water-meter-segmentation")

with mlflow.start_run():
    # Log hyperparameters (adjust based on actual train.py variables)
    mlflow.log_params({
        "learning_rate": lr,
        "batch_size": batch_size,
        "epochs": num_epochs,
        "model": "U-Net"
    })

    # Training loop (existing code)...

    # Log metrics after each epoch
    mlflow.log_metrics({
        "train_loss": train_loss,
        "val_loss": val_loss,
        "val_iou": val_iou
    }, step=epoch)

    # Log best model
    mlflow.pytorch.log_model(model, "model",
        registered_model_name="water-meter-segmentation")

    # Log existing checkpoints
    mlflow.log_artifact("WMS/models/best.pth")
```

#### 4.3 GitHub Actions CI Pipeline
Create `.github/workflows/ci.yaml`:
```yaml
name: CI Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  code-quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.10'
      - run: pip install flake8 black mypy pytest
      - run: flake8 WMS/src/
      - run: black --check WMS/src/
      - run: mypy WMS/src/

  unit-tests:
    runs-on: ubuntu-latest
    needs: code-quality
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.10'
      - run: pip install -r WMS/requirements.txt
      - run: pytest WMS/tests/ -v --cov=WMS/src
```

#### 4.4 Training Workflow
Create `.github/workflows/train.yaml`:
```yaml
name: Model Training

on:
  push:
    branches: [main]
    paths:
      - 'WMS/src/**'
      - 'WMS/configs/**'
      - 'dvc.lock'

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      should_train: ${{ steps.check.outputs.should_train }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2
      - id: check
        run: |
          if git diff --name-only HEAD~1 | grep -E '\.dvc$|dvc\.lock|WMS/src/'; then
            echo "should_train=true" >> $GITHUB_OUTPUT
          fi

  train:
    needs: detect-changes
    if: needs.detect-changes.outputs.should_train == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: eu-central-1
      - run: |
          pip install dvc[s3]
          dvc pull
      - run: |
          pip install -r WMS/requirements.txt
          python WMS/src/train.py
        env:
          MLFLOW_TRACKING_URI: ${{ secrets.MLFLOW_TRACKING_URI }}
      - run: dvc push
```

#### 4.5 Verification
- [ ] MLflow server accessible
- [ ] CI pipeline passes on push
- [ ] Training triggers on code/data changes
- [ ] Experiments logged in MLflow

---

### Phase 5: Kubernetes & Deployment

**Status:** PENDING

**Objectives:**
- Create Docker images for model serving
- Build Helm charts for deployment
- Implement namespace isolation

**Tasks:**

#### 5.1 Dockerfile for Serving
Create `docker/Dockerfile.serve`:
```dockerfile
FROM pytorch/torchserve:0.9.0-cpu

# Copy TorchServe config
COPY docker/torchserve/config.properties /home/model-server/

# Copy model archive (created from WMS/models/best.pth)
COPY WMS/models/model-store/*.mar /home/model-server/model-store/

USER model-server
EXPOSE 8080 8081 8082

CMD ["torchserve", "--start", \
     "--model-store=/home/model-server/model-store", \
     "--models=wms=wms.mar"]
```

**Create Model Archive (MAR):**
```bash
# Convert best.pth to TorchServe format
torch-model-archiver --model-name wms \
  --version 1.0 \
  --model-file WMS/src/model.py \
  --serialized-file WMS/models/best.pth \
  --handler image_segmenter \
  --export-path WMS/models/model-store/
```

#### 5.2 Helm Chart
Create `infrastructure/helm/wms-model/`:
```yaml
# Chart.yaml
apiVersion: v2
name: wms-model
version: 1.0.0
description: Water Meter Segmentation Model

# values.yaml
replicaCount: 2
namespace: model-v1
image:
  repository: <account>.dkr.ecr.eu-central-1.amazonaws.com/wms-model
  tag: latest
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "2000m"
```

#### 5.3 Deployment Workflow
Create `.github/workflows/deploy.yaml`:
```yaml
name: Deploy Model

on:
  workflow_run:
    workflows: ["Model Training"]
    types: [completed]

jobs:
  deploy:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: eu-central-1
      - uses: aws-actions/amazon-ecr-login@v2
      - run: |
          IMAGE_TAG=$(git rev-parse --short HEAD)
          docker build -f docker/Dockerfile.serve -t $ECR_REGISTRY/wms-model:$IMAGE_TAG .
          docker push $ECR_REGISTRY/wms-model:$IMAGE_TAG
      - run: |
          aws eks update-kubeconfig --name mlops-cluster
          helm upgrade --install wms-model-$IMAGE_TAG \
            ./infrastructure/helm/wms-model \
            --namespace model-$IMAGE_TAG \
            --create-namespace \
            --set image.tag=$IMAGE_TAG
```

#### 5.4 Verification
- [ ] Docker image builds successfully
- [ ] Image pushes to ECR
- [ ] Helm deployment creates namespace
- [ ] Model endpoint accessible

---

### Phase 6: Monitoring & Observability

**Status:** PENDING

**Objectives:**
- Deploy Prometheus and Grafana
- Create ML-specific dashboards
- Configure alerting

**Tasks:**

#### 6.1 Deploy Prometheus Stack
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f infrastructure/helm/monitoring/prometheus-values.yaml
```

#### 6.2 Grafana Dashboards
Create dashboards for:
- Inference latency (P50, P95, P99)
- Requests per second
- Error rate
- CPU/Memory usage per model version
- Model version distribution

#### 6.3 Custom ML Metrics
Add to model serving code:
```python
from prometheus_client import Counter, Histogram

INFERENCE_COUNT = Counter('wms_inference_total', 'Total inferences', ['version', 'status'])
INFERENCE_LATENCY = Histogram('wms_inference_latency_seconds', 'Latency', ['version'])
```

#### 6.4 Alerting Rules
```yaml
groups:
  - name: ml-alerts
    rules:
      - alert: HighInferenceLatency
        expr: wms_inference_latency_seconds:avg > 1
        for: 5m
        labels:
          severity: warning
```

#### 6.5 Verification
- [ ] Prometheus collecting metrics
- [ ] Grafana dashboards displaying data
- [ ] Alerts firing correctly

---

### Phase 7: Comparison Framework

**Status:** PENDING

**Objectives:**
- Document manual deployment process
- Create metrics collection tools
- Generate comparison reports

**Tasks:**

#### 7.1 Manual Deployment Documentation
Create `comparison/manual/instructions.md`:
- Step-by-step manual deployment guide
- Time tracking checkboxes
- Error logging template

#### 7.2 Automated Metrics Collector
Create `comparison/automated/metrics_collector.py`:
```python
@dataclass
class DeploymentMetrics:
    deployment_id: str
    method: str  # 'automated' or 'manual'
    total_duration_seconds: float
    stages: dict
    errors_count: int
    success: bool
```

#### 7.3 Comparison Tasks
Define standardized tasks:
1. Deploy new model version
2. Rollback to previous version
3. Scale model replicas
4. Update model configuration
5. Debug failed deployment

#### 7.4 Report Generation
Comparison metrics:
| Metric | Manual | Automated |
|--------|--------|-----------|
| Deployment Time | X min | Y min |
| Error Rate | X% | Y% |
| Rollback Time | X min | Y min |
| Human Hours | X hrs | Y hrs |

#### 7.5 Verification
- [ ] Manual instructions complete
- [ ] Metrics collector working
- [ ] Reports generated

---

### Phase 8: Testing & Documentation

**Status:** PENDING

**Objectives:**
- Comprehensive testing
- Complete documentation
- Final thesis deliverables

**Tasks:**

#### 8.1 Model Performance Testing
```python
def test_model_accuracy():
    predictions = model.predict(test_images)
    iou = calculate_iou(predictions, test_labels)
    assert iou > 0.85

def test_inference_latency():
    latencies = [measure_inference(img) for img in test_images[:100]]
    assert avg(latencies) < 0.5
    assert percentile(latencies, 95) < 1.0
```

#### 8.2 Load Testing
```bash
# Using k6
k6 run --vus 50 --duration 30s scripts/load_test.js
```

#### 8.3 Documentation
- [ ] Complete README.md
- [ ] SETUP.md - Installation guide
- [ ] DEPLOYMENT.md - Operations guide
- [ ] COMPARISON.md - Results analysis

#### 8.4 Verification
- [ ] All tests passing
- [ ] Load test results acceptable
- [ ] Documentation complete

---

## Timeline Summary

| Phase | Description | Dependencies |
|-------|-------------|--------------|
| 1 | Architecture Documentation | None |
| 2 | Mermaid Diagrams | Phase 1 |
| 3 | Foundation Setup | Phase 2 |
| 4 | ML Pipeline Setup | Phase 3 |
| 5 | Kubernetes & Deployment | Phase 4 |
| 6 | Monitoring & Observability | Phase 5 |
| 7 | Comparison Framework | Phase 6 |
| 8 | Testing & Documentation | Phase 7 |

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| AWS costs | Use spot instances, schedule downtime |
| Training time | Checkpoint resume, incremental training |
| Pipeline failures | Rollback mechanisms, alerting |
| Data privacy | Keep dataset private, use synthetic for demos |

## Success Criteria

- [ ] CI/CD pipeline triggers automatically on changes
- [ ] Models versioned and tracked in MLflow
- [ ] Kubernetes namespaces isolate model versions
- [ ] Monitoring dashboards operational
- [ ] Comparison report shows improvements
- [ ] All tests passing
