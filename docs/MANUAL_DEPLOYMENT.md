# Manual Deployment Guide

## Overview

This guide documents the **manual** deployment process for the Water Meters Segmentation model. This process is used for **comparative analysis** in the thesis to demonstrate the advantages of automated CI/CD deployment.

**Purpose:** Show the time, effort, and complexity required to deploy a model **without** automation.

**Comparison:**
| Aspect | Manual Deployment (this guide) | Automated CI/CD |
|--------|-------------------------------|-----------------|
| Time to deploy | ~2-3 hours | ~15 minutes |
| Human effort | High (many manual steps) | Low (just git push) |
| Error prone | Yes (manual commands) | No (automated, tested) |
| Reproducibility | Low (depends on operator) | High (identical every time) |
| Rollback | Manual (risky) | Automated (kubectl rollout undo) |
| Monitoring setup | Manual configuration | Auto-configured |

---

## Prerequisites

Before starting manual deployment:

- ✅ EC2 instance running with k3s installed
- ✅ SSH access to EC2 (`~/.ssh/labsuser.pem`)
- ✅ AWS CLI configured locally
- ✅ Docker installed locally OR on EC2
- ✅ Model trained and available in MLflow
- ✅ kubectl configured to access k3s cluster

---

## Step 1: Download Model from MLflow (Manual)

**Time:** ~5-10 minutes

### 1.1 Start EC2 Instance

```bash
# Get EC2 instance ID
EC2_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=wms-project-k3s" \
           "Name=instance-state-name,Values=stopped" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text)

# Start instance
aws ec2 start-instances --instance-ids $EC2_ID

# Wait for it to be running (manual polling)
aws ec2 wait instance-running --instance-ids $EC2_ID

# Get public IP
EC2_IP=$(aws ec2 describe-instances \
  --instance-ids $EC2_ID \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "EC2 IP: $EC2_IP"
```

### 1.2 Wait for MLflow to Start

```bash
# SSH to EC2
ssh -i ~/.ssh/labsuser.pem ec2-user@$EC2_IP

# Check if MLflow is running (manual check, may need to wait 2-5 min)
curl http://localhost:5000/health

# If not running, start MLflow manually
cd ~/mlflow
mlflow server \
  --backend-store-uri sqlite:///mlflow.db \
  --default-artifact-root s3://wms-mlflow-artifacts-<ACCOUNT_ID>/ \
  --host 0.0.0.0 \
  --port 5000 &

# Wait and check again
sleep 30
curl http://localhost:5000/health
```

### 1.3 Download Production Model

On EC2:

```bash
# Download model from MLflow Production stage
python3 << 'EOF'
import mlflow
from mlflow.tracking import MlflowClient
import os

mlflow.set_tracking_uri("http://localhost:5000")
client = MlflowClient()

# Get Production model
versions = client.get_latest_versions("water-meter-segmentation", stages=["Production"])
if not versions:
    print("ERROR: No Production model found!")
    exit(1)

model_version = versions[0]
model_uri = f"models:/water-meter-segmentation/Production"

# Download to local directory
os.makedirs("/tmp/wms-model", exist_ok=True)
mlflow.pytorch.load_model(model_uri)  # This downloads artifacts

print(f"Model downloaded: version {model_version.version}")
EOF
```

**Potential issues:**

- MLflow not started → manual start required
- Network timeout → retry
- Wrong model version → manual investigation

---

## Step 2: Build Docker Image (Manual)

**Time:** ~10-15 minutes (depending on image size and network)

### 2.1 Create Dockerfile (if not exists)

On your **local machine** or **EC2**:

```bash
# Check if Dockerfile exists
cat docker/Dockerfile.serve

# If not, create it manually (error-prone!)
```

### 2.2 Build Docker Image

On EC2 (or locally):

```bash
# Navigate to project root
cd ~/Water-Meters-Segmentation-Automatization

# Build Docker image manually
docker build -f docker/Dockerfile.serve -t wms-model:latest .

# Check image size
docker images | grep wms-model

# Test image locally (optional but recommended)
docker run -d -p 8000:8000 --name wms-test wms-model:latest

# Wait for startup
sleep 10

# Test health endpoint
curl http://localhost:8000/health

# Stop test container
docker stop wms-test
docker rm wms-test
```

