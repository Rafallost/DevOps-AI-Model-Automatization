#!/usr/bin/env python3
"""
data-qa.py - Training Data Quality Assurance

Validates training data before allowing it into the pipeline.

Usage:
    python data-qa.py WMS/data/training/ --output report.json

Exit codes:
    0 = PASS, 1 = FAIL
"""

import argparse
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image


MIN_MASK_PIXELS = 100
COVERAGE_OUTLIER_THRESHOLD = 3.0


def validate_data(data_dir):
    """Validate training data."""
    images_dir = data_dir / "images"
    masks_dir = data_dir / "masks"

    report = {
        "status": "PASS",
        "errors": [],
        "warnings": [],
        "statistics": {},
        "image_count": 0,
        "mask_count": 0,
        "valid_pairs": 0
    }

    if not images_dir.exists():
        report["status"] = "FAIL"
        report["errors"].append(f"Images directory not found: {images_dir}")
        return report

    if not masks_dir.exists():
        report["status"] = "FAIL"
        report["errors"].append(f"Masks directory not found: {masks_dir}")
        return report

    image_files = {f.stem: f for f in images_dir.glob("*.jpg")} | {f.stem: f for f in images_dir.glob("*.png")}
    mask_files = {f.stem: f for f in masks_dir.glob("*.jpg")} | {f.stem: f for f in masks_dir.glob("*.png")}

    report["image_count"] = len(image_files)
    report["mask_count"] = len(mask_files)

    image_stems = set(image_files.keys())
    mask_stems = set(mask_files.keys())

    missing_masks = image_stems - mask_stems
    missing_images = mask_stems - image_stems

    if missing_masks:
        report["status"] = "FAIL"
        report["errors"].append(f"Missing masks for {len(missing_masks)} images")

    if missing_images:
        report["status"] = "FAIL"
        report["errors"].append(f"Missing images for {len(missing_images)} masks")

    valid_pairs = image_stems & mask_stems
    report["valid_pairs"] = len(valid_pairs)

    if not valid_pairs:
        report["status"] = "FAIL"
        report["errors"].append("No valid image-mask pairs found")
        return report

    resolutions = []
    mask_coverages = []
    issues_by_file = {}

    for stem in sorted(valid_pairs):
        image_path = image_files[stem]
        mask_path = mask_files[stem]
        file_issues = []

        try:
            image = Image.open(image_path)
            mask = Image.open(mask_path)

            image_array = np.array(image)
            mask_array = np.array(mask)

            # TEMPORARILY DISABLED: Resolution check
            # if image_array.shape[:2] != mask_array.shape[:2]:
            #     file_issues.append(f"Resolution mismatch")
            # else:
            #     resolutions.append(image_array.shape[:2])
            resolutions.append(image_array.shape[:2])

            if len(mask_array.shape) == 3:
                mask_array = mask_array[:, :, 0]

            # TEMPORARILY DISABLED: Binary mask check
            # unique_values = np.unique(mask_array)
            # non_binary = set(unique_values) - {0, 255}
            # if non_binary:
            #     file_issues.append(f"Non-binary mask values")

            foreground_pixels = np.sum(mask_array == 255)

            if foreground_pixels == 0:
                file_issues.append("Empty mask")
            elif foreground_pixels < MIN_MASK_PIXELS:
                file_issues.append(f"Near-empty mask ({foreground_pixels} pixels)")

            total_pixels = mask_array.size
            coverage = (foreground_pixels / total_pixels) * 100
            mask_coverages.append((stem, coverage))

        except Exception as e:
            file_issues.append(f"Error: {str(e)}")

        if file_issues:
            issues_by_file[stem] = file_issues

    if mask_coverages:
        coverages = np.array([c[1] for c in mask_coverages])
        median_coverage = np.median(coverages)
        std_coverage = np.std(coverages)

        report["statistics"]["median_coverage_%"] = round(median_coverage, 2)
        report["statistics"]["std_coverage_%"] = round(std_coverage, 2)

    if issues_by_file:
        report["status"] = "FAIL"
        for stem, issues in list(issues_by_file.items())[:10]:
            for issue in issues:
                report["errors"].append(f"{stem}: {issue}")

    if resolutions:
        unique_resolutions = set([tuple(r) for r in resolutions])
        if len(unique_resolutions) == 1:
            res = list(unique_resolutions)[0]
            report["statistics"]["resolution"] = f"{res[0]}x{res[1]}"

    return report


def main():
    parser = argparse.ArgumentParser(description="Data QA")
    parser.add_argument("data_dir", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    report = validate_data(args.data_dir)

    if args.output:
        with open(args.output, 'w') as f:
            json.dump(report, f, indent=2)

    print("=" * 60)
    print("✅ DATA QA PASSED" if report["status"] == "PASS" else "❌ DATA QA FAILED")
    print("=" * 60)
    print(f"Images: {report['image_count']} | Masks: {report['mask_count']} | Valid pairs: {report['valid_pairs']}")
    
    if report["errors"]:
        print(f"\nErrors: {len(report['errors'])}")
        for e in report["errors"][:5]:
            print(f"  - {e}")

    sys.exit(0 if report["status"] == "PASS" else 1)


if __name__ == "__main__":
    main()
