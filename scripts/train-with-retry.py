#!/usr/bin/env python3
"""
Training wrapper with retry logic. Each attempt uses a different random seed.

Usage:
    python train-with-retry.py --config WMS/configs/train.yaml --max-retries 3

Calls train.py internally, runs quality-gate.py after each attempt.
Writes training-report.json with all attempt results.

Assumes CWD is the Working-repo root (the layout CI uses).
train.py is expected to accept --config and --seed flags and to write
WMS/models/metrics.json on success (added in Phase 3).
"""

import argparse
import json
import os
import subprocess
import sys
import time

# Paths relative to Working-repo root (CWD in CI / local run)
TRAIN_SCRIPT = "WMS/src/train.py"
METRICS_FILE = "WMS/models/metrics.json"
REPORT_FILE = "training-report.json"

# quality-gate.py lives in the same directory as this script
QUALITY_GATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "quality-gate.py")

BASE_SEED = 42  # seeds: 42, 43, 44, …


def run_training(config_path, seed):
    """Execute train.py for one attempt.

    Returns:
        (exit_code, metrics_dict | None)
    """
    # Remove stale metrics.json so we can detect a fresh write
    if os.path.exists(METRICS_FILE):
        os.remove(METRICS_FILE)

    cmd = [sys.executable, TRAIN_SCRIPT, "--config", config_path, "--seed", str(seed)]
    print(f"  cmd: {' '.join(cmd)}")

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)

    # Read metrics produced by train.py (Phase 3 adds this)
    metrics = None
    if os.path.exists(METRICS_FILE):
        with open(METRICS_FILE) as fh:
            metrics = json.load(fh)

    return result.returncode, metrics


def run_quality_gate(report_path, baseline_dice, baseline_iou, tolerance):
    """Run quality-gate.py and return its exit code."""
    cmd = [
        sys.executable, QUALITY_GATE,
        "--report", report_path,
        "--baseline-dice", str(baseline_dice),
        "--baseline-iou", str(baseline_iou),
        "--tolerance", str(tolerance),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    return result.returncode


def main():
    # Ensure unicode output works on Windows consoles (no-op on Linux/CI)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser(description="Training with automatic retry")
    parser.add_argument("--config", required=True, help="Path to train.yaml")
    parser.add_argument("--max-retries", type=int, default=3,
                        help="Maximum number of training attempts")
    parser.add_argument("--baseline-dice", type=float, default=0.9275)
    parser.add_argument("--baseline-iou", type=float, default=0.8865)
    parser.add_argument("--tolerance", type=float, default=0.02)
    args = parser.parse_args()

    report = {
        "started_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "status": "FAIL",
        "attempts": [],
    }

    for n in range(1, args.max_retries + 1):
        seed = BASE_SEED + n - 1  # 42, 43, 44

        print(f"\n{'=' * 60}")
        print(f"  Attempt {n}/{args.max_retries}  (seed={seed})")
        print("=" * 60)

        exit_code, metrics = run_training(args.config, seed)

        report["attempts"].append({
            "attempt": n,
            "seed": seed,
            "exit_code": exit_code,
            "metrics": metrics or {},
        })

        # Persist after every attempt — quality-gate reads the file
        with open(REPORT_FILE, "w") as fh:
            json.dump(report, fh, indent=2)

        if exit_code != 0:
            tail = "retrying…" if n < args.max_retries else "no retries left."
            print(f"  Training exited with code {exit_code} — {tail}")
            continue

        if not metrics:
            print("  WARNING: metrics.json not produced by train.py — skipping quality gate")
            continue

        gate_rc = run_quality_gate(
            REPORT_FILE, args.baseline_dice, args.baseline_iou, args.tolerance
        )
        if gate_rc == 0:
            report["status"] = "PASS"
            report["best_attempt"] = n
            with open(REPORT_FILE, "w") as fh:
                json.dump(report, fh, indent=2)
            print(f"\nQuality gate PASSED on attempt {n}.")
            sys.exit(0)

        tail = "retrying…" if n < args.max_retries else "no retries left."
        print(f"  Quality gate FAILED — {tail}")

    # All attempts exhausted
    with open(REPORT_FILE, "w") as fh:
        json.dump(report, fh, indent=2)
    print(f"\nAll {args.max_retries} attempts exhausted. Report saved to {REPORT_FILE}")
    sys.exit(1)


if __name__ == "__main__":
    main()
