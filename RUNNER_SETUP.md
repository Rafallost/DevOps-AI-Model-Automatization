# GitHub Actions Self-Hosted Runner Setup

## Overview

This guide explains how to install and configure a GitHub Actions self-hosted runner on the EC2 instance. The runner will execute training workflows directly on EC2, giving them access to:
- MLflow server (localhost:5000)
- k3s cluster (localhost:6443)
- AWS resources via IAM instance profile
- Training data on local disk

## Prerequisites

- EC2 instance running (Phase 5 complete)
- SSH access to EC2
- GitHub repository admin access

## Installation Steps

### 1. Get Runner Token from GitHub

1. Go to your GitHub repository: https://github.com/Rafallost/Water-Meters-Segmentation-Autimatization
2. Navigate to **Settings** → **Actions** → **Runners**
3. Click **New self-hosted runner**
4. Select **Linux** and **x64**
5. **Copy the token** from the configuration command (you'll need it in step 3)

### 2. SSH to EC2

```bash
ssh -i ~/.ssh/labsuser.pem ec2-user@<EC2_PUBLIC_IP>
```

### 3. Install GitHub Actions Runner

Run the following commands on EC2:

```bash
# Create runner directory
mkdir -p ~/actions-runner && cd ~/actions-runner

# Download latest runner (check GitHub for current version)
RUNNER_VERSION="2.319.1"  # Update if needed
curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
  https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Extract
tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Configure runner
./config.sh \
  --url https://github.com/Rafallost/Water-Meters-Segmentation-Autimatization \
  --token <TOKEN_FROM_GITHUB> \
  --name ec2-runner \
  --labels self-hosted,linux,x64,ml-training \
  --work _work

# When prompted:
# - Runner group: Default
# - Work folder: _work (default)
```

### 4. Install Runner Dependencies

The runner needs Python and other tools:

```bash
# Install Python 3.12 (if not already installed)
sudo yum install -y python3.12 python3.12-pip

# Make Python 3.12 available as python3
sudo alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# Verify
python3 --version  # Should show 3.12.x

# Install git (required by GitHub Actions)
sudo yum install -y git

# Install AWS CLI (if not already installed)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### 5. Install Runner as a Service

This ensures the runner starts automatically and runs in the background:

```bash
cd ~/actions-runner

# Install service
sudo ./svc.sh install

# Start service
sudo ./svc.sh start

# Check status
sudo ./svc.sh status

# View logs
journalctl -u actions.runner.* -f
```

### 6. Verify Installation

1. Go to GitHub: **Settings** → **Actions** → **Runners**
2. You should see **ec2-runner** with status **Idle** (green dot)

### 7. Test the Runner

Trigger the training workflow manually:

1. Go to **Actions** tab in GitHub
2. Select **Train Model** workflow
3. Click **Run workflow** → **Run workflow**
4. Watch the workflow execute on your EC2 runner

## Runner Management

### View Logs

```bash
# View runner service logs
sudo journalctl -u actions.runner.* -f

# View runner job logs
cd ~/actions-runner/_diag
ls -lt  # Latest logs at the top
```

### Stop Runner

```bash
cd ~/actions-runner
sudo ./svc.sh stop
```

### Start Runner

```bash
cd ~/actions-runner
sudo ./svc.sh start
```

### Uninstall Runner

```bash
cd ~/actions-runner

# Stop and uninstall service
sudo ./svc.sh stop
sudo ./svc.sh uninstall

# Remove configuration
./config.sh remove --token <NEW_TOKEN_FROM_GITHUB>
```

## Troubleshooting

### Runner not appearing in GitHub

**Check runner service status:**
```bash
sudo ./svc.sh status
```

**Restart runner:**
```bash
sudo ./svc.sh stop
sudo ./svc.sh start
```

**Check logs for errors:**
```bash
sudo journalctl -u actions.runner.* -n 50
```

### Workflow fails with "No such file or directory"

**Ensure Python 3.12 is available:**
```bash
python3 --version
which python3
```

**Check PATH in runner environment:**
```bash
# Add to ~/.bashrc if needed
export PATH="/usr/bin:$PATH"
```

### DVC pull fails

**Ensure AWS credentials are configured:**
```bash
aws sts get-caller-identity
```

**Check S3 access:**
```bash
aws s3 ls s3://wms-training-data-<ACCOUNT_ID>/
```

### MLflow connection fails

**Check MLflow is running:**
```bash
curl http://localhost:5000/health
```

**If not running, start it:**
```bash
cd ~/mlflow
mlflow server \
  --backend-store-uri sqlite:///mlflow.db \
  --default-artifact-root s3://wms-mlflow-artifacts-<ACCOUNT_ID>/ \
  --host 0.0.0.0 \
  --port 5000 &
```

## Security Notes

1. **Runner has localhost access** to MLflow (5000) and k3s API (6443)
2. **Runner uses EC2 IAM role** for AWS credentials - no secrets needed
3. **Runner work directory** (`_work/`) contains checked out code - ensure it's cleaned after jobs
4. **Logs may contain sensitive data** - protect runner logs

## Cost Implications

- **Runner itself**: Free (self-hosted)
- **EC2 while runner is active**: Standard t3.xlarge cost ($0.0832/hour)
- **Data transfer**: DVC pull from S3 (egress charges)
- **S3 storage**: MLflow artifacts

**Best practice**: Stop EC2 when not actively training to minimize costs.

## Next Steps

After runner is installed:
1. ✅ Test training workflow manually
2. Create a PR with data changes to trigger automatic training
3. Verify model registration to MLflow
4. Check quality gate enforcement

---

**Last Updated**: 2026-02-07