**Potential issues:**

- Dockerfile syntax error → manual fix
- Missing dependencies → update requirements.txt and rebuild
- Build fails → debug and retry
- Image too large → optimize manually

---

## Step 3: Push to ECR (Manual)

**Time:** ~5-10 minutes

### 3.1 Login to ECR

```bash
# Get ECR login password
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  055677744286.dkr.ecr.us-east-1.amazonaws.com
```

### 3.2 Tag and Push Image

```bash
# Tag image for ECR
docker tag wms-model:latest \
  055677744286.dkr.ecr.us-east-1.amazonaws.com/wms-model:latest

# Push to ECR (slow - 8-9 GB upload!)
docker push 055677744286.dkr.ecr.us-east-1.amazonaws.com/wms-model:latest

# Manually verify push succeeded
aws ecr describe-images \
  --repository-name wms-model \
  --region us-east-1
```

**Potential issues:**

- ECR login expired → re-login
- Network timeout during push → retry
- Insufficient permissions → check IAM role

---

## Step 4: Configure kubectl (Manual)

**Time:** ~5-10 minutes

### 4.1 Get kubeconfig from EC2

On EC2:

```bash
# Copy kubeconfig to accessible location
sudo cp /etc/rancher/k3s/k3s.yaml ~/kubeconfig
sudo chown ec2-user:ec2-user ~/kubeconfig

# Modify kubeconfig to use EC2 public IP
sed -i "s/127.0.0.1/$EC2_IP/g" ~/kubeconfig
```

On your local machine:

```bash
# Download kubeconfig
scp -i ~/.ssh/labsuser.pem ec2-user@$EC2_IP:~/kubeconfig ~/.kube/wms-config

# Set KUBECONFIG environment variable
export KUBECONFIG=~/.kube/wms-config

# Test connection
kubectl get nodes
```

**Potential issues:**

- Permission denied → fix file permissions
- Connection timeout → check security group allows port 6443
- kubeconfig wrong IP → manually edit file

---

## Step 5: Create ECR Pull Secret (Manual)

**Time:** ~5 minutes

### 5.1 Generate ECR Secret

```bash
# Get ECR auth token
ECR_TOKEN=$(aws ecr get-login-password --region us-east-1)

# Create kubectl secret manually
kubectl create secret docker-registry ecr-secret \
  --docker-server=055677744286.dkr.ecr.us-east-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$ECR_TOKEN" \
  --namespace=default

# Verify secret created
kubectl get secret ecr-secret -o yaml
```

**Potential issues:**

- Token expires after 12 hours → recreate secret
- Namespace mismatch → specify correct namespace
- Secret already exists → delete and recreate

---

## Step 6: Deploy to k3s (Manual)

**Time:** ~10-15 minutes

### 6.1 Create Kubernetes Manifests (if using raw YAML)

**Option A: Using Helm (semi-automated)**

```bash
# Install Helm chart manually
helm upgrade --install wms-model devops/helm/ml-model/ \
  -f infrastructure/helm-values.yaml \
  --namespace=default \
  --create-namespace

# Wait for deployment to complete (manual polling)
kubectl get pods -w

# Check pod logs for errors
kubectl logs -l app=wms-model --tail=50
```

**Option B: Using raw kubectl (fully manual)**

Create deployment.yaml manually:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wms-model
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wms-model
  template:
    metadata:
      labels:
        app: wms-model
    spec:
      imagePullSecrets:
        - name: ecr-secret
      containers:
        - name: model
          image: 055677744286.dkr.ecr.us-east-1.amazonaws.com/wms-model:latest
          ports:
            - containerPort: 8000
          env:
            - name: MLFLOW_TRACKING_URI
              value: "http://10.0.1.16:5000" # MANUAL: Get internal IP!
            - name: MODEL_VERSION
              value: "production"
          resources:
            limits:
              memory: "512Mi"
              cpu: "500m"
            requests:
              memory: "256Mi"
              cpu: "250m"
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 30
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 15
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: wms-model
spec:
  type: NodePort
  selector:
    app: wms-model
  ports:
    - port: 8000
      targetPort: 8000
      nodePort: 30080 # Fixed port for external access
