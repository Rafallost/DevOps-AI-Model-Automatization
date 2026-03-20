# Training Data Management

## Goal

This document explains how training data (images + masks) is managed in the project. Data is handled by DVC and an automated Git hook workflow.

## Data structure

- Raw files: WMS/data/training/images/, WMS/data/training/masks/
- DVC metadata: WMS/data/training/images.dvc, WMS/data/training/masks.dvc

## Setup

1. Install: git, dvc, aws, python3.
2. Optionally configure AWS CLI for local AWS operations.
3. Install pre-push hook: bash scripts/install-git-hooks.sh.

## How pre-push hook works (real logic)

The hook in scripts/install-git-hooks.sh does:

1. Reads pushed refs and intercepts pushes to main.
2. Detects new raw image/mask files in WMS/data/training/....
3. If raw files appear, it creates timestamped branch data/YYYYMMDD-HHMMSS.
4. Commits the files there and pushes the data branch.
5. Blocks the original push to main (returns non-zero).

Below successful run example:
![Hook](/DevOps-AI-Model-Automatization/Thesis/img/05_pipline_ci_cd/hook.png)

## Adding new training data (recommended flow)

1. Copy images to WMS/data/training/images/ (.jpg/.jpeg/.png).
2. Copy masks to WMS/data/training/masks/ (.png).
3. Ensure matching names: id_01.jpg ? id_01.png.
4. git add WMS/data/training/images/ WMS/data/training/masks/
5. git commit -m data: add new training data
6. git push origin main

Then the hook creates and pushes data branch automatically.

## CI flow after branch creation

On data branch, GitHub Actions pipeline:

1. Downloads existing S3 dataset and new files.
2. Executes scripts/data-qa.py.
3. If QA passes, creates PR and trains model.
4. If quality gate passes, promotes model to Production.

## Validation script

data-qa.py checks:

- image-mask pairing,
- at least one valid pair,
- non-empty mask pixels,
- resolution and coverage stats.

## Troubleshooting

- Use git status, dvc status, dvc diff.
- If push is blocked, fix files and push again.
- Confirm hook is installed in .git/hooks/pre-push.
