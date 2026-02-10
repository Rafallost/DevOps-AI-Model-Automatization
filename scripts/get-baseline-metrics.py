#!/usr/bin/env python3
"""
Get baseline metrics from Production model in MLflow Model Registry.

Usage:
    python devops/scripts/get-baseline-metrics.py [--mlflow-uri URI]

Returns:
    JSON with baseline metrics (Dice, IoU) from Production model
    Exit code 0 if found, 1 if no Production model exists
"""

import argparse
import json
import os
import sys

import mlflow
from mlflow.tracking import MlflowClient


def get_baseline_metrics(mlflow_uri=None):
    """
    Get baseline metrics from Production model.

    Returns:
        dict: Baseline metrics (dice, iou) or None if no Production model
    """
    if mlflow_uri:
        mlflow.set_tracking_uri(mlflow_uri)

    client = MlflowClient()

    try:
        # Get Production model from registry
        prod_versions = client.get_latest_versions(
            "water-meter-segmentation", stages=["Production"]
        )

        if not prod_versions:
            return None

        prod_version = prod_versions[0]

        # Get the run that created this model
        prod_run = client.get_run(prod_version.run_id)
        metrics = prod_run.data.metrics

        # Extract metrics with fallback chain
        baseline_dice = (
            metrics.get("final_test_dice")
            or metrics.get("test_dice")
            or metrics.get("val_dice", 0)
        )
        baseline_iou = (
            metrics.get("final_test_iou")
            or metrics.get("test_iou")
            or metrics.get("val_iou", 0)
        )

        return {
            "dice": baseline_dice,
            "iou": baseline_iou,
            "model_version": prod_version.version,
            "run_id": prod_version.run_id,
        }

    except Exception as e:
        print(f"Error fetching Production model: {e}", file=sys.stderr)
        return None


def main():
    parser = argparse.ArgumentParser(
        description="Get baseline metrics from Production model"
    )
    parser.add_argument(
        "--mlflow-uri",
        default=os.environ.get("MLFLOW_TRACKING_URI", "http://localhost:5000"),
        help="MLflow tracking URI",
    )
    parser.add_argument(
        "--output",
        choices=["json", "simple"],
        default="json",
        help="Output format",
    )

    args = parser.parse_args()

    baseline = get_baseline_metrics(args.mlflow_uri)

    if baseline is None:
        if args.output == "json":
            print(
                json.dumps(
                    {
                        "status": "no_baseline",
                        "message": "No Production model found",
                        "baseline": {"dice": 0.0, "iou": 0.0},
                    }
                )
            )
        else:
            print("0.0")  # Simple output for scripts
        sys.exit(1)

    if args.output == "json":
        print(json.dumps({"status": "success", "baseline": baseline}, indent=2))
    else:
        # Simple output: just the Dice score
        print(f"{baseline['dice']}")

    sys.exit(0)


if __name__ == "__main__":
    main()
