# DevOps Scripts

Repository scripts for infrastructure, deployment, and model operations.

## Main scripts

- deploy-to-cloud.sh: provisioning with Terraform and EC2 setup.
- stop-cloud.sh: destroy infrastructure.
- cleanup-aws.sh: remove AWS resources.
- setup-k3s.sh: install k3s and Helm.
- setup-mlflow.sh: install and start MLflow.
- cerify-deployment.sh: run verification checks.
- install-git-hooks.sh: install pre-push hook.
- cleanup-old-deployments.sh: remove old model-\* namespaces.
- cleanup-s3-dvc.sh: cleanup orphaned DVC objects from S3.
- data-qa.py: validate image-mask dataset.
- get-baseline-metrics.py: fetch Production baseline metrics.
- promote-model.py: promote model to Production.
- update-model-metadata.py: update model-metadata.json.

## How to use

1. Bash scripts/install-git-hooks.sh
2. Add new training data, commit, and push main.
3. CI will run validation and training from data/\* branch.

## Notes

    rain-with-retry.py and quality-gate.py are legacy reference scripts.
