# Self-Hosted Runner Quick Check

## Is the runner already installed?

### Method 1: Check on GitHub (fastest)

1. Go to: https://github.com/Rafallost/Water-Meters-Segmentation-Autimatization/settings/actions/runners
2. Look for a runner named **`ec2-runner`**
3. Check status:
   - 🟢 **Idle** = ✅ Runner working, ready to go!
   - 🔴 **Offline** = Runner exists but EC2 stopped or service down

### Method 2: Check on EC2

```bash
# SSH to EC2
ssh -i ~/.ssh/labsuser.pem ec2-user@<EC2_IP>

# Check if runner directory exists
ls -la ~/actions-runner

# If exists, check service status
cd ~/actions-runner
sudo ./svc.sh status
```

---

## If Runner is Offline (red)

### Solution 1: Start EC2 (runner auto-starts)

```bash
# Get EC2 instance ID
EC2_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=wms-project-k3s" \
           "Name=instance-state-name,Values=stopped" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text)

# Start EC2
aws ec2 start-instances --instance-ids $EC2_ID
aws ec2 wait instance-running --instance-ids $EC2_ID

# Get IP
EC2_IP=$(aws ec2 describe-instances \
  --instance-ids $EC2_ID \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "EC2 started at $EC2_IP"

# Wait 1-2 minutes for runner service to start
sleep 120

# Check GitHub runners page - should show Idle now
```

### Solution 2: Restart runner service

```bash
# SSH to EC2
ssh -i ~/.ssh/labsuser.pem ec2-user@$EC2_IP

# Restart runner service
cd ~/actions-runner
sudo ./svc.sh stop
sudo ./svc.sh start

# Check status
sudo ./svc.sh status
```

---

## If Runner Does NOT Exist

Then you need to install it using the token you provided.

### Quick Install (using your token)

```bash
# SSH to EC2
ssh -i ~/.ssh/labsuser.pem ec2-user@<EC2_IP>

# Create runner directory
mkdir -p ~/actions-runner && cd ~/actions-runner

# Download runner (check latest version at GitHub)
RUNNER_VERSION="2.319.1"
curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
  https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Extract
tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Configure runner
./config.sh \
  --url https://github.com/Rafallost/Water-Meters-Segmentation-Autimatization \
  --token AZ2UCCT6D6OZJMPT4I7CGYDJRJUUC \
  --name ec2-runner \
  --labels self-hosted,linux,x64,ml-training \
  --work _work

# Install as service (auto-start on boot)
sudo ./svc.sh install
sudo ./svc.sh start

# Verify
sudo ./svc.sh status
```

Expected output:
```
● actions.runner.Rafallost-Water-Meters-Segmentation-Autimatization.ec2-runner.service - GitHub Actions Runner
   Loaded: loaded
   Active: active (running)
```

---

## Verify Installation

After starting/installing:

1. Go to GitHub runners page
2. You should see **ec2-runner** with status **Idle** (green)
3. Test workflow:
   ```bash
   # Trigger release-deploy workflow manually
   gh workflow run release-deploy.yaml
   ```

---

## Troubleshooting

### Runner shows as Online but workflow doesn't use it

**Cause:** Workflow might be using different labels

**Solution:** Check workflow file uses `runs-on: self-hosted`

### Token expired

**Symptom:** `./config.sh` fails with authentication error

**Solution:** Get new token from GitHub:
1. Go to: https://github.com/Rafallost/Water-Meters-Segmentation-Autimatization/settings/actions/runners
2. Click "New self-hosted runner"
3. Copy new token
4. Run `./config.sh` again with new token

### Service won't start

**Check logs:**
```bash
sudo journalctl -u actions.runner.* -n 50
```

**Common issues:**
- Wrong permissions: `sudo chown -R ec2-user:ec2-user ~/actions-runner`
- Port conflict: Check if another runner is running
- Network issue: Check EC2 security group allows outbound HTTPS

---

## Summary

**Most likely scenario:** Runner already installed from Phase 4, just needs EC2 to be started.

**Quick test:**
1. Start EC2
2. Check GitHub runners page
3. If shows Idle → you're good!
4. If not showing → install using token

**Token you provided:** `AZ2UCCT6D6OZJMPT4I7CGYDJRJUUC`
(Only use if runner doesn't exist)
