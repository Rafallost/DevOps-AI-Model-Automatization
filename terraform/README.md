# Terraform

AWS infrastructure orchestration for complete ML deployment:
- EC2 instance (t3.large) with k3s Kubernetes cluster
- VPC + subnet + security groups
- S3 buckets (DVC data, MLflow artifacts)
- ECR repository (Docker images)
- IAM roles and optional GitHub OIDC
- Optional monitoring (Prometheus + Grafana)

## Project Structure

```
terraform/
├── main.tf              # Root module configuration
├── variables.tf         # Input variables
├── outputs.tf          # Output values (IPs, URLs, etc.)
├── terraform.tfstate   # State file (DO NOT commit in production!)
├── terraform.tfvars    # Variable overrides (local config)
└── modules/
    ├── vpc/            # Network setup (VPC, subnet, security group)
    ├── s3-mlops/       # S3 buckets (DVC + MLflow artifacts)
    ├── ecr/            # ECR registry for Docker images
    ├── ec2-k3s/        # EC2 instance with k3s + MLflow + monitoring
    └── iam-github-oidc/ # GitHub Actions OIDC (optional)
```
---

## Automation Summary: What Terraform Does vs Manual Setup

| Component | Automated? | Details |
|-----------|-----------|---------|
| **AWS Infrastructure** | ✅ | VPC, subnet, security group, EC2, S3, ECR |
| **OS Installation** | ✅ | Amazon Linux 2023 AMI selection |
| **System Packages** | ✅ | Docker, Python, git, kubectl, helm via user-data.sh |
| **k3s Kubernetes** | ✅ | Installed and configured as systemd service |
| **MLflow Server** | ✅ | Installed, configured with S3 backend, runs on localhost:5000 |
| **Monitoring (Prometheus/Grafana)** | ✅ | Optional, installed if `install_monitoring=true` |
| **GitHub Runner** | ❌ | Dependencies only; token registration still manual |
| **Docker Build & Push** | ❌ | GitHub Actions pipeline handles this |
| **Model Deployment** | ❌ | GitHub Actions + Helm deploy to k3s |
| **Pre-push Hooks** | ❌ | Must run `install-git-hooks.sh` on EC2 manually |

**TL;DR**: Terraform creates and configures infrastructure; GitHub Actions handles CI/CD pipelines.

---
## Full Terraform Workflow

### Step 1: Initialize Terraform
```bash
cd infrastructure/terraform
terraform init
```
- Downloads AWS provider plugin
- Creates `.terraform/` directory
- Initializes backend (local or remote state storage)

### Step 2: Validate Configuration
```bash
terraform validate
```
- Checks syntax and logical errors
- Verifies module references
- Recommended before `plan`

### Step 3: Review Changes (IMPORTANT!)
```bash
terraform plan -var-file=terraform.tfvars
```
This shows **everything** that will be created/modified/deleted:
- EC2 instance spec
- Security group rules
- S3 bucket configuration
- IAM roles
- Network topology
- Resource costs (estimates)

**Output example:**
```
Plan: 15 to add, 0 to change, 0 to destroy.
```

**Review checklist:**
- [ ] Correct region (us-east-1)?
- [ ] Correct instance type (t3.large)?
- [ ] S3 bucket names unique (account ID appended)?
- [ ] Security group allows SSH + ModelPort + MLflow?
- [ ] IAM role uses LabInstanceProfile (AWS Academy)?

### Step 4: Apply Configuration
```bash
# Interactive (recommended for first deployment)
terraform apply -var-file=terraform.tfvars

# Or automated (requires approval from Step 3)
terraform apply -var-file=terraform.tfvars -auto-approve
```

After `apply`, Terraform will:
1. Create all AWS resources
2. Run user-data.sh on EC2 (installs k3s, docker, MLflow, etc.)
3. Output EC2 public IP, security group IDs, S3 bucket names
4. Save state to `terraform.tfstate`

### Step 5: Verify Deployment
```bash
# Check outputs
terraform output

# Example output:
# ec2_public_ip = "54.123.45.67"
# k3s_ready = true
# mlflow_url = "http://54.123.45.67:5000"
# ecr_repository_url = "055677744286.dkr.ecr.us-east-1.amazonaws.com/wms-model"

# SSH to EC2 and verify services
ssh -i ~/.ssh/labsuser.pem ec2-user@<EC2_IP>
systemctl status docker
systemctl status k3s
systemctl status mlflow
```

### Step 6: Destroy Infrastructure (Clean Up)
```bash
# Review what will be deleted
terraform plan -destroy -var-file=terraform.tfvars

# Delete all resources
terraform destroy -var-file=terraform.tfvars

# Or automated
terraform destroy -var-file=terraform.tfvars -auto-approve
```

