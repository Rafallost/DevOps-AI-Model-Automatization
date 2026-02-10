#!/bin/bash
# Install Git Hooks for automatic data branch creation
# Usage: ./devops/scripts/install-git-hooks.sh

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)
HOOKS_DIR="$REPO_ROOT/.git/hooks"

echo "=== Installing Git Hooks ==="
echo "Repository: $REPO_ROOT"

# Create pre-push hook
cat > "$HOOKS_DIR/pre-push" << 'HOOK_EOF'
#!/bin/bash
# Pre-push hook: Create data branch with new training data
# Data merging happens in GitHub Actions (no AWS credentials needed)

set -e

echo "🔍 Checking for training data changes..."

while read local_ref local_sha remote_ref remote_sha; do
  # Only intercept pushes to main
  if [[ "$remote_ref" == "refs/heads/main" ]]; then

    # Detect raw training images/masks (not .dvc metadata files)
    RAW_FILES=$(git diff --name-only --diff-filter=A "$remote_sha" "$local_sha" 2>/dev/null | \
                grep -E "^WMS/data/training/(images|masks)/.*\.(jpg|jpeg|png)$" || true)

    if [ -n "$RAW_FILES" ]; then
      echo ""
      echo "╔════════════════════════════════════════════════════════════╗"
      echo "║  🔍 Raw training data detected                             ║"
      echo "╚════════════════════════════════════════════════════════════╝"
      echo ""

      # Count new files
      NEW_IMAGES=$(echo "$RAW_FILES" | grep -c "images/" || echo "0")
      NEW_MASKS=$(echo "$RAW_FILES" | grep -c "masks/" || echo "0")
      echo "📦 New files detected:"
      echo "   • Images: $NEW_IMAGES"
      echo "   • Masks: $NEW_MASKS"
      echo ""
      echo "Detected files:"
      echo "$RAW_FILES" | sed 's/^/  • /'
      echo ""

      # Save current branch
      CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

      # Create timestamped data branch
      TIMESTAMP=$(date +%Y%m%d-%H%M%S)
      BRANCH="data/$TIMESTAMP"
      echo "🌿 Creating data branch: $BRANCH"

      # Create new branch
      git checkout -b "$BRANCH" || {
        echo "❌ Failed to create branch"
        exit 1
      }

      # Commit the new files (no merging - that happens in GitHub Actions)
      echo "💾 Committing new training data..."
      git add WMS/data/training/

      # Check if there are changes to commit
      if git diff --staged --quiet; then
        echo "⚠️  No changes to commit"
        git checkout "$CURRENT_BRANCH"
        git branch -D "$BRANCH"
        exit 0
      fi

      git commit -m "data: add $NEW_IMAGES new training images

Data will be merged with existing S3 dataset in GitHub Actions.

Branch: $BRANCH
Timestamp: $TIMESTAMP"

      # Push branch to remote
      echo "🚀 Pushing to remote: $BRANCH"
      git push -u origin "$BRANCH" || {
        echo "❌ Failed to push branch"
        git checkout "$CURRENT_BRANCH"
        git branch -D "$BRANCH"
        exit 1
      }

      # Return to original branch and block push to main
      echo ""
      echo "╔════════════════════════════════════════════════════════════╗"
      echo "║  ✅ SUCCESS - New data pushed to branch                    ║"
      echo "╚════════════════════════════════════════════════════════════╝"
      echo ""
      echo "What happens next:"
      echo "  1. GitHub Actions will download existing data from S3"
      echo "  2. Merge: existing S3 data + your new data = complete dataset"
      echo "  3. Validate merged dataset (resolution, pairs, masks)"
      echo "  4. Create Pull Request with merged dataset"
      echo "  5. Training pipeline will run automatically"
      echo ""
      echo "Branch: $BRANCH"
      REPO_URL=$(git remote get-url origin 2>/dev/null | sed 's/.*github.com[:/]//' | sed 's/.git$//')
      if [ -n "$REPO_URL" ]; then
        echo "Track: https://github.com/$REPO_URL/actions"
      fi
      echo ""
      echo "ℹ️  No AWS credentials needed - merging happens in GitHub Actions!"
      echo ""

      git checkout "$CURRENT_BRANCH"
      exit 1  # Block push to main
    fi

    # Handle manual DVC workflow (user already ran 'dvc add' and committed .dvc files)
    DVC_FILES=$(git diff --name-only "$remote_sha" "$local_sha" 2>/dev/null | \
                grep -E "^WMS/data/training/.*\.dvc$" || true)

    if [ -n "$DVC_FILES" ]; then
      echo ""
      echo "╔════════════════════════════════════════════════════════════╗"
      echo "║  📦 DVC metadata changes detected (manual workflow)        ║"
      echo "╚════════════════════════════════════════════════════════════╝"
      echo ""
      echo "Note: You used manual 'dvc add'. Redirecting to data branch..."
      echo ""

      # Save current branch
      ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)

      # Create timestamped branch
      TIMESTAMP=$(date +%Y%m%d-%H%M%S)
      BRANCH="data/$TIMESTAMP"

      echo "📦 Creating branch: $BRANCH"
      git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH"

      echo "🚀 Pushing to $BRANCH..."
      git push -u origin "$BRANCH" 2>&1 | grep -v "^$"

      if [ $? -eq 0 ]; then
        echo ""
        echo "✅ Success! Changes pushed to: $BRANCH"
        echo ""
        echo "Next steps:"
        echo "  1. GitHub Actions will validate your data"
        echo "  2. Pull Request will be created automatically"
        echo "  3. Training will run if validation passes"
        echo ""

        git checkout "$ORIGINAL_BRANCH" 2>/dev/null

        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║  ℹ️  Error below is NORMAL and can be ignored             ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
      else
        echo "❌ Failed to push to $BRANCH"
        git checkout "$ORIGINAL_BRANCH" 2>/dev/null
        git branch -D "$BRANCH" 2>/dev/null
        exit 1
      fi

      # Block push to main
      exit 1
    fi
  fi
done

# Allow push if:
#  - No training data changes detected
#  - Not pushing to main (e.g., pushing to feature branch)
exit 0
HOOK_EOF

# Make hook executable
chmod +x "$HOOKS_DIR/pre-push"

echo ""
echo "✅ Git hooks installed successfully!"
echo ""
echo "What this does:"
echo "  • When you 'git push origin main' with training data changes"
echo "  • Hook automatically creates a 'data/YYYYMMDD-HHMMSS' branch"
echo "  • Pushes your new data there (no AWS credentials needed!)"
echo "  • GitHub Actions downloads S3 data and merges automatically"
echo ""
echo "To test:"
echo "  1. Add a new training image and mask"
echo "  2. git add WMS/data/training/"
echo "  3. git commit -m 'test: new training data'"
echo "  4. git push origin main"
echo "  5. Watch the magic happen! ✨"
echo ""
echo "ℹ️  No local AWS credentials required - all merging happens in CI!"
echo ""
