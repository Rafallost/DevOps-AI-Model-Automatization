# Manual Deployment Guide

## Goal

Manual deployment instructions for EC2/k3s/MLflow based on repo scripts.

## Requirements

- AWS CLI configured
- Terraform installed
- SSH key labsuser.pem

## 1) Provision infrastructure

```bash
cd terraform
terraform init
terraform apply -var-file=terraform.tfvars -auto-approve
```

## 2) Verify EC2 and MLflow

- Get EC2 IP from Terraform output (mlflow_server_ip).
- ssh -i ~/.ssh/labsuser.pem ec2-user@<EC2_IP>
- curl http://localhost:5000/health
- kubectl get nodes

## 3) Start MLflow manually (if needed)

```bash
bash scripts/setup-mlflow.sh <MLFLOW_BUCKET>
sudo systemctl status mlflow
```

## 4) Install k3s + Helm

```bash
bash scripts/setup-k3s.sh
```

## 5) Deploy application with Helm

```bash
helm upgrade --install wms-model helm/ml-model \
  --set image.repository=<ECR_URL>/wms-model \
  --set image.tag=latest \
  --set env[0].name=MLFLOW_TRACKING_URI \
  --set env[0].value=http://localhost:5000
```

## 6) Verify deployment

```bash
bash scripts/verify-deployment.sh <EC2_IP> ~/.ssh/labsuser.pem
```

## 7) Shutdown and destroy

```bash
bash scripts/stop-cloud.sh
bash scripts/cleanup-aws.sh
```

## Notes

Prefer CI automation; this guide is for manual analysis and comparison.
