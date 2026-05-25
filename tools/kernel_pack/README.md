# Runtime Kernel Pack

This tool converts a reviewed factory catalog into a small runtime-facing
manifest. It does not create a Godot project and does not render terrain.

The pack is the contract between offline DEM preparation and the future
heightfield runtime. Runtime code should read this manifest instead of reaching
into `factory/catalog/*` directly.

## Build

```powershell
python tools/kernel_pack/build_runtime_kernel_pack.py --catalog factory/catalog/promoted_kernel_catalog.json --out factory/runtime/kernel_pack_v1.json
```

## Validate Only

```powershell
python tools/kernel_pack/build_runtime_kernel_pack.py --catalog factory/catalog/promoted_kernel_catalog.json --out factory/runtime/kernel_pack_v1.json --dry-run
```

## Verify Sampling

```powershell
python tools/heightfield_prototype/verify_runtime_pack.py --catalog factory/runtime/kernel_pack_v1.json --out factory/runtime/kernel_pack_verification.json
python tools/heightfield_prototype/sample_terrain_reference.py --catalog factory/runtime/kernel_pack_v1.json --out factory/runtime/terrain_sample_reference.json
```

The verifier checks deterministic repeated samples and shared chunk-edge samples
across the current review seeds without rendering terrain. It includes a full
neighboring chunk edge check, which is the required seam proof for the CPU
reference provider.

## Contract

The pack uses meters, world-space deterministic sampling, and no per-chunk
normalization. Height arrays remain external `.npy` artifacts for now so the
runtime can choose CPU, C++, or GPU upload paths later without rewriting the
offline factory.

Current runtime defaults use 2048m chunks and `129 x 129` LOD0. The pack also
records `257 x 257` as the high-detail candidate once threaded/native mesh
building is ready.

DEM kernel features should be sampled at roughly `2.20x` to `3.20x` the region
size. Tighter sampling looked too busy in the gray heightfield previews.

Runtime region selection uses `4 x 4` region provinces. A province gives nearby
regions a shared style bias, while each region still gets deterministic local
kernel transforms for uniqueness.

Required runtime artifacts per kernel:

```text
normalized_height.npy
residual_m.npy
preview_height.png
```

Optional/debug artifacts:

```text
preview_slope.png
preview_residual.png
height_m.npy
```
