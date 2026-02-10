# Phase 5: AWS Infrastructure Deployment

This Terraform configuration provisions all AWS resources for the Water Meter Segmentation MLOps project.

## What Gets Created

- **VPC**: Single public subnet, internet gateway, security group
- **EC2**: t3.small instance with k3s, Docker, Helm, MLflow
- **S3**: Two buckets (DVC data, MLflow artifacts)
- **ECR**: Docker image registry
- **IAM**: GitHub Actions OIDC role for CI/CD

**Estimated cost**: $2-3 for 4 days of testing

---

## Prerequisites

### 1. Install Terraform

```bash
# Windows (using Chocolatey)
choco install terraform

# Or download from: https://www.terraform.io/downloads
```

### 2. Configure AWS CLI

```bash
# Install AWS CLI (if not already installed)
# Download from: https://aws.amazon.com/cli/

# Configure with your credentials
aws configure
# Enter: Access Key ID, Secret Access Key, Region: eu-central-1
```

### 3. Create SSH Key Pair

**In AWS Console:**
1. Go to EC2 → Key Pairs → Create key pair
2. Name: `wms-ssh-key` (or your choice)
3. Type: RSA
4. Format: .pem
5. Download and save to `~/.ssh/wms-ssh-key.pem`

```bash
# Set permissions (Linux/Mac)
chmod 400 ~/.ssh/wms-ssh-key.pem

# Windows: Right-click file → Properties → Security → Advanced
# Remove all users except yourself, set to Read-only
```

### 4. Get Your Public IP

```bash
curl ifconfig.me
# Copy the output, you'll need it for terraform.tfvars
```

---

## Configuration

Edit `Water-Meters-Segmentation-Autimatization/infrastructure/terraform.tfvars`:

```hcl
my_ip    = "YOUR_IP_HERE/32"  # From curl ifconfig.me
key_name = "wms-ssh-key"      # Name from AWS Console
```

---

## Pre-Apply Safety Checklist

**DO NOT run `terraform apply` until ALL boxes are checked:**

- [ ] AWS billing alert set at $40 threshold (if your account allows)
- [ ] `my_ip` in terraform.tfvars is YOUR current IP with /32 suffix
- [ ] `key_name` in terraform.tfvars matches your AWS key pair name
- [ ] You have the .pem file saved locally
- [ ] You've reviewed the plan (see step 3 below)

---

## Deployment Steps

### 1. Initialize Terraform

```bash
cd DevOps-AI-Model-Automatization/terraform
terraform init
```

Expected output: "Terraform has been successfully initialized!"

### 2. Plan (Review What Will Be Created)

```bash
terraform plan -var-file=../../Water-Meters-Segmentation-Autimatization/infrastructure/terraform.tfvars
```

**CRITICAL: Read the entire plan output. Verify:**
- [ ] 1 VPC + 1 subnet + 1 internet gateway + 1 route table
- [ ] 1 security group with SSH (22) and HTTP (8000) from your IP
- [ ] 1 EC2 instance (t3.small)
- [ ] 1 Elastic IP
- [ ] 2 S3 buckets with versioning
- [ ] 1 ECR repository
- [ ] 1 IAM role + OIDC provider
- [ ] 1 IAM instance profile
- [ ] **ZERO NAT Gateways** (would cost $32/month)
- [ ] **ZERO RDS instances** (would cost $13/month)

If the plan shows ~15-20 resources and NO expensive items, proceed.

### 3. Apply (Create Resources)

```bash
terraform apply -var-file=../../Water-Meters-Segmentation-Autimatization/infrastructure/terraform.tfvars
```

Type `yes` when prompted.

**This is when AWS charges begin.** Application takes ~5 minutes.

### 4. Save Outputs

```bash
terraform output
```

**IMPORTANT: Save these values:**
- `ec2_instance_id`: For starting/stopping EC2
- `ec2_public_ip`: For SSH and MLflow access
- `github_actions_role_arn`: Already in your workflows

Example output:
```
ec2_instance_id = "i-0123456789abcdef0"
ec2_public_ip   = "3.120.45.67"
mlflow_url      = "http://3.120.45.67:5000"
ssh_command     = "ssh -i ~/.ssh/wms-ssh-key.pem ec2-user@3.120.45.67"
```

---

## Verification

### 1. SSH into EC2

```bash
# Use the ssh_command from terraform output
ssh -i ~/.ssh/wms-ssh-key.pem ec2-user@<PUBLIC_IP>
```

### 2. Check Services

```bash
# On EC2
sudo systemctl status mlflow
sudo systemctl status k3s
kubectl get nodes
docker --version
helm version
```

All should show as active/running.

### 3. Access MLflow UI

Open browser: `http://<PUBLIC_IP>:5000`

