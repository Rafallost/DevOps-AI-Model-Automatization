#!/usr/bin/env python3
"""
Compares new model metrics with baseline.

Usage:
    python quality-gate.py --report training-report.json \
        --baseline-dice 0.9275 --baseline-iou 0.8865 --tolerance 0.02

Exit codes: 0 = PASS (model >= baseline - tolerance), 1 = FAIL

The script reads training-report.json (written by train-with-retry.py), picks the
attempt with the highest val_dice, and checks both val_dice and val_iou against
the baseline minus the configured tolerance.
"""

import argparse
import json
import sys


def main():
    # Ensure unicode output works on Windows consoles (no-op on Linux/CI)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser(description="Quality gate — metrics vs baseline")
    parser.add_argument("--report", required=True, help="Path to training-report.json")
    parser.add_argument("--baseline-dice", type=float, default=0.9275,
                        help="Baseline Dice score (from reference model)")
    parser.add_argument("--baseline-iou", type=float, default=0.8865,
                        help="Baseline IoU score (from reference model)")
    parser.add_argument("--tolerance", type=float, default=0.02,
                        help="Allowed drop below baseline before FAIL")
    args = parser.parse_args()

    with open(args.report) as fh:
        report = json.load(fh)

    attempts = report.get("attempts", [])
    if not attempts:
        print("Quality Gate: FAIL — no attempts in report")
        sys.exit(1)

    # Pick the attempt with the best val_dice
    best = max(attempts, key=lambda a: a.get("metrics", {}).get("val_dice", 0.0))
    metrics = best.get("metrics", {})
    val_dice = metrics.get("val_dice", 0.0)
    val_iou = metrics.get("val_iou", 0.0)

    min_dice = args.baseline_dice - args.tolerance
    min_iou = args.baseline_iou - args.tolerance

    dice_ok = val_dice >= min_dice
    iou_ok = val_iou >= min_iou
    passed = dice_ok and iou_ok

    print("Quality Gate:", "PASS" if passed else "FAIL")
    print(f"  Dice: {val_dice:.4f}  (>= {min_dice:.4f})  {'✓' if dice_ok else '✗'}")
    print(f"  IoU:  {val_iou:.4f}  (>= {min_iou:.4f})  {'✓' if iou_ok else '✗'}")
    print(f"  (attempt {best.get('attempt', '?')}, seed {best.get('seed', '?')})")

    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
