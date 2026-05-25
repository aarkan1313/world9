#!/usr/bin/env python3
"""Run the no-write pre-port release gate for runtime references."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import lock_runtime_artifacts
import validate_runtime_readiness


ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "factory" / "runtime"
DEFAULT_READINESS = RUNTIME / "runtime_readiness_report.json"
DEFAULT_MANIFEST = RUNTIME / "runtime_artifact_manifest.json"


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical(data: Any) -> str:
    return json.dumps(data, sort_keys=True, separators=(",", ":"))


def run_gate(readiness_path: Path, manifest_path: Path) -> dict[str, Any]:
    errors: list[str] = []
    current_readiness = validate_runtime_readiness.validate()
    stored_readiness = read_json(readiness_path) if readiness_path.exists() else None
    artifact_verify = lock_runtime_artifacts.verify(manifest_path) if manifest_path.exists() else None

    if current_readiness.get("status") != "pass":
        errors.append("current_readiness_not_pass")
    errors.extend("readiness:%s" % error for error in current_readiness.get("errors", []))

    if stored_readiness is None:
        errors.append("stored_readiness_missing")
    elif stored_readiness.get("status") != "pass":
        errors.append("stored_readiness_not_pass")
    elif canonical(stored_readiness) != canonical(current_readiness):
        errors.append("stored_readiness_drift")

    if artifact_verify is None:
        errors.append("artifact_manifest_missing")
    elif artifact_verify.get("status") != "pass":
        errors.append("artifact_manifest_verify_not_pass")
        errors.extend("artifact:%s" % error for error in artifact_verify.get("errors", []))

    return {
        "version": 1,
        "schema": "worldgen9.runtime_release_gate.v1",
        "readiness_report": readiness_path.as_posix(),
        "artifact_manifest": manifest_path.as_posix(),
        "summary": {
            "kernel_count": current_readiness.get("summary", {}).get("kernel_count"),
            "family_count": current_readiness.get("summary", {}).get("family_count"),
            "chunk_size_m": current_readiness.get("summary", {}).get("chunk_size_m"),
            "lod0_vertices_per_side": current_readiness.get("summary", {}).get("lod0_vertices_per_side"),
            "travel_window_count": current_readiness.get("summary", {}).get("travel_window_count"),
            "artifact_count": artifact_verify.get("artifact_count") if artifact_verify else None,
        },
        "errors": errors,
        "status": "pass" if not errors else "fail",
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--readiness", default=str(DEFAULT_READINESS))
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    parser.add_argument("--json", action="store_true", help="Print the full gate report as JSON.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = run_gate(Path(args.readiness), Path(args.manifest))
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        summary = report["summary"]
        print(
            "[runtime-release] status=%s errors=%d kernels=%s families=%s artifacts=%s"
            % (
                report["status"],
                len(report["errors"]),
                summary.get("kernel_count"),
                summary.get("family_count"),
                summary.get("artifact_count"),
            )
        )
        for error in report["errors"]:
            print("[runtime-release] error: %s" % error)
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
