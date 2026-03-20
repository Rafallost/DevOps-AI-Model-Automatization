# Helm Chart: ml-model

## Role in Project Architecture

Helm is the **deployment orchestrator** for the ML model service in this project. It handles:

1. **Container Orchestration**: Deploys FastAPI model server on k3s Kubernetes cluster (running on EC2)
2. **Environment Management**: Manages configuration between dev/prod environments via `values.yaml` overrides
3. **MLflow Integration**: Exposes model service with automatic connection to MLflow tracking server
4. **Monitoring**: Ships with Prometheus ServiceMonitor for metrics collection
5. **Health Management**: Configures liveness/readiness probes for automatic pod recovery
6. **ECR Authentication**: Manages private Docker image pull from AWS ECR

## System Flow

```
GitHub Actions (deploy-model.yaml)
    ↓
Builds Docker image → Pushes to ECR
    ↓
Creates ECR credentials in k3s
    ↓
Helm Chart deploys pod with:
  - Image from ECR
  - MLflow URI from values.yaml
  - Resource limits (512Mi RAM, 500m CPU)
  - Health checks every 30s
    ↓
Pod runs on k3s (single node on t3.large)
    ↓
Accessible via NodePort (30080)
    ↓
Prometheus scrapes /metrics endpoint (30s interval)
```

---

## Chart Structure

```
helm/ml-model/
├── Chart.yaml              # Metadata (name, version, maintainer)
├── values.yaml             # Default configuration values
└── templates/
    ├── deployment.yaml     # Kubernetes Deployment spec
    ├── service.yaml        # Service for pod networking
    ├── servicemonitor.yaml # Prometheus monitoring config
    └── _helpers.tpl        # Helm template helper functions
```

---

## Templates Explained

### 1. `deployment.yaml` — Main Application Pod
Defines how the model service runs:
- **Container Image**: Pulled from ECR (user-configurable)
- **Port**: 8000 (FastAPI default)
- **Health Checks**:
  - `livenessProbe`: If pod dies, k3s restarts it
  - `readinessProbe`: If pod not responding, traffic is paused
- **Networking**: `hostNetwork: true` allows pod to access host's localhost (for MLflow on 127.0.0.1:5000)
- **Resource Limits**: 512Mi RAM, 500m CPU (designed for t3.large with headroom for k3s + MLflow)
- **Environment Variables**: Configurable via `values.yaml`

### 2. `service.yaml` — Network Access
Exposes the pod to outside world:
- **Type**: `NodePort` (not LoadBalancer—AWS Academy cost constraint)
- **Port**: 8000 (inside cluster)
- **NodePort**: 30080 (fixed external port on EC2)
- **Access Pattern**: `http://<EC2_IP>:30080/predict`

### 3. `servicemonitor.yaml` — Prometheus Integration
Automatic metrics collection:
- **Scrapes**: Pod's `/metrics` endpoint every 30 seconds
- **Collects**: FastAPI/Prometheus metrics (request count, latency, errors)
- **Requires**: `prometheus-community/kube-prometheus-stack` deployment (optional, installed by Terraform if `install_monitoring=true`)

### 4. `_helpers.tpl` — Template Functions
Reusable Helm template helpers:
- `ml-model.name`: Chart name
- `ml-model.fullname`: Release name with namespace
- `ml-model.chart`: Version info
- Used by all templates to maintain consistency

---

## Values Configuration

### Default (`values.yaml`) vs Override (`helm-values.yaml`)

**Never edit `helm/ml-model/values.yaml` directly** — it's the defaults.
**Instead, override in `infrastructure/helm-values.yaml`** for your environment.

| Value | Default | Description | Override? |
|-------|---------|-------------|-----------|
| `replicaCount` | 1 | Number of pod instances (scale horizontally) | ✅ For HA |
| `deploymentStrategy` | Recreate | k8s update strategy (Recreate or RollingUpdate) | ✅ For zero-downtime |
| `image.repository` | "" (must set) | ECR Docker image URL | ✅ **Required** |
| `image.tag` | "latest" | Docker image version | ✅ Pin to commit hash |
| `image.pullPolicy` | Always | Always pull fresh image | ✅ Or IfNotPresent |
| `imagePullSecrets` | [] | ECR authentication credentials | Auto-created by GitHub Actions |
| `service.type` | NodePort | k8s service type | ⚠️ Don't change (LoadBalancer $$) |
| `service.port` | 8000 | Kubernetes cluster port | ✅ If app port differs |
| `service.nodePort` | 30080 | External EC2 port | ✅ Avoid conflicts |
| `resources.limits.memory` | 512Mi | Max RAM per pod | ✅ If model larger |
| `resources.limits.cpu` | 500m | Max CPU per pod | ✅ Check app needs |
| `env[].MLFLOW_TRACKING_URI` | (none) | MLflow backend URL | ✅ **Required** |
| `env[].MODEL_VERSION` | (none) | Which MLflow model stage to load | ✅ "production" |
| `livenessProbe.initialDelaySeconds` | 30 | Wait before first health check | ✅ Slow startup = increase |
| `readinessProbe.periodSeconds` | 10 | Health check frequency | ✅ Lower = faster recovery |
| `serviceMonitor.enabled` | true | Enable Prometheus scraping | ✅ false if no Prometheus |
| `serviceMonitor.interval` | 30s | Prometheus scrape interval | ✅ Lower = more detail |
| `nodeSelector` | {} | Pin pod to specific node | ✅ For node affinity |
| `tolerations` | [] | Pod toleration for node taints | ✅ For multi-node setup |
| `affinity` | {} | Pod scheduling preferences | ✅ For podAntiAffinity |

---

## Usage Examples

