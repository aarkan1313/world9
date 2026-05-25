#!/usr/bin/env python3
"""Build a safe visual-review queue for expanding the runtime kernel pack.

This combines the tagged accepted catalog, duplicate-candidate report, and the
current promoted pack. It does not promote anything automatically. It creates a
small review queue that avoids known overlaps with already-promoted kernels and
keeps unresolved/low-confidence kernels out of the expansion path.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TAGGED = ROOT / "factory" / "catalog" / "accepted_kernel_catalog_tagged.json"
DEFAULT_DUPLICATES = ROOT / "factory" / "catalog" / "kernel_duplicate_candidates.json"
DEFAULT_PROMOTED = ROOT / "factory" / "catalog" / "promoted_kernel_catalog.json"
DEFAULT_OUT = ROOT / "factory" / "catalog" / "kernel_expansion_review_queue.json"
DEFAULT_CATALOG_OUT = ROOT / "factory" / "catalog" / "kernel_expansion_review_queue_catalog.json"
DEFAULT_SHEET = ROOT / "factory" / "catalog" / "expansion_review" / "expansion_queue_contact_sheet.png"

TARGET_FAMILIES = (
    "mountain",
    "glacial",
    "badlands",
    "desert",
    "karst",
    "coast",
    "grassland",
    "rainforest",
    "volcanic",
)

HOLD_FAMILIES = {"wetland", "temperate", "tundra", "uncategorized"}
AUTO_HOLD_TAGS = {"bathymetry_or_ocean_context", "coast_or_ocean_context_candidate"}


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def duplicate_graph(report: dict[str, Any]) -> dict[str, set[str]]:
    graph: dict[str, set[str]] = {}
    for candidate in report.get("candidates", []):
        a = candidate.get("kernel_a")
        b = candidate.get("kernel_b")
        if not isinstance(a, str) or not isinstance(b, str):
            continue
        graph.setdefault(a, set()).add(b)
        graph.setdefault(b, set()).add(a)
    return graph


def normalized(value: float, limit: float) -> float:
    return max(0.0, min(1.0, value / max(1e-6, limit)))


def score_kernel(kernel: dict[str, Any], duplicate_count: int) -> float:
    confidence = float(kernel.get("family_confidence", 0.0) or 0.0)
    quality = float(kernel.get("quality_score", 0.0) or 0.0)
    height_range = float(kernel.get("height_range_m", 0.0) or 0.0)
    slope_p95 = float(kernel.get("slope_p95_deg", 0.0) or 0.0)
    roughness = float(kernel.get("roughness_residual_std_m", 0.0) or 0.0)
    duplicate_penalty = min(0.35, duplicate_count * 0.035)
    return (
        confidence * 0.35
        + quality * 0.25
        + normalized(height_range, 3500.0) * 0.18
        + normalized(slope_p95, 45.0) * 0.12
        + normalized(roughness, 220.0) * 0.10
        - duplicate_penalty
    )


def manual_hold_ids(promoted: dict[str, Any]) -> set[str]:
    held = promoted.get("excluded_or_held", {})
    if not isinstance(held, dict):
        return set()
    return {key for key in held if "__" in key}


def is_candidate(kernel: dict[str, Any], min_confidence: float) -> bool:
    family = str(kernel.get("inferred_family", kernel.get("terrain_family", "uncategorized")))
    if family in HOLD_FAMILIES:
        return False
    if family not in TARGET_FAMILIES:
        return False
    if str(kernel.get("tag_status", "")) == "unresolved":
        return False
    if float(kernel.get("family_confidence", 0.0) or 0.0) < min_confidence:
        return False
    tags = set(kernel.get("terrain_tags", []))
    if tags & AUTO_HOLD_TAGS:
        return False
    if "polar_dem_product" in tags and str(kernel.get("tag_status", "")) != "retained":
        return False
    artifacts = kernel.get("artifacts", {})
    preview = artifacts.get("preview_height_png") if isinstance(artifacts, dict) else None
    return bool(preview and Path(str(preview)).exists())


def make_contact_sheet(queue: list[dict[str, Any]], output_path: Path) -> None:
    if not queue:
        return
    thumb_w = 180
    thumb_h = 180
    label_h = 48
    cols = 6
    rows = int(math.ceil(len(queue) / cols))
    sheet = Image.new("RGB", (cols * thumb_w, rows * (thumb_h + label_h)), (22, 24, 24))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("arial.ttf", 12)
    except Exception:
        font = ImageFont.load_default()
    for index, item in enumerate(queue):
        artifacts = item.get("artifacts", {})
        preview = artifacts.get("preview_height_png")
        if not preview:
            continue
        image = Image.open(preview).convert("L").resize((thumb_w, thumb_h), Image.Resampling.BILINEAR).convert("RGB")
        x = (index % cols) * thumb_w
        y = (index // cols) * (thumb_h + label_h)
        sheet.paste(image, (x, y))
        draw.rectangle((x, y + thumb_h, x + thumb_w, y + thumb_h + label_h), fill=(18, 18, 18))
        label = "%s  %.2f" % (item.get("inferred_family", "?"), float(item.get("expansion_score", 0.0)))
        draw.text((x + 6, y + thumb_h + 5), label, fill=(232, 232, 232), font=font)
        short_id = str(item.get("kernel_id", "unknown")).split("__", 1)[-1][:25]
        draw.text((x + 6, y + thumb_h + 23), short_id, fill=(200, 200, 200), font=font)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path)


def build_queue(
    tagged_catalog: dict[str, Any],
    duplicates: dict[str, Any],
    promoted: dict[str, Any],
    per_family: int,
    min_confidence: float,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    promoted_ids = {kernel.get("kernel_id") for kernel in promoted.get("kernels", [])}
    manual_holds = manual_hold_ids(promoted)
    graph = duplicate_graph(duplicates)
    kernels = tagged_catalog.get("kernels", [])
    by_family: dict[str, list[dict[str, Any]]] = {family: [] for family in TARGET_FAMILIES}
    held: dict[str, int] = {
        "already_promoted": 0,
        "manual_hold": 0,
        "duplicate_with_promoted": 0,
        "low_confidence_or_unresolved": 0,
        "held_family": 0,
    }

    for kernel in kernels:
        kernel_id = kernel.get("kernel_id")
        family = str(kernel.get("inferred_family", kernel.get("terrain_family", "uncategorized")))
        if kernel_id in promoted_ids:
            held["already_promoted"] += 1
            continue
        if kernel_id in manual_holds:
            held["manual_hold"] += 1
            continue
        if family in HOLD_FAMILIES or family not in TARGET_FAMILIES:
            held["held_family"] += 1
            continue
        if not is_candidate(kernel, min_confidence):
            held["low_confidence_or_unresolved"] += 1
            continue
        if graph.get(str(kernel_id), set()) & promoted_ids:
            held["duplicate_with_promoted"] += 1
            continue
        item = {
            **kernel,
            "expansion_score": score_kernel(kernel, len(graph.get(str(kernel_id), set()))),
            "duplicate_candidate_count": len(graph.get(str(kernel_id), set())),
            "expansion_status": "review_candidate",
        }
        by_family.setdefault(family, []).append(item)

    selected: list[dict[str, Any]] = []
    selected_ids: set[str] = set()
    for family in TARGET_FAMILIES:
        family_items = sorted(by_family.get(family, []), key=lambda k: float(k["expansion_score"]), reverse=True)
        family_selected = 0
        for item in family_items:
            kernel_id = str(item["kernel_id"])
            if graph.get(kernel_id, set()) & selected_ids:
                continue
            selected.append(item)
            selected_ids.add(kernel_id)
            family_selected += 1
            if family_selected >= per_family:
                break

    summary: dict[str, Any] = {
        "target_families": list(TARGET_FAMILIES),
        "per_family_target": per_family,
        "min_confidence": min_confidence,
        "selected_count": len(selected),
        "held_counts": held,
        "selected_by_family": {},
        "available_by_family": {},
    }
    for family in TARGET_FAMILIES:
        summary["available_by_family"][family] = len(by_family.get(family, []))
        summary["selected_by_family"][family] = sum(1 for item in selected if item.get("inferred_family") == family)
    return selected, summary


def slim_catalog(queue: list[dict[str, Any]], source_catalog: str) -> dict[str, Any]:
    return {
        "version": 1,
        "status": "expansion_review_queue",
        "source_catalog": source_catalog,
        "kernel_count": len(queue),
        "selection_policy": "Metadata-only next-review queue. Not promoted. Excludes unresolved, held families, current promoted kernels, and duplicate candidates overlapping promoted/selected kernels.",
        "kernels": queue,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tagged-catalog", default=str(DEFAULT_TAGGED))
    parser.add_argument("--duplicates", default=str(DEFAULT_DUPLICATES))
    parser.add_argument("--promoted", default=str(DEFAULT_PROMOTED))
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--catalog-out", default=str(DEFAULT_CATALOG_OUT))
    parser.add_argument("--contact-sheet", default=str(DEFAULT_SHEET))
    parser.add_argument("--per-family", type=int, default=8)
    parser.add_argument("--min-confidence", type=float, default=0.45)
    parser.add_argument("--no-contact-sheet", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    tagged = read_json(Path(args.tagged_catalog))
    duplicates = read_json(Path(args.duplicates))
    promoted = read_json(Path(args.promoted))
    queue, summary = build_queue(tagged, duplicates, promoted, int(args.per_family), float(args.min_confidence))
    report = {
        "version": 1,
        "schema": "worldgen9.kernel_expansion_review_queue.v1",
        "inputs": {
            "tagged_catalog": str(args.tagged_catalog).replace("\\", "/"),
            "duplicates": str(args.duplicates).replace("\\", "/"),
            "promoted": str(args.promoted).replace("\\", "/"),
        },
        "summary": summary,
        "queue": [
            {
                "kernel_id": item["kernel_id"],
                "inferred_family": item["inferred_family"],
                "family_confidence": item["family_confidence"],
                "expansion_score": item["expansion_score"],
                "duplicate_candidate_count": item["duplicate_candidate_count"],
                "tags": item.get("terrain_tags", []),
                "height_range_m": item.get("height_range_m"),
                "slope_p95_deg": item.get("slope_p95_deg"),
                "preview_height_png": item.get("artifacts", {}).get("preview_height_png"),
            }
            for item in queue
        ],
    }
    if not args.dry_run:
        write_json(Path(args.out), report)
        write_json(Path(args.catalog_out), slim_catalog(queue, str(args.tagged_catalog).replace("\\", "/")))
        if not args.no_contact_sheet:
            make_contact_sheet(queue, Path(args.contact_sheet))
    print("[expansion-queue] selected=%d by_family=%s" % (len(queue), summary["selected_by_family"]))
    print("[expansion-queue] held=%s" % summary["held_counts"])
    if not args.dry_run:
        print("[expansion-queue] out=%s" % args.out)
        print("[expansion-queue] catalog=%s" % args.catalog_out)
        if not args.no_contact_sheet:
            print("[expansion-queue] contact_sheet=%s" % args.contact_sheet)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
