# Deployment Verification Guide

## Overview

This guide explains how to verify that the **automated deployment** to k3s succeeded. Use this after the `release-deploy.yaml` workflow completes.

---

## Quick Verification Checklist

After deployment workflow finishes:

- [ ] GitHub Actions workflow status: ✅ Success
- [ ] Docker image in ECR with `latest` tag
- [ ] k3s pod running and healthy
- [ ] `/health` endpoint returns 200 OK
- [ ] `/predict` endpoint accepts requests
- [ ] Prometheus metrics available
- [ ] Grafana dashboard shows data (if monitoring enabled)

---

## Step 1: Check GitHub Actions Workflow

### 1.1 Workflow Status

Go to: **GitHub → Actions → Release & Deploy**

Check latest run:
- ✅ Green checkmark = Success
- ❌ Red X = Failed (check logs)
- 🟡 Yellow dot = In progress (wait)

### 1.2 Review Logs

Click on the workflow run → **build-and-deploy** job

Check each step:
- ✅ Login to ECR
- ✅ Build + Push Docker
- ✅ Deploy via Helm

If any step fails, scroll down for error details.

---

## Step 2: Verify Docker Image in ECR

### 2.1 Check ECR Repository

```bash
# List images in ECR
aws ecr describe-images \
  --repository-name wms-model \
  --region us-east-1 \
  --query 'imageDetails[*].[imageTags[0],imagePushedAt,imageSizeInBytes]' \
  --output table
```

Expected output:
```
--------------------------------
|      DescribeImages          |
+--------+-----------+---------+
| latest | 2026-02-09| 8.5GB   |
+--------+-----------+---------+
```

### 2.2 Check Image Tag

```bash
# Get latest image digest
aws ecr describe-images \
  --repository-name wms-model \
  --region us-east-1 \
  --image-ids imageTag=latest \
  --query 'imageDetails[0].imageDigest' \
  --output text
```

This digest should match what was deployed.

---

## Step 3: Connect to k3s Cluster

### 3.1 SSH to EC2

```bash
# Get EC2 IP
EC2_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=wms-project-k3s" \
           "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

# SSH to EC2
ssh -i ~/.ssh/labsuser.pem ec2-user@$EC2_IP
```

### 3.2 Check kubectl Access

On EC2:

```bash
# List nodes
kubectl get nodes

# Expected output:
# NAME              STATUS   ROLE                  AGE   VERSION
# ip-10-0-1-xx      Ready    control-plane,master  5d    v1.28.5+k3s1

# List all pods
kubectl get pods --all-namespaces
```

---

## Step 4: Verify Pod Status

### 4.1 Check Deployment

```bash
# List deployments
kubectl get deployments

# Expected output:
# NAME        READY   UP-TO-DATE   AVAILABLE   AGE
# wms-model   1/1     1            1           5m
```

If **READY** is `0/1`:
- Pod is not healthy → check logs (Step 5)

If **AVAILABLE** is `0`:
- Pod not ready yet → wait 1-2 minutes
- OR pod crashing → check events (Step 5.2)

### 4.2 Check Pod Details

```bash
# Get pod name
POD_NAME=$(kubectl get pods -l app=wms-model -o jsonpath='{.items[0].metadata.name}')

# Show pod status
kubectl get pod $POD_NAME

# Expected output:
# NAME                        READY   STATUS    RESTARTS   AGE
# wms-model-xxxxxxxxx-xxxxx   1/1     Running   0          5m
```

**Possible statuses:**
- ✅ `Running` with `1/1 READY` → Good!
- ⏳ `ContainerCreating` → Wait (pulling image)
- ⏳ `Pending` → Waiting for resources
- ❌ `ImagePullBackOff` → ECR auth issue (check Step 6.1)
- ❌ `CrashLoopBackOff` → App crashes (check Step 5.1)
- ❌ `Error` → Failed to start (check Step 5.1)

### 4.3 Check Pod Resources

```bash
# Show resource usage
kubectl top pod $POD_NAME

# Expected output:
# NAME                        CPU(cores)   MEMORY(bytes)
# wms-model-xxxxxxxxx-xxxxx   50m          300Mi
```

If CPU or Memory is at limit:
- Increase resource requests/limits in `helm-values.yaml`

---

## Step 5: Check Pod Logs and Events

### 5.1 View Pod Logs

```bash
# View last 50 lines
kubectl logs $POD_NAME --tail=50

# Follow logs in real-time
kubectl logs $POD_NAME -f

# View logs from previous crash (if pod restarted)
kubectl logs $POD_NAME --previous
```

**Look for:**
- ✅ `"Model loaded successfully"`
- ✅ `"Uvicorn running on http://0.0.0.0:8000"`
- ❌ `"Error loading model"` → MLflow connection issue
- ❌ `"ModuleNotFoundError"` → Missing dependency
- ❌ `"Out of memory"` → Increase memory limits

### 5.2 Check Events

