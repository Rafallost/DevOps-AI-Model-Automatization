#!/bin/bash
# Standalone k3s setup script
# This is also embedded in EC2 user-data.sh, but can be run manually if needed

set -euo pipefail

echo "=== Installing k3s ==="

# Install k3s
curl -sfL https://get.k3s.io | sh -

# Make kubeconfig readable
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

# Set KUBECONFIG for current user
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Installing Helm ==="
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "=== Verifying installation ==="
sudo systemctl status k3s --no-pager
kubectl get nodes

echo "✓ k3s and Helm installed successfully"
echo "Run: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
