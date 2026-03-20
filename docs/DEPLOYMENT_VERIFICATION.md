# Deployment Verification Guide

## Goal

Verify deployment and service health after model release.

## Quick verification (script)

Run:

```bash
bash scripts/verify-deployment.sh <EC2_IP> ~/.ssh/labsuser.pem
```

This script checks SSH, k3s readiness, MLflow health, deployment pod status, API health, and model registry.

## Helm deployment verification

If deploying with Helm (helm/ml-model), verify:

1. helm list -n default
2. kubectl get deployments -n default
3. kubectl describe deployment wms-model -n default
4. kubectl get svc -n default (NodePort service expected)

Check key values in helm/ml-model/values.yaml:

- image.repository (ECR URL)
- image.tag (latest or specific tag)
- env.MLFLOW_TRACKING_URI (e.g. http://localhost:5000)
- service.type, service.port
- readiness and liveness probe settings

## Manual Kubernetes checks

```bash
kubectl get nodes
kubectl get pods -n default
kubectl get svc -n default
kubectl logs -l app.kubernetes.io/name=ml-model -n default --tail=100
```

## API health checks

1. Determine NodePort:

```bash
kubectl get svc wms-model-ml-model -n default -o jsonpath='{.spec.ports[0].nodePort}'
```

2. Health endpoint:

```bash
curl http://<EC2_IP>:<NODE_PORT>/health
```

3. Predict endpoint:

```bash
curl -X POST http://<EC2_IP>:<NODE_PORT>/predict -F  image=@test.jpg
```

4. Metrics endpoint:

```bash
curl http://<EC2_IP>:<NODE_PORT>/metrics | head
```

## MLflow registry checks

```bash
curl -s http://localhost:5000/api/2.0/mlflow/registered-models/get?name=water-meter-segmentation
```

Ensure Production stage exists.

## Common issues and fixes

- ImagePullBackOff: create/update ECR secret and ensure image tag is correct.
- CrashLoopBackOff: check pod logs for MLflow URI or model load errors.
- Service not accessible: verify NodePort and firewall/security groups.
- No predictions: verify model in MLflow and app startup logs.
