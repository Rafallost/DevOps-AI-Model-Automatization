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
# Pre-push hook: Auto-create data branch for training data changes

echo "🔍 Checking for training data changes..."

while read local_ref local_sha remote_ref remote_sha; do
  # Only intercept pushes to main
  if [[ "$remote_ref" == "refs/heads/main" ]]; then
    # Check if there are any changes to training data
    if git diff --name-only "$remote_sha" "$local_sha" 2>/dev/null | grep -q "WMS/data/training"; then
      echo ""
      echo "╔════════════════════════════════════════════════════════════╗"
      echo "║  🚫 Direct push to main with training data blocked        ║"
      echo "╚════════════════════════════════════════════════════════════╝"
      echo ""
      echo "Training data changes detected. Creating data branch..."

      # Create timestamped branch
      TIMESTAMP=$(date +%Y%m%d-%H%M%S)
      BRANCH="data/$TIMESTAMP"

      echo "📦 Creating branch: $BRANCH"

      # Create and switch to the new branch
      git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH"

      # Push to the new branch
      echo "🚀 Pushing to $BRANCH..."
      git push -u origin "$BRANCH"

      if [ $? -eq 0 ]; then
        echo ""
        echo "✅ Success! Your changes are now on branch: $BRANCH"
        echo ""
        echo "Next steps:"
        echo "  1. GitHub Actions will validate your data"
        echo "  2. If valid, a Pull Request will be created automatically"
        echo "  3. Training will run automatically"
        echo "  4. If model improves, PR will be auto-approved"
        echo "  5. You (or admin) can then merge the PR"
        echo ""
        echo "Monitor progress: https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/')/actions"
        echo ""
      else
        echo "❌ Failed to push to $BRANCH"
        echo "Please check your connection and try again"
      fi

      # Block the original push to main
      exit 1
    fi
  fi
done

# Allow push if no training data changes or not pushing to main
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
echo "  • Pushes your changes there instead"
echo "  • GitHub Actions takes over from there"
echo ""
echo "To test:"
echo "  1. Add a new training image"
echo "  2. git add WMS/data/training/"
echo "  3. git commit -m 'test: new training data'"
echo "  4. git push origin main"
echo "  5. Watch the magic happen! ✨"
echo ""
