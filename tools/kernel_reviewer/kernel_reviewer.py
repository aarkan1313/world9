#!/usr/bin/env python3
"""Click-through kernel review utility for WorldGen9.

Shows one kernel preview at a time and records Yes/No/Maybe decisions. Decisions
are written after every click so the review can be stopped and resumed.
"""
from __future__ import annotations

import argparse
import json
import math
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import tkinter as tk
from tkinter import ttk

from PIL import Image, ImageTk


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOG = ROOT / "factory" / "catalog" / "accepted_kernel_catalog.json"
DEFAULT_REVIEW_DIR = ROOT / "factory" / "reviews"
DEFAULT_STATE = DEFAULT_REVIEW_DIR / "kernel_review_state.json"


@dataclass
class ReviewPaths:
    catalog: Path
    state: Path
    review_dir: Path

    @property
    def yes_catalog(self) -> Path:
        return self.review_dir / "user_shortlist_kernel_catalog.json"

    @property
    def no_catalog(self) -> Path:
        return self.review_dir / "user_rejected_kernel_catalog.json"

    @property
    def maybe_catalog(self) -> Path:
        return self.review_dir / "user_review_queue_kernel_catalog.json"


def read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def kernel_preview_path(kernel: dict[str, Any]) -> Path | None:
    artifacts = kernel.get("artifacts", {})
    for key in ("preview_height_png", "preview_slope_png", "preview_residual_png"):
        value = artifacts.get(key)
        if value and Path(value).exists():
            return Path(value)
    value = kernel.get("preview_height_png")
    if value and Path(value).exists():
        return Path(value)
    return None


def load_catalog(path: Path) -> list[dict[str, Any]]:
    data = read_json(path, {})
    kernels = data.get("kernels")
    if not isinstance(kernels, list):
        raise RuntimeError("catalog has no kernels list: %s" % path)
    return kernels


