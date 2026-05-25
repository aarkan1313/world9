# Runtime Height Contract

Date: 2026-05-24

This is the pre-Godot contract for the first infinite terrain runtime. It is
engine-independent and should hold for Python prototypes, GDScript, C++, and
future GPU paths.

## Coordinate Contract

```text
world_x: meters
world_z: meters
height_y: meters
origin: arbitrary world origin, not tied to a DEM tile
sampling: deterministic world-space sampling
normalization: no per-chunk normalization
```

The same `(world_x, world_z)` must return the same height and facts regardless
of which chunk asks for it.

## Runtime Inputs

The first DEM-kernel-informed provider reads:

```text
D:/workflows/worldgen9/factory/runtime/kernel_pack_v1.json
```

The provider may load these arrays:

```text
normalized_height_npy
residual_m_npy
```

It may use preview PNGs only for debug UI or offline review. Preview images are
not runtime source data.

## TerrainSample V1

The first pass only needs height plus enough debug facts to prove the sampler is
stable and explain what produced the height.

Required fields:

```text
height_m: float
valid: bool
source_mask: int
region_id: int
primary_family_id: int
secondary_family_id: int
kernel_a_id: int
kernel_b_id: int
blend_weight: float
```

Recommended debug/future fields:

```text
macro_height_m: float
kernel_relief_m: float
detail_height_m: float
valley_adjust_m: float
slope_hint: float
roughness_hint: float
confidence: float
```

Do not add rivers, biomes, foliage, textures, settlements, or erosion state to
`TerrainSample` V1. Reserve those as future world facts after height and seams
are stable.

## Source Mask

Use bit flags so the sample can describe mixed sources without changing shape:

```text
1 = procedural_macro
2 = dem_kernel_relief
4 = residual_detail
8 = valley_hint
16 = direct_dem_sample_reserved
32 = hydrology_reserved
64 = erosion_reserved
```

For current prototype output, `source_mask` should usually include:

```text
procedural_macro | dem_kernel_relief | residual_detail | valley_hint
```

## HeightProvider V1

The runtime interface should be conceptually:

```text
sample_height(world_x, world_z) -> float
sample(world_x, world_z) -> TerrainSample
sample_grid(origin_x, origin_z, step_m, count_x, count_z) -> TerrainSampleGrid
```

The mesh builder should call `sample_grid` or repeated `sample_height`; it must
not know about DEM kernels, palettes, or region selection.

## Chunk Contract

Chunks are render/cache containers, not terrain authorities.

```text
chunk_size_m: 2048
recommended_first_lod0_vertices_per_side: 129
high_detail_candidate_lod0_vertices_per_side: 257
lod0_step_m: 16 if using 2048 / 128 at 129 vertices
high_detail_lod0_step_m: 8 if using 2048 / 256 at 257 vertices
height_preview_step_m: 32 for offline visual prototypes
kernel_world_scale_region_multiplier: 2.20 to 3.20
province_size_regions: 4
```

Adjacent chunks must share exact world coordinates along the edge. For example:

```text
east edge of chunk (0, 0): x = 2048
west edge of chunk (1, 0): x = 2048
```

Do not duplicate an almost-equivalent coordinate such as `2048.0001`.

## Seam Metric

For two adjacent chunks:

```text
delta_m = abs(height_a(shared_world_x, shared_world_z) - height_b(shared_world_x, shared_world_z))
```

Acceptance for the first CPU/reference provider:

```text
mean_abs_delta_m = 0.0
p95_abs_delta_m = 0.0
max_abs_delta_m = 0.0
```

Later GPU paths may use a tiny epsilon only if profiling proves it is required,
and the visual seam debug view must still pass.

## Determinism Checks

The provider must pass:

```text
same coordinate sampled twice gives same value
same coordinate sampled by neighboring chunks gives same value
same seed and kernel pack gives same values across runs
changing seed changes terrain but preserves seam rules
```

Current reference artifacts:

