#!/usr/bin/env python3
"""Build a deterministic HTML index for current Godot runtime review artifacts."""
from __future__ import annotations

import argparse
import html
import json
import os
import struct
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "factory" / "runtime"
DEFAULT_OUT_DIR = RUNTIME / "godot_review_index"

SECTIONS: list[dict[str, Any]] = [
    {
        "title": "Plain Gray Landform Readability",
        "question": "Do the gray terrain views read as broad contiguous landforms without obvious chunk seams or block artifacts?",
        "files": [
            "factory/runtime/godot_rendered_preview/preview_gray.png",
            "factory/runtime/godot_streaming_preview/streaming_settled_gray.png",
            "factory/runtime/godot_streaming_review/streaming_review_contact_sheet.png",
            "factory/runtime/godot_landform_quality/landform_quality_contact_sheet.png",
            "factory/runtime/godot_landform_quality/landform_quality_report.json",
            "factory/runtime/godot_landform_profiles/landform_profile_contact_sheet.png",
            "factory/runtime/godot_landform_profiles/landform_profile_report.json",
        ],
    },
    {
        "title": "Scale And Mesh Density",
        "question": "Do the wide and close 65-vertex review frames show useful extra shape without stepping or scale confusion?",
        "files": [
            "factory/runtime/godot_streaming_scale_review/streaming_scale_review_contact_sheet.png",
            "factory/runtime/godot_streaming_scale_review/streaming_scale_review_manifest.json",
            "factory/runtime/godot_walk_density_review/walk_density_contact_sheet.png",
            "factory/runtime/godot_walk_density_review/walk_density_manifest.json",
            "factory/runtime/godot_walk_density_review/walk_density_129_4m.png",
            "factory/runtime/godot_walk_density_review/walk_density_257_2m.png",
        ],
    },
    {
        "title": "Hydrology Debug Readability",
        "question": "Do wetness and channel hints generally follow valleys/divides, and do tile boundaries stay visually coherent?",
        "files": [
            "factory/runtime/godot_rendered_preview/preview_hydrology.png",
            "factory/runtime/godot_hydrology_hints/hydrology_hint_contact_sheet.png",
            "factory/runtime/godot_hydrology_hints/hydrology_hint_report.json",
            "factory/runtime/godot_hydrology_hints/hydrology_consistency_report.json",
            "factory/runtime/godot_hydrology_tiles/hydrology_tile_boundary_contact_sheet.png",
            "factory/runtime/godot_hydrology_tiles/hydrology_tile_cache_report.json",
        ],
    },
    {
        "title": "Far Clipmap Review",
        "question": "Do far rings improve horizon readability without holes, obvious level bands, or distracting material differences?",
        "files": [
            "factory/runtime/godot_far_clipmap/far_clipmap_gray.png",
            "factory/runtime/godot_far_clipmap/far_clipmap_surface_material.png",
            "factory/runtime/godot_far_clipmap/far_clipmap_levels.png",
            "factory/runtime/godot_far_clipmap/far_clipmap_4ring_wide.png",
            "factory/runtime/godot_streaming_far_overview/streaming_far_overview_contact_sheet.png",
            "factory/runtime/godot_streaming_far_overview/streaming_far_overview_manifest.json",
            "factory/runtime/godot_streaming_far_overview/streaming_far_overview_3ring.png",
            "factory/runtime/godot_streaming_far_overview/streaming_far_overview_4ring.png",
        ],
    },
    {
        "title": "Local Detail And Displacement Review",
        "question": "Do local height/normal/displacement previews add detail without spikes, edge cracks, or misleading collision expectations?",
        "files": [
            "factory/runtime/godot_local_detail_displacement/local_detail_base.png",
            "factory/runtime/godot_local_detail_displacement/local_detail_texture_material.png",
            "factory/runtime/godot_local_detail_displacement/local_detail_displacement.png",
            "factory/runtime/godot_local_detail_displacement/local_detail_displacement_manifest.json",
            "factory/runtime/godot_walk_local_detail_review/walk_local_detail_contact_sheet.png",
            "factory/runtime/godot_walk_local_detail_review/walk_local_detail_manifest.json",
        ],
    },
]


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def html_href(path: Path, out_dir: Path) -> str:
    return Path(os.path.relpath(path, out_dir)).as_posix()


def png_size(path: Path) -> tuple[int, int] | None:
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) < 24:
        return None
    if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        return None
    width, height = struct.unpack(">II", header[16:24])
    return int(width), int(height)


