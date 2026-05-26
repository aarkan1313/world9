# Landform Tuning And Erosion Order

Last updated: 2026-05-26

## Why This Exists

Kernel gallery/tour review proved the runtime can select and display the current
DEM-derived kernel set. The next open question is not whether kernels exist. It
is whether the infinite world uses them at the right strength, vertical scale,
and spatial frequency.

Current review notes:

```text
kernel variety appears usable
world scale may be too broad
mountains may not be tall/varied enough
future terrain should support passes, saddles, valleys, and navigable corridors
```

These should be solved as generator contracts, not one-off scene hacks.

## Implemented Slice: Landform Tuning Profiles

Review-only landform tuning profiles now exist before changing defaults.

Implemented profile targets:

```text
balanced_current
strong_mountains
compressed_scale
```

Candidate knobs:

```text
macro_relief_scale
kernel_relief_strength
mountain_boost
valley_bias_strength
regional_scale_multiplier
pass_corridor_strength, disabled by default
```

`balanced_current` is the neutral default and is gated to match unprofiled
terrain. `strong_mountains` raises macro/kernel relief with extra boost for
mountain, glacial, and volcanic families. `compressed_scale` samples macro and
kernel terrain at a shorter effective world scale while leaving region IDs and
family selection anchored to the normal world grid.

Review profiles are opt-in. The native prepared-grid/chunk payload path now
receives the same profile parameters as the GDScript provider, so profile
switches can use the normal native worker flow instead of blocking far/near
refresh or falling back to multi-second synchronous GDScript generation.

## Acceptance Checks

Each profile should be compared at the same selected world sites.

Metrics:

```text
height range
p05/p95 relief
mean and p95 slope
local relief window stats
kernel contribution amount
seam continuity
native/GDScript parity
motion/profile budget impact
```

Visual review:

```text
mountain silhouettes read taller and less flat
large landforms are visible at walk/tour scale
compressed-scale profile shows more variation per travel distance
terrain does not become noisy, stamped, or obviously tiled
no new chunk/clipmap seams appear
```

Current proof:

```text
res://worldgen_terrain/tests/terrain_landform_profile_compare_check.gd
res://worldgen_terrain/tests/terrain_landform_profile_tour_scene_check.gd
res://worldgen_terrain/scenes/terrain_landform_profile_tour.tscn
factory/runtime/godot_landform_profiles/landform_profile_report.json
factory/runtime/godot_landform_profiles/landform_profile_contact_sheet.png
```

The gate currently checks:

```text
neutral profile does not change default sampled heights
strong_mountains increases relief on at least one selected mountain-family site
compressed_scale changes local-relief/frequency on the same selected sites
same-coordinate adjacent grid seams stay under 1cm
non-neutral profiles keep native prepared-grid support
live profile tour exposes the same profiles with manual profile switching and far coverage enabled
```

Live review controls:

```text
V: advance landform profile
P: toggle automatic profile cycling
N/B: next/previous representative site
WASD + mouse: normal walk/fly controls
```

The live scene keeps automatic profile cycling disabled by default and throttles
profile-tour far refresh to one level per frame. Far clipmap page requests
include the active profile in their cache identity, and the native backend
consumes the profile scalars so `V` profile changes do not create stale neutral
pages or black/missing zones.

## Passes And Traversable Corridors

Mountain passes should come before full erosion, but after the basic landform
scale/relief profiles are measurable.

Reason:

```text
passes are macro route/topology facts
erosion is a shaping/detail pass
```

Implemented placeholder:

```text
TerrainWorldFacts emits deterministic per-region pass/corridor facts
facts include endpoints, width, priority, ruggedness, palette/family context
facts expose sample hints but do not alter height yet (`affects_height=false`)
terrain_world_facts_pass_corridor_check.gd proves determinism and no height deformation
```

A pass/corridor field can guide later systems:

```text
river headwaters and valley routes
road/path suitability
settlement access
animal migration
snowline and biome transitions
erosion flow directions
```

Do not implement passes by directly carving arbitrary visible chunks. Model them
as deterministic world facts that the height provider can sample, then let the
renderer consume the resulting height.

## Where Erosion Fits

Erosion is not the next step. It belongs after:

```text
1. base landform scale and relief are accepted
2. kernel influence strength/frequency are tunable
3. hydrology hints are useful and coherent
4. river/channel routing has at least a stable first pass
5. pass/corridor fields exist or are explicitly deferred
```

Erosion should improve an already-readable terrain. It should not hide weak
macro terrain, bad kernel scale, visible LOD shifts, or missing river logic.

## Erosion Order

Use three tiers, in this order:

```text
1. DEM-derived erosion residuals
2. thermal erosion / slope relaxation
3. hydraulic-inspired cached shaping
```

### 1. DEM-Derived Erosion Residuals

Extract erosion-like detail from accepted DEM kernels and apply it as a bounded
detail/residual layer.

This is the safest first erosion-adjacent step because it keeps the project
rooted in real terrain without running expensive simulations.

### 2. Thermal Erosion

Use thermal-style slope relaxation to soften implausibly steep or noisy slopes.

This should be deterministic, tile-safe, and optional per profile.

### 3. Hydraulic-Inspired Cached Shaping

Hydraulic-style erosion should use hydrology and river facts. It should run on
larger region/page tiles or offline/generated caches, not every visible chunk
every frame.

Runtime terrain should sample cached erosion facts:

```text
erosion_amount
deposition_amount
channel_bias
flow_accumulation
sediment/floodplain hint
```

## Hard Rules

```text
do not run full erosion in the live renderer path
do not erode individual chunks independently
do not let erosion break deterministic seam contracts
do not use erosion to cover unresolved LOD/clipmap artifacts
do not add final biome art before the world facts are stable
```

## Immediate Roadmap Position

Current recommended order:

```text
1. visually review landform profile contact sheet and live profile behavior
2. choose whether to keep balanced_current or revise default scale/relief
3. add pass/corridor world-fact placeholder
4. continue hydrology/rivers
5. add erosion residuals only after the above reads correctly
```