```text
plans/godot_phase1_port_plan.md
factory/runtime/hash_reference/hash_reference.json
factory/runtime/runtime_readiness_report.json
factory/runtime/kernel_pack_verification.json
factory/runtime/terrain_sample_reference.json
factory/runtime/chunk_reference/chunk_reference_manifest.json
factory/runtime/mesh_reference/mesh_reference_manifest.json
factory/runtime/streamer_reference/streamer_reference.json
factory/runtime/streamer_reference_fifo/streamer_reference.json
factory/runtime/runtime_budget/runtime_budget.json
factory/runtime/region_grammar/region_grammar_report.json
factory/runtime/provider_decisions/provider_decisions_reference.json
```

The verification report must include both:

```text
shared_coordinate_edges
full_neighbor_chunk_edges
```

`full_neighbor_chunk_edges` is the stronger check because it samples complete
neighbor chunks separately, then compares the shared edge.

The chunk reference fixture stores four independently sampled neighboring chunk
height grids plus hashes at the current `129 x 129` LOD0 target. Future
Godot/GDScript/C++ providers should reproduce the shared-edge values exactly
for the same seed, pack, chunk size, and vertex count.

The mesh reference fixture converts those `129 x 129` chunk grids into local
mesh arrays. It validates shared-edge world x/z coordinates and heights. Skirts
are not part of this reference because the first seam contract must pass
without visual crack-hiding.

The streamer reference fixture defines the active chunk set and LOD rings around
a moving viewer. It is the parity target for `TerrainStreamer` before scene-node
pooling, threaded builds, or runtime-specific queue behavior are added.

The intended Phase 1 queue policy is `priority_cancel`: cancel retired queued
work, then sort remaining queued work by ring, LOD, Manhattan distance, and
coordinate. FIFO is retained only as a comparison artifact because it spends
early build budget on far rings.

The runtime budget fixture estimates active mesh cost for the same streamer
rules. Current guidance is to start at `129 x 129` LOD0 for 81 active chunks:
about 491520 active triangles and 14.303 MiB for position/normal/UV arrays,
uint32 indices, and a CPU height cache. `257 x 257` is still a valid target,
but should be tested after threaded/native mesh building is in place because it
raises the active estimate to 1966080 triangles before temporary build buffers,
collision, materials, or node overhead.

The current visual reference uses broader DEM kernel sampling than the first
prototype attempts. Runtime implementations should treat the `2.20` to `3.20`
region multiplier range as part of the height-provider contract until a better
terrain mix replaces it.

The first runtime region grammar uses `4 x 4` region provinces. Provinces give
nearby regions a coherent style bias, while each region still chooses
deterministic kernel transforms so the output remains unique at large scale.

The provider-decisions fixture is the implementation parity target below
`TerrainSample`. Runtime ports should first match base region, smoothstep
corner weights, province coordinates, palette choices, family bias order,
kernel IDs, moderation values, and kernel transforms. Height and mesh parity
should be debugged only after these provider decisions match.

The hash reference fixture is the lowest-level parity target. Runtime ports
must match `stable_hash`, `hash_grid`, `value_noise`, and `fbm` reference cases
before checking provider decisions. Otherwise every higher-level deterministic
choice can drift while still looking superficially plausible.

The runtime readiness report is the aggregate gate for the current pre-Godot
state. It verifies that the pack, hash reference, provider decisions, terrain
sample reference, seam verifier, chunk/mesh fixtures, streamer fixtures,
runtime budget, region grammar, and visual summary are present, passing, and
consistent with the same runtime defaults.

The Godot Phase 1 port plan defines the required implementation order:

```text
settings
kernel pack loader
hash/noise parity
height provider
TerrainSample parity
mesh builder
streamer
chunk wrapper
terrain world
debug modes
```

Do not skip straight to rendered terrain before provider-decision, height,
chunk, mesh, and streamer parity have evidence.

## Runtime Boundary

Allowed in Phase 1:

```text
height sampling
macro terrain
DEM kernel relief
residual detail
valley hint as height adjustment/debug field
plain material/debug colors
```

Not allowed in Phase 1:

```text
textures
biomes
foliage
river meshes
erosion simulation
direct raw GeoTIFF reads
per-chunk min/max normalization
per-call or per-grid mean subtraction
```
