# CLAUDE.md — Project Context for AI Assistants

## Most important rules

1. The project description is in `DevOps-AI-Model-Automatization/README.md`.
2. Do the job in small steps and verify that each step is correct and aligned with the assumptions.
3. Create working, simple code (avoid unnecessary complexity).
4. Keep the core system flow described below.
5. Code inserts in the plan.md file are more of an illustrative idea and a starting point than a sacred law
6. **Implementation phases, ordering, and priorities are defined in `PLAN.md` and take precedence over any phase descriptions here.**

## Core System Flow

**This is the heart of the project.** Everything we build serves this flow:

```
USER uploads data → DATA QA → [FAIL: error message]
                           → [PASS: proceed to PR-based workflow]
                                    ↓
                              TRAINING (up to 3 attempts)
                                    ↓
                              QUALITY GATE (metrics + smoke tests)
                                    ↓
                    [WORSE after 3 tries: reject PR with comment]
                    [BETTER: approve + merge → BUILD → DEPLOY]
```

> This file provides context for AI assistants (Claude, Copilot, etc.) working on this project.
> Read this file completely before starting any work.

---

## Project Overview

**Project Title:** "Application of DevOps Techniques in Implementing Automatic CI/CD Process for Training and Versioning AI Models"

**Type:** Bachelor's Thesis (Engineering Degree)

**Goal:** Compare manual vs. automated ML model deployment, demonstrating DevOps benefits for AI/ML workflows.

**Budget Constraint:** ~$50 USD total on AWS (one-time project — build, test, document, tear down)

---

## Repository Architecture

This project uses **three repositories** connected via **Git submodules**:

```
┌──────────────────────────────────────────┐
│  Water-Meters-Segmentation-Automatization│  ◄── WORKING REPO (main)
│  github.com/Rafallost/...                │
├──────────────────────────────────────────┤
│  • ML code (WMS/)                        │
│  • Training data (DVC tracked)           │
│  • GitHub Actions workflows              │
│  • devops/ ← SUBMODULE                   │
└───────────────┬──────────────────────────┘
                │ git submodule
                ▼
┌─────────────────────────────────────────┐
│  DevOps-AI-Model-Automatization         │  ◄── THIS REPO (infrastructure)
│  github.com/Rafallost/...               │
├─────────────────────────────────────────┤
│  • Terraform modules                    │
│  • Helm charts                          │
│  • Automation scripts                   │
│  • Documentation & diagrams             │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  Water-Meters-Segmentation              │  ◄── REFERENCE (read-only)
│  github.com/Rafallost/...               │
├─────────────────────────────────────────┤
│  • Original U-Net model                 │
│  • Baseline: Dice 0.9275, IoU 0.8865    │
│  • DO NOT MODIFY                        │
└─────────────────────────────────────────┘
```

### Which repository am I in?

- **DevOps-AI-Model-Automatization** (this repo): infrastructure, Terraform, Helm, scripts, documentation
- **Water-Meters-Segmentation-Automatization**: ML code, training data, workflows, project-specific configs
- **Water-Meters-Segmentation**: reference only — baseline metrics source

---

## Core Flow — Detailed Steps

1. **User provides new training data** (images + masks to `WMS/data/training/`).
2. **Data QA validates automatically:**
   - Image↔mask pairs match
   - Resolutions are correct (512×512)
   - Masks are binary (0/255)
   - **FAIL:** PR comment with error list, label `invalid-data`
   - **PASS:** PR comment confirming data is OK, proceed to training

   > Note: Automatic branch/PR creation is optional and depends on GitHub Actions permissions. The supported default path is a user-created PR.

3. **Training runs (up to 3 attempts):**
   - Each attempt uses a different random seed
   - Logs to MLflow (metrics, model artifacts)
   - Model version = `{git_sha}-{data_version}`

4. **Quality Gate compares results to baseline:**
   - Metric thresholds (2% tolerance): Dice ≥ 0.9075, IoU ≥ 0.8665
   - **Smoke tests required:** `/health`, `/predict`, `/metrics`
   - **PASS:** approve PR, ready for merge
   - **FAIL:** retry with a different seed (up to 3 attempts total)
   - **FAIL after 3 attempts:** reject PR with a detailed comment

5. **After merge to `main`:**
   - Tag model version
   - Promote model in MLflow (e.g. `Production` stage)
   - Build Docker image → push to ECR
   - Helm deploy to k3s → smoke test

6. **Monitoring:** Prometheus + Grafana dashboards (run during testing only)

---

## Model Storage & Versioning

- MLflow is the **single source of truth** for all trained models.
- Models are **not** stored in Git or DVC.
- Deployment pulls models from MLflow by version or stage (e.g. `Production`).
- `WMS/models/` is strictly for local development and is gitignored.

---

## Important Constraints

### Budget constraints (CRITICAL)

- Total AWS budget: ~$50
- **DO NOT** use: EKS, RDS, NAT Gateway, Load Balancer
- **DO** use: k3s on EC2, SQLite, public subnet, NodePort
- Always run `cleanup-aws.sh` after testing

### Data paths

- Correct: `WMS/data/training/images/` and `WMS/data/training/masks/`
- Wrong: `WMS/data/raw/` (does not exist)

### Submodule usage

```bash
# Clone with submodule
git clone --recurse-submodules <repo-url>

# If already cloned without submodule
git submodule update --init --recursive

# Update submodule to latest
cd devops && git pull origin main && cd ..
git add devops && git commit -m "chore: update devops submodule"
```

---

## Documentation & Writing Guidelines

- Treat `PLAN.md` as the **authoritative implementation roadmap**.
- Write detailed documentation **after the system is working**, as defined in Phase 9 of the plan.
- Use an academic tone suitable for an engineering thesis.
- Prefer Mermaid diagrams for architecture and flow visualization.

---

## Contact & Resources

- **Thesis Supervisor:** [Name]
- **Original Model Repo:** github.com/Rafallost/Water-Meters-Segmentation
- **Working Repo:** github.com/Rafallost/Water-Meters-Segmentation-Automatization
- **This Repo:** github.com/Rafallost/DevOps-AI-Model-Automatization
