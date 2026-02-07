#!/bin/bash
# verify-deployment.sh - Quick verification script after EC2 recovery

set -e

EC2_IP="${1:-13.219.216.230}"
SSH_KEY="${2:-$HOME/.ssh/labsuser.pem}"

echo "=========================================="
echo "🔍 Deployment Verification Script"
echo "=========================================="
echo "EC2 IP: $EC2_IP"
echo "SSH Key: $SSH_KEY"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test SSH connection
echo -n "1. Testing SSH connection... "
if ssh -i "$SSH_KEY" -o ConnectTimeout=10 ec2-user@"$EC2_IP" 'echo "OK"' &>/dev/null; then
    echo -e "${GREEN}✓ SSH working${NC}"
else
    echo -e "${RED}✗ SSH failed${NC}"
    echo "Please check instance status in AWS Console"
    exit 1
fi

# Check k3s
echo -n "2. Checking k3s... "
if ssh -i "$SSH_KEY" ec2-user@"$EC2_IP" 'kubectl get nodes | grep -q Ready' &>/dev/null; then
    echo -e "${GREEN}✓ k3s ready${NC}"
else
    echo -e "${RED}✗ k3s not ready${NC}"
    exit 1
fi

# Check MLflow
echo -n "3. Checking MLflow... "
if ssh -i "$SSH_KEY" ec2-user@"$EC2_IP" 'curl -s http://localhost:5000/health | grep -q OK' &>/dev/null; then
    echo -e "${GREEN}✓ MLflow running${NC}"
else
    echo -e "${YELLOW}⚠ MLflow not responding${NC}"
fi

# Check pod status
echo -n "4. Checking application pod... "
POD_STATUS=$(ssh -i "$SSH_KEY" ec2-user@"$EC2_IP" 'kubectl get pods -l app.kubernetes.io/name=ml-model -o jsonpath="{.items[0].status.phase}"' 2>/dev/null || echo "NotFound")

if [ "$POD_STATUS" = "Running" ]; then
    echo -e "${GREEN}✓ Pod running${NC}"

    # Get pod details
    READY=$(ssh -i "$SSH_KEY" ec2-user@"$EC2_IP" 'kubectl get pods -l app.kubernetes.io/name=ml-model -o jsonpath="{.items[0].status.containerStatuses[0].ready}"' 2>/dev/null || echo "false")
    RESTARTS=$(ssh -i "$SSH_KEY" ec2-user@"$EC2_IP" 'kubectl get pods -l app.kubernetes.io/name=ml-model -o jsonpath="{.items[0].status.containerStatuses[0].restartCount}"' 2>/dev/null || echo "0")

    echo "   Ready: $READY, Restarts: $RESTARTS"

    if [ "$READY" = "true" ]; then
        echo -e "   ${GREEN}✓ Container ready${NC}"
    else
        echo -e "   ${YELLOW}⚠ Container not ready yet${NC}"
    fi
else
    echo -e "${RED}✗ Pod status: $POD_STATUS${NC}"
    echo ""
    echo "Recent pod events:"
    ssh -i "$SSH_KEY" ec2-user@"$EC2_IP" 'kubectl describe pod -l app.kubernetes.io/name=ml-model | tail -20'
    exit 1
fi

# Check service endpoints
echo -n "5. Checking service endpoints... "
NODE_PORT=$(ssh -i "$SSH_KEY" ec2-user@"$EC2_IP" 'kubectl get svc wms-model-ml-model -o jsonpath="{.spec.ports[0].nodePort}"' 2>/dev/null || echo "")

if [ -n "$NODE_PORT" ]; then
    echo -e "${GREEN}✓ Service exposed on port $NODE_PORT${NC}"

    # Test /health endpoint
    echo -n "   Testing /health... "
    if ssh -i "$SSH_KEY" ec2-user@"$EC2_IP" "curl -s http://localhost:$NODE_PORT/health | grep -q model_loaded" &>/dev/null; then
        echo -e "${GREEN}✓ Working${NC}"
    else
        echo -e "${YELLOW}⚠ Not responding yet${NC}"
    fi

    # Test /metrics endpoint
    echo -n "   Testing /metrics... "
    if ssh -i "$SSH_KEY" ec2-user@"$EC2_IP" "curl -s http://localhost:$NODE_PORT/metrics | grep -q predictions_total" &>/dev/null; then
        echo -e "${GREEN}✓ Working${NC}"
    else
        echo -e "${YELLOW}⚠ Not responding yet${NC}"
    fi
else
    echo -e "${RED}✗ Service not found${NC}"
    exit 1
fi

# Check model registry
echo -n "6. Checking MLflow model registry... "
MODEL_VERSION=$(ssh -i "$SSH_KEY" ec2-user@"$EC2_IP" 'curl -s http://localhost:5000/api/2.0/mlflow/registered-models/get?name=water-meter-segmentation 2>/dev/null | grep -o "\"current_stage\":\"Production\"" | wc -l' || echo "0")

if [ "$MODEL_VERSION" -gt 0 ]; then
    echo -e "${GREEN}✓ Production model registered${NC}"
else
    echo -e "${YELLOW}⚠ No production model found${NC}"
fi

# Final summary
echo ""
echo "=========================================="
echo -e "${GREEN}✓ VERIFICATION COMPLETE${NC}"
echo "=========================================="
echo ""
echo "Service URL: http://$EC2_IP:$NODE_PORT"
echo ""
echo "Next steps:"
echo "  1. Test prediction: curl -X POST http://$EC2_IP:$NODE_PORT/predict -F 'file=@image.jpg'"
echo "  2. Test training pipeline: Trigger GitHub Actions workflow"
echo ""
