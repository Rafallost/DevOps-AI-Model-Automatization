# MLOps System Diagrams

## 1. C4 Context Diagram - System Overview

```mermaid
graph TB
    subgraph Actors
        ML[ML Engineer<br/>Develops, trains, and deploys ML models]
        DevOps[DevOps Engineer<br/>Manages infrastructure and CI/CD]
        API[API Consumer<br/>Integrates with model inference API]
    end

    subgraph MLOps["MLOps Platform"]
        System[Automated CI/CD pipeline<br/>for training, versioning,<br/>and deploying U-Net<br/>segmentation models]
    end

    subgraph External["External Systems"]
        GitHub[GitHub<br/>Rafallost/Water-Meters-Segmentation]
        AWS[AWS Cloud<br/>EKS, S3, ECR, RDS]
        Kaggle[Kaggle Dataset<br/>Water Meters Dataset]
    end

    ML -->|Develops models,<br/>monitors experiments| System
    DevOps -->|Configures infrastructure,<br/>monitors pipelines| System
    API -->|Requests model<br/>predictions| System

    System -->|Stores code,<br/>triggers pipelines| GitHub
    System -->|Runs on AWS<br/>infrastructure| AWS
    Kaggle -->|Provides training data| System

    style System fill:#1168bd,stroke:#0b4884,color:#fff
    style GitHub fill:#999,stroke:#666,color:#fff
    style AWS fill:#999,stroke:#666,color:#fff
    style Kaggle fill:#999,stroke:#666,color:#fff
```

---

## 2. Data Flow Diagram - Training and Deployment Pipeline

```mermaid
flowchart LR
    subgraph Developer
        DEV[ML Engineer]
    end

    subgraph SourceControl["Source Control"]
        REPO[GitHub Repo<br/>WMS/src/*.py<br/>WMS/models/*.pth<br/>DVC pointers]
    end

    subgraph CICD["CI/CD Pipeline"]
        GHA[GitHub Actions]
        LINT[Code Quality<br/>flake8, pytest]
        DETECT[Change Detection<br/>DVC + Git]
        TRAIN[Training Job<br/>WMS/src/train.py<br/>U-Net model]
        BUILD[Build & Push<br/>Docker]
        DEPLOY[Deploy<br/>Helm]
    end

    subgraph Storage["Storage Layer"]
        S3_DATA[(S3 DVC Bucket<br/>Training datasets)]
        S3_ART[(S3 MLflow Bucket<br/>Model artifacts)]
        ECR[(ECR Registry<br/>Container images)]
    end

    subgraph MLOps["MLOps Platform"]
        MLFLOW[MLflow Server<br/>Experiment tracking<br/>Model registry]
        MLDB[(MLflow DB<br/>RDS MySQL)]
    end

    subgraph Runtime["Kubernetes Runtime"]
        SERVE[Model Serving<br/>TorchServe]
        MON[Monitoring<br/>Prometheus + Grafana]
    end

    subgraph Consumer
        USER[API Consumer]
    end

    DEV -->|1. git push| REPO
    REPO -->|2. Webhook trigger| GHA
    GHA -->|3a. Run tests| LINT
    GHA -->|3b. Detect changes| DETECT
    DETECT -->|4. dvc pull| S3_DATA
    DETECT -->|5. If data changed| TRAIN
    TRAIN -->|Read data| S3_DATA
    TRAIN -->|6. Log metrics & model| MLFLOW
    MLFLOW --> MLDB
    MLFLOW --> S3_ART
    TRAIN -->|7. On success| BUILD
    BUILD -->|Push image| ECR
    BUILD -->|8. Deploy to K8s| DEPLOY
    DEPLOY -->|Helm upgrade| SERVE
    USER -->|9. Inference request| SERVE
    SERVE -->|Expose /metrics| MON
    DEV -.->|View dashboards| MON
    DEV -.->|View experiments| MLFLOW
```

---

## 3. Deployment Diagram - AWS Infrastructure

