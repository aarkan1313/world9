#!/usr/bin/env python3
"""Export an engine-independent terrain mesh reference from chunk heights."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CHUNK_DIR = ROOT / "factory" / "runtime" / "chunk_reference"
DEFAULT_OUT_DIR = ROOT / "factory" / "runtime" / "mesh_reference"


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def sha256_array(arr: np.ndarray) -> str:
    return hashlib.sha256(np.ascontiguousarray(arr).tobytes()).hexdigest()


def build_indices(vertices_per_side: int) -> np.ndarray:
    quads = vertices_per_side - 1
    indices = np.empty((quads * quads * 6,), dtype=np.uint32)
    write = 0
    for z in range(quads):
        row = z * vertices_per_side
        next_row = (z + 1) * vertices_per_side
        for x in range(quads):
            a = row + x
            b = row + x + 1
            c = next_row + x
            d = next_row + x + 1
            indices[write : write + 6] = (a, c, b, b, c, d)
            write += 6
    return indices


def build_vertices(height: np.ndarray, origin: list[float], step_m: float) -> np.ndarray:
    rows, cols = height.shape
    xs = np.arange(cols, dtype=np.float32) * np.float32(step_m)
    zs = np.arange(rows, dtype=np.float32) * np.float32(step_m)
    xg, zg = np.meshgrid(xs, zs)
    vertices = np.stack([xg, height.astype(np.float32), zg], axis=-1)
    return vertices.reshape((-1, 3)).astype(np.float32)


def build_uvs(vertices_per_side: int) -> np.ndarray:
    coords = np.linspace(0.0, 1.0, vertices_per_side, dtype=np.float32)
    u, v = np.meshgrid(coords, coords)
    return np.stack([u, v], axis=-1).reshape((-1, 2)).astype(np.float32)


def build_normals(height: np.ndarray, step_m: float) -> np.ndarray:
    dz, dx = np.gradient(height.astype(np.float32), np.float32(step_m), np.float32(step_m))
    normals = np.stack([-dx, np.ones_like(height, dtype=np.float32), -dz], axis=-1)
    length = np.linalg.norm(normals, axis=-1, keepdims=True)
    normals = normals / np.maximum(length, np.float32(1e-6))
    return normals.reshape((-1, 3)).astype(np.float32)


def validate_mesh(vertices: np.ndarray, normals: np.ndarray, uvs: np.ndarray, indices: np.ndarray) -> list[str]:
    errors: list[str] = []
    if vertices.ndim != 2 or vertices.shape[1] != 3:
        errors.append("vertices_shape_invalid")
    if normals.shape != vertices.shape:
        errors.append("normals_shape_mismatch")
    if uvs.ndim != 2 or uvs.shape[0] != vertices.shape[0] or uvs.shape[1] != 2:
        errors.append("uvs_shape_invalid")
    if indices.ndim != 1 or indices.size % 3 != 0:
        errors.append("indices_shape_invalid")
    if indices.size and int(np.max(indices)) >= vertices.shape[0]:
        errors.append("index_out_of_range")
    if not np.isfinite(vertices).all():
        errors.append("vertices_nonfinite")
    if not np.isfinite(normals).all():
        errors.append("normals_nonfinite")
    normal_len = np.linalg.norm(normals, axis=1)
    if float(np.max(np.abs(normal_len - 1.0))) > 1e-4:
        errors.append("normals_not_unit_length")
    return errors


def edge_vertex_delta(
    a: np.ndarray,
    b: np.ndarray,
    origin_a: list[float],
    origin_b: list[float],
    side: str,
    vertices_per_side: int,
) -> dict[str, Any]:
    av = a.reshape((vertices_per_side, vertices_per_side, 3))
    bv = b.reshape((vertices_per_side, vertices_per_side, 3))
    aw = av.copy()
    bw = bv.copy()
    aw[..., 0] += np.float32(origin_a[0])
    aw[..., 2] += np.float32(origin_a[1])
    bw[..., 0] += np.float32(origin_b[0])
    bw[..., 2] += np.float32(origin_b[1])
    if side == "east_west":
        delta_y = np.abs(aw[:, -1, 1] - bw[:, 0, 1])
        delta_x = np.abs(aw[:, -1, 0] - bw[:, 0, 0])
        delta_z = np.abs(aw[:, -1, 2] - bw[:, 0, 2])
    elif side == "north_south":
        delta_y = np.abs(aw[-1, :, 1] - bw[0, :, 1])
        delta_x = np.abs(aw[-1, :, 0] - bw[0, :, 0])
        delta_z = np.abs(aw[-1, :, 2] - bw[0, :, 2])
    else:
        raise ValueError(side)
    return {
        "side": side,
        "samples": int(delta_y.size),
        "max_abs_world_x_delta_m": float(np.max(delta_x)),
        "max_abs_world_z_delta_m": float(np.max(delta_z)),
        "mean_abs_height_delta_m": float(np.mean(delta_y)),
        "p95_abs_height_delta_m": float(np.percentile(delta_y, 95.0)),
        "max_abs_height_delta_m": float(np.max(delta_y)),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chunk-dir", default=str(DEFAULT_CHUNK_DIR))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    chunk_dir = Path(args.chunk_dir)
    out_dir = Path(args.out_dir)
    manifest = read_json(chunk_dir / "chunk_reference_manifest.json")
    vertices_per_side = int(manifest["vertices_per_side"])
    step_m = float(manifest["step_m"])
    indices = build_indices(vertices_per_side)
    uvs = build_uvs(vertices_per_side)

    mesh_entries = []
    meshes: dict[tuple[int, int], dict[str, np.ndarray]] = {}
    errors: list[str] = []
    if not args.dry_run:
        out_dir.mkdir(parents=True, exist_ok=True)

    for chunk in manifest.get("chunks", []):
        coord = tuple(int(v) for v in chunk["chunk"])
        height = np.load(chunk_dir / str(chunk["height_npy"])).astype(np.float32)
        vertices = build_vertices(height, chunk["origin"], step_m)
        normals = build_normals(height, step_m)
        mesh_errors = validate_mesh(vertices, normals, uvs, indices)
        errors.extend("%+d,%+d:%s" % (coord[0], coord[1], error) for error in mesh_errors)
        base = "chunk_%+d_%+d" % (coord[0], coord[1])
        if not args.dry_run:
            np.save(out_dir / f"{base}_vertices.npy", vertices)
            np.save(out_dir / f"{base}_normals.npy", normals)
        meshes[coord] = {"vertices": vertices, "normals": normals}
        mesh_entries.append(
            {
                "chunk": list(coord),
                "origin": chunk["origin"],
                "vertices_npy": f"{base}_vertices.npy",
                "normals_npy": f"{base}_normals.npy",
                "vertex_count": int(vertices.shape[0]),
                "triangle_count": int(indices.size // 3),
                "bounds_local": {
                    "min": [float(v) for v in np.min(vertices, axis=0)],
                    "max": [float(v) for v in np.max(vertices, axis=0)],
                },
                "vertices_sha256": sha256_array(vertices),
                "normals_sha256": sha256_array(normals),
            }
        )

    if not args.dry_run:
        np.save(out_dir / "shared_indices.npy", indices)
        np.save(out_dir / "shared_uvs.npy", uvs)

    edge_reports = [
        {
            "chunk_a": [0, 0],
            "chunk_b": [1, 0],
            **edge_vertex_delta(
                meshes[(0, 0)]["vertices"],
                meshes[(1, 0)]["vertices"],
                [0.0, 0.0],
                [float(manifest["chunk_size_m"]), 0.0],
                "east_west",
                vertices_per_side,
            ),
        },
        {
            "chunk_a": [0, 0],
            "chunk_b": [0, 1],
            **edge_vertex_delta(
                meshes[(0, 0)]["vertices"],
                meshes[(0, 1)]["vertices"],
                [0.0, 0.0],
                [0.0, float(manifest["chunk_size_m"])],
                "north_south",
                vertices_per_side,
            ),
        },
        {
            "chunk_a": [0, 1],
            "chunk_b": [1, 1],
            **edge_vertex_delta(
                meshes[(0, 1)]["vertices"],
                meshes[(1, 1)]["vertices"],
                [0.0, float(manifest["chunk_size_m"])],
                [float(manifest["chunk_size_m"]), float(manifest["chunk_size_m"])],
                "east_west",
                vertices_per_side,
            ),
        },
        {
            "chunk_a": [1, 0],
            "chunk_b": [1, 1],
            **edge_vertex_delta(
                meshes[(1, 0)]["vertices"],
                meshes[(1, 1)]["vertices"],
                [float(manifest["chunk_size_m"]), 0.0],
                [float(manifest["chunk_size_m"]), float(manifest["chunk_size_m"])],
                "north_south",
                vertices_per_side,
            ),
        },
    ]
    if any(
        report["max_abs_height_delta_m"] != 0.0
        or report["max_abs_world_x_delta_m"] != 0.0
        or report["max_abs_world_z_delta_m"] != 0.0
        for report in edge_reports
    ):
        errors.append("edge_height_delta_nonzero")

    output_manifest = {
        "version": 1,
        "schema": "worldgen9.mesh_reference.v1",
        "source_chunk_reference": str(chunk_dir / "chunk_reference_manifest.json").replace("\\", "/"),
        "chunk_size_m": manifest["chunk_size_m"],
        "vertices_per_side": vertices_per_side,
        "step_m": step_m,
        "coordinate_space": "local_xz_world_height_y",
        "skirts": "not_included_lod0_reference",
        "shared_indices_npy": "shared_indices.npy",
        "shared_uvs_npy": "shared_uvs.npy",
        "index_count": int(indices.size),
        "triangle_count": int(indices.size // 3),
        "index_sha256": sha256_array(indices),
        "uv_sha256": sha256_array(uvs),
        "chunks": mesh_entries,
        "edge_reports": edge_reports,
        "errors": errors,
        "status": "pass" if not errors else "fail",
    }
    if not args.dry_run:
        write_json(out_dir / "mesh_reference_manifest.json", output_manifest)
    print("[mesh-reference] chunks=%d vertices_per_chunk=%d triangles_per_chunk=%d status=%s" % (len(mesh_entries), vertices_per_side * vertices_per_side, indices.size // 3, output_manifest["status"]))
    for report in edge_reports:
        print("[mesh-reference] %s %s->%s max_y=%.9f" % (report["side"], report["chunk_a"], report["chunk_b"], report["max_abs_height_delta_m"]))
    if not args.dry_run:
        print("[mesh-reference] out=%s" % out_dir)
    return 0 if output_manifest["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
