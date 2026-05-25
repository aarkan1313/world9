# Runtime Kernel Pack Schema V1

This document describes `worldgen9.runtime_kernel_pack.v1`.

The pack is a manifest, not a terrain renderer. It defines which reviewed DEM
kernels are allowed into the first infinite-heightfield runtime and where their
array artifacts live.

## Top-Level Fields

```text
version: integer, currently 1
schema: "worldgen9.runtime_kernel_pack.v1"
source_catalog: path to the reviewed factory catalog used to build the pack
coordinate_contract: deterministic sampling rules
runtime_defaults: first-pass chunk and region constants
region_palettes: named mixes of terrain families
families: per-family runtime scales and kernel ids
kernel_count: number of kernels
kernels: runtime kernel entries
```

## Coordinate Contract

```text
units: meters
sampling: deterministic_world_space
normalization: no_per_chunk_normalization
kernel_edge_mode: mirrored_repeat
chunk_seam_rule: same_world_coordinate_returns_same_height_from_any_chunk
```

This means a chunk may never normalize its own local min/max. The height
provider owns height values globally, and any two chunks sampling the same world
coordinate must receive the same result.

## Runtime Defaults

```text
chunk_size_m: 2048
lod0_vertices_per_side: 129
high_detail_lod0_vertices_per_side: 257
region_size_m: 32768
province_size_regions: 4
height_resolution_m: 32
kernel_world_scale_min_region_multiplier: 2.20
kernel_world_scale_max_region_multiplier: 3.20
```

These are defaults, not permanent engine constants. The important invariant is
the world-space sample contract.

`129 x 129` is the conservative first engine target from the runtime budget
fixture. `257 x 257` remains the high-detail candidate after threaded/native
mesh building is stable.

Kernel world-scale multipliers make DEM features much broader than the region
blend cell. This is deliberate: sampling kernels too tightly makes hillshade
noisy and produces harsh first-pass mesh slopes.

`province_size_regions` groups nearby regions into broader style provinces.
Regions inside a province mostly use the province palette, with compatible
local variation so the world is coherent without becoming a repeated stamp.

## Kernel Entry

```text
id: stable kernel id
family: terrain family
demtype: DEM source product
promotion_status: human/tooling promotion status
promotion_weight: scalar for future weighted selection
sample.shape: array shape, expected [512, 512] for current factory output
sample.dtype: array dtype
sample.source_sample_px: source reduction size
sample.approx_sample_spacing_m: approximate meters per kernel sample
stats: quality and terrain metrics
source.dem_path: original DEM source path
source.bounds: source geographic/projected bounds from factory
artifacts.normalized_height_npy: normalized heightfield used for relief shape
artifacts.residual_m_npy: residual detail field
artifacts.preview_height_png: visual review preview
```

The runtime should treat `height_m_npy`, `preview_slope_png`, and
`preview_residual_png` as optional debug assets.

## First Runtime Use

For the first Godot/C++ implementation:

```text
1. Load this JSON manifest.
2. Load normalized_height_npy and residual_m_npy arrays for promoted kernels.
3. Select kernels by deterministic world-space region hash.
4. Sample kernels with mirrored repeat.
5. Blend neighboring regions in world space.
6. Return global height without local chunk normalization.
7. Verify adjacent chunk edges with exact shared coordinate samples.
```
