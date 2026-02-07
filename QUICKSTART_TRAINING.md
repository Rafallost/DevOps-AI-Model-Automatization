# Quick Start: Training Pipeline

## 🎯 Goal
Get the automated training pipeline running in ~30 minutes.

## ✅ Prerequisites
- [ ] AWS Lab session started
- [ ] EC2 instance running (Phase 5 complete)
- [ ] MLflow server running on EC2:5000
- [ ] GitHub repository access

## 📋 Steps

### 1. Setup GitHub Actions Runner (15 min)

SSH to EC2 and follow **RUNNER_SETUP.md**:

```bash
# Quick version:
ssh -i ~/.ssh/labsuser.pem ec2-user@<EC2_IP>

# Download and configure runner
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64-2.319.1.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.319.1/actions-runner-linux-x64-2.319.1.tar.gz
tar xzf actions-runner-linux-x64-2.319.1.tar.gz

# Get token from GitHub:
# Settings → Actions → Runners → New self-hosted runner

./config.sh \
  --url https://github.com/Rafallost/Water-Meters-Segmentation-Autimatization \
  --token <TOKEN> \
  --name ec2-runner \
  --labels self-hosted,linux,x64,ml-training

# Install and start service
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
```

**Verify**: Check GitHub Settings → Actions → Runners - should see "ec2-runner" (Idle)

### 2. Test Training Workflow (5 min)

**Option A: Manual trigger (recommended for first test)**
1. Go to GitHub → Actions → Train Model
2. Click "Run workflow" → "Run workflow"
3. Watch it execute

**Option B: Create a test PR**
1. Create branch: `git checkout -b test-training`
2. Make small change to training config or data
3. Push and create PR
4. Workflow should trigger automatically

### 3. Monitor Training (10 min)

**On EC2:**
```bash
# Watch runner logs
sudo journalctl -u actions.runner.* -f

# Watch MLflow logs
# (in separate terminal)
tail -f ~/mlflow/mlflow.log
```

**On GitHub:**
- Watch workflow progress in Actions tab
- See real-time logs for each step

### 4. Verify Results (5 min)

After training completes:

**Check MLflow:**
```bash
# On EC2
curl http://localhost:5000/api/2.0/mlflow/experiments/get-by-name?experiment_name=water-meter-segmentation

# Or open in browser (via SSH tunnel):
# ssh -L 5000:localhost:5000 -i ~/.ssh/labsuser.pem ec2-user@<EC2_IP>
# Then visit: http://localhost:5000
```

**Check Model Registry:**
```python
# On EC2
python3 << 'EOF'
import mlflow
from mlflow.tracking import MlflowClient

mlflow.set_tracking_uri("http://localhost:5000")
client = MlflowClient()

# List registered models
models = client.search_registered_models()
for model in models:
    print(f"\nModel: {model.name}")

    # Get latest versions
    versions = client.search_model_versions(f"name='{model.name}'")
    for v in sorted(versions, key=lambda x: int(x.version), reverse=True)[:3]:
        print(f"  Version {v.version}: {v.current_stage}")
EOF
```

**Expected output:**
```
Model: water-meter-segmentation
  Version 3: Production
  Version 2: Archived
  Version 1: Archived
```

## 🎉 Success Criteria

- [ ] Runner appears as "Idle" in GitHub
- [ ] Workflow completes without errors
- [ ] Training runs for ~50 epochs (~10 min on CPU)
- [ ] Metrics logged to MLflow (Dice, IoU)
- [ ] Model registered to MLflow
- [ ] If improved: Model promoted to Production stage
- [ ] PR comment shows training results

## 📊 What Happens During Training

1. **Data preparation**: DVC pulls training data from S3 (or uses local cache)
2. **Training**: 50 epochs with WaterMetersUNet
3. **Validation**: Calculates Dice and IoU on validation set
4. **Quality Gate**:
   - **Thresholds**: Dice ≥ 0.9075, IoU ≥ 0.8665 (2% tolerance)
   - **Baseline**: Dice 0.9275, IoU 0.8865
5. **Results**:
   - **Pass + Improved**: Model promoted to Production
   - **Pass + Not Improved**: Model saved but not deployed
   - **Fail**: Workflow fails, PR cannot merge

## 🔧 Troubleshooting

### Runner not starting

```bash
# Check runner status
cd ~/actions-runner
sudo ./svc.sh status

# View logs
sudo journalctl -u actions.runner.* -n 100
```

### Training fails with "MLflow connection refused"

```bash
# Check MLflow is running
curl http://localhost:5000/health

# If not, start it
cd ~/mlflow
mlflow server \
  --backend-store-uri sqlite:///mlflow.db \
  --default-artifact-root s3://wms-mlflow-artifacts-<ACCOUNT_ID>/ \
  --host 0.0.0.0 \
  --port 5000 &
```

### DVC pull fails

```bash
# Check AWS credentials
aws sts get-caller-identity

# Manually pull data
cd ~/Water-Meters-Segmentation-Autimatization/WMS/data/training
dvc pull images.dvc masks.dvc
```

### Workflow times out

Default timeout is 60 minutes. Training on CPU can take 10-15 minutes for 50 epochs.

If it's taking too long:
1. Reduce epochs in `WMS/configs/train.yaml` (e.g., 20 epochs for testing)
2. Check EC2 isn't under heavy load

## 🚀 Next Steps

After successful test:

1. **Trigger training on real changes**:
   - Add new training images to `WMS/data/training/images/`
   - Add corresponding masks to `WMS/data/training/masks/`
   - Create PR → Training triggers automatically

2. **Auto-deployment**:
   - When model improves, it's automatically promoted to Production
   - Task #17: Add auto-deploy step to rebuild and redeploy serving app

3. **Monitoring**:
   - Task #9: Setup Prometheus/Grafana to track training metrics over time

## 📝 Files Created

- `.github/workflows/train.yml` - Training workflow
- `devops/RUNNER_SETUP.md` - Detailed runner installation guide
- `devops/QUICKSTART_TRAINING.md` - This file

## 💰 Cost Reminder

- **Training cost**: ~$0.0832/hour for EC2 (t3.large)
- **10-15 min training** ≈ $0.015 per run
- **Stop EC2 when not training** to save costs

---

**Ready to test? Start with Step 1!** 🚀
