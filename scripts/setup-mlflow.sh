#!/bin/bash
# Standalone MLflow setup script
# Use this if user-data.sh failed or if you need to restart MLflow manually

set -euo pipefail

MLFLOW_BUCKET="${1:-wms-mlflow-artifacts-036136800740}"

echo "=== Installing MLflow ==="
pip3 install mlflow boto3

# Create working directory
sudo mkdir -p /opt/mlflow

echo "=== Creating systemd service ==="
sudo tee /etc/systemd/system/mlflow.service > /dev/null <<EOF
[Unit]
Description=MLflow Tracking Server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/mlflow server \\
  --backend-store-uri sqlite:////opt/mlflow/mlflow.db \\
  --default-artifact-root s3://${MLFLOW_BUCKET}/ \\
  --host 0.0.0.0
WorkingDirectory=/opt/mlflow
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "=== Starting MLflow service ==="
sudo systemctl daemon-reload
sudo systemctl start mlflow
sudo systemctl enable mlflow

echo "=== Verifying MLflow ==="
sleep 3
sudo systemctl status mlflow --no-pager

echo "✓ MLflow installed and running"
echo "Access MLflow UI at: http://$(curl -s ifconfig.me):5000"