**Important**: This will:
- ❌ Terminate EC2 instance
- ❌ Delete VPC and network interfaces
- ❌ **Empty and delete S3 buckets** (WARNING: Data loss!)
- ❌ Delete ECR repository and images
- ❌ Delete IAM roles

---

## Configuration Variables

Edit `infrastructure/terraform.tfvars`:

```hcl
# AWS Region
aws_region        = "us-east-1"
availability_zone = "us-east-1a"

# EC2 Configuration
instance_type = "t3.large"  # 8GB RAM, 2 vCPU (AWS Academy limit)
key_name = "vockey"         # Pre-created SSH key pair

# S3 Buckets (globally unique - account ID auto-appended)
dvc_bucket    = "wms-dvc-data-055677744286"         # DVC training data
mlflow_bucket = "wms-mlflow-artifacts-055677744286" # MLflow artifacts

# GitHub Repository
github_repo = "Rafallost/Water-Meters-Segmentation-Automatization"

# Monitoring (Prometheus + Grafana)
install_monitoring = true
grafana_password   = "WMS-Monitoring-2026!"
```

---

## Common Issues

### "terraform plan" shows "No changes"
- Terraform state is in sync with AWS
- All resources already exist
- To check actual state: `terraform refresh`

### "Error: S3 bucket already exists"
- S3 names are globally unique across AWS
- Solution: Append different suffix to bucket name in `terraform.tfvars`
- Example: `wms-dvc-data-123456789` (different account ID)

### "Error: Insufficient capacity"
- AWS Academy t3.large limit reached
- Solution: Try different availability zone or different region
- Or: Reduce instance size to t3.medium (not recommended for ML)

### "terraform.tfstate" file corrupted
- **Never edit directly**
- Restore from backup: `cp terraform.tfstate.backup terraform.tfstate`
- Or use: `terraform state pull > backup.json`

### EC2 instance created but services not starting
- SSH to instance and check: `tail -50 /var/log/user-data.log`
- Wait 2-3 minutes for user-data.sh to complete
- Check: `systemctl status docker`, `systemctl status k3s`

---

## AWS Academy Constraints

⚠️ **Important limitations**:
- ❌ Cannot create new IAM roles (use pre-existing `LabInstanceProfile`)
- ❌ No AWS Load Balancer (use NodePort instead)
- ❌ Limited t3.large instances per region
- ✅ Can create EC2, VPC, S3, ECR, SecurityGroups
- ✅ Can create IAM role for GitHub OIDC (if needed)

---

## Workflow Diagram

```
terraform init
    ↓
terraform validate
    ↓
terraform plan -var-file=terraform.tfvars
    ↓ (Review output carefully!)
terraform apply -var-file=terraform.tfvars
    ↓
EC2 runs user-data.sh (2-3 mins)
    ↓
k3s + Docker + MLflow + Monitoring ready
    ↓
GitHub Actions can deploy models
    ↓
(Later) terraform destroy
```

---

## Modules Explained

| Module | Creates | Purpose |
|--------|---------|---------|
| `vpc` | VPC, Subnet, SecurityGroup, Internet Gateway | Network isolation, firewall rules |
| `s3-mlops` | 2 S3 buckets + lifecycle policies | DVC data versioning, MLflow artifact storage |
| `ecr` | ECR repository + lifecycle rules | Private Docker registry for model images |
| `ec2-k3s` | EC2 instance, EIP, user-data script | ML service deployment platform |
| `iam-github-oidc` | IAM OIDC provider, GitHub Actions trust | Secure GitHub Actions ↔ AWS auth (optional) |

---

## Advanced: Remote State Storage

By default, Terraform stores state locally in `terraform.tfstate` (insecure for teams).

To use S3 backend:
```hcl
# terraform.tf or main.tf
terraform {
  backend "s3" {
    bucket         = "wms-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

Then: `terraform init` (will ask to migrate state to S3)

---

## Useful Commands

```bash
# Validate syntax
terraform validate

# Format code
terraform fmt -recursive

# Show all resources
terraform state list

# Show specific resource details
terraform state show aws_instance.k3s

# Import existing AWS resource (rare)
terraform import aws_instance.k3s i-1234567890abcdef0

# Output only specific value
terraform output ec2_public_ip

# Show state as JSON
terraform state pull | jq '.resources[] | select(.type=="aws_instance")'
```

---

## Notes

- **State file**: Keep `terraform.tfstate` and `terraform.tfstate.backup` safe (contains sensitive data)
- **AWS Academy**: LabInstanceProfile has broad permissions; use in sandbox only
- **GitHub OIDC**: Optional—enables keyless GitHub Actions auth to AWS (requires IAM setup)
- **Costs**: t3.large ≈ $0.10/hour in AWS Academy (included in free tier)
