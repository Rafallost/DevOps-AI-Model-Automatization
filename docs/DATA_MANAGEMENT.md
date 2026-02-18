# Training Data Management Guide

## Overview

This project uses **DVC (Data Version Control)** with **S3 backend** to manage training data. Raw images and masks are stored in S3, while Git tracks only lightweight `.dvc` metadata files.

**Key Benefits:**

- Git repository stays small (no large binary files)
- Data versioned alongside code
- Automatic upload/download to/from S3
- Content-addressed storage (duplicate files handled efficiently)

---

## Table of Contents

1. [Viewing Current Training Data](#viewing-current-training-data)
2. [Adding New Training Data (Automated Workflow)](#adding-new-training-data-automated-workflow)
3. [Manual DVC Workflow (Advanced)](#manual-dvc-workflow-advanced)
4. [Safety Mechanisms](#safety-mechanisms)
5. [Troubleshooting](#troubleshooting)

---

## Viewing Current Training Data

### Option 1: Pull Data from DVC/S3

To download the current training data to your local machine:

```bash
# Pull all training data
cd Water-Meters-Segmentation-Automatization
dvc pull WMS/data/training/images.dvc WMS/data/training/masks.dvc

# Data is now available in:
# WMS/data/training/images/
# WMS/data/training/masks/
```

**View images:**

```bash
ls -lh WMS/data/training/images/
ls -lh WMS/data/training/masks/
```

### Option 2: Check Metadata Without Downloading

View what data is tracked without downloading:

```bash
# Show DVC cache info
dvc cache dir

# Show tracked files
cat WMS/data/training/images.dvc
cat WMS/data/training/masks.dvc
```

### Option 3: Browse S3 Directly (AWS Console)

1. Log in to AWS Console
2. Navigate to S3
3. Open bucket: `wms-dvc-storage` (or your configured DVC remote)
4. Browse `files/md5/` directory structure

**Note:** Files are stored by MD5 hash (content-addressed), not original filenames.

---

## Adding New Training Data (Automated Workflow)

### Simplified Workflow (Recommended)

The pre-push Git hook **automatically handles DVC processing**. You just work with files normally.

#### Step 1: Add Images and Masks

```bash
# Copy new training images
cp /path/to/new/images/*.jpg WMS/data/training/images/

# Copy corresponding masks
cp /path/to/new/masks/*.png WMS/data/training/masks/

# Verify file counts match
echo "Images: $(ls WMS/data/training/images/ | wc -l)"
echo "Masks:  $(ls WMS/data/training/masks/ | wc -l)"
```

**Requirements:**

- Images: `.jpg`, `.jpeg`, or `.png` format
- Masks: `.png` format (binary: 0 or 255 pixel values)
- Resolution: 512×512 pixels
- Filenames: Each image must have matching mask (e.g., `id_25.jpg` ↔ `id_25.png`)

#### Step 2: Commit Files (as usual)

```bash
git add WMS/data/training/images/
git add WMS/data/training/masks/
git commit -m "data: add new water meter images (id_25-30)"
```

**Note:** You're committing raw files to Git locally. The hook will convert them to DVC.

#### Step 3: Push to Main

```bash
git push origin main
```

**What happens automatically:**

1. **Pre-push hook intercepts** the push
2. **Detects raw images/masks** in your commits
3. **Creates timestamped data branch** (e.g., `data/20260209-143022`)
4. **Runs `dvc add`** on images and masks
5. **Uploads data to S3** via `dvc push`
6. **Commits `.dvc` metadata files** to data branch (NOT raw files)
7. **Pushes data branch** to GitHub
8. **Blocks push to main** (by design)

**Expected output:**

```
🔍 Checking for training data changes...

╔════════════════════════════════════════════════════════════╗
║  📦 Raw training data detected - Auto-DVC processing       ║
╚════════════════════════════════════════════════════════════╝

Detected 12 raw file(s):
WMS/data/training/images/id_25.jpg
WMS/data/training/images/id_26.jpg
...

📦 Creating data branch: data/20260209-143022
🔄 Processing with DVC...
  • Running: dvc add WMS/data/training/images
  • Running: dvc add WMS/data/training/masks

📤 Uploading data to S3...
📝 Committing DVC metadata...
🚀 Pushing to remote branch: data/20260209-143022

╔════════════════════════════════════════════════════════════╗
║  ✅ SUCCESS - Data processed and pushed!                   ║
╚════════════════════════════════════════════════════════════╝

What happened:
  ✓ Raw files processed with 'dvc add'
  ✓ Data uploaded to S3 (managed by DVC)
  ✓ DVC metadata (.dvc files) pushed to: data/20260209-143022
  ✓ Raw files NOT in Git history (only .dvc references)

Next steps:
  1. GitHub Actions will validate your data
  2. If valid, Pull Request will be created automatically
  3. Training pipeline will run (up to 3 attempts)
  4. Quality gate compares new model vs baseline
  5. If improved, PR auto-approved for review & merge
```

#### Step 4: Automated Pipeline (No Action Needed)

On the `data/YYYYMMDD-HHMMSS` branch, GitHub Actions automatically:

1. **Data QA Validation** (`data-qa.py`)
   - Checks image↔mask pairs match
   - Validates resolution (512×512)
   - Verifies masks are binary (0/255)

2. **If validation PASSES:**
   - Creates Pull Request
   - Runs training pipeline (up to 3 attempts with different seeds)
   - Evaluates model quality vs baseline
   - Auto-approves PR if model improves

3. **If validation FAILS:**
   - Posts error comment on commit
   - No PR created
   - You can fix issues and push again to the same branch

#### Step 5: Review and Merge (Manual)

Once the PR is auto-approved:

- Review training metrics in PR comments
- Verify quality gate passed
- **Merge the PR** to deploy the new model

---

## Manual DVC Workflow (Advanced)

If you prefer manual control over DVC processing, you can bypass the automated hook.

### Option 1: Use `dvc add` Manually

```bash
# Add new files
cp new_images/*.jpg WMS/data/training/images/
cp new_masks/*.png WMS/data/training/masks/

# Process with DVC
dvc add WMS/data/training/images
dvc add WMS/data/training/masks

# Upload to S3
dvc push

# Commit .dvc metadata
git add WMS/data/training/*.dvc
git add WMS/data/training/images/.gitignore
git add WMS/data/training/masks/.gitignore
git commit -m "dvc: add new training data"

# Push to main
git push origin main
```

**Result:** The pre-push hook detects `.dvc` files and redirects to a data branch (same as automated workflow).

### Option 2: Commit Directly to Data Branch

```bash
# Create data branch manually
git checkout -b data/my-experiment

# Add data with DVC
dvc add WMS/data/training/images
dvc push
git add *.dvc
git commit -m "dvc: experimental dataset"

# Push directly to data branch (hook allows this)
git push origin data/my-experiment
```

---

## Safety Mechanisms

### 1. Duplicate Filenames

**Question:** What if someone uploads images with the same filenames?

**Answer:** DVC uses **content-addressed storage** (MD5 hashing). Files are identified by content, not name.

**Example:**

```bash
# User A uploads id_25.jpg (cat photo, MD5: abc123)
# User B uploads id_25.jpg (dog photo, MD5: def456)
```

**Result:**

- Both files stored in S3 with different hashes
- `.dvc` file points to the correct hash
- No data loss or corruption
- Git history tracks which version was used for each training run

### 2. Accidental Large Files in Git

**Protection:** `.gitignore` blocks raw training data:

```gitignore
# Training data - managed by DVC (not Git)
WMS/data/training/images/
WMS/data/training/masks/
```

**If you accidentally stage large files:**

```bash
# Unstage files
git reset HEAD WMS/data/training/images/
git reset HEAD WMS/data/training/masks/

# Clean working directory
git clean -fd WMS/data/training/
```

### 3. Data Validation (Quality Gate)

Every data upload is validated **before** training:

**Checks:**

- ✅ Image↔mask filename matching
- ✅ Resolution: 512×512 pixels
- ✅ Mask format: binary PNG (0 or 255 values)
- ✅ File format: `.jpg`, `.jpeg`, `.png`

**If validation fails:**

- PR is NOT created
- Error comment posted on commit
- Training does NOT run
- You can fix issues and push again

### 4. S3 Upload Failures

**If `dvc push` fails:**

- Hook aborts the push
- Returns to original branch
- Deletes the failed data branch
- You see clear error message

**Common causes:**

- AWS credentials expired
- Network connection issue
- S3 bucket permissions

**Fix:**

```bash
# Refresh AWS credentials (AWS Academy labs)
aws configure

# Verify DVC configuration
dvc remote list
dvc remote modify storage url s3://wms-dvc-storage/dvcstore

# Try again
git push origin main
```

### 5. Version Control & Rollback

**Every data upload is versioned:**

```bash
# View data history
git log --oneline -- WMS/data/training/*.dvc

# Rollback to previous version
git checkout <commit-hash> -- WMS/data/training/images.dvc
dvc checkout
```

**Result:** DVC downloads the old data version from S3.

---

## Troubleshooting

### Issue 1: "DVC add failed"

**Error:**

```
❌ DVC add failed for images
```

**Causes:**

- Directory doesn't exist
- No files in directory
- Permission issues

**Fix:**

```bash
# Verify files exist
ls -la WMS/data/training/images/
ls -la WMS/data/training/masks/

# Check DVC status
dvc status
```

### Issue 2: "DVC push to S3 failed"

**Error:**

```
❌ DVC push to S3 failed
Please check your AWS credentials and DVC configuration
```

**Fix:**

```bash
# Check AWS credentials
aws sts get-caller-identity

# For AWS Academy Labs (credentials expire ~4 hours)
# Re-download credentials from AWS Academy and run:
aws configure

# Verify DVC remote
dvc remote list
```

### Issue 3: "Images directory not found" in GitHub Actions

**Cause:** Workflow didn't pull data from DVC before validation.

**Fix:** The `training-data-pipeline.yaml` workflow automatically runs `dvc pull` before validation. If this step fails, check AWS secrets in GitHub:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

### Issue 4: "Branch already exists"

**Error:**

```
❌ Failed to create branch data/20260209-143022
```

**Cause:** Rare timestamp collision (same second).

**Fix:** Wait 1 second and push again. The hook uses seconds precision, so waiting ensures a unique timestamp.

### Issue 5: Training Data Not Appearing Locally

**Problem:** After cloning the repo, `WMS/data/training/` is empty.

**Solution:** Pull data from DVC:

```bash
dvc pull WMS/data/training/images.dvc
dvc pull WMS/data/training/masks.dvc
```

**For new contributors:**

```bash
# Clone with submodules
git clone --recurse-submodules <repo-url>
cd Water-Meters-Segmentation-Automatization

# Configure AWS credentials
aws configure

# Pull training data
dvc pull
```

---

## Summary: Recommended Workflow

### For Data Contributors:

1. **Add files** to `WMS/data/training/images/` and `WMS/data/training/masks/`
2. **Commit** as usual: `git add ... && git commit -m "..."`
3. **Push** to main: `git push origin main`
4. **Wait** for automated validation and training
5. **Review** PR and merge if model improves

### For Reviewers:

1. **Check** PR created by GitHub Actions
2. **Review** validation report (image count, resolution, coverage)
3. **Review** training metrics (Dice, IoU, Hausdorff)
4. **Review** quality gate result (passed/improved)
5. **Merge** if satisfied

### For Developers:

1. **Pull** latest data: `dvc pull`
2. **Run** training locally: `python WMS/src/train.py --config WMS/configs/train.yaml`
3. **Experiment** with different hyperparameters
4. **Push** results to feature branch (not main)

---

## Additional Resources

- **DVC Documentation:** https://dvc.org/doc
- **Project Architecture:** `devops/CLAUDE.md`
- **Training Pipeline:** `.github/workflows/train.yml`
- **Data QA Script:** `devops/scripts/data-qa.py`
- **Quality Gate:** `.github/workflows/train.yml` (lines 200-250)

---

## Questions?

If you encounter issues not covered here:

1. Check workflow logs in GitHub Actions
2. Review `KNOWN_ISSUES.md` for AWS Academy limitations
3. Check MLflow tracking server for training history
4. Contact repository maintainers
