#!/bin/bash
# Deploy Water Meter Segmentation app to AWS EC2
#
# Usage: ./devops/scripts/deploy-to-cloud.sh [model-version]
#
# This script:
# 1. Starts EC2 infrastructure (MLflow server, k3s cluster)
# 2. Deploys the latest Production model
# 3. Provides access URLs
#
# Remember to run ./devops/scripts/stop-cloud.sh when done to save costs!

set -e

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  🚀 Water Meter Segmentation - Cloud Deployment           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed"
    echo ""
    echo "Install instructions:"
    echo "  Windows: choco install terraform"
    echo "  macOS:   brew install terraform"
    echo "  Linux:   https://www.terraform.io/downloads"
    exit 1
fi

# Check AWS credentials
echo "🔐 Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials not configured"
    echo ""
    echo "To set up AWS credentials:"
    echo "  1. AWS Academy → Learner Lab → Start Lab"
    echo "  2. AWS Details → Show AWS CLI credentials"
    echo "  3. Copy credentials to ~/.aws/credentials or set as env vars"
    echo ""
    exit 1
fi
echo "✅ AWS credentials valid"
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

# Initialize Terraform (if needed)
if [ ! -d ".terraform" ]; then
    echo "📦 Initializing Terraform..."
    terraform init
    echo ""
fi

# Start EC2 infrastructure
echo "🚀 Starting EC2 infrastructure..."
echo "This may take 3-5 minutes..."
echo ""
terraform apply -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Terraform apply failed"
    exit 1
fi

# Get EC2 IP
EC2_IP=$(terraform output -raw mlflow_server_ip 2>/dev/null)
if [ -z "$EC2_IP" ]; then
    echo "❌ Could not retrieve EC2 IP address"
    exit 1
fi

echo ""
echo "✅ EC2 infrastructure started: $EC2_IP"
echo ""

# Wait for MLflow server to be ready
echo "⏳ Waiting for MLflow server to be ready..."
MAX_ATTEMPTS=60
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -sf "http://$EC2_IP:5000/health" > /dev/null 2>&1; then
        echo "✅ MLflow server is ready!"
        break
    fi

    ATTEMPT=$((ATTEMPT + 1))
    if [ $((ATTEMPT % 10)) -eq 0 ]; then
        echo "Still waiting... ($ATTEMPT/$MAX_ATTEMPTS)"
    fi
    sleep 5
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "❌ MLflow server did not become ready in time"
    echo "Check EC2 instance status in AWS Console"
    exit 1
fi

echo ""

# Check if k3s is installed (for future Helm deployments)
# For now, we'll skip the actual deployment since Helm charts may not be ready
echo "ℹ️  Kubernetes deployment skipped (run manually if needed)"
echo ""

# TODO: Uncomment when Helm charts are ready
# echo "🚀 Deploying application with Helm..."
# HELM_DIR="$PROJECT_ROOT/infrastructure/helm"
# if [ -f "$HELM_DIR/Chart.yaml" ]; then
#     # Copy kubeconfig from EC2
#     ssh -i ~/.ssh/labsuser.pem ubuntu@$EC2_IP "cat /etc/rancher/k3s/k3s.yaml" > /tmp/k3s.yaml
#     sed -i "s/127.0.0.1/$EC2_IP/g" /tmp/k3s.yaml
#     export KUBECONFIG=/tmp/k3s.yaml
#
#     # Deploy with Helm
#     helm upgrade --install wms-app "$HELM_DIR" \
#       -f "$HELM_DIR/helm-values.yaml" \
#       --set mlflowTrackingUri="http://$EC2_IP:5000"
#
#     # Wait for deployment
#     kubectl wait --for=condition=ready pod -l app=wms-serve --timeout=300s
#     echo "✅ Application deployed!"
# else
#     echo "⚠️  Helm chart not found, skipping deployment"
# fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ Deployment Complete!                                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Access your services:"
echo "  📊 MLflow UI:  http://$EC2_IP:5000"
echo "  🌐 Web App:    http://$EC2_IP:8000 (if deployed)"
echo "  📖 API Docs:   http://$EC2_IP:8000/docs (if deployed)"
echo ""
echo "SSH Access:"
echo "  ssh -i ~/.ssh/labsuser.pem ubuntu@$EC2_IP"
echo ""
echo "⚠️  IMPORTANT: When you're done, stop infrastructure to save costs:"
echo "  ./devops/scripts/stop-cloud.sh"
echo ""
echo "💡 Tip: Infrastructure costs ~$0.10/hour when running"
echo "    Don't forget to shut down when finished!"
echo ""