```

Apply manually:

```bash
kubectl apply -f deployment.yaml

# Wait for pod to be ready (manual checking)
kubectl get pods -w

# If pod fails, debug manually
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

**Potential issues:**

- ImagePullBackOff → check ECR secret
- CrashLoopBackOff → check logs for errors
- Pod stuck Pending → check resource limits
- Wrong MLflow URI → manually update and redeploy

---

## Step 7: Verify Deployment (Manual)

**Time:** ~5-10 minutes

### 7.1 Check Pod Status

```bash
# Check pods are running
kubectl get pods -l app=wms-model

# Check service
kubectl get svc wms-model

# Get NodePort
kubectl get svc wms-model -o jsonpath='{.spec.ports[0].nodePort}'
```

### 7.2 Test Health Endpoint

```bash
# Test from EC2 (localhost)
curl http://localhost:30080/health

# Test from your machine (external)
curl http://$EC2_IP:30080/health
```

Expected response:

```json
{ "status": "healthy", "model_loaded": true }
```

### 7.3 Test Prediction Endpoint

```bash
# Download test image
curl -o test_meter.jpg https://example.com/water_meter.jpg

# Send prediction request
curl -X POST http://$EC2_IP:30080/predict \
  -F "image=@test_meter.jpg" \
  -o predicted_mask.png

# Check if mask was generated
file predicted_mask.png
```

**Potential issues:**

- 404 Not Found → service not exposed correctly
- Connection refused → NodePort wrong or firewall blocking
- 500 Internal Server Error → check pod logs
- Timeout → model loading slow, increase timeout

---

## Step 8: Setup Monitoring (Manual)

**Time:** ~20-30 minutes

### 8.1 Install Prometheus

```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus manually
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace

# Wait for all pods to be ready
kubectl get pods -n monitoring -w
```

### 8.2 Configure ServiceMonitor

```bash
# Create ServiceMonitor for WMS model
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: wms-model
  namespace: default
spec:
  selector:
    matchLabels:
      app: wms-model
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
EOF
```

### 8.3 Access Grafana Dashboard

```bash
# Port-forward Grafana (manual)
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Open browser: http://localhost:3000
# Login: admin / prom-operator (default)

# Manually import dashboard for ML metrics
# Manually configure data source
# Manually create custom queries
```

**Potential issues:**

- Helm repo not added → add manually
- Prometheus pods crash → check logs and resources
- ServiceMonitor not scraping → check labels match
- Grafana login fails → reset password manually

---

## Step 9: Document and Verify

**Time:** ~10-15 minutes

### Manual Checklist:

- [ ] EC2 started manually
- [ ] MLflow started and checked manually
- [ ] Model downloaded from MLflow
- [ ] Docker image built successfully
- [ ] Image pushed to ECR
- [ ] kubectl configured to access k3s
- [ ] ECR pull secret created
- [ ] Deployment applied via Helm or kubectl
- [ ] Pods running and healthy
- [ ] /health endpoint returns 200
- [ ] /predict endpoint works
- [ ] Monitoring configured
- [ ] Grafana dashboard accessible

### Record Deployment Info:

```bash
# Get deployment details manually
kubectl describe deployment wms-model > deployment-details.txt
kubectl get pods -o wide > pod-info.txt
kubectl get events --sort-by=.metadata.creationTimestamp > events.log

# Record metrics manually
echo "Deployment completed at: $(date)" >> deployment-log.txt
echo "Time taken: X hours Y minutes" >> deployment-log.txt
```

---

## Step 10: Cleanup (Manual)

When testing is done:

```bash
# Delete deployment
kubectl delete deployment wms-model
kubectl delete service wms-model
kubectl delete secret ecr-secret

# Stop EC2 manually
aws ec2 stop-instances --instance-ids $EC2_ID

# Remove local images
docker rmi wms-model:latest
docker rmi 055677744286.dkr.ecr.us-east-1.amazonaws.com/wms-model:latest
```

---

## Common Issues and Troubleshooting

### Issue 1: Image Pull Fails

**Symptom:** Pod stuck in `ImagePullBackOff`

