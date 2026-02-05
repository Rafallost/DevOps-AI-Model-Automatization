#!/usr/bin/env python3
"""
Training data validation.
Checks: image↔mask pair matching, resolutions, file formats, mask binarity,
        near-empty masks, coverage/centroid outliers,
        JPG compression artefacts in masks (non-binary pixel values after load).

Usage:
    python data-qa.py WMS/data/training/ --output report.json

Exit codes: 0 = PASS, 1 = FAIL
Output: JSON report with errors list + statistics

Notes:
- Masks should be PNG. JPG compression introduces non-binary values even for
  visually binary images; flag any mask with pixels outside {0, 255} after load.
- A mask with fewer than MIN_MASK_PIXELS (default 100) foreground pixels is
  treated as effectively empty and reported as an error.
- Coverage outliers are detected by comparing each mask's foreground area and
  centroid to the dataset median; masks far outside the expected range are flagged.
"""

import argparse
import json
import os
import sys

import cv2
import numpy as np

MIN_MASK_PIXELS = 100
OUTLIER_MAD_FACTOR = 3.0  # threshold = median ± factor × MAD


# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------

def check_pairs(images_dir, masks_dir):
    """Return (errors, set of filenames present in both directories)."""
    img_files = {f for f in os.listdir(images_dir) if not f.startswith(".")}
    mask_files = {f for f in os.listdir(masks_dir) if not f.startswith(".")}

    errors = []
    orphan_imgs = img_files - mask_files
    orphan_masks = mask_files - img_files
    if orphan_imgs:
        errors.append(f"Images without matching masks: {sorted(orphan_imgs)}")
    if orphan_masks:
        errors.append(f"Masks without matching images: {sorted(orphan_masks)}")

    return errors, img_files & mask_files


def check_resolutions(images_dir, masks_dir, pairs):
    """Each image and its corresponding mask must share spatial dimensions."""
    errors = []
    for fname in sorted(pairs):
        img = cv2.imread(os.path.join(images_dir, fname))
        mask = cv2.imread(os.path.join(masks_dir, fname), cv2.IMREAD_GRAYSCALE)
        if img is None:
            errors.append(f"{fname}: failed to load image")
            continue
        if mask is None:
            errors.append(f"{fname}: failed to load mask")
            continue
        if img.shape[:2] != mask.shape:
            errors.append(
                f"{fname}: resolution mismatch — "
                f"image {img.shape[1]}x{img.shape[0]}, "
                f"mask {mask.shape[1]}x{mask.shape[0]}"
            )
    return errors


def check_formats(pairs):
    """Warn when masks use JPEG (compression artifacts break binarity)."""
    warnings = []
    jpg_exts = {".jpg", ".jpeg"}
    for fname in sorted(pairs):
        if os.path.splitext(fname)[1].lower() in jpg_exts:
            warnings.append(
                f"{fname}: mask is JPEG — compression can introduce "
                "non-binary pixel values; PNG is strongly preferred"
            )
    return warnings


def check_mask_binarity(masks_dir, pairs):
    """Masks must contain only pixel values 0 and 255."""
    errors = []
    for fname in sorted(pairs):
        mask = cv2.imread(os.path.join(masks_dir, fname), cv2.IMREAD_GRAYSCALE)
        if mask is None:
            continue
        unique = set(int(v) for v in np.unique(mask))
        bad = unique - {0, 255}
        if bad:
            errors.append(
                f"{fname}: non-binary pixel values {sorted(bad)} "
                "(likely JPEG compression artefacts)"
            )
    return errors


def check_near_empty(masks_dir, pairs):
    """Flag masks whose foreground pixel count is below the minimum threshold."""
    errors = []
    for fname in sorted(pairs):
        mask = cv2.imread(os.path.join(masks_dir, fname), cv2.IMREAD_GRAYSCALE)
        if mask is None:
            continue
        fg = int(np.sum(mask >= 127))
        if fg < MIN_MASK_PIXELS:
            errors.append(
                f"{fname}: near-empty mask — {fg} foreground pixels "
                f"(minimum {MIN_MASK_PIXELS})"
            )
    return errors