def sort_kernels(kernels: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(
        kernels,
        key=lambda k: (
            str(k.get("terrain_family", "uncategorized")),
            str(k.get("kernel_id", "")),
        ),
    )


class KernelReviewer:
    def __init__(self, root: tk.Tk, kernels: list[dict[str, Any]], paths: ReviewPaths) -> None:
        self.root = root
        self.paths = paths
        self.kernels = kernels
        self.by_id = {str(k["kernel_id"]): k for k in kernels}
        self.state = self.load_state()
        self.index = self.find_resume_index()
        self.photo: ImageTk.PhotoImage | None = None
        self.zoom = 1.0
        self.preview_mode = tk.StringVar(value="height")
        self.status_filter = tk.StringVar(value="unreviewed")
        self.family_filter = tk.StringVar(value="all")

        self.root.title("WorldGen9 Kernel Reviewer")
        self.root.geometry("1180x860")
        self.root.minsize(900, 680)
        self.build_ui()
        self.refresh()

    def load_state(self) -> dict[str, Any]:
        state = read_json(self.paths.state, {})
        decisions = state.get("decisions")
        if not isinstance(decisions, dict):
            decisions = {}
        return {
            "version": 1,
            "catalog": str(self.paths.catalog).replace("\\", "/"),
            "current_kernel_id": state.get("current_kernel_id"),
            "decisions": decisions,
        }

    def build_ui(self) -> None:
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(1, weight=1)

        top = ttk.Frame(self.root, padding=8)
        top.grid(row=0, column=0, sticky="ew")
        top.columnconfigure(9, weight=1)

        ttk.Label(top, text="Family").grid(row=0, column=0, padx=(0, 4))
        families = ["all"] + sorted({str(k.get("terrain_family", "uncategorized")) for k in self.kernels})
        self.family_combo = ttk.Combobox(top, textvariable=self.family_filter, values=families, width=16, state="readonly")
        self.family_combo.grid(row=0, column=1, padx=(0, 12))
        self.family_combo.bind("<<ComboboxSelected>>", lambda _e: self.jump_to_filtered())

        ttk.Label(top, text="Show").grid(row=0, column=2, padx=(0, 4))
        self.status_combo = ttk.Combobox(
            top,
            textvariable=self.status_filter,
            values=["unreviewed", "all", "yes", "no", "maybe"],
            width=12,
            state="readonly",
        )
        self.status_combo.grid(row=0, column=3, padx=(0, 12))
        self.status_combo.bind("<<ComboboxSelected>>", lambda _e: self.jump_to_filtered())

        ttk.Label(top, text="Preview").grid(row=0, column=4, padx=(0, 4))
        self.preview_combo = ttk.Combobox(
            top,
            textvariable=self.preview_mode,
            values=["height", "slope", "residual"],
            width=10,
            state="readonly",
        )
        self.preview_combo.grid(row=0, column=5, padx=(0, 12))
        self.preview_combo.bind("<<ComboboxSelected>>", lambda _e: self.refresh())

        ttk.Button(top, text="Prev", command=self.prev_kernel).grid(row=0, column=6, padx=2)
        ttk.Button(top, text="Next", command=self.next_kernel).grid(row=0, column=7, padx=2)
        ttk.Button(top, text="Open Folder", command=self.open_current_folder).grid(row=0, column=8, padx=(12, 2))

        self.progress_label = ttk.Label(top, text="")
        self.progress_label.grid(row=0, column=9, sticky="e")

        main = ttk.Frame(self.root, padding=(8, 0, 8, 8))
        main.grid(row=1, column=0, sticky="nsew")
        main.columnconfigure(0, weight=1)
        main.rowconfigure(0, weight=1)

        self.image_label = ttk.Label(main, anchor="center")
        self.image_label.grid(row=0, column=0, sticky="nsew")

        side = ttk.Frame(main, padding=(10, 0, 0, 0), width=320)
        side.grid(row=0, column=1, sticky="ns")
        side.grid_propagate(False)

        self.meta_text = tk.Text(side, width=42, height=28, wrap="word")
        self.meta_text.grid(row=0, column=0, sticky="nsew")
        self.meta_text.configure(state="disabled")

        buttons = ttk.Frame(side)
        buttons.grid(row=1, column=0, pady=(10, 0), sticky="ew")
        for i in range(3):
            buttons.columnconfigure(i, weight=1)
        ttk.Button(buttons, text="Yes", command=lambda: self.decide("yes")).grid(row=0, column=0, sticky="ew", padx=2)
        ttk.Button(buttons, text="Maybe", command=lambda: self.decide("maybe")).grid(row=0, column=1, sticky="ew", padx=2)
        ttk.Button(buttons, text="No", command=lambda: self.decide("no")).grid(row=0, column=2, sticky="ew", padx=2)

        buttons2 = ttk.Frame(side)
        buttons2.grid(row=2, column=0, pady=(8, 0), sticky="ew")
        for i in range(3):
            buttons2.columnconfigure(i, weight=1)
        ttk.Button(buttons2, text="Undo", command=self.undo_current).grid(row=0, column=0, sticky="ew", padx=2)
        ttk.Button(buttons2, text="Export", command=self.save_outputs).grid(row=0, column=1, sticky="ew", padx=2)
        ttk.Button(buttons2, text="Quit", command=self.root.destroy).grid(row=0, column=2, sticky="ew", padx=2)

        self.root.bind("<Left>", lambda _e: self.prev_kernel())
        self.root.bind("<Right>", lambda _e: self.next_kernel())
        self.root.bind("<y>", lambda _e: self.decide("yes"))
        self.root.bind("<Y>", lambda _e: self.decide("yes"))
        self.root.bind("<n>", lambda _e: self.decide("no"))
        self.root.bind("<N>", lambda _e: self.decide("no"))
        self.root.bind("<m>", lambda _e: self.decide("maybe"))
        self.root.bind("<M>", lambda _e: self.decide("maybe"))
        self.root.bind("<space>", lambda _e: self.next_kernel())

    def current(self) -> dict[str, Any]:
        return self.kernels[self.index]

    def decision_for(self, kernel: dict[str, Any]) -> str | None:
        decision = self.state["decisions"].get(str(kernel["kernel_id"]))
        if isinstance(decision, dict):
            value = decision.get("decision")
            return str(value) if value else None
        return None

    def kernel_matches_filter(self, kernel: dict[str, Any]) -> bool:
        family = self.family_filter.get()
        status = self.status_filter.get()
        if family != "all" and str(kernel.get("terrain_family", "uncategorized")) != family:
            return False
        decision = self.decision_for(kernel)
        if status == "unreviewed":
            return decision is None
        if status == "all":
            return True
        return decision == status

    def find_resume_index(self) -> int:
        current_id = self.state.get("current_kernel_id")
        if current_id:
            for i, kernel in enumerate(self.kernels):
                if kernel.get("kernel_id") == current_id:
                    return i
        for i, kernel in enumerate(self.kernels):
            if str(kernel["kernel_id"]) not in self.state["decisions"]:
                return i
        return 0

    def jump_to_filtered(self) -> None:
        for i, kernel in enumerate(self.kernels):
            if self.kernel_matches_filter(kernel):
                self.index = i
                self.refresh()
                return
        self.refresh()

    def find_next(self, direction: int) -> int:
        total = len(self.kernels)
        for step in range(1, total + 1):
            idx = (self.index + direction * step) % total
            if self.kernel_matches_filter(self.kernels[idx]):
                return idx
        return self.index

    def next_kernel(self) -> None:
        self.index = self.find_next(1)
        self.refresh()

    def prev_kernel(self) -> None:
        self.index = self.find_next(-1)
        self.refresh()

    def preview_path_for_mode(self, kernel: dict[str, Any]) -> Path | None:
        artifacts = kernel.get("artifacts", {})
        mode_key = {
            "height": "preview_height_png",
            "slope": "preview_slope_png",
            "residual": "preview_residual_png",
        }.get(self.preview_mode.get(), "preview_height_png")
        value = artifacts.get(mode_key)
        if value and Path(value).exists():
            return Path(value)
        return kernel_preview_path(kernel)

    def refresh_image(self, kernel: dict[str, Any]) -> None:
        path = self.preview_path_for_mode(kernel)
        if not path:
            self.image_label.configure(image="", text="No preview image")
            self.photo = None
            return
        image = Image.open(path).convert("RGB")
        max_w = max(320, self.root.winfo_width() - 390)
        max_h = max(320, self.root.winfo_height() - 110)
        scale = min(max_w / image.width, max_h / image.height)
        scale = min(scale, 3.0)
        size = (max(1, int(image.width * scale)), max(1, int(image.height * scale)))
        image = image.resize(size, Image.Resampling.BILINEAR)
        self.photo = ImageTk.PhotoImage(image)
        self.image_label.configure(image=self.photo, text="")

    def refresh_meta(self, kernel: dict[str, Any]) -> None:
        decision = self.decision_for(kernel) or "unreviewed"
        lines = [
            "Decision: %s" % decision.upper(),
            "",
            "ID:",
            str(kernel.get("kernel_id")),
            "",
            "Family: %s" % kernel.get("terrain_family"),
            "Quality: %.3f" % float(kernel.get("quality_score", 0.0)),
            "Coverage: %.3f" % float(kernel.get("coverage_fraction", 0.0)),
            "Height range: %.1f m" % float(kernel.get("height_range_m", 0.0)),
            "Mean slope: %.2f deg" % float(kernel.get("mean_slope_deg", 0.0)),
            "Slope p95: %.2f deg" % float(kernel.get("slope_p95_deg", 0.0)),
            "Roughness: %.2f" % float(kernel.get("roughness_residual_std_m", 0.0)),
            "",
            "Source:",
            str(kernel.get("source_dem_path")),
            "",
            "Keys:",
            "Y = yes, N = no, M = maybe",
            "Left/Right = move",
            "Space = next",
        ]
        self.meta_text.configure(state="normal")
        self.meta_text.delete("1.0", "end")
        self.meta_text.insert("1.0", "\n".join(lines))
        self.meta_text.configure(state="disabled")

    def refresh_progress(self) -> None:
        counts = {"yes": 0, "no": 0, "maybe": 0}
        for decision in self.state["decisions"].values():
            if isinstance(decision, dict) and decision.get("decision") in counts:
                counts[decision["decision"]] += 1
        reviewed = sum(counts.values())
        text = "%d/%d  yes=%d maybe=%d no=%d" % (
            reviewed,
            len(self.kernels),
            counts["yes"],
            counts["maybe"],
            counts["no"],
        )
        self.progress_label.configure(text=text)

    def refresh(self) -> None:
        kernel = self.current()
        self.state["current_kernel_id"] = str(kernel["kernel_id"])
        self.save_state_only()
        self.refresh_image(kernel)
        self.refresh_meta(kernel)
        self.refresh_progress()

    def decide(self, value: str) -> None:
        kernel = self.current()
        self.state["decisions"][str(kernel["kernel_id"])] = {
            "decision": value,
            "kernel_id": str(kernel["kernel_id"]),
            "terrain_family": str(kernel.get("terrain_family", "uncategorized")),
        }
        self.save_outputs()
        self.next_kernel()

    def undo_current(self) -> None:
        kernel_id = str(self.current()["kernel_id"])
        self.state["decisions"].pop(kernel_id, None)
        self.save_outputs()
        self.refresh()

    def save_state_only(self) -> None:
        write_json(self.paths.state, self.state)

    def make_catalog_for(self, decision_value: str) -> dict[str, Any]:
        selected = []
        for kernel in self.kernels:
            decision = self.state["decisions"].get(str(kernel["kernel_id"]))
            if isinstance(decision, dict) and decision.get("decision") == decision_value:
                selected.append(kernel)
        return {
            "version": 1,
            "source_catalog": str(self.paths.catalog).replace("\\", "/"),
            "decision": decision_value,
            "kernel_count": len(selected),
            "kernels": selected,
        }

    def save_outputs(self) -> None:
        self.save_state_only()
        write_json(self.paths.yes_catalog, self.make_catalog_for("yes"))
        write_json(self.paths.no_catalog, self.make_catalog_for("no"))
        write_json(self.paths.maybe_catalog, self.make_catalog_for("maybe"))
        self.refresh_progress()

    def open_current_folder(self) -> None:
        kernel = self.current()
        preview = kernel_preview_path(kernel)
        if preview:
            folder = str(preview.parent)
            os.startfile(folder)  # type: ignore[attr-defined]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    parser.add_argument("--state", default=str(DEFAULT_STATE))
    parser.add_argument("--check", action="store_true", help="Validate catalog loading and exit without opening the GUI")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    catalog = Path(args.catalog)
    state = Path(args.state)
    paths = ReviewPaths(catalog=catalog, state=state, review_dir=state.parent)
    kernels = sort_kernels(load_catalog(catalog))
    if args.check:
        preview_count = sum(1 for kernel in kernels if kernel_preview_path(kernel))
        print("catalog=%s" % catalog)
        print("kernels=%d" % len(kernels))
        print("previews=%d" % preview_count)
        return 0 if kernels and preview_count == len(kernels) else 1
    root = tk.Tk()
    KernelReviewer(root, kernels, paths)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
