# Infinite Heightfield Prototype Plan

Last updated: 2026-05-24

This phase happens before Godot runtime work. The goal is to prove that the
promoted DEM kernels can produce large, continuous, good-looking heightfields in
plain grayscale.

## Goal

Generate reviewable terrain previews from kernel catalogs:

```text
height preview
slope preview
region/style map
seam report
zoom crops
```

The prototype should answer:

```text
can DEM-derived kernels make believable continuous terrain?
do region transitions avoid obvious tile borders?
does the sample function stay deterministic?
can we separate macro shape from kernel detail?
which kernel families are useful for first runtime work?
```

## Input Catalogs

Start with:

```text
D:/workflows/worldgen9/factory/catalog/promoted_kernel_catalog.json
```

When manual review is far enough along, also support:

```text
D:/workflows/worldgen9/factory/reviews/user_shortlist_kernel_catalog.json
```

The user shortlist should override the promoted catalog when present and non-empty.

## Important Interpretation Rule

Some kernels look significantly different from others. That is not automatically
bad.

Different kernels are useful if they read as different terrain roles:

```text
macro ridges
glacial valleys
dry basins
canyon drainage
rolling grassland
volcanic cones/slopes
coast/fjord relief
humid dissected hills
```

They become bad only if the generator reads them as:

```text
random pasted tiles
water/no-data masks
rotated/framed projected footprints
visual noise with no landform role
unbalanced overrepresentation of one source area
```

So the prototype should track both terrain family and terrain role.

## First Algorithm

Use a layered height model:

```text
macro height
+ regional terrain style
+ kernel residual/detail
+ low-amplitude local noise
= final height
```

### 1. Macro Height

Use deterministic broad noise or a simple region graph.

Purpose:

```text
large landform continuity
avoid flat canvas
avoid kernels carrying all elevation
```

Start simple:

```text
continent-scale low frequency value noise
ridge-like directional noise
large basin/plateau bias
```

### 2. Region Style Map

Divide the world into large regions:

```text
region_size_m = 8192 to 32768
```

Each region chooses 1-3 kernel families:

```text
region A: mountain + glacial
region B: badlands + desert
region C: grassland + rainforest
region D: coast + mountain
```

Blend neighboring region styles with smooth weights.

### 3. Kernel Detail

Use kernels as detail/style sources, not as pasted square terrain.

For each sample point:

```text
choose region family weights
choose one or more kernels from those families
sample normalized/residual kernel fields
rotate/flip/offset deterministically per region
scale contribution by family parameters
blend smoothly
```

Do not directly paste whole DEM height patches into the world.

### 4. Family Scaling

Different families need different influence:

```text
mountain/glacial: high relief, strong ridges
badlands/desert: medium relief, drainage/roughness detail
karst/rainforest: medium relief, dense dissection
grassland: lower relief, broad smooth structure
coast: contextual relief, use carefully away from water masks
volcanic: localized cone/slope influence, not everywhere
```

Wetland/delta kernels should remain out of the first heightfield seed. Add them
later as hydrology/wetness context.

## Determinism Contract

The prototype should expose one conceptual function:

```text
sample_height(world_x_m, world_z_m, seed) -> height_m
```

Rules:

```text
same coordinate always returns same height
result does not depend on preview tile/chunk
all region choices derive from integer world-region coordinates and seed
kernel transforms derive from region coordinate and seed
no per-output-image normalization inside the height function
```

## Seam Tests

Generate adjacent tiles from the same sample function:

```text
tile A: x 0..8192
tile B: x 8192..16384
```

Compare shared edge samples:

```text
mean edge delta
p95 edge delta
max edge delta
```

Expected first-pass target:

```text
mean = 0
p95 = 0
max = 0
```

If edge deltas are non-zero, the sample function is chunk-dependent and must be
fixed before Godot.

## Outputs

Write outputs under:

```text
D:/workflows/worldgen9/prototypes/infinite_heightfield/
```

First run should produce:

```text
height_preview_8192.png
slope_preview_8192.png
region_style_preview_8192.png
height_preview_16384.png
zoom_crop_*.png
seam_report.json
prototype_config.json
```

## Review Criteria

The prototype is useful if:

```text
terrain has large readable structure
family transitions are not hard square borders
kernels add terrain character without obvious stamping
different families feel distinct but compatible
plain grayscale terrain already looks interesting
seam report is exact or near-exact zero
```

The prototype fails if:

```text
it looks like random DEM tiles pasted together
it overuses noisy high-frequency residuals
water/no-data masks drive terrain shape
region boundaries are visible
terrain has no macro coherence
seams depend on output tile origin
```

## Long-Term Runtime Infrastructure

The likely long-term architecture:

```text
Python offline tools
-> reviewed kernel/data catalogs
-> Godot project host
-> C++ terrain core through GDExtension
-> GPU-assisted rendering/detail where profiling proves value
```

### Python

Use Python for:

```text
DEM ingest
cataloging
kernel generation
preview generation
offline validation
batch experiments
data packaging
```

Python should not be responsible for runtime terrain sampling in the shipped
game/tool.

### Godot / GDScript

Use Godot/GDScript for:

```text
scene integration
editor controls
debug UI
prototype wiring
small glue code
visual review tools inside editor later
```

Avoid putting heavy terrain generation loops in GDScript once the design is
known.

### C++ / GDExtension

Use C++ for:

```text
deterministic height sampling
kernel sampling
region selection
mesh generation
LOD data generation
seam tests
runtime caches
threaded terrain jobs
collision heightfield generation
```

C++ should own the performance-critical terrain contracts after the Python
prototype proves the math.

### GPU

Use GPU work where it gives clear wins:

```text
far terrain clipmaps
height/normal textures
shader displacement
normal generation
detail synthesis
debug heatmaps
possibly compute-assisted terrain buffers later
```

Do not move core terrain logic to GPU too early. First prove:

```text
height contract
region determinism
kernel blending
seam correctness
runtime data layout
```

Then decide which parts should be GPU-backed.

### Likely Final Shape

```text
near terrain:
    C++ chunk renderer / collision / gameplay queries

far terrain:
    GPU-friendly clipmap or hybrid renderer

data:
    Python-built kernel packs and catalogs

engine:
    Godot hosts scene, UI, materials, editor tools, and orchestration
```

This keeps the system fast without prematurely locking the terrain math into a
GPU-only path that is hard to debug.

## Immediate Next Step

After the user has enough Yes/No review data:

```text
1. Build a prototype using user_shortlist_kernel_catalog.json if it exists.
2. Fall back to promoted_kernel_catalog.json otherwise.
3. Generate 8192m and 16384m previews.
4. Generate seam_report.json.
5. Review images before any Godot runtime implementation.
```
