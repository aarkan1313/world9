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

## Next Slice: Landform Tuning Profiles

Add review-only landform tuning profiles before changing defaults.

Initial profile targets:

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

The first implementation should keep the saved walk scene default unchanged.
Review profiles should be opt-in and measurable.

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

## Passes And Traversable Corridors

Mountain passes should come before full erosion, but after the basic landform
scale/relief profiles are measurable.

Reason:

```text
passes are macro route/topology facts
erosion is a shaping/detail pass
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
1. landform tuning profile contract
2. profile comparison probe/contact sheet/tour
3. choose or revise default scale/relief
4. add pass/corridor world-fact placeholder
5. continue hydrology/rivers
6. add erosion residuals only after the above reads correctly
```
