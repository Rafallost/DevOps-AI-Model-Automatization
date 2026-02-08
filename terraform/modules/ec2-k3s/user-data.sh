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
  --host 0.0.0.0 \
  --workers 2 \
  --gunicorn-opts "--timeout 300 --keep-alive 120"
WorkingDirectory=/opt/mlflow
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start mlflow
systemctl enable mlflow

# ── Automatic Cleanup & Monitoring ──
echo "Setting up automatic cleanup..."

# Configure journald log rotation (max 500MB, 7 days)
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size-limit.conf <<'JOURNAL_EOF'
[Journal]
SystemMaxUse=500M
MaxRetentionSec=7d
JOURNAL_EOF
systemctl restart systemd-journald

# Configure logrotate for application logs
cat > /etc/logrotate.d/mlflow <<'LOGROTATE_EOF'
/opt/mlflow/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0644 root root
}
LOGROTATE_EOF

# Create cleanup script
cat > /usr/local/bin/cleanup-k3s.sh <<'CLEANUP_EOF'
#!/bin/bash
# Automatic cleanup script for k3s and logs
echo "Running cleanup at $(date)"

# Clean old k3s images (unused for 24h+)
echo "Cleaning k3s images..."
/usr/local/bin/k3s crictl rmi --prune 2>/dev/null || true

# Clean old logs
echo "Cleaning old logs..."
journalctl --vacuum-time=7d
find /var/log -name "*.gz" -mtime +7 -delete 2>/dev/null || true

# Clean failed/unknown k3s pods
echo "Cleaning failed k3s pods..."
/usr/local/bin/k3s kubectl delete pods --field-selector=status.phase==Failed --all-namespaces 2>/dev/null || true
/usr/local/bin/k3s kubectl delete pods --field-selector=status.phase==Unknown --all-namespaces 2>/dev/null || true

# Report disk usage
echo "Disk usage after cleanup:"
df -h / | grep -v tmpfs

echo "Cleanup completed at $(date)"
CLEANUP_EOF

chmod +x /usr/local/bin/cleanup-k3s.sh

# Run cleanup daily at 3 AM
cat > /etc/cron.d/cleanup-k3s <<'CRON_EOF'
0 3 * * * root /usr/local/bin/cleanup-k3s.sh >> /var/log/cleanup-k3s.log 2>&1
CRON_EOF

# Run initial cleanup
/usr/local/bin/cleanup-k3s.sh

echo "=== User-data script completed at $(date) ==="
echo "Services status:"
systemctl status docker --no-pager
systemctl status k3s --no-pager
systemctl status mlflow --no-pager

echo "Disk usage:"
df -h /
