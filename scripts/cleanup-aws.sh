#!/bin/bash
# cleanup-aws.sh - AWS Resource Cleanup Script
#
# ⚠️  WARNING: This script DELETES ALL AWS RESOURCES for this project
# Run ONLY after project testing and thesis submission is complete
#
# Usage:
#   bash cleanup-aws.sh
#
# What it does:
#   1. Empties S3 buckets (required before terraform destroy)
#   2. Runs terraform destroy (removes EC2, VPC, ECR, IAM, etc.)
#   3. Verifies cleanup via AWS CLI
#
# Budget protection: This prevents ongoing AWS charges

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}⚠️  AWS RESOURCE CLEANUP - DESTRUCTIVE OPERATION ⚠️${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "This script will DELETE:"
echo "  - All S3 buckets (wms-*)"
echo "  - EC2 instance + Elastic IP"
echo "  - ECR repository + all images"
echo "  - VPC, subnets, security groups"
echo "  - IAM roles and policies"
echo ""
echo -e "${YELLOW}This action CANNOT be undone!${NC}"
echo ""
read -p "Are you sure you want to proceed? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo -e "${GREEN}Starting cleanup...${NC}"
echo ""

# ============================================================================
# Step 1: Empty S3 Buckets
# ============================================================================
# S3 buckets with versioning enabled cannot be deleted while they contain
# objects or versions. We must delete all versions and delete markers first.

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Emptying S3 buckets (all versions + delete markers)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

# Define bucket names
DVC_BUCKET="wms-dvc-data-${ACCOUNT_ID}"
MLFLOW_BUCKET="wms-mlflow-artifacts-${ACCOUNT_ID}"

for BUCKET in "$DVC_BUCKET" "$MLFLOW_BUCKET"; do
    echo ""
    echo "Processing bucket: $BUCKET"

    # Check if bucket exists
    if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
        echo "  → Bucket exists, emptying..."

        # Delete all object versions
        echo "  → Deleting object versions..."
        aws s3api list-object-versions \
            --bucket "$BUCKET" \
            --output json \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' 2>/dev/null | \
        jq -r '.[]? | .Key + "\t" + .VersionId' | \
        while IFS=$'\t' read -r KEY VERSION_ID; do
            if [ -n "$KEY" ] && [ -n "$VERSION_ID" ]; then
                aws s3api delete-object \
                    --bucket "$BUCKET" \
                    --key "$KEY" \
                    --version-id "$VERSION_ID" >/dev/null 2>&1
                echo "    ✓ Deleted: $KEY (version: $VERSION_ID)"
            fi
        done

        # Delete all delete markers
        echo "  → Deleting delete markers..."
        aws s3api list-object-versions \
            --bucket "$BUCKET" \
            --output json \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' 2>/dev/null | \
        jq -r '.[]? | .Key + "\t" + .VersionId' | \
        while IFS=$'\t' read -r KEY VERSION_ID; do
            if [ -n "$KEY" ] && [ -n "$VERSION_ID" ]; then
                aws s3api delete-object \
                    --bucket "$BUCKET" \
                    --key "$KEY" \
                    --version-id "$VERSION_ID" >/dev/null 2>&1
                echo "    ✓ Deleted marker: $KEY (version: $VERSION_ID)"
            fi
        done

        echo "  ✅ Bucket emptied: $BUCKET"
    else
        echo "  ⚠️  Bucket not found (may already be deleted): $BUCKET"
    fi
done

echo ""
echo "✅ S3 buckets emptied"

# ============================================================================
# Step 2: Terraform Destroy
# ============================================================================
# Destroy all Terraform-managed resources

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Destroying Terraform resources"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Navigate to terraform directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"
TFVARS_FILE="$SCRIPT_DIR/../../infrastructure/terraform.tfvars"

if [ ! -d "$TERRAFORM_DIR" ]; then
    echo "❌ Error: Terraform directory not found: $TERRAFORM_DIR"
    exit 1
fi

if [ ! -f "$TFVARS_FILE" ]; then
    echo "❌ Error: terraform.tfvars not found: $TFVARS_FILE"
    exit 1
fi

cd "$TERRAFORM_DIR"
echo "Working directory: $(pwd)"

# Initialize terraform (in case state is stale)
echo "Initializing Terraform..."
terraform init -upgrade

# Destroy all resources
echo ""
echo "Running terraform destroy..."
terraform destroy \
    -var-file="$TFVARS_FILE" \
    -auto-approve

echo ""
echo "✅ Terraform destroy completed"

# ============================================================================
# Step 3: Verification
# ============================================================================
# Verify that resources are actually deleted

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ISSUES=0

# Check EC2 instances
echo ""
echo "Checking EC2 instances..."
INSTANCES=$(aws ec2 describe-instances \
    --region us-east-1 \
    --filters "Name=tag:Project,Values=wms" "Name=instance-state-name,Values=running,stopped,stopping" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text)

if [ -z "$INSTANCES" ]; then
    echo "  ✅ No EC2 instances found"
else
    echo "  ⚠️  WARNING: EC2 instances still exist: $INSTANCES"
    ISSUES=$((ISSUES + 1))
fi

# Check Elastic IPs
echo "Checking Elastic IPs..."
EIPS=$(aws ec2 describe-addresses \
    --region us-east-1 \
    --query 'Addresses[].AllocationId' \
    --output text)

if [ -z "$EIPS" ]; then
    echo "  ✅ No Elastic IPs allocated"
else
    echo "  ⚠️  WARNING: Elastic IPs still allocated: $EIPS"
    echo "     These cost \$0.005/hour even when not attached!"
    ISSUES=$((ISSUES + 1))
fi

# Check S3 buckets
echo "Checking S3 buckets..."
WMS_BUCKETS=$(aws s3api list-buckets \
    --query "Buckets[?starts_with(Name, 'wms-')].Name" \
    --output text)

if [ -z "$WMS_BUCKETS" ]; then
    echo "  ✅ No wms-* buckets found"
else
    echo "  ⚠️  WARNING: S3 buckets still exist: $WMS_BUCKETS"
    ISSUES=$((ISSUES + 1))
fi

# Check ECR repositories
echo "Checking ECR repositories..."
ECR_REPOS=$(aws ecr describe-repositories \
    --region us-east-1 \
    --query 'repositories[?repositoryName==`wms-model`].repositoryName' \
    --output text 2>/dev/null || true)

if [ -z "$ECR_REPOS" ]; then
    echo "  ✅ No ECR repositories found"
else
    echo "  ⚠️  WARNING: ECR repository still exists: $ECR_REPOS"
    ISSUES=$((ISSUES + 1))
fi

# Check VPCs (excluding default)
echo "Checking VPCs..."
VPC_COUNT=$(aws ec2 describe-vpcs \
    --region us-east-1 \
    --filters "Name=tag:Project,Values=wms" \
    --query 'length(Vpcs)' \
    --output text)

if [ "$VPC_COUNT" = "0" ]; then
    echo "  ✅ No project VPCs found"
else
    echo "  ⚠️  WARNING: $VPC_COUNT project VPC(s) still exist"
    ISSUES=$((ISSUES + 1))
fi

# ============================================================================
# Final Summary
# ============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Cleanup Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✅ All resources successfully deleted!${NC}"
else
    echo -e "${YELLOW}⚠️  $ISSUES issue(s) found - manual verification recommended${NC}"
fi

echo ""
echo "POST-CLEANUP CHECKLIST:"
echo "  1. Verify in AWS Console → EC2 → Instances (should be empty)"
echo "  2. Verify in AWS Console → EC2 → Elastic IPs (should be empty)"
echo "  3. Verify in AWS Console → S3 (no wms-* buckets)"
echo "  4. Verify in AWS Console → ECR (no wms-model repository)"
echo "  5. Verify in AWS Console → VPC (only default VPC)"
echo "  6. Check Billing Dashboard to confirm charges stopped"
echo ""
echo "AWS Console: https://console.aws.amazon.com/"
echo "Billing: https://console.aws.amazon.com/billing/home#/bills"
echo ""

if [ $ISSUES -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Please manually delete remaining resources in AWS Console${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Cleanup completed successfully${NC}"
exit 0