```bash
# Show recent events
kubectl describe pod $POD_NAME | grep -A 10 Events

# Or view all events
kubectl get events --sort-by=.metadata.creationTimestamp | grep wms-model
```

**Common events:**
- `Successfully pulled image` → Good
- `Failed to pull image` → ECR auth issue
- `Back-off restarting failed container` → App crashes
- `Insufficient memory` → Increase limits

---

## Step 6: Troubleshoot Common Issues

### 6.1 ImagePullBackOff

**Cause:** Cannot pull image from ECR

**Solution:**

```bash
# Check if ECR secret exists
kubectl get secret ecr-secret

# If missing or expired, recreate:
ECR_TOKEN=$(aws ecr get-login-password --region us-east-1)

kubectl delete secret ecr-secret --ignore-not-found
kubectl create secret docker-registry ecr-secret \
  --docker-server=055677744286.dkr.ecr.us-east-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$ECR_TOKEN"

# Restart deployment to use new secret
kubectl rollout restart deployment wms-model
```

### 6.2 CrashLoopBackOff

**Cause:** Application crashes on startup

**Solution:**

```bash
# Check logs for error
kubectl logs $POD_NAME --tail=100

# Common causes:
# 1. Wrong MLflow URI → Update helm-values.yaml
# 2. Model not found → Check MLflow has Production model
# 3. Out of memory → Increase limits

# After fixing, redeploy:
helm upgrade --install wms-model devops/helm/ml-model/ \
  -f infrastructure/helm-values.yaml
```

### 6.3 Pending Status

**Cause:** Not enough resources

**Solution:**

```bash
# Check node resources
kubectl describe node

# If out of memory/CPU, reduce resource requests in helm-values.yaml
# Or upgrade EC2 instance type (t3.small → t3.medium)
```

---

## Step 7: Test Health Endpoint

### 7.1 From Inside Pod

```bash
# Execute curl inside the pod
kubectl exec $POD_NAME -- curl http://localhost:8000/health
```

Expected response:
```json
{"status":"healthy","model_loaded":true}
```

### 7.2 From EC2 (via Service)

```bash
# Get service
kubectl get svc wms-model

# Test via service name
curl http://wms-model:8000/health

# Or via ClusterIP
SVC_IP=$(kubectl get svc wms-model -o jsonpath='{.spec.clusterIP}')
curl http://$SVC_IP:8000/health
```

### 7.3 From EC2 (via NodePort)

```bash
# Get NodePort
NODE_PORT=$(kubectl get svc wms-model -o jsonpath='{.spec.ports[0].nodePort}')

# Test from localhost
curl http://localhost:$NODE_PORT/health
```

Expected:
```json
{"status":"healthy","model_loaded":true}
```

### 7.4 From Your Machine (External)

```bash
# Get EC2 public IP
EC2_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=wms-project-k3s" \
           "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

# Get NodePort
NODE_PORT=$(ssh -i ~/.ssh/labsuser.pem ec2-user@$EC2_IP \
  "kubectl get svc wms-model -o jsonpath='{.spec.ports[0].nodePort}'")

# Test health endpoint
curl http://$EC2_IP:$NODE_PORT/health
```

If this **fails**:
- Check Security Group allows NodePort (default: 30000-32767)
- Add rule if needed:
  ```bash
  SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=tag:Name,Values=wms-project-sg" \
    --query "SecurityGroups[0].GroupId" \
    --output text)

  aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port $NODE_PORT \
    --cidr 0.0.0.0/0
  ```

---

## Step 8: Test Prediction Endpoint

### 8.1 Prepare Test Image

```bash
# Download sample water meter image
curl -o test_meter.jpg \
  https://raw.githubusercontent.com/Rafallost/Water-Meters-Segmentation/main/WMS/data/test/images/id_1.jpg
```

### 8.2 Send Prediction Request

```bash
# Send POST request with image
curl -X POST http://$EC2_IP:$NODE_PORT/predict \
  -F "image=@test_meter.jpg" \
  -o predicted_mask.png

# Check response
file predicted_mask.png
```

Expected:
```
predicted_mask.png: PNG image data, 512 x 512, 8-bit/color RGB
```

### 8.3 Verify Mask Quality

```bash
# Check file size (should be 50-200 KB)
ls -lh predicted_mask.png

# View image (if GUI available)
# or transfer to local machine:
scp -i ~/.ssh/labsuser.pem \
  ec2-user@$EC2_IP:~/predicted_mask.png \
  ./predicted_mask.png
```

---

## Step 9: Check Prometheus Metrics

### 9.1 View Metrics Endpoint

```bash
# Get metrics from pod
curl http://$EC2_IP:$NODE_PORT/metrics
```

