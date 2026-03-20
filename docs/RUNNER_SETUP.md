# GitHub Actions Runner Setup

## Goal
Install and configure new self-hosted runner and data hooks.

## Step 1: Create runner in GitHub
Go to GitHub: Settings -> Actions -> Runners -> New self-hosted runner.

## Step 2: Install on EC2
```bash
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner.tar.gz -L https://github.com/actions/runner/releases/download/v2.331.0/actions-runner-linux-x64-2.331.0.tar.gz
tar xzf actions-runner.tar.gz
./config.sh --url https://github.com/<org>/<repo> --token <TOKEN> --name ec2-runner --labels self-hosted,linux
sudo ./svc.sh install
sudo ./svc.sh start
```

## Step 3: Dependencies
✅ **Already installed by Terraform** (user-data.sh on EC2 startup)

Terraform automatically installs:
- `python3`, `git`, `docker`
- `kubectl`, `helm`
- `mlflow`, `boto3`
- `libicu` (required for .NET 6.0 runner)

No manual installation needed. If deploying fresh EC2, dependencies are installed automatically.

## Step 4: Install pre-push hooks
```bash
bash scripts/install-git-hooks.sh
```

## Step 5: Test
Add data, commit, push main.
Check that branch data/YYYYMMDD-HHMMSS is created and pushed.

## Notes
No local AWS credentials are required for data branch creation (CI does merge and upload).

## Automation Summary

**What Terraform does automatically** (user-data.sh):
- ✅ Installs all system dependencies (docker, python3, git, kubectl, helm, mlflow, boto3, libicu)
- ✅ Configures kubeconfig at `/home/ec2-user/.kube/config`
- ✅ Sets up MLflow systemd service
- ✅ Enables k3s cluster

**What requires manual setup per fresh EC2 instance**:
- ❌ GitHub runner token registration (Step 1-2) — token expires after 1 hour, so it cannot be stored in Terraform for security reasons
- ❌ Running `./config.sh` with token (Step 2) — one-time per instance, then runs automatically on boot

**Fresh EC2 instance?**
If you terminate and redeploy EC2: Go to GitHub Settings → Actions → Runners → Create new token, then repeat Step 1-2.
