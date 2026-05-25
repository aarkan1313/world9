# Godot Phase 1 Port Plan

Date: 2026-05-24

This is the implementation order for the first Godot project shell. The shell
currently exists at `D:/workflows/worldgen9/wg-9-directory/`.

## Goal

Build the smallest visible infinite terrain runtime that matches the current
engine-independent references:

```text
plain gray 2048m chunks
129 x 129 LOD0 first
bounded active chunk set
priority/cancel mesh build queue
DEM-kernel-informed procedural height provider
exact same-height shared edges
debug views for chunk, LOD, height, and seams
```

No textures, biomes, foliage, rivers, erosion, settlements, gameplay, or direct
raw GeoTIFF reads belong in Phase 1.

Before writing engine code, the current references should pass:

```text
python tools/heightfield_prototype/runtime_release_gate.py
```

That no-write gate wraps the two underlying checks:

```text
python tools/heightfield_prototype/validate_runtime_readiness.py --out factory/runtime/runtime_readiness_report.json
python tools/heightfield_prototype/lock_runtime_artifacts.py --out factory/runtime/runtime_artifact_manifest.json --verify
```

The reports are:

```text
factory/runtime/runtime_readiness_report.json
factory/runtime/runtime_artifact_manifest.json
```

## Implementation Order

1. `TerrainSettings`

   Constants and paths only:

   ```text
   chunk_size_m = 2048
   lod0_vertices_per_side = 129
   visible_radius_chunks = 4
   region_size_m = 32768
   province_size_regions = 4
   kernel_world_scale_region_multiplier = 2.20 to 3.20
   runtime_pack_path = factory/runtime/kernel_pack_v1.json
   ```

2. `RuntimeKernelPack`

   Load `kernel_pack_v1.json`, then load only runtime arrays:

   ```text
   normalized_height_npy
   residual_m_npy
   ```

   Preview PNGs are debug/offline artifacts, not runtime source data.

   Current Godot runner:

   ```text
   godot --headless --path wg-9-directory --script res://worldgen_terrain/tests/runtime_pack_load_check.gd
   ```

3. Hash And Noise Parity

   Before region/provider work, match:

   ```text
   factory/runtime/hash_reference/hash_reference.json
   ```

   Current Godot runner:

   ```text
   godot --headless --path wg-9-directory --script res://worldgen_terrain/tests/hash_noise_parity_check.gd
   ```

   Required:

   ```text
   stable_hash FNV-1a 32-bit values match
   hash_grid values match
   value_noise and fbm reference values match within declared CPU epsilon
   ```

   Do not continue to provider-decision parity until this passes.

4. `TerrainHeightProvider`

   Implement world-space sampling before mesh work:

   ```text
   sample_height(world_x, world_z) -> float
   sample(world_x, world_z) -> TerrainSample
   sample_grid(origin_x, origin_z, step_m, count_x, count_z)
   ```

   First parity gate:

   ```text
   factory/runtime/provider_decisions/provider_decisions_reference.json
   ```

   Current Godot runner for non-height provider decisions:

   ```text
   godot --headless --path wg-9-directory --script res://worldgen_terrain/tests/provider_decision_parity_check.gd
   ```

   Match base region, smoothstep corner weights, province coordinates, palette
   choices, family bias order, kernel IDs, slope moderation, kernel transforms,
   and effective relief/detail scales before checking heights. The current
   runner intentionally ignores `height_m`, `macro_height_m`,
   `kernel_relief_m`, `detail_height_m`, `valley_adjust_m`, and
   `region_debug_value`; those belong to the `TerrainSample`/height gate.

5. `TerrainSample` Parity

   Second parity gate:

   ```text
   factory/runtime/terrain_sample_reference.json
   factory/runtime/kernel_pack_verification.json
   ```

   Current Godot runner:

   ```text
   godot --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_sample_parity_check.gd
   ```

   Required:

   ```text
   repeated samples are deterministic
   same coordinate matches Python reference within chosen CPU epsilon
   shared coordinate and full-neighbor chunk edges match exactly for CPU path
   no per-call, per-grid, or per-chunk normalization
   ```

6. `TerrainMeshBuilder`

   Third parity gate:

   ```text
   factory/runtime/chunk_reference/chunk_reference_manifest.json
   factory/runtime/mesh_reference/mesh_reference_manifest.json
   ```

   Current Godot chunk-grid runner:

   ```text
   godot --headless --path wg-9-directory --script res://worldgen_terrain/tests/chunk_reference_parity_check.gd
   ```

   Current Godot mesh runner:

   ```text
   godot --headless --path wg-9-directory --script res://worldgen_terrain/tests/mesh_reference_parity_check.gd
   ```

   Build local x/z vertices with world height y. Reuse one index buffer per
   vertex density. Do not add skirts until this reference passes without them.

7. `TerrainStreamer`

   Fourth parity gate:

   ```text
   factory/runtime/streamer_reference/streamer_reference.json
   factory/runtime/streamer_reference_fifo/streamer_reference.json
   ```

   Match active chunk coordinates and LOD rings. Use `priority_cancel`, not
   FIFO, for build queue behavior:

   ```text
   cancel retired queued work
   sort by ring, LOD, Manhattan distance, then coordinate
   build budget starts at 2 chunks/frame
   active count remains 81 for radius 4
   ```

8. `TerrainChunk`

   Holds chunk coordinate, LOD, mesh instance, debug metadata, and current build
   state. It should not know about DEM kernels or provider internals.

9. `TerrainWorld`

   Owns the provider, streamer, chunk pool, and debug mode selection. It should
   expose a viewer/camera target position and update streaming from that.

## Debug Modes

Implement these before adding visual features:

```text
gray shaded terrain
chunk id colors
LOD ring colors
height bands
seam view
provider family/palette view
```

The first useful screenshot set should show:

```text
plain gray view
LOD ring view
seam view at chunk borders
family/palette debug view
```

## Performance Starting Point

Use:

```text
2048m chunks
129 x 129 LOD0
visible radius 4
81 active chunks
2 build jobs per frame
collision off
textures off
```

Reference budget:

```text
factory/runtime/runtime_budget/runtime_budget.json
```

Current estimate for `129 x 129` LOD0:

```text
491520 active triangles
14.303 MiB estimated mesh/height memory
```

Test `257 x 257` only after 129 is stable and mesh builds are threaded/native
enough to profile honestly.

## Native And GPU Path

Start with the simplest CPU implementation that matches fixtures. Then move
expensive work in this order:

```text
GDScript orchestration
C# or GDExtension/C++ for height grid and mesh array generation
worker thread build queue
GPU height/kernel sampling only after CPU parity and profiling
clipmap or hybrid far terrain only after chunked terrain is stable
```

Do not start with GPU sampling. It makes parity failures harder to debug.

## Acceptance Gates

Phase 1 is not accepted until all are true:

```text
runtime_readiness_report status is pass before porting
runtime_artifact_manifest verification passes before porting
runtime_release_gate passes without writing files
infinite_travel_report status is pass before visual port comparison
provider decisions match reference
hash/noise values match reference
TerrainSample values match reference within declared CPU epsilon
chunk edge height deltas are zero for CPU path
mesh edge world coordinates and heights match reference
streamer active set and LOD rings match reference
viewer can move continuously and chunk count stays bounded
plain gray terrain reads as large contiguous landforms
debug screenshots prove seams and LOD rings
```

Any C++/GPU optimization has to preserve those gates or ship with a written
reason and a measured epsilon.
