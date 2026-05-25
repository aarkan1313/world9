#!/usr/bin/env python3
"""Create or verify a hash manifest for runtime reference artifacts."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "factory" / "runtime"
VISUAL = ROOT / "prototypes" / "seed_compare_runtime_v7_balanced"
DEFAULT_OUT = RUNTIME / "runtime_artifact_manifest.json"

ARTIFACT_ROOTS = [
    RUNTIME,
    VISUAL / "seed_comparison_summary.json",
    VISUAL / "seed_comparison_contact_sheet.png",
]


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def iter_artifacts(exclude: Path) -> list[Path]:
    artifacts: list[Path] = []
    resolved_exclude = exclude.resolve()
    for root in ARTIFACT_ROOTS:
        if root.is_dir():
            candidates = [path for path in root.rglob("*") if path.is_file()]
        else:
            candidates = [root]
        for path in candidates:
            if path.resolve() == resolved_exclude:
                continue
            artifacts.append(path)
    return sorted(set(artifacts), key=relative)


def build_manifest(exclude: Path) -> dict[str, Any]:
    artifacts = []
    errors = []
    for path in iter_artifacts(exclude):
        if not path.exists():
            errors.append(f"missing:{relative(path)}")
            continue
        artifacts.append(
            {
                "path": relative(path),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
        )

    return {
        "version": 1,
        "schema": "worldgen9.runtime_artifact_manifest.v1",
        "root": ROOT.as_posix(),
        "artifact_count": len(artifacts),
        "artifacts": artifacts,
        "errors": errors,
        "status": "pass" if not errors else "fail",
    }


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def verify(manifest_path: Path) -> dict[str, Any]:
    expected = read_json(manifest_path)
    current = build_manifest(manifest_path)
    errors = list(current["errors"])

    expected_by_path = {
        artifact["path"]: artifact
        for artifact in expected.get("artifacts", [])
    }
    current_by_path = {
        artifact["path"]: artifact
        for artifact in current.get("artifacts", [])
    }

    for path, expected_artifact in expected_by_path.items():
        current_artifact = current_by_path.get(path)
        if current_artifact is None:
            errors.append(f"missing_expected:{path}")
            continue
        if current_artifact["sha256"] != expected_artifact.get("sha256"):
            errors.append(f"sha256_mismatch:{path}")
        if current_artifact["bytes"] != expected_artifact.get("bytes"):
            errors.append(f"bytes_mismatch:{path}")

    for path in current_by_path:
        if path not in expected_by_path:
            errors.append(f"unexpected_artifact:{path}")

    return {
        "version": 1,
        "schema": "worldgen9.runtime_artifact_manifest_verify.v1",
        "manifest": manifest_path.as_posix(),
        "artifact_count": len(current_by_path),
        "errors": errors,
        "status": "pass" if not errors else "fail",
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--verify", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest_path = Path(args.out)
    if args.verify:
        report = verify(manifest_path)
        print("[runtime-artifacts] verify status=%s errors=%d" % (report["status"], len(report["errors"])))
        for error in report["errors"]:
            print("[runtime-artifacts] error: %s" % error)
        return 0 if report["status"] == "pass" else 1

    manifest = build_manifest(manifest_path)
    write_json(manifest_path, manifest)
    print("[runtime-artifacts] status=%s artifacts=%d" % (manifest["status"], manifest["artifact_count"]))
    print("[runtime-artifacts] out=%s" % manifest_path)
    for error in manifest["errors"]:
        print("[runtime-artifacts] error: %s" % error)
    return 0 if manifest["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
