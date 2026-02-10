#!/usr/bin/env python3
"""
Promote a model to Production stage in MLflow Model Registry.

Usage:
    python devops/scripts/promote-model.py --run-id <run_id> [--stage Production]

This script:
1. Creates a new model version from the specified run
2. Transitions it to the specified stage (default: Production)
3. Archives existing versions in that stage
"""

import argparse
import os
import sys

import mlflow
from mlflow.tracking import MlflowClient


def promote_model(run_id, model_name="water-meter-segmentation", stage="Production"):
    """
    Promote a model to Production stage.

    Args:
        run_id: MLflow run ID containing the model
        model_name: Name of the registered model
        stage: Target stage (default: Production)

    Returns:
        dict: Model version information
    """
    client = MlflowClient()

    try:
        # Create new model version
        print(f"Creating model version from run: {run_id}")
        model_version = client.create_model_version(
            name=model_name, source=f"runs:/{run_id}/model", run_id=run_id
        )

        print(f"✅ Created model version: {model_version.version}")

        # Transition to target stage
        print(f"Transitioning to {stage} stage...")
        client.transition_model_version_stage(
            name=model_name,
            version=model_version.version,
            stage=stage,
            archive_existing_versions=True,  # Auto-archive old versions
        )

        print(f"✅ Model version {model_version.version} promoted to {stage}!")

        return {
            "model_name": model_name,
            "version": model_version.version,
            "stage": stage,
            "run_id": run_id,
        }

    except Exception as e:
        print(f"❌ Error promoting model: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Promote model to Production")
    parser.add_argument("--run-id", required=True, help="MLflow run ID")
    parser.add_argument(
        "--model-name",
        default="water-meter-segmentation",
        help="Model name in registry",
    )
    parser.add_argument(
        "--stage", default="Production", help="Target stage (default: Production)"
    )
    parser.add_argument(
        "--mlflow-uri",
        default=os.environ.get("MLFLOW_TRACKING_URI", "http://localhost:5000"),
        help="MLflow tracking URI",
    )

    args = parser.parse_args()

    # Set MLflow tracking URI
    mlflow.set_tracking_uri(args.mlflow_uri)

    # Promote model
    result = promote_model(args.run_id, args.model_name, args.stage)

    print("\n" + "=" * 50)
    print("PROMOTION COMPLETE")
    print("=" * 50)
    print(f"Model: {result['model_name']}")
    print(f"Version: {result['version']}")
    print(f"Stage: {result['stage']}")
    print(f"Run ID: {result['run_id']}")
    print("=" * 50)


if __name__ == "__main__":
    main()