Expected output (Prometheus format):
```
# HELP wms_predictions_total Total number of predictions made
# TYPE wms_predictions_total counter
wms_predictions_total 1.0

# HELP wms_predict_latency_seconds Prediction latency in seconds
# TYPE wms_predict_latency_seconds histogram
wms_predict_latency_seconds_bucket{le="0.1"} 0.0
wms_predict_latency_seconds_bucket{le="0.5"} 1.0
...
```

### 9.2 Check ServiceMonitor (if monitoring enabled)

```bash
# Check if ServiceMonitor exists
kubectl get servicemonitor wms-model

# Check Prometheus targets
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &

# Open browser: http://localhost:9090/targets
# Look for "wms-model" target with status "UP"
```

---

## Step 10: Performance Verification

### 10.1 Load Test (optional)

```bash
# Install Apache Bench (if not installed)
sudo yum install httpd-tools -y

# Send 100 requests, 10 concurrent
ab -n 100 -c 10 -p test_meter.jpg -T 'multipart/form-data' \
  http://$EC2_IP:$NODE_PORT/predict
```

Check:
- ✅ Requests per second
- ✅ Mean latency
- ✅ Failed requests (should be 0)

### 10.2 Memory Usage Over Time

```bash
# Watch resource usage
watch kubectl top pod $POD_NAME
```

Check for:
- ❌ Memory continuously increasing → memory leak
- ✅ Stable memory usage → good

---

## Success Criteria

Deployment is **verified successful** if:

- ✅ GitHub Actions workflow: Success
- ✅ Docker image in ECR: Present
- ✅ Pod status: `Running` with `1/1 READY`
- ✅ Health endpoint: Returns `{"status":"healthy"}`
- ✅ Predict endpoint: Returns valid PNG mask
- ✅ Metrics endpoint: Returns Prometheus metrics
- ✅ No errors in pod logs
- ✅ No crash restarts (`RESTARTS` = 0)
- ✅ Resource usage stable (not increasing)

---

## Rollback (if deployment fails)

If new deployment is broken:

```bash
# Rollback to previous version
kubectl rollout undo deployment wms-model

# Check rollback status
kubectl rollout status deployment wms-model

# Verify previous version works
curl http://$EC2_IP:$NODE_PORT/health
```

Or manually deploy specific version:

```bash
# List Docker image tags in ECR
aws ecr list-images --repository-name wms-model

# Update image tag in helm-values.yaml
# Redeploy
helm upgrade --install wms-model devops/helm/ml-model/ \
  -f infrastructure/helm-values.yaml
```

---

## Monitoring Dashboard (if Grafana enabled)

### Access Grafana

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &

# Open browser: http://localhost:3000
# Login: admin / <password from terraform.tfvars>
```

### Key Metrics to Monitor

1. **Prediction Rate**
   - Metric: `rate(wms_predictions_total[5m])`
   - Chart: Line graph
   - Alert if: < 0.1/sec (no traffic)

2. **Prediction Latency**
   - Metric: `wms_predict_latency_seconds`
   - Chart: Heatmap or histogram
   - Alert if: p99 > 5 seconds

3. **Error Rate**
   - Metric: `rate(wms_predict_errors_total[5m])`
   - Chart: Line graph
   - Alert if: > 0.01/sec (1% error rate)

4. **Resource Usage**
   - Metric: `container_memory_usage_bytes`, `container_cpu_usage_seconds_total`
   - Chart: Line graph
   - Alert if: > 80% of limits

---

## Next Steps

After successful verification:

1. ✅ Document deployment in `production_history.jsonl`
2. ✅ Update README with deployment URL
3. ✅ Share endpoint with team/stakeholders
4. ✅ Setup alerts in Grafana (if monitoring enabled)
5. ✅ Schedule regular health checks
6. ✅ Plan for scaling if traffic increases

---

## For Thesis: Metrics to Collect

When verifying deployment for thesis analysis:

### Time Metrics:
- Workflow start time
- Workflow end time
- Total deployment duration
- Time to pod ready
- Time to first successful /predict

### Quality Metrics:
- Image size (GB)
- Pod restart count
- Failed request rate
- P50, P95, P99 latency
- Resource utilization (%)

### Automation Metrics:
- Number of manual steps: 0 (fully automated)
- Number of failures requiring intervention
- Reproducibility: 100% (same result every time)

---

## Troubleshooting Checklist

If deployment verification fails, check in order:

1. [ ] GitHub Actions logs for build/push errors
2. [ ] ECR has latest image with correct tag
3. [ ] ECR secret exists and is valid (`kubectl get secret ecr-secret`)
4. [ ] Pod is running (`kubectl get pods`)
5. [ ] Pod logs show no errors (`kubectl logs $POD_NAME`)
6. [ ] Health endpoint responds (`curl /health`)
7. [ ] Security group allows NodePort traffic
8. [ ] MLflow connection works from pod
9. [ ] Model exists in MLflow Production stage
10. [ ] Resources (CPU/Memory) sufficient

---

**Summary:** This guide covers all verification steps to ensure automated deployment succeeded and the model is serving predictions correctly.
