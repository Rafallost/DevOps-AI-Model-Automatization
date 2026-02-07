#!/bin/bash
# EC2 User Data Script - Installs Docker, k3s, Helm, MLflow
# Runs at instance launch (Amazon Linux 2023)

set -euo pipefail

# Redirect all output to log file for debugging
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== Starting user-data script at $(date) ==="

# Update system
echo "Updating system packages..."
yum update -y

# ── Docker ──
echo "Installing Docker..."
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# ── Python 3 + pip ──
echo "Installing Python 3..."
yum install -y python3 python3-pip git

# ── k3s ──
echo "Installing k3s..."
# Skip SELinux RPM due to dependency conflict on Amazon Linux 2
# (container-selinux version mismatch with selinux-policy-targeted)
curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_SELINUX_RPM=true sh -
# Make kubeconfig readable by non-root users
chmod 644 /etc/rancher/k3s/k3s.yaml
# Set KUBECONFIG and kubectl alias for ec2-user
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /home/ec2-user/.bashrc
echo 'alias kubectl="/usr/local/bin/k3s kubectl"' >> /home/ec2-user/.bashrc

# ── Helm ──
echo "Installing Helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ── MLflow ──
echo "Installing MLflow..."
# Amazon Linux 2023 has OpenSSL 3.0, so no urllib3 pinning needed
pip3 install mlflow boto3
mkdir -p /opt/mlflow

# Create MLflow systemd service
cat > /etc/systemd/system/mlflow.service <<'EOF'
[Unit]
Description=MLflow Tracking Server
After=network-online.target
Wants=network-online.target

[Service]
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
ExecStart=/usr/local/bin/mlflow server \
  --backend-store-uri sqlite:////opt/mlflow/mlflow.db \
  --default-artifact-root s3://${mlflow_bucket}/ \
  --host 0.0.0.0
WorkingDirectory=/opt/mlflow
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start mlflow
systemctl enable mlflow

echo "=== User-data script completed at $(date) ==="
echo "Services status:"
systemctl status docker --no-pager
systemctl status k3s --no-pager
systemctl status mlflow --no-pager