def file_record(rel_path: str, out_dir: Path) -> dict[str, Any]:
    path = ROOT / rel_path
    record: dict[str, Any] = {
        "path": rel_path,
        "exists": path.exists(),
    }
    if not path.exists():
        return record
    record["bytes"] = path.stat().st_size
    record["href"] = html_href(path, out_dir)
    if path.suffix.lower() == ".png":
        size = png_size(path)
        if size is not None:
            record["width"] = size[0]
            record["height"] = size[1]
    return record


def build_manifest(out_dir: Path) -> dict[str, Any]:
    sections = []
    errors = []
    for section in SECTIONS:
        files = [file_record(str(path), out_dir) for path in section["files"]]
        for record in files:
            if not record["exists"]:
                errors.append("missing:%s" % record["path"])
        sections.append({
            "title": section["title"],
            "question": section["question"],
            "files": files,
        })
    return {
        "version": 1,
        "schema": "worldgen9.godot_review_index.v1",
        "root": ROOT.as_posix(),
        "sections": sections,
        "errors": errors,
        "status": "pass" if not errors else "fail",
    }


def render_html(manifest: dict[str, Any]) -> str:
    parts: list[str] = [
        "<!doctype html>",
        '<html lang="en">',
        "<head>",
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        "<title>WorldGen9 Godot Review Index</title>",
        "<style>",
        "body{margin:0;font:14px/1.45 system-ui,Segoe UI,Arial,sans-serif;background:#111;color:#e8e8e8}",
        "main{max-width:1400px;margin:0 auto;padding:24px}",
        "h1{font-size:24px;margin:0 0 8px} h2{font-size:18px;margin:28px 0 6px}",
        ".meta,.question{color:#b8b8b8;margin:0 0 14px}",
        ".grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:14px}",
        ".card{background:#1b1b1b;border:1px solid #343434;border-radius:6px;padding:10px}",
        ".card img{display:block;width:100%;height:auto;background:#050505;border-radius:4px}",
        ".path{font-family:Consolas,monospace;font-size:12px;color:#cfcfcf;word-break:break-all;margin-top:8px}",
        ".detail{color:#999;font-size:12px;margin-top:3px}",
        ".missing{border-color:#8f3b3b;background:#2a1717}",
        "a{color:#8fd0ff;text-decoration:none} a:hover{text-decoration:underline}",
        "</style>",
        "</head>",
        "<body><main>",
        "<h1>WorldGen9 Godot Review Index</h1>",
        '<p class="meta">Deterministic index of current runtime visual artifacts. Generated without timestamps so it can be locked by the runtime artifact manifest.</p>',
    ]
    for section in manifest["sections"]:
        parts.append("<section>")
        parts.append("<h2>%s</h2>" % html.escape(str(section["title"])))
        parts.append('<p class="question">%s</p>' % html.escape(str(section["question"])))
        parts.append('<div class="grid">')
        for file_info in section["files"]:
            exists = bool(file_info["exists"])
            card_class = "card" if exists else "card missing"
            parts.append('<article class="%s">' % card_class)
            path_text = html.escape(str(file_info["path"]))
            if exists and str(file_info["path"]).lower().endswith(".png"):
                href = html.escape(str(file_info["href"]))
                parts.append('<a href="%s"><img src="%s" alt="%s"></a>' % (href, href, path_text))
            elif exists:
                href = html.escape(str(file_info["href"]))
                parts.append('<a href="%s">%s</a>' % (href, path_text))
            else:
                parts.append("Missing artifact")
            parts.append('<div class="path">%s</div>' % path_text)
            if exists:
                detail = ["%d bytes" % int(file_info["bytes"])]
                if "width" in file_info and "height" in file_info:
                    detail.append("%dx%d" % (int(file_info["width"]), int(file_info["height"])))
                parts.append('<div class="detail">%s</div>' % html.escape(" | ".join(detail)))
            parts.append("</article>")
        parts.append("</div></section>")
    parts.append("</main></body></html>")
    return "\n".join(parts) + "\n"


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--verify", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    out_dir = Path(args.out_dir)
    manifest = build_manifest(out_dir)
    if args.verify:
        print("[godot-review-index] status=%s errors=%d" % (manifest["status"], len(manifest["errors"])))
        for error in manifest["errors"]:
            print("[godot-review-index] error: %s" % error)
        return 0 if manifest["status"] == "pass" else 1

    out_dir.mkdir(parents=True, exist_ok=True)
    write_text(out_dir / "review_index_manifest.json", json.dumps(manifest, indent=2))
    write_text(out_dir / "index.html", render_html(manifest))
    print("[godot-review-index] status=%s sections=%d out=%s" % (
        manifest["status"],
        len(manifest["sections"]),
        (out_dir / "index.html").as_posix(),
    ))
    for error in manifest["errors"]:
        print("[godot-review-index] error: %s" % error)
    return 0 if manifest["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