### Basic Installation (Production)
```bash
helm upgrade --install wms-model helm/ml-model \
  --set image.repository=055677744286.dkr.ecr.us-east-1.amazonaws.com/wms-model \
  --set image.tag=latest \
  --set env[0].name=MLFLOW_TRACKING_URI \
  --set env[0].value=http://localhost:5000 \
  --set env[1].name=MODEL_VERSION \
  --set env[1].value=production
```

### Install with Custom Values File
```bash
helm upgrade --install wms-model helm/ml-model \
  -f infrastructure/helm-values.yaml
```

### Verify Deployment
```bash
# Check pod status
kubectl get pods -l app=ml-model

# Check pod logs
kubectl logs -l app=ml-model --tail=50

# Check service endpoint
kubectl get svc -l app=ml-model

# Test the API
curl http://<EC2_IP>:30080/health
curl -X POST http://<EC2_IP>:30080/predict -d '{"image": "..."}'

# Check Prometheus is scraping
kubectl get servicemonitor
```

### Uninstall
```bash
helm uninstall wms-model
```

---

## Expansion Possibilities

### 1. **Horizontal Scaling** (Multiple Pods)
**Current**: 1 pod on 1 node (t3.large)
**Scalable to**:
```yaml
replicaCount: 3  # 3 pods behind load balancer
serviceMonitor:
  interval: 10s   # More frequent health checks
affinity:
  podAntiAffinity: # Spread pods across nodes (requires multi-node cluster)
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - ml-model
        topologyKey: kubernetes.io/hostname
```
**Requirement**: Multi-node k3s cluster (via Terraform multi-EC2 setup)

### 2. **Resource Auto-Scaling** (HPA)
Add Horizontal Pod Autoscaler:
```yaml
# New template: templates/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "ml-model.fullname" . }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "ml-model.fullname" . }}
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### 3. **Ingress Controller** (Better External Access)
Replace NodePort with Ingress:
```yaml
# New template: templates/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "ml-model.fullname" . }}
spec:
  rules:
  - host: ml-model.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: {{ include "ml-model.fullname" . }}
            port:
              number: 8000
```
**Requires**: k3s with Traefik or nginx-ingress installed

### 4. **ConfigMap/Secret Management**
Externalizing configuration:
```yaml
# New template: templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "ml-model.fullname" . }}-config
data:
  model_path: "/app/models/best.pth"
  log_level: "INFO"
  # Reference in deployment: valueFrom.configMapKeyRef

# New template: templates/secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "ml-model.fullname" . }}-secrets
type: Opaque
stringData:
  mlflow_uri: "http://localhost:5000"
  aws_region: "us-east-1"
  # Reference in deployment: valueFrom.secretKeyRef
```

### 5. **Network Policy** (Security)
Restrict traffic:
```yaml
# New template: templates/networkpolicy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "ml-model.fullname" . }}-policy
spec:
  podSelector:
    matchLabels:
      app: ml-model
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 8000
```

### 6. **PersistentVolume** (Model Caching)
Cache downloaded MLflow models:
```yaml
# New template: templates/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ include "ml-model.fullname" . }}-models
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  # In deployment: volumeMounts: [{name: models, mountPath: /app/models}]
```

### 7. **RBAC (Role-Based Access Control)**
Limit pod permissions:
```yaml
# New template: templates/serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "ml-model.fullname" . }}

# templates/role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ include "ml-model.fullname" . }}
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]

# templates/rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ include "ml-model.fullname" . }}
roleRef:
  apiVersion: rbac.authorization.k8s.io/v1
  kind: Role
  name: {{ include "ml-model.fullname" . }}
subjects:
- kind: ServiceAccount
  name: {{ include "ml-model.fullname" . }}
```

### 8. **Multi-Environment Support**
Separate Helm releases:
```bash
# Dev environment
helm upgrade --install wms-model-dev helm/ml-model \
  -f environments/dev-values.yaml

# Staging
helm upgrade --install wms-model-staging helm/ml-model \
  -f environments/staging-values.yaml

# Production
helm upgrade --install wms-model-prod helm/ml-model \
  -f environments/prod-values.yaml
```

### 9. **GitOps with Flux/ArgoCD**
Automated sync from Git:
```yaml
# ArgoCD Application manifest
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: wms-model
spec:
  project: default
  source:
    repoURL: https://github.com/Rafallost/Water-Meters-Segmentation-Automatization
    targetRevision: main
    path: helm/ml-model
    helm:
      valueFiles:
      - ../../infrastructure/helm-values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: default
```

### 10. **Canary Deployments**
Gradual rollout (requires Flagger):
```yaml
# Flagger Canary resource
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: {{ include "ml-model.fullname" . }}
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "ml-model.fullname" . }}
  progressDeadlineSeconds: 60
  service:
    port: 8000
  analysis:
    interval: 1m
    threshold: 5
    maxWeight: 50
    stepWeight: 10
    metrics:
    - name: request-success-rate
      thresholdRange:
        min: 99
```

---

## Checklist: From Single Pod to Enterprise

- [ ] **Current**: Single pod on EC2 with NodePort access
- [ ] **Next**: Add HPA for auto-scaling
- [ ] **Then**: Multi-node k3s cluster with pod affinity
- [ ] **Then**: Ingress controller + domain name
- [ ] **Then**: GitOps (ArgoCD/Flux) for declarative deployments
- [ ] **Finally**: Canary deployments + traffic routing (Flagger/Istio)

---

## Notes

- This chart is **generic** — works with any FastAPI/Gunicorn model service
- Terraform user-data.sh pre-installs `kubectl`, `helm`, `k3s`
- GitHub Actions automatically pushes images to ECR and triggers deployment
- For AWS Academy: NodePort + fixed port 30080 (no AWS Load Balancer cost)
- MLflow runs on EC2 localhost — k3s pod accesses via `hostNetwork: true`
