# GPU Page Backend Sprint

Status: started, not complete.

The current durable direction is persistent terrain pages:

- stable world-space page requests
- native/provider height-page generation
- persistent page meshes
- shader displacement from height textures
- previous/current page blending
- coarse/fine LOD morph in shader
- bounded GPU page residency

## Completed In This Sprint

- Source-only backup was written to `D:/workflows/worldgen9/backups/`.
- `backups/` is ignored so source checkpoints do not commit local archives.
- Added `terrain_gpu_compute_probe_check.gd`.
- Added `--suite gpu` to `tools/godot_runtime_gate.py`.
- The GPU suite runs renderer-enabled, not headless.
- The headless path reports missing `RenderingDevice` as unsupported instead of failing.
- Added `TerrainGpuPageNormalBackend` with persistent local `RenderingDevice` state and cached shader/pipeline RIDs.
- Added an opt-in far-clipmap integration flag, `use_gpu_page_normal_backend`, for GPU-generated RGBF normal bytes in sync/fallback page commits.
- Added direct `Texture2DRD` capability and residency checks.
- Added an opt-in far-clipmap integration flag, `use_gpu_rd_page_textures`, for direct RD page textures from preencoded RF/RGBF bytes.
- Added a review-only `TerrainQualityProfile.GPU_PAGE_REVIEW` contract that routes the normal walk-preview scene through direct RD page residency without changing the saved default walk profile.
- Added saved review scene `res://worldgen_terrain/scenes/terrain_gpu_page_review.tscn`.
- Added a main-renderer-device compute-to-texture probe proving a compute shader can write an `R32F` texture RID that can be sampled/wrapped later.
- Added opt-in main-renderer-device far-page normal texture compute (`use_gpu_rd_compute_normals`) inside `TerrainGpuPageResidency`.
- Updated `gpu_page_review` and `terrain_gpu_page_review.tscn` so the review path now uploads RF height pages as `Texture2DRD` and computes RGBAF normal page textures directly on the main RenderingDevice.
- Renderer-enabled proof currently passes on D3D12 / RTX 5090 Laptop GPU.
- The probe validates:
  - storage-buffer dispatch
  - GPU readback
  - terrain-style height-page normal encoding
  - RGBF byte layout compatible with the existing far page texture payload path
  - CPU parity within `0.0001`
- The backend gate validates:
  - repeated page-normal dispatch through one compiled pipeline
  - same-size RGBF output byte layout
  - opt-in far-clipmap consumption of GPU-generated normal page data
- The direct RD residency gate validates:
  - `Texture2DRD` wrapping of main RenderingDevice texture RIDs
  - bounded far-page residency using RD textures instead of ImageTexture uploads
  - opt-in far-clipmap consumption of direct RD page textures
  - explicit RID teardown without leak warnings
- The GPU page review profile gate validates:
  - quality-profile wiring into the normal walk-preview scene
  - direct RD residency under the profile path
  - zero ImageTexture uploads for the profile's far pages
  - explicit scene/clipmap teardown without RID leaks
- The saved GPU page review scene gate validates:
  - the `.tscn` has the GPU review profile id
  - the saved scene enables the GPU page-normal/RD texture flags
  - the saved scene reaches direct RD page uploads with zero ImageTexture uploads
- The compute-to-texture probe validates:
  - main RenderingDevice storage-image writes
  - `R32F` texture readback for proof only
  - no invalid main-device `submit()` / `sync()` calls
- The direct RD compute-normal residency gate validates:
  - height page texture creation with storage-image usage
  - main RenderingDevice compute dispatch from height texture to normal texture
  - `Texture2DRD` wrapping of both height and computed normal texture RIDs
  - zero ImageTexture uploads on the opt-in review path
  - explicit cleanup of page texture and compute uniform-set RIDs
- Added renderer-only height-image far-page commits and worker payloads for the direct-RD
  review path. When `use_gpu_rd_page_textures` and
  `use_gpu_rd_compute_normals` are both active and the main RenderingDevice is
  available, sync commits and native workers now use RF height bytes only and
  skip CPU/native RGBF normal-byte generation. The old RF/RGBF payload stays as
  the fallback when RD compute is not available.
- Direct-RD page descriptors now avoid constructing CPU `Image` wrappers when
  raw RF/RGBF bytes can be handed directly to `Texture2DRD`; fallback
  ImageTexture descriptors are still built on demand if direct RD cannot be
  used.
- Added `TerrainPageTextureBackend` as the first page texture backend boundary.
  It owns the descriptor-to-texture decision, ImageTexture fallback, bounded GPU
  page residency, protected keys, and diagnostics while leaving
  `TerrainFarClipmapNode` as clipmap orchestration.
- Added `terrain_gpu_page_review_capture_check.gd` to the renderer-backed
  artifact path. It captures `terrain_gpu_page_review.tscn`, writes
  `factory/runtime/godot_gpu_page_review/gpu_page_review.png` plus a manifest,
  and verifies direct RD height/normal residency with zero ImageTexture uploads.

## Important Constraint

Do not wire the current local `RenderingDevice` probe directly into live streaming as a page-by-page runtime path.

Reason: the current probe creates a local device, dispatches compute, synchronizes, and reads data back to CPU. That is useful for capability and parity testing, but it would likely add stutter if used for live page generation.

The production path should avoid CPU readback where possible:

- generate/update GPU-resident page textures directly, and
- keep native worker generated bytes as the CPU fallback while GPU-direct texture writes mature.

## Next Integration Boundary

The current code boundary is now:

```text
height page bytes + page metadata
  -> TerrainPageTextureBackend
    -> ImageTexture fallback
    -> bounded Texture2DRD residency
    -> opt-in main RenderingDevice compute-to-texture normal path
  -> existing page residency/material commit contract
```

Acceptance for the next slice:

- no visual semantic change
- no per-frame renderer device creation in live terrain
- no forced GPU readback in the default walk scene
- direct RD texture residency remains opt-in until visual/perf acceptance
- direct RD compute normals remain opt-in until visual/perf acceptance
- height-image-only worker payloads remain tied to the direct-RD compute-normal
  path and must not be used by fallback ImageTexture materials
- `gpu_page_review` and `terrain_gpu_page_review.tscn` are the review entry points for this path; `walk_review` and `terrain_walk_preview.tscn` remain the production-safe/default review path
- the GPU page review capture must stay present in the Godot review index before
  the direct-RD path can be considered visually accepted
- fast and quality gates stay green
- `--suite gpu` proves any GPU path that claims to be enabled

## Not Done Yet

- Default live use of direct RD page textures.
- GPU compute-to-texture height-page generation from provider facts.
- GPU-resident material masks.
- GPU page generation from DEM/provider facts.
- Live walk scene defaulting to GPU compute.
- Re-promoting corridor tour as an acceptance gate.

Those remain roadmap work, not accepted finished systems.
