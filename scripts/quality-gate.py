#!/usr/bin/env python3
"""
quality-gate.py - Model Quality Gate

⚠️  DEPRECATED / UNUSED ⚠️
This script is NOT used in the current CI/CD pipeline.
Quality gate logic is implemented inline in .github/workflows/train.yml
with dynamic baseline from MLflow Production model.

This file is kept for reference only.

---

Compares new model metrics with baseline thresholds.

Usage:
    python quality-gate.py \
        --dice 0.9301 \
        --iou 0.8890 \
        --baseline-dice 0.9275 \
        --baseline-iou 0.8865 \
        --tolerance 0.02

Exit codes:
    0 = PASS (metrics meet or exceed threshold)
    1 = FAIL (metrics below threshold)
"""

import argparse
import json
import sys


def quality_gate(
    current_dice, current_iou,
    baseline_dice, baseline_iou,
    tolerance
):
    """
    Check if current metrics meet quality gate.
    
    Returns:
        dict with pass/fail status and details
    """
    threshold_dice = baseline_dice - tolerance
    threshold_iou = baseline_iou - tolerance

    dice_pass = current_dice >= threshold_dice
    iou_pass = current_iou >= threshold_iou

    passed = dice_pass and iou_pass
    # Improved = BOTH metrics better than baseline (strict improvement)
    improved = current_dice > baseline_dice and current_iou > baseline_iou
    
    result = {
        "passed": passed,
        "improved": improved,
        "metrics": {
            "current": {
                "dice": current_dice,
                "iou": current_iou
            },
            "baseline": {
                "dice": baseline_dice,
                "iou": baseline_iou
            },
            "threshold": {
                "dice": threshold_dice,
                "iou": threshold_iou
            }
        },
        "checks": {
            "dice": {
                "current": current_dice,
                "threshold": threshold_dice,
                "passed": dice_pass,
                "delta": current_dice - baseline_dice
            },
            "iou": {
                "current": current_iou,
                "threshold": threshold_iou,
                "passed": iou_pass,
                "delta": current_iou - baseline_iou
            }
        }
    }
    
    return result


def format_result(result):
    """Format result as human-readable text."""
    lines = []
    lines.append("=" * 60)
    
    if result["passed"]:
        status = "✅ QUALITY GATE PASSED"
        if result["improved"]:
            status += " (IMPROVED)"
    else:
        status = "❌ QUALITY GATE FAILED"
    
    lines.append(status)
    lines.append("=" * 60)
    lines.append("")
    
    lines.append("Metrics Comparison:")
    lines.append("")
    lines.append(f"{'Metric':<10} {'Current':<10} {'Baseline':<10} {'Threshold':<10} {'Status':<10}")
    lines.append("-" * 60)
    
    for metric in ["dice", "iou"]:
        check = result["checks"][metric]
        status_icon = "✅" if check["passed"] else "❌"
        delta_pct = (check["delta"] / result["metrics"]["baseline"][metric]) * 100
        
        lines.append(
            f"{metric.upper():<10} "
            f"{check['current']:<10.4f} "
            f"{result['metrics']['baseline'][metric]:<10.4f} "
            f"{check['threshold']:<10.4f} "
            f"{status_icon} ({delta_pct:+.2f}%)"
        )
    
    lines.append("")
    
    if result["passed"]:
        if result["improved"]:
            lines.append("🚀 Model improved over baseline - ready for deployment")
        else:
            lines.append("✅ Model meets minimum quality - ready for deployment")
    else:
        lines.append("⚠️  Model below threshold - training failed quality gate")
    
    lines.append("=" * 60)
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Model quality gate")
    parser.add_argument("--dice", type=float, required=True, help="Current Dice score")
    parser.add_argument("--iou", type=float, required=True, help="Current IoU score")
    parser.add_argument("--baseline-dice", type=float, required=True, help="Baseline Dice (fetch from MLflow Production model)")
    parser.add_argument("--baseline-iou", type=float, required=True, help="Baseline IoU (fetch from MLflow Production model)")
    parser.add_argument("--tolerance", type=float, default=0.0, help="Acceptable degradation (0.0 = strict improvement required)")
    parser.add_argument("--output", type=str, help="Output JSON file")
    
    args = parser.parse_args()
    
    result = quality_gate(
        args.dice, args.iou,
        args.baseline_dice, args.baseline_iou,
        args.tolerance
    )
    
    # Save JSON
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(result, f, indent=2)
    
    # Print report
    print()
    print(format_result(result))
    
    sys.exit(0 if result["passed"] else 1)


if __name__ == "__main__":
    main()