**Solution:**

```bash
# Check ECR secret
kubectl get secret ecr-secret -o yaml

# Recreate if expired
kubectl delete secret ecr-secret
# Repeat Step 5.1
```

### Issue 2: Pod Crashes

**Symptom:** `CrashLoopBackOff` or `Error` status

**Solution:**

```bash
# Check logs
kubectl logs <pod-name>

# Common causes:
# - Wrong MLflow URI → update deployment
# - Missing dependencies → rebuild Docker image
# - Out of memory → increase limits
```

### Issue 3: Slow Deployment

**Symptom:** Pod takes >10 minutes to start

**Solution:**

- Check image size (should be ~8-9 GB)
- ECR pull of ~8-9 GB image takes 5-10 min on t3.large --- expected behaviour
- Model loading from MLflow is slow → optimize model size

### Issue 4: Cannot Access from External IP

**Symptom:** `curl http://$EC2_IP:30080/health` times out

**Solution:**

```bash
# Check security group allows port 30080
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=wms-project-sg"

# Add rule if missing
aws ec2 authorize-security-group-ingress \
  --group-id <sg-id> \
  --protocol tcp \
  --port 30080 \
  --cidr 0.0.0.0/0
```

---

## Time & Effort Summary

### Total Time (Manual Deployment):

| Step                 | Time           | Complexity |
| -------------------- | -------------- | ---------- |
| 1. Download Model    | 5-10 min       | Medium     |
| 2. Build Docker      | 10-15 min      | High       |
| 3. Push to ECR       | 5-10 min       | Medium     |
| 4. Configure kubectl | 5-10 min       | Medium     |
| 5. Create ECR Secret | 5 min          | Low        |
| 6. Deploy to k3s     | 10-15 min      | High       |
| 7. Verify Deployment | 5-10 min       | Medium     |
| 8. Setup Monitoring  | 20-30 min      | Very High  |
| 9. Documentation     | 10-15 min      | Low        |
| **TOTAL**            | **75-120 min** | **High**   |

**Actual time with issues:** 2-3 hours (debugging, retries, errors)

---

## Comparison: Manual vs Automated CI/CD

### Manual Deployment (This Guide):

```
Developer actions:
1. Start EC2 (wait 2 min)
2. SSH to EC2, check MLflow (wait 5 min)
3. Download model manually
4. Build Docker (wait 10 min)
5. Login to ECR
6. Push to ECR (wait 10 min)
7. Configure kubectl
8. Create K8s secret
9. Apply Helm/kubectl
10. Wait for pod (wait 5 min)
11. Test health endpoint
12. Test predict endpoint
13. Setup monitoring (manual)
14. Document everything

Total: 2-3 hours, high error rate, low reproducibility
```

### Automated CI/CD:

```
Developer action:
1. git push origin main

System does:
- Build Docker ✓
- Push to ECR ✓
- Deploy to k3s ✓
- Health checks ✓
- Monitoring auto-configured ✓

Total: 15 minutes, automated, 100% reproducible
```

**Advantage: 8-12x faster, 0 manual steps, consistent quality!**

---

## For Thesis: Metrics to Collect

When performing manual deployment for comparison:

1. **Time Metrics:**
   - Time to deploy (start to verified working)
   - Waiting time (EC2 start, MLflow, builds, pulls)
   - Active work time (typing commands)

2. **Error Metrics:**
   - Number of failed attempts
   - Number of manual retries
   - Time spent debugging

3. **Effort Metrics:**
   - Number of manual commands executed
   - Number of files manually edited
   - Number of SSH sessions needed

4. **Quality Metrics:**
   - Configuration drift (differences between deploys)
   - Missing steps (forgotten monitoring, etc.)
   - Documentation completeness

---

## Conclusion

Manual deployment is:

- ✅ Possible (you can deploy without CI/CD)
- ❌ Time-consuming (2-3 hours vs 15 minutes)
- ❌ Error-prone (many manual steps)
- ❌ Not reproducible (each deployment differs)
- ❌ Requires expert knowledge
- ❌ Difficult to scale (imagine 10 models!)

**This demonstrates the value of automated CI/CD for ML model deployment.**