def check_outliers(masks_dir, pairs):
    """Detect coverage and centroid outliers using MAD-based thresholds."""
    # Collect per-mask statistics
    stats = {}
    for fname in sorted(pairs):
        mask = cv2.imread(os.path.join(masks_dir, fname), cv2.IMREAD_GRAYSCALE)
        if mask is None:
            continue
        binary = (mask >= 127).astype(np.uint8)
        fg = int(np.sum(binary))
        coverage = fg / binary.size
        if fg > 0:
            ys, xs = np.where(binary)
            cx = float(np.mean(xs)) / mask.shape[1]  # normalised [0, 1]
            cy = float(np.mean(ys)) / mask.shape[0]
        else:
            cx, cy = 0.5, 0.5
        stats[fname] = {"coverage": coverage, "cx": cx, "cy": cy}

    warnings = []
    if len(stats) < 3:
        return warnings  # not enough samples

    # Coverage outliers
    cov_arr = np.array([s["coverage"] for s in stats.values()])
    med_cov = float(np.median(cov_arr))
    mad_cov = float(np.median(np.abs(cov_arr - med_cov)))
    thresh_cov = OUTLIER_MAD_FACTOR * mad_cov if mad_cov > 0 else 0.1

    for fname, s in stats.items():
        if abs(s["coverage"] - med_cov) > thresh_cov:
            warnings.append(
                f"{fname}: coverage outlier "
                f"({s['coverage']:.3f} vs median {med_cov:.3f})"
            )

    # Centroid outliers
    cx_arr = np.array([s["cx"] for s in stats.values()])
    cy_arr = np.array([s["cy"] for s in stats.values()])
    med_cx, med_cy = float(np.median(cx_arr)), float(np.median(cy_arr))
    mad_cx = float(np.median(np.abs(cx_arr - med_cx)))
    mad_cy = float(np.median(np.abs(cy_arr - med_cy)))
    thresh_cx = OUTLIER_MAD_FACTOR * mad_cx if mad_cx > 0 else 0.3
    thresh_cy = OUTLIER_MAD_FACTOR * mad_cy if mad_cy > 0 else 0.3

    for fname, s in stats.items():
        if abs(s["cx"] - med_cx) > thresh_cx or abs(s["cy"] - med_cy) > thresh_cy:
            warnings.append(
                f"{fname}: centroid outlier "
                f"(({s['cx']:.2f},{s['cy']:.2f}) vs median ({med_cx:.2f},{med_cy:.2f}))"
            )

    return warnings


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    # Ensure unicode output works on Windows consoles (no-op on Linux/CI)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser(description="Training data QA validation")
    parser.add_argument("data_dir", help="Training data root (must contain images/ and masks/)")
    parser.add_argument("--output", default="report.json", help="JSON report output path")
    args = parser.parse_args()

    images_dir = os.path.join(args.data_dir, "images")
    masks_dir = os.path.join(args.data_dir, "masks")

    for path, label in [(images_dir, "images"), (masks_dir, "masks")]:
        if not os.path.isdir(path):
            print(f"ERROR: {label} directory not found: {path}")
            sys.exit(1)

    # --- run checks -----------------------------------------------------------
    errors, pairs = check_pairs(images_dir, masks_dir)

    if not pairs:
        report = {
            "status": "FAIL",
            "errors": errors,
            "warnings": [],
            "statistics": {"total_pairs": 0, "total_errors": len(errors), "total_warnings": 0},
        }
        with open(args.output, "w") as fh:
            json.dump(report, fh, indent=2)
        print("Data QA: FAIL — no valid image-mask pairs")
        sys.exit(1)

    errors.extend(check_resolutions(images_dir, masks_dir, pairs))
    errors.extend(check_mask_binarity(masks_dir, pairs))
    errors.extend(check_near_empty(masks_dir, pairs))

    warnings = check_formats(pairs)
    warnings.extend(check_outliers(masks_dir, pairs))

    # --- write report ---------------------------------------------------------
    status = "PASS" if not errors else "FAIL"
    report = {
        "status": status,
        "errors": errors,
        "warnings": warnings,
        "statistics": {
            "total_pairs": len(pairs),
            "total_errors": len(errors),
            "total_warnings": len(warnings),
        },
    }

    with open(args.output, "w") as fh:
        json.dump(report, fh, indent=2)

    # --- human-readable summary -----------------------------------------------
    print(f"Data QA: {status}")
    print(f"  Pairs: {len(pairs)} | Errors: {len(errors)} | Warnings: {len(warnings)}")
    for e in errors:
        print(f"  ✗ {e}")
    for w in warnings:
        print(f"  ⚠ {w}")

    sys.exit(0 if status == "PASS" else 1)


if __name__ == "__main__":
    main()
