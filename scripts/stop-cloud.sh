#!/bin/bash
# Stop EC2 infrastructure to save costs
#
# Usage: ./devops/scripts/stop-cloud.sh

set -e

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  🛑 Stopping EC2 Infrastructure                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Navigate to terraform directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$PROJECT_ROOT/infrastructure/terraform"

if [ ! -d "$TERRAFORM_DIR" ]; then
    echo "❌ Terraform directory not found: $TERRAFORM_DIR"
    exit 1
fi

cd "$TERRAFORM_DIR"

# Check if infrastructure is running
if [ ! -f "terraform.tfstate" ]; then
    echo "ℹ️  No infrastructure found (already stopped or never started)"
    exit 0
fi

# Get current EC2 IP before destroying
EC2_IP=$(terraform output -raw mlflow_server_ip 2>/dev/null || echo "N/A")

echo "🔍 Current infrastructure:"
if [ "$EC2_IP" != "N/A" ]; then
    echo "  EC2 IP: $EC2_IP"
else
    echo "  Status: Unknown (may already be stopped)"
fi
echo ""

# Confirm destruction
echo "⚠️  This will destroy all EC2 resources and stop billing."
read -p "Continue? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "🗑️  Destroying infrastructure..."
terraform destroy -auto-approve

if [ $? -eq 0 ]; then
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  ✅ Infrastructure Stopped Successfully                    ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "💰 Billing stopped - no more charges until next deployment"
    echo ""
else
    echo ""
    echo "❌ Terraform destroy failed"
    echo "Check AWS Console to verify resources are deleted"
    exit 1
fi
