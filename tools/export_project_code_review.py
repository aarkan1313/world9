#!/usr/bin/env python3
"""Export the WorldGen9 review surface into a single Markdown file.

The exporter is intentionally conservative: it includes source, scene, config,
tooling, and planning files, while skipping DEM data, Godot caches, Rust build
outputs, native binaries, generated artifacts, and large binary assets.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


DEFAULT_ROOT = Path(r"D:\workflows\worldgen9")
DEFAULT_OUT = DEFAULT_ROOT / "review_exports" / "world9_project_code_review.md"

TEXT_EXTENSIONS = {
    ".gd",
    ".tscn",
    ".tres",
    ".gdextension",
    ".godot",
    ".rs",
    ".toml",
    ".lock",
    ".py",
    ".ps1",
    ".md",
    ".txt",
    ".json",
    ".csv",
    ".yml",
    ".yaml",
    ".ini",
    ".cfg",
    ".schema",
    ".svg",
}

BINARY_EXTENSIONS = {
    ".dll",
    ".pdb",
    ".lib",
    ".exp",
    ".exe",
    ".rlib",
    ".rmeta",
    ".pyc",
    ".pyo",
    ".npy",
    ".npz",
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
    ".tif",
    ".tiff",
    ".zip",
    ".7z",
    ".rar",
    ".blend",
    ".import",
    ".uid",
}

SKIP_DIR_NAMES = {
    ".git",
    ".godot",
    "__pycache__",
    "target",
    "bin",
    "dems",
    "factory",
    "review_exports",
}

DEFAULT_INCLUDE_DIRS = (
    "wg-9-directory",
    "native",
    "tools",
    "plans",
    "prototypes",
)


@dataclass(frozen=True)
class ExportFile:
    path: Path
    rel: str
    size_bytes: int
    line_count: int
    text: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compile WorldGen9 source/config/plans into one Markdown review bundle."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=DEFAULT_ROOT,
        help=f"Project root. Default: {DEFAULT_ROOT}",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT,
        help=f"Markdown output path. Default: {DEFAULT_OUT}",
    )
    parser.add_argument(
        "--max-file-kib",
        type=int,
        default=512,
        help="Skip individual files larger than this size. Default: 512 KiB.",
    )
    parser.add_argument(
        "--no-plans",
        action="store_true",
        help="Exclude planning/spec documents from the export.",
    )
    parser.add_argument(
        "--include-generated",
        action="store_true",
        help="Include generated runtime pack JSON and other generated text files.",
    )
    return parser.parse_args()


def is_under(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def relpath(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def language_for(path: Path) -> str:
    suffix = path.suffix.lower()
    name = path.name.lower()
    if suffix == ".gd":
        return "gdscript"
    if suffix == ".tscn" or suffix == ".tres":
        return "ini"
    if suffix == ".rs":
        return "rust"
    if suffix == ".py":
        return "python"
    if suffix == ".ps1":
        return "powershell"
    if suffix == ".toml":
        return "toml"
    if suffix == ".json":
        return "json"
    if suffix in {".yml", ".yaml"}:
        return "yaml"
    if suffix == ".md":
        return "markdown"
    if suffix == ".svg":
        return "xml"
    if name == "project.godot" or suffix in {".gdextension", ".godot", ".ini", ".cfg"}:
        return "ini"
    return "text"


def fence_for(text: str, language: str) -> str:
    longest = 0
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("`"):
            run = len(stripped) - len(stripped.lstrip("`"))
            longest = max(longest, run)
    ticks = "`" * max(3, longest + 1)
    return f"{ticks}{language}"


def should_skip_dir(path: Path, root: Path, no_plans: bool) -> bool:
    rel_parts = path.relative_to(root).parts if path != root else ()
    if not rel_parts:
        return False
    if path.name in SKIP_DIR_NAMES:
        return True
    if no_plans and rel_parts[0] == "plans":
        return True
    return False


def should_include_file(path: Path, root: Path, no_plans: bool, include_generated: bool) -> tuple[bool, str]:
    rel_parts = path.relative_to(root).parts
    if not rel_parts:
        return False, "outside root"
    top = rel_parts[0]
    if top not in DEFAULT_INCLUDE_DIRS and path.name.lower() != "readme.md":
        return False, "outside review include dirs"
    if no_plans and top == "plans":
        return False, "plans excluded"
    if any(part in SKIP_DIR_NAMES for part in rel_parts[:-1]):
        return False, "inside skipped directory"
    suffix = path.suffix.lower()
    if suffix in BINARY_EXTENSIONS:
        return False, "binary/generated extension"
    if suffix not in TEXT_EXTENSIONS and path.name.lower() not in {"project.godot", "cargo.lock"}:
        return False, "non-review extension"
    rel = relpath(path, root)
    if not include_generated and (
        rel.endswith("worldgen_terrain/runtime/kernel_pack_manifest.json")
        or rel.endswith("worldgen_terrain/runtime/kernel_pack_runtime.json")
    ):
        return False, "generated runtime pack"
    return True, ""


def iter_candidate_files(root: Path, no_plans: bool) -> Iterable[Path]:
    for dirpath, dirnames, filenames in os.walk(root):
        current = Path(dirpath)
        kept_dirs: list[str] = []
        for dirname in dirnames:
            child = current / dirname
            if not should_skip_dir(child, root, no_plans):
                kept_dirs.append(dirname)
        dirnames[:] = kept_dirs
        for filename in filenames:
            yield current / filename


def read_text_file(path: Path) -> str:
    data = path.read_bytes()
    if b"\x00" in data[:4096]:
        raise UnicodeError("looks binary")
    return data.decode("utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n")


def collect_files(args: argparse.Namespace) -> tuple[list[ExportFile], list[tuple[str, str]]]:
    root = args.root.resolve()
    max_bytes = args.max_file_kib * 1024
    included: list[ExportFile] = []
    skipped: list[tuple[str, str]] = []

    for path in sorted(iter_candidate_files(root, args.no_plans), key=lambda p: relpath(p, root).lower()):
        ok, reason = should_include_file(path, root, args.no_plans, args.include_generated)
        rel = relpath(path, root)
        if not ok:
            skipped.append((rel, reason))
            continue
        try:
            size = path.stat().st_size
        except OSError as exc:
            skipped.append((rel, f"stat failed: {exc}"))
            continue
        if size > max_bytes:
            skipped.append((rel, f"larger than {args.max_file_kib} KiB"))
            continue
        try:
            text = read_text_file(path)
        except Exception as exc:
            skipped.append((rel, f"read failed: {exc}"))
            continue
        included.append(
            ExportFile(
                path=path,
                rel=rel,
                size_bytes=size,
                line_count=0 if text == "" else text.count("\n") + (0 if text.endswith("\n") else 1),
                text=text,
            )
        )

    return included, skipped


def render_tree(files: list[ExportFile]) -> str:
    lines = []
    for item in files:
        lines.append(f"- `{item.rel}` ({item.line_count} lines, {item.size_bytes} bytes)")
    return "\n".join(lines)


def render_markdown(root: Path, files: list[ExportFile], skipped: list[tuple[str, str]], args: argparse.Namespace) -> str:
    now = dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="seconds")
    total_lines = sum(item.line_count for item in files)
    total_bytes = sum(item.size_bytes for item in files)
    skipped_by_reason: dict[str, int] = {}
    for _, reason in skipped:
        skipped_by_reason[reason] = skipped_by_reason.get(reason, 0) + 1

    parts: list[str] = [
        "# WorldGen9 Code Review Export",
        "",
        f"Generated: `{now}`",
        f"Root: `{root}`",
        "",
        "## Summary",
        "",
        f"- Included files: `{len(files)}`",
        f"- Included lines: `{total_lines}`",
        f"- Included bytes: `{total_bytes}`",
        f"- Max file size: `{args.max_file_kib} KiB`",
        f"- Plans included: `{'no' if args.no_plans else 'yes'}`",
        f"- Generated runtime packs included: `{'yes' if args.include_generated else 'no'}`",
        "",
        "## Exclusions",
        "",
        "Skipped by design: DEM/cache data, factory artifacts, Godot cache/import metadata, native binaries, Rust `target` outputs, review exports, Python bytecode, and large/binary assets.",
        "",
    ]

    if skipped_by_reason:
        parts.append("Skipped file counts by reason:")
        parts.append("")
        for reason, count in sorted(skipped_by_reason.items()):
            parts.append(f"- `{reason}`: {count}")
        parts.append("")

    parts.extend(["## Included File Index", "", render_tree(files), ""])

    parts.append("## File Contents")
    parts.append("")
    for item in files:
        language = language_for(item.path)
        opener = fence_for(item.text, language)
        closer = "`" * len(opener.split()[0])
        parts.extend(
            [
                f"### `{item.rel}`",
                "",
                f"Lines: `{item.line_count}`  Bytes: `{item.size_bytes}`",
                "",
                opener,
                item.text.rstrip("\n"),
                closer,
                "",
            ]
        )

    return "\n".join(parts)


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    if not root.exists():
        raise SystemExit(f"Project root does not exist: {root}")
    files, skipped = collect_files(args)
    markdown = render_markdown(root, files, skipped, args)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(markdown, encoding="utf-8", newline="\n")
    print(f"wrote={args.out}")
    print(f"included_files={len(files)}")
    print(f"included_lines={sum(item.line_count for item in files)}")
    print(f"included_bytes={sum(item.size_bytes for item in files)}")
    print(f"skipped_files={len(skipped)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
