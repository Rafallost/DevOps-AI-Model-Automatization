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

# Setup kubeconfig for ec2-user (standard location for kubectl/helm/GitHub Actions)
echo "Setting up kubeconfig for ec2-user..."
mkdir -p /home/ec2-user/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/.kube/config
chown -R ec2-user:ec2-user /home/ec2-user/.kube
chmod 600 /home/ec2-user/.kube/config

# Set KUBECONFIG for interactive sessions
echo 'export KUBECONFIG=/home/ec2-user/.kube/config' >> /home/ec2-user/.bashrc
echo 'alias kubectl="/usr/local/bin/k3s kubectl"' >> /home/ec2-user/.bashrc

# Make kubeconfig available globally for systemd services (like GitHub Actions runner)
echo 'KUBECONFIG=/home/ec2-user/.kube/config' >> /etc/environment

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
  --default-artifact-root file:///opt/mlflow/artifacts \
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

# ── Prometheus + Grafana (Optional Monitoring Stack) ──
if [ "${install_monitoring}" = "true" ]; then
  echo "Installing Prometheus + Grafana monitoring stack..."

  # Wait for k3s to be fully ready
  echo "Waiting for k3s to be ready..."
  until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
    sleep 5
  done

  # Add Helm repository
  echo "Adding prometheus-community Helm repo..."
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update

  # Create monitoring namespace
  kubectl create namespace monitoring || true

  # Install kube-prometheus-stack
  echo "Installing kube-prometheus-stack (this may take 2-3 minutes)..."
  helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
    --set grafana.adminPassword=${grafana_password} \
    --set prometheus.prometheusSpec.retention=7d \
    --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
    --set prometheus.prometheusSpec.resources.limits.memory=1Gi \
    --set grafana.resources.requests.memory=128Mi \
    --set grafana.resources.limits.memory=256Mi \
    --wait --timeout=5m

  echo "✅ Prometheus + Grafana installed!"
  echo "   Grafana admin password: ${grafana_password}"
  echo "   Access Grafana: kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
  echo "   Access Prometheus: kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
else
  echo "Skipping Prometheus + Grafana installation (install_monitoring=false)"
fi

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
