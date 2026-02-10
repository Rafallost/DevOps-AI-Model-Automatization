#!/usr/bin/env python3
"""
Update model-metadata.json file with new model information.

Usage:
    python devops/scripts/update-model-metadata.py \
        --dice 0.9234 --iou 0.8765 --version abc123 \
        [--run-id <run_id>] [--data-count 49]
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path


def update_metadata(dice, iou, version, run_id=None, data_count=None, metadata_file="model-metadata.json"):
    """
    Update model metadata file.

    Args:
        dice: Dice coefficient score
        iou: IoU score
        version: Model version (git commit hash)
        run_id: MLflow run ID (optional)
        data_count: Number of training images (optional)
        metadata_file: Path to metadata file
    """
    metadata_path = Path(metadata_file)

    # Load existing metadata if it exists
    if metadata_path.exists():
        with open(metadata_path) as f:
            metadata = json.load(f)
    else:
        metadata = {}

    # Update with new values
    metadata.update({
        "model_version": version,
        "metrics": {
            "dice": float(dice),
            "iou": float(iou)
        },
        "trained_at": datetime.utcnow().isoformat() + "Z",
    })

    if run_id:
        metadata["run_id"] = run_id

    if data_count:
        metadata["training_data_count"] = int(data_count)

    # Write back to file
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)

    print(f"✅ Updated {metadata_file}")
    print(json.dumps(metadata, indent=2))


def main():
    parser = argparse.ArgumentParser(description="Update model metadata file")
    parser.add_argument("--dice", type=float, required=True, help="Dice coefficient")
    parser.add_argument("--iou", type=float, required=True, help="IoU score")
    parser.add_argument("--version", required=True, help="Model version (git SHA)")
    parser.add_argument("--run-id", help="MLflow run ID")
    parser.add_argument("--data-count", type=int, help="Number of training images")
    parser.add_argument(
        "--file",
        default="model-metadata.json",
        help="Path to metadata file (default: model-metadata.json)",
    )

    args = parser.parse_args()

    try:
        update_metadata(
            dice=args.dice,
            iou=args.iou,
            version=args.version,
            run_id=args.run_id,
            data_count=args.data_count,
            metadata_file=args.file,
        )
    except Exception as e:
        print(f"❌ Error updating metadata: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
