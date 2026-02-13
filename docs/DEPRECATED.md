# Deprecated Scripts and Components

This document lists scripts and components that are no longer used in the current simplified pipeline but are kept for reference.

**Pipeline version:** Simplified (single run, implemented 2026-02-10)

---

## 🗑️ Deprecated Scripts

### `devops/scripts/train-with-retry.py`

**Original purpose:** Orchestrate 3 training attempts with different seeds and retry logic

**Why deprecated:**
- Simplified pipeline uses **single training run** (not 3 attempts)
- Retry logic now handled directly in `.github/workflows/train.yml`
- Quality gate integrated into workflow (not separate script)

**Last used:** Before 2026-02-10 (original 3-attempt pipeline)

**Status:** ⚠️ DEPRECATED - kept for reference only

**Replacement:** Logic integrated into `.github/workflows/train.yml`

---

### `devops/scripts/quality-gate.py`

**Original purpose:** Standalone script to compare model metrics against hardcoded baseline

**Why deprecated:**
- Quality gate logic now integrated into `.github/workflows/train.yml`
- Baseline is **dynamic** (fetched from MLflow Production model), not hardcoded
- No longer needs separate script

**Last used:** Before 2026-02-10 (original pipeline)

**Status:** ⚠️ DEPRECATED - kept for reference only

**Replacement:** Quality gate step in `.github/workflows/train.yml`:
```yaml
- name: Quality Gate - Compare with Production baseline
  id: quality_gate
  run: |
    # Fetches baseline dynamically from MLflow
    # Compares: new_dice > baseline_dice AND new_iou > baseline_iou
```

**Note:** Could still be useful for manual model comparison outside of CI/CD.

---

## 📝 Why Keep These Files?

1. **Historical reference** - shows evolution of the pipeline
2. **Code reuse** - logic can be extracted if needed
3. **Documentation** - referenced in PLAN.md and other docs
4. **Backup** - in case we need to revert to 3-attempt approach

---

## 🧹 Cleanup Options

If you want to clean up the repository:

### Option 1: Move to `deprecated/` folder
```bash
mkdir -p devops/scripts/deprecated
git mv devops/scripts/train-with-retry.py devops/scripts/deprecated/
git mv devops/scripts/quality-gate.py devops/scripts/deprecated/
git commit -m "chore: move deprecated scripts to deprecated/ folder"
```

### Option 2: Delete entirely
```bash
git rm devops/scripts/train-with-retry.py
git rm devops/scripts/quality-gate.py
git commit -m "chore: remove deprecated training scripts

Scripts replaced by integrated workflow logic in train.yml:
- train-with-retry.py: single run approach (no retries needed)
- quality-gate.py: dynamic baseline in workflow"
```

**Recommendation:** Keep for now (Option 1) since they're referenced in documentation. Can delete later after docs are fully updated.

---

## ✅ Currently Active Scripts

For reference, here are the **actively used** scripts in the current pipeline:

### Data Management
- `devops/scripts/data-qa.py` - Data quality validation
- Pre-push hook (`.git/hooks/pre-push`) - Data merging

### Deployment
- `devops/scripts/deploy-to-cloud.sh` - Deploy to EC2
- `devops/scripts/stop-cloud.sh` - Stop infrastructure
- `devops/scripts/verify-deployment.sh` - Verify deployment

### Infrastructure
- `devops/scripts/setup-k3s.sh` - k3s installation
- `devops/scripts/setup-mlflow.sh` - MLflow setup
- `devops/scripts/cleanup-aws.sh` - AWS cleanup

### Model Management (NEW)
- `devops/scripts/get-baseline-metrics.py` - Fetch Production baseline
- `devops/scripts/promote-model.py` - Promote model to Production
- `devops/scripts/update-model-metadata.py` - Update metadata JSON

### Hook Installation
- `devops/scripts/install-git-hooks.sh` - Install pre-push hook
- `devops/scripts/install-git-hooks.bat` - Windows version

---

**Last updated:** 2026-02-10
