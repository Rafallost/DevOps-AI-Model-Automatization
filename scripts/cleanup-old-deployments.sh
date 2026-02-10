#!/bin/bash
# Cleanup script for old/failed model deployments in Kubernetes
# Removes old namespaces with pattern "model-*" and their Helm releases

set -euo pipefail

echo "=== Kubernetes Deployment Cleanup ==="
echo "This script will remove old model-* namespaces and their resources"
echo ""

# Check if running in dry-run mode
DRY_RUN="${1:-false}"

if [[ "$DRY_RUN" == "true" || "$DRY_RUN" == "--dry-run" ]]; then
  echo "🔍 DRY RUN MODE - No changes will be made"
  echo ""
  DRY_RUN=true
else
  DRY_RUN=false
  echo "⚠️  LIVE MODE - Changes will be applied!"
  echo "   Run with '--dry-run' to preview changes first"
  echo ""
  read -p "Continue? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

# Find all namespaces with pattern "model-*"
echo "Searching for old model namespaces..."
OLD_NAMESPACES=$(kubectl get namespaces -o json | \
  jq -r '.items[].metadata.name | select(startswith("model-"))')

if [[ -z "$OLD_NAMESPACES" ]]; then
  echo "✅ No old model-* namespaces found - nothing to clean up!"
  exit 0
fi

echo "Found namespaces to delete:"
echo "$OLD_NAMESPACES" | while read -r ns; do
  echo "  - $ns"
done
echo ""

# Count resources
NAMESPACE_COUNT=$(echo "$OLD_NAMESPACES" | wc -l)
echo "Total: $NAMESPACE_COUNT old namespace(s)"
echo ""

# Delete Helm releases first (cleaner deletion)
echo "=== Step 1: Uninstalling Helm releases ==="
echo "$OLD_NAMESPACES" | while read -r ns; do
  RELEASES=$(helm list -n "$ns" -q 2>/dev/null || true)
  if [[ -n "$RELEASES" ]]; then
    echo "$RELEASES" | while read -r release; do
      if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would uninstall: helm uninstall $release -n $ns"
      else
        echo "Uninstalling Helm release: $release (namespace: $ns)"
        helm uninstall "$release" -n "$ns" || echo "  ⚠️  Failed to uninstall $release"
      fi
    done
  else
    echo "  No Helm releases in $ns"
  fi
done
echo ""

# Delete namespaces (this also deletes all resources within)
echo "=== Step 2: Deleting namespaces ==="
echo "$OLD_NAMESPACES" | while read -r ns; do
  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] Would delete: kubectl delete namespace $ns"
  else
    echo "Deleting namespace: $ns"
    kubectl delete namespace "$ns" --timeout=60s || echo "  ⚠️  Failed to delete $ns"
  fi
done
echo ""

# Show remaining resources
echo "=== Current State After Cleanup ==="
if [[ "$DRY_RUN" == false ]]; then
  echo "Remaining namespaces:"
  kubectl get namespaces | grep -E "NAME|model-|default" || echo "  (none)"
  echo ""

  echo "Active Helm releases:"
  helm list -A | grep -E "NAME|wms-model" || echo "  (none)"
  echo ""

  echo "Active deployments:"
  kubectl get deployments -A | grep -E "NAME|wms-model" || echo "  (none)"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "✅ Dry run complete - no changes made"
  echo "   Run without '--dry-run' to apply changes"
else
  echo "✅ Cleanup complete!"
  echo "   Removed $NAMESPACE_COUNT old namespace(s)"
fi
