# Architecture Documentation

## Overview

This document describes the architecture of the MLOps platform for automated CI/CD pipeline that trains, versions, and deploys AI models (Water Meter Segmentation) using DevOps techniques.

**Source Model Repository:** [github.com/Rafallost/Water-Meters-Segmentation](https://github.com/Rafallost/Water-Meters-Segmentation)

**Model Architecture:** U-Net (Semantic Segmentation)

**Dataset:** Water Meters Dataset (Kaggle)

## System Context

The MLOps platform automates the entire machine learning lifecycle:

- **Code/Data Changes** → Automatic detection and pipeline triggering
- **Model Training** → Reproducible training with experiment tracking
- **Model Versioning** → Full version control for models and data
- **Deployment** → Kubernetes-based deployment with namespace isolation
- **Monitoring** → Real-time metrics and visualization

## Architecture Diagrams

All diagrams are in Mermaid format (renders in GitHub/VS Code).

| Diagram | Description |
| ------- | ----------- |
| [C4 Context](docs/diagrams/diagrams.md#1-c4-context-diagram---system-overview) | High-level system context |
| [Data Flow](docs/diagrams/diagrams.md#2-data-flow-diagram---training-and-deployment-pipeline) | Pipeline data flow |
| [Deployment](docs/diagrams/diagrams.md#3-deployment-diagram---aws-infrastructure) | AWS infrastructure layout |
| [CI/CD Sequence](docs/diagrams/diagrams.md#4-cicd-pipeline-sequence) | Step-by-step pipeline flow |
| [Model Versioning](docs/diagrams/diagrams.md#5-model-versioning-flow) | Model versioning and deployment |

**View all diagrams:** [docs/diagrams/diagrams.md](docs/diagrams/diagrams.md)

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              GitHub                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │  WMS/src/    │  │  WMS/data/   │  │infrastructure│  │   .github/   │    │
│  │  (ML Code)   │  │  (DVC)       │  │  terraform/  │  │  workflows/  │    │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘    │
└─────────┼─────────────────┼─────────────────┼─────────────────┼────────────┘
          │                 │                 │                 │
          ▼                 ▼                 ▼                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GitHub Actions CI/CD                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │ Code Quality │  │ Data Change  │  │   Training   │  │   Deploy     │    │
│  │   (lint)     │  │  Detection   │  │   Pipeline   │  │   to EKS     │    │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                                       │
│  ┌─────────────────────────────────┐  ┌──────────────────────────────────┐ │
│  │         S3 Buckets              │  │         Amazon ECR               │ │
│  │  ┌─────────┐  ┌──────────────┐  │  │  ┌────────────────────────────┐  │ │
│  │  │DVC Data │  │MLflow Artifacts│ │  │  │   wms-model:v1.0.0        │  │ │
│  │  └─────────┘  └──────────────┘  │  │  │   wms-model:v1.1.0        │  │ │
│  └─────────────────────────────────┘  │  └────────────────────────────┘  │ │
│                                       └──────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        Amazon EKS Cluster                            │   │
│  │  ┌────────────────┐ ┌────────────────┐ ┌─────────────────────────┐  │   │
│  │  │ NS: model-v1   │ │ NS: model-v2   │ │   NS: monitoring        │  │   │
│  │  │ ┌────────────┐ │ │ ┌────────────┐ │ │ ┌─────────┐ ┌─────────┐ │  │   │
│  │  │ │ TorchServe │ │ │ │ TorchServe │ │ │ │Promethe-│ │ Grafana │ │  │   │
│  │  │ │   Pod      │ │ │ │   Pod      │ │ │ │   us    │ │         │ │  │   │
│  │  │ └────────────┘ │ │ └────────────┘ │ │ └─────────┘ └─────────┘ │  │   │
│  │  └────────────────┘ └────────────────┘ └─────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Technology Stack

### Core Technologies

| Category            | Technology  | Version | Purpose                             |
| ------------------- | ----------- | ------- | ----------------------------------- |
| **ML Framework**    | PyTorch     | 2.1.x   | Deep learning model training        |
| **ML Framework**    | TorchVision | 0.16.x  | Computer vision utilities           |
| **MLOps**           | MLflow      | 2.10.x  | Experiment tracking, model registry |
| **Data Versioning** | DVC         | 3.40.x  | Dataset and model versioning        |
| **Language**        | Python      | 3.10.x  | Runtime environment                 |

### CI/CD & Infrastructure

| Category            | Technology     | Version | Purpose                     |
| ------------------- | -------------- | ------- | --------------------------- |
| **CI/CD**           | GitHub Actions | -       | Workflow automation         |
| **Container**       | Docker         | 24.x    | Containerization            |
| **Registry**        | Amazon ECR     | -       | Container image storage     |
| **Orchestration**   | Kubernetes     | 1.28.x  | Container orchestration     |
| **Cloud K8s**       | Amazon EKS     | 1.28    | Managed Kubernetes          |
| **IaC**             | Terraform      | 1.6.x   | Infrastructure provisioning |
| **Package Manager** | Helm           | 3.13.x  | Kubernetes deployments      |

### Monitoring & Serving

| Category          | Technology       | Version | Purpose                 |
| ----------------- | ---------------- | ------- | ----------------------- |
| **Model Serving** | TorchServe       | 0.9.x   | PyTorch model serving   |
| **Monitoring**    | Prometheus       | 2.48.x  | Metrics collection      |
| **Visualization** | Grafana          | 10.2.x  | Dashboards and alerting |
| **Database**      | Amazon RDS MySQL | 8.0     | MLflow metadata store   |

## AWS Infrastructure

### Network Architecture

```
AWS Account
├── VPC (10.0.0.0/16)
│   ├── Public Subnets (3 AZs)
│   │   ├── 10.0.1.0/24 (eu-central-1a)
│   │   ├── 10.0.2.0/24 (eu-central-1b)
│   │   └── 10.0.3.0/24 (eu-central-1c)
│   │
│   ├── Private Subnets (3 AZs)
│   │   ├── 10.0.10.0/24 (eu-central-1a)
│   │   ├── 10.0.11.0/24 (eu-central-1b)
│   │   └── 10.0.12.0/24 (eu-central-1c)
│   │
│   ├── Internet Gateway
│   └── NAT Gateway (per AZ for HA)
```

### Compute Resources

| Resource    | Type               | Configuration                      |
| ----------- | ------------------ | ---------------------------------- |
| EKS Cluster | Managed Kubernetes | v1.28, 3 AZs                       |
| Node Group  | EC2 Managed        | t3.large, 2-5 nodes (auto-scaling) |
| RDS MySQL   | Database           | db.t3.micro, single-AZ             |

### Storage Resources

| Resource                 | Type           | Purpose                         |
| ------------------------ | -------------- | ------------------------------- |
| `mlops-dvc-data`         | S3 Bucket      | DVC remote storage for datasets |
| `mlops-mlflow-artifacts` | S3 Bucket      | MLflow model artifacts and logs |
| `wms-model`              | ECR Repository | Docker images for model serving |

## Component Details

### 1. Source Control & Data Versioning

**GitHub Repository:** `Rafallost/Water-Meters-Segmentation`

**Repository Structure:**

```
WMS/
├── src/
│   ├── model.py          # U-Net model architecture
│   ├── train.py          # Training script (8KB)
│   ├── dataset.py        # Dataset class
│   ├── predicts.py       # Inference/predictions
│   ├── prepareDataset.py # Data preparation
│   └── transforms.py     # Data augmentations
├── models/
│   ├── best.pth          # Best model checkpoint (~990KB)
│   └── unet_epoch*.pth   # 50 epoch checkpoints
└── data/
    └── (DVC-tracked)
```

**DVC Configuration:**

- Remote storage: S3 bucket
- Tracks: datasets, model checkpoints (best.pth, unet_epoch*.pth)
- Pipeline: `dvc.yaml` defines training stages

### 2. CI/CD Pipeline (GitHub Actions)

**Workflows:**

| Workflow      | Trigger          | Purpose                        |
| ------------- | ---------------- | ------------------------------ |
| `ci.yaml`     | Push/PR          | Linting, testing, code quality |
| `train.yaml`  | Data/code change | Model training with MLflow     |
| `deploy.yaml` | Training success | Build image, deploy to EKS     |

**Change Detection Logic:**

```
on push:
  if (WMS/src/*.py changed OR dvc.lock changed):
    trigger training
  if (training success):
    trigger deployment
```

### 3. MLflow Tracking Server

**Configuration:**

- Backend Store: RDS MySQL
- Artifact Store: S3 bucket
- Tracking: experiments, parameters, metrics
- Registry: model versions with stages (Staging, Production)

**Logged Metrics (from WMS/src/train.py):**

- Training loss, validation loss
- IoU (Intersection over Union) - primary metric for segmentation
- Dice coefficient
- Training duration
- Model checkpoints (unet_epoch*.pth)

### 4. Model Serving (TorchServe)

**Model:** U-Net from `WMS/models/best.pth`

**Features:**

- REST API for inference (image segmentation)
- Model versioning support
- Health checks and readiness probes
- Prometheus metrics endpoint (`/metrics`)

**Endpoints:**
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/predictions/wms` | POST | Run segmentation inference |
| `/ping` | GET | Health check |
| `/metrics` | GET | Prometheus metrics |

**Input/Output:**
- Input: Water meter image (PNG/JPEG)
- Output: Segmentation mask (binary mask of meter display)

### 5. Kubernetes Namespaces

**Isolation Strategy:**

- Each model version gets dedicated namespace
- Resource quotas per namespace
- Network policies for security

| Namespace    | Components                         |
| ------------ | ---------------------------------- |
| `model-v1`   | TorchServe pod, Service, ConfigMap |
| `model-v2`   | TorchServe pod, Service, ConfigMap |
| `mlflow`     | MLflow server, PVC                 |
| `monitoring` | Prometheus, Grafana                |

### 6. Monitoring Stack

**Prometheus:**

- Scrapes metrics from TorchServe pods
- Custom recording rules for ML metrics
- Alert rules for latency, errors

**Grafana Dashboards:**

- Model Performance: inference latency, throughput
- Infrastructure: CPU, memory, network
- ML Metrics: prediction distribution, model versions

## Data Flow

### Training Flow

```
1. Developer pushes code/data changes
2. GitHub Actions detects changes
3. Pipeline pulls data from S3 (DVC)
4. Training job executes
5. Metrics logged to MLflow
6. Model artifact saved to S3
7. Model registered in MLflow registry
```

### Deployment Flow

```
1. Training completes successfully
2. Docker image built with new model
3. Image pushed to ECR
4. Helm deploys to new namespace
5. Old version remains for rollback
6. Prometheus discovers new pods
```

### Inference Flow

```
1. Client sends image to ALB
2. ALB routes to model service
3. TorchServe runs inference
4. Response returned to client
5. Metrics recorded in Prometheus
```

## Security Considerations

### IAM Roles

| Role                   | Purpose            | Permissions              |
| ---------------------- | ------------------ | ------------------------ |
| EKS Cluster Role       | Cluster management | EKS control plane        |
| EKS Node Role          | Worker nodes       | EC2, ECR pull, S3 read   |
| GitHub Actions Role    | CI/CD pipeline     | ECR push, EKS deploy, S3 |
| MLflow Service Account | MLflow server      | S3 read/write, RDS       |

### Network Security

- EKS nodes in private subnets
- ALB in public subnets
- Security groups limit ingress
- Network policies in Kubernetes

### Secrets Management

- AWS Secrets Manager for credentials
- Kubernetes Secrets for pods
- GitHub Secrets for CI/CD

## Scalability

### Horizontal Scaling

- EKS node group: 2-5 nodes (auto-scaling)
- Model pods: HPA based on CPU/memory
- Multiple model versions in parallel

### Performance Optimization

- Model optimization: TorchScript, quantization
- Caching: S3 intelligent tiering
- CDN: CloudFront for static assets (future)

## Disaster Recovery

### Backup Strategy

| Component  | Backup Method         | Frequency  |
| ---------- | --------------------- | ---------- |
| MLflow DB  | RDS automated backups | Daily      |
| S3 Buckets | Versioning enabled    | Continuous |
| EKS Config | Terraform state in S3 | On change  |

### Recovery Procedures

1. **Model Rollback**: Deploy previous version via Helm
2. **Data Recovery**: Restore from S3 versioning
3. **Infrastructure**: Re-apply Terraform
