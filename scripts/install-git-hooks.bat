@echo off
REM Install Git Hooks for automatic data branch creation (Windows)
REM Usage: devops\scripts\install-git-hooks.bat

echo === Installing Git Hooks for Windows ===
echo.

REM Find repo root
for /f "delims=" %%i in ('git rev-parse --show-toplevel') do set REPO_ROOT=%%i
echo Repository: %REPO_ROOT%

REM Convert to Windows path
set HOOKS_DIR=%REPO_ROOT%\.git\hooks

echo Creating pre-push hook...

(
echo #!/bin/bash
echo # Pre-push hook: Auto-create data branch for training data changes
echo.
echo echo "🔍 Checking for training data changes..."
echo.
echo while read local_ref local_sha remote_ref remote_sha; do
echo   # Only intercept pushes to main
echo   if [[ "$remote_ref" == "refs/heads/main" ]]; then
echo     # Check if there are any changes to training data
echo     if git diff --name-only "$remote_sha" "$local_sha" 2^>/dev/null ^| grep -q "WMS/data/training"; then
echo       echo ""
echo       echo "╔════════════════════════════════════════════════════════════╗"
echo       echo "║  🚫 Direct push to main with training data blocked        ║"
echo       echo "╚════════════════════════════════════════════════════════════╝"
echo       echo ""
echo       echo "Training data changes detected. Creating data branch..."
echo.
echo       # Create timestamped branch
echo       TIMESTAMP=$(date +%%Y%%m%%d-%%H%%M%%S^)
echo       BRANCH="data/$TIMESTAMP"
echo.
echo       echo "📦 Creating branch: $BRANCH"
echo.
echo       # Create and switch to the new branch
echo       git checkout -b "$BRANCH" 2^>/dev/null ^|^| git checkout "$BRANCH"
echo.
echo       # Push to the new branch
echo       echo "🚀 Pushing to $BRANCH..."
echo       git push -u origin "$BRANCH"
echo.
echo       if [ $? -eq 0 ]; then
echo         echo ""
echo         echo "✅ Success! Your changes are now on branch: $BRANCH"
echo         echo ""
echo         echo "Next steps:"
echo         echo "  1. GitHub Actions will validate your data"
echo         echo "  2. If valid, a Pull Request will be created automatically"
echo         echo "  3. Training will run automatically"
echo         echo "  4. If model improves, PR will be auto-approved"
echo         echo "  5. You (or admin^) can then merge the PR"
echo         echo ""
echo       else
echo         echo "❌ Failed to push to $BRANCH"
echo         echo "Please check your connection and try again"
echo       fi
echo.
echo       # Block the original push to main
echo       exit 1
echo     fi
echo   fi
echo done
echo.
echo # Allow push if no training data changes or not pushing to main
echo exit 0
) > "%HOOKS_DIR%\pre-push"

echo.
echo [OK] Git hooks installed successfully!
echo.
echo What this does:
echo   - When you 'git push origin main' with training data changes
echo   - Hook automatically creates a 'data/YYYYMMDD-HHMMSS' branch
echo   - Pushes your changes there instead
echo   - GitHub Actions takes over from there
echo.
echo To test:
echo   1. Add a new training image
echo   2. git add WMS/data/training/
echo   3. git commit -m "test: new training data"
echo   4. git push origin main
echo   5. Watch the magic happen!
echo.
pause