```mermaid
graph TB
    subgraph GitHub["GitHub"]
        subgraph Repo["Rafallost/Water-Meters-Segmentation"]
            SRC[WMS/src/<br/>model.py, train.py<br/>dataset.py, predicts.py]
            MODELS[WMS/models/<br/>best.pth<br/>50 checkpoints]
            INFRA[infrastructure/<br/>Terraform/Helm]
            WORKFLOWS[.github/workflows/<br/>CI/CD pipelines]
        end
        subgraph Actions["GitHub Actions"]
            CI[CI Pipeline<br/>Linting, testing]
            TRAIN_P[Training Pipeline<br/>Model training]
            DEPLOY_P[Deploy Pipeline<br/>Build & deploy]
        end
    end

    subgraph AWS["AWS Cloud (eu-central-1)"]
        subgraph VPC["VPC (10.0.0.0/16)"]
            subgraph Public["Public Subnets"]
                ALB[Application<br/>Load Balancer]
                NAT[NAT Gateway]
            end
            subgraph Private["Private Subnets"]
                subgraph EKS["Amazon EKS (K8s 1.28)"]
                    subgraph NS_V1["Namespace: model-v1"]
                        POD_V1[Model Pod v1<br/>TorchServe]
                        SVC_V1[Service v1<br/>ClusterIP]
                    end
                    subgraph NS_V2["Namespace: model-v2"]
                        POD_V2[Model Pod v2<br/>TorchServe]
                        SVC_V2[Service v2<br/>ClusterIP]
                    end
                    subgraph NS_ML["Namespace: mlflow"]
                        MLFLOW_S[MLflow Server]
                    end
                    subgraph NS_MON["Namespace: monitoring"]
                        PROM[Prometheus]
                        GRAF[Grafana]
                    end
                end
            end
        end
        subgraph Storage["Storage Services"]
            S3_DVC[(S3: DVC Data<br/>Training datasets)]
            S3_MLF[(S3: MLflow Artifacts<br/>Model artifacts)]
            ECR_R[(ECR Repository<br/>Docker images)]
            RDS[(RDS MySQL<br/>MLflow metadata)]
        end
    end

    DEV[ML Engineer] -->|git push| SRC
    DEV -.->|Monitors| GRAF
    DEV -.->|Tracks experiments| MLFLOW_S

    SRC -->|Triggers| CI
    CI -->|On success| TRAIN_P
    TRAIN_P -->|DVC pull/push| S3_DVC
    TRAIN_P -->|Log metrics| MLFLOW_S
    TRAIN_P -->|On success| DEPLOY_P
    DEPLOY_P -->|Push image| ECR_R
    DEPLOY_P -->|Helm deploy| EKS

    USER[End User] -->|HTTPS| ALB
    ALB --> SVC_V1
    ALB --> SVC_V2

    POD_V1 -->|/metrics| PROM
    POD_V2 -->|/metrics| PROM
    PROM --> GRAF

    MLFLOW_S --> RDS
    MLFLOW_S --> S3_MLF

    style EKS fill:#ff9900,stroke:#cc7a00
    style AWS fill:#232f3e,stroke:#1a242f,color:#fff
```

---

## 4. CI/CD Pipeline Sequence

```mermaid
sequenceDiagram
    participant Dev as ML Engineer
    participant GH as GitHub
    participant GHA as GitHub Actions
    participant DVC as DVC/S3
    participant Train as Training Job
    participant MLF as MLflow
    participant ECR as ECR
    participant K8s as Kubernetes

    Dev->>GH: 1. Push code/data changes
    GH->>GHA: 2. Trigger webhook

    rect rgba(100, 149, 237, 0.3)
        Note over GHA: CI Stage
        GHA->>GHA: 3. Run linting (flake8)
        GHA->>GHA: 4. Run tests (pytest)
    end

    rect rgba(60, 179, 113, 0.3)
        Note over GHA,Train: Training Stage
        GHA->>DVC: 5. Check for data changes
        DVC-->>GHA: Data changed
        GHA->>Train: 6. Start training job
        Train->>DVC: 7. Pull training data
        Train->>Train: 8. Train U-Net model
        Train->>MLF: 9. Log metrics & artifacts
    end

    rect rgba(255, 165, 0, 0.3)
        Note over GHA,K8s: Deployment Stage
        GHA->>ECR: 10. Build & push Docker image
        GHA->>K8s: 11. Deploy via Helm
        K8s->>K8s: 12. Rolling update
    end

    Dev-->>MLF: View experiments
    Dev-->>K8s: Monitor via Grafana
```

---

## 5. Model Versioning Flow

```mermaid
graph LR
    subgraph Training["Model Training"]
        T1[Train v1.0] --> M1[Model v1.0<br/>accuracy: 85%]
        T2[Train v1.1] --> M2[Model v1.1<br/>accuracy: 88%]
        T3[Train v2.0] --> M3[Model v2.0<br/>accuracy: 92%]
    end

    subgraph Registry["MLflow Model Registry"]
        M1 --> REG1[Registered v1.0<br/>Stage: Archived]
        M2 --> REG2[Registered v1.1<br/>Stage: Staging]
        M3 --> REG3[Registered v2.0<br/>Stage: Production]
    end

    subgraph Kubernetes["Kubernetes Namespaces"]
        REG2 --> NS1[namespace: model-staging<br/>Testing & validation]
        REG3 --> NS2[namespace: model-prod<br/>Production traffic]
    end

    subgraph Monitoring
        NS1 --> MON1[Grafana Dashboard<br/>Staging metrics]
        NS2 --> MON2[Grafana Dashboard<br/>Production metrics]
    end

    style REG3 fill:#28a745,stroke:#1e7e34,color:#fff
    style NS2 fill:#28a745,stroke:#1e7e34,color:#fff
```