Should see MLflow tracking UI (no experiments yet - that's normal).

### 4. Test DVC Push

```bash
# On your local machine, in working repo
cd Water-Meters-Segmentation-Autimatization

# Update DVC remote (already configured, just verifying)
dvc remote list
# Should show: s3remote s3://wms-dvc-data-036136800740/dvc

# First push (uploads training data to S3)
dvc push
```

This uploads ~9 images (~1 MB). First real AWS cost: ~$0.01.

---

## Daily Usage

### Start EC2 (Before Working)

```bash
aws ec2 start-instances --instance-ids <INSTANCE_ID> --region eu-central-1

# Wait ~2 minutes, then SSH
```

### Stop EC2 (After Working)

```bash
aws ec2 stop-instances --instance-ids <INSTANCE_ID> --region eu-central-1
```

**Stopped EC2 = $0/hour compute, but EIP still costs $0.005/hour.**

For breaks longer than 1 day, consider releasing the EIP (see PLAN.md budget rules).

---

## Optional: Enable Prometheus + Grafana Monitoring

Monitoring is **disabled by default** to save resources (~500MB RAM). Enable it for production-like deployments.

### Enable Monitoring

Add to your `terraform.tfvars` (in main repo):

```hcl
# Optional monitoring (requires t3.medium minimum, recommended t3.xlarge)
install_monitoring = true
grafana_password   = "your-secure-password"  # Change this!
```

Then apply:

```bash
terraform apply -var-file=../../Water-Meters-Segmentation-Autimatization/infrastructure/terraform.tfvars
```

### Access Dashboards

After EC2 starts (~3 minutes for monitoring stack to be ready):

**Grafana (Dashboards):**
```bash
ssh -i ~/.ssh/labsuser.pem -L 3000:localhost:3000 ec2-user@<EC2_IP>
# In another terminal:
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Open browser: http://localhost:3000
# Login: admin / <your-grafana-password>
```

**Prometheus (Metrics):**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open browser: http://localhost:9090
```

### Pre-Built Dashboards

Grafana comes with dashboards for:
- **Kubernetes / Compute Resources / Pod** - Pod CPU/RAM usage
- **Kubernetes / Compute Resources / Namespace** - Namespace overview
- **Prometheus / Overview** - Prometheus server stats

### Custom Dashboard for ML Model

In Grafana:
1. **Dashboards** → **New** → **New Dashboard**
2. Add panels for:
   - `wms_predictions_total` - Total predictions
   - `wms_predict_latency_seconds` - Prediction latency (p50, p95, p99)
   - `container_memory_usage_bytes{pod=~"wms-model.*"}` - Model pod RAM
   - `rate(wms_predictions_total[5m])` - Predictions per second

### Disable Monitoring

To remove monitoring (frees ~500MB RAM):

```hcl
# terraform.tfvars
install_monitoring = false
```

Then:
```bash
terraform apply -var-file=../../Water-Meters-Segmentation-Autimatization/infrastructure/terraform.tfvars
```

Or manually:
```bash
ssh -i ~/.ssh/labsuser.pem ec2-user@<EC2_IP>
helm uninstall kube-prometheus-stack --namespace monitoring
kubectl delete namespace monitoring
```

### Resource Impact

| Component | CPU | RAM | Disk |
|-----------|-----|-----|------|
| Prometheus | ~200m | ~512MB | ~2GB (7-day retention) |
| Grafana | ~50m | ~128MB | ~100MB |
| Exporters | ~50m | ~100MB | - |
| **Total** | ~300m | ~750MB | ~2.1GB |

**Minimum:** t3.medium (4GB RAM)
**Recommended:** t3.xlarge (8GB RAM) - used in this project

---

## Next Steps

After Phase 5 is complete:

1. **Set up self-hosted GitHub Actions runner** (see PLAN.md Phase 5.8)
2. **Proceed to Phase 6**: Docker + Helm deployment
3. **Update working repo DVC remote**: Already done via Phase 1

---

## Cleanup (After Project Completion)

**WARNING: This destroys ALL resources and stops all charges.**

```bash
cd devops
./scripts/cleanup-aws.sh
```

Or manually:

```bash
cd terraform
terraform destroy -var-file=../../Water-Meters-Segmentation-Autimatization/infrastructure/terraform.tfvars
```

Then verify in AWS Console that ZERO resources remain.

---

## Troubleshooting

### User-data script failed

SSH into EC2 and check logs:
```bash
sudo cat /var/log/user-data.log
```

If MLflow or k3s didn't start, run manual setup:
```bash
cd devops/scripts
./setup-k3s.sh
./setup-mlflow.sh wms-mlflow-artifacts-036136800740
```

### Can't SSH

- Check security group allows port 22 from your IP
- Verify .pem file permissions (400 on Linux/Mac)
- Confirm you're using correct IP (EIP, not instance IP)

### Terraform errors

- `Error: InvalidKeyPair.NotFound` → key_name doesn't exist in AWS
- `Error: UnauthorizedOperation` → AWS credentials not configured
- `Error: BucketAlreadyExists` → S3 bucket name collision (append different suffix)

---

## Cost Monitoring

Check spending daily:
```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-02-01,End=2026-02-28 \
  --granularity DAILY \
  --metrics UnblendedCost \
  --region us-east-1
```

Or: AWS Console → Billing Dashboard
