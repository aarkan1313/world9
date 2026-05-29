# GPU Page Backend Sprint

Status: blocked for live visual acceptance as of 2026-05-28.

The current durable direction is persistent terrain pages:

- stable world-space page requests
- native/provider height-page generation
- persistent page meshes
- shader displacement from height textures
- previous/current page blending
- coarse/fine LOD morph in shader
- bounded GPU page residency

## Active Blocker - 2026-05-28

Live review still shows a large black terrain slab/rectangle near the viewer
while the overlay can report full active chunk residency, no queued work, and no
active workers. This invalidates the previous assumption that the full level-0
underlay plus near residency halo solved the black-square failure.

Do not treat the current `fast` or `gpu` suites as visual acceptance for this
bug. They prove useful data contracts, residency counts, and some renderer
paths, but they do not currently prove that every visible near/far terrain
surface has valid geometry, material, texture bindings, and depth/culling state
during live fast movement.

Next work must be diagnostic before more feature work:

- identify whether the black slab is near chunk mesh, far clipmap page, page
  material fallback, invalid texture binding, stale payload, culling/AABB, or
  render-order/depth state
- add visible provenance/debug colors for near chunks and every far level
- add a renderer capture gate that fails on large near-camera black connected
  components when the terrain should be filled
- only then fix the source and update acceptance wording

The canonical restart/handoff for this blocker is
`plans/orchestrator_handoff_current_state.md`.

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
- Added a review-only `TerrainQualityProfile.GPU_PAGE_REVIEW` contract that first routed the normal walk-preview scene through direct RD page residency without changing the saved default walk profile; that path has now been promoted into `walk_review` after startup/motion gates passed.
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
- Runtime readiness now validates the GPU page review manifest directly, not
  just the review-index file presence.
- The same manifest now records far-page descriptor state and drain counters,
  locking the rule that the direct-RD review path uses raw height bytes /
  height-only page descriptors and does not rebuild CPU image wrappers for page
  materials.
- Added `terrain_gpu_page_review_motion_check.gd` to the renderer-enabled GPU
  suite. It drives `terrain_gpu_page_review.tscn` through several page-recenter
  movements, writes `factory/runtime/godot_gpu_page_review/gpu_page_motion_manifest.json`,
  and verifies each settled stop keeps direct-RD descriptors, zero descriptor
  image rebuilds, zero ImageTexture uploads, and no protected page-cache evictions.
- Promoted the default `walk_review` far-page path to use direct `Texture2DRD`
  height textures plus main RenderingDevice-computed normal textures whenever the
  renderer device is available.
- Added `terrain_walk_gpu_page_default_check.gd` so the saved
  `terrain_walk_preview.tscn` itself proves direct-RD far-page residency with
  zero ImageTexture uploads; `gpu_page_review` remains as the explicit visual
  acceptance scene for this same path.
- Added `TerrainGpuHeightPageBackend` as the first isolated GPU height-page
  generation proof. It uses a local `RenderingDevice` compute shader to produce
  RF macro-height page bytes from stable page parameters, validates against the
  authoritative CPU hash/noise math, and covers positive/negative world origins
  plus macro and regional profile scaling.
- Fixed the GPU macro-height shader hash path to match the existing
  GDScript/Rust wide-multiply hash semantics; a failed offset-page parity case
  caught the bug before live integration.
- Added `terrain_gpu_height_page_backend_check.gd` to the renderer-enabled GPU
  suite. It proves positive-origin pages, negative-origin pages, profile-scaled
  pages, byte layout, pipeline reuse, and fail-fast handling for malformed
  request dimensions/scales.
- Extended `TerrainGpuHeightPageBackend` with an isolated DEM-kernel sampling
  compute path. The gate loads a real normalized runtime kernel, samples it with
  the same mirrored bilinear rules used by `TerrainHeightProvider`, and proves
  GPU/CPU parity across negative coordinates, rotation, and UV offsets.
- Added an isolated prepared-provider page assembly compute path. It consumes
  the same prepared corner entries as the native prepared-grid path, flattens
  real runtime kernel arrays, and computes macro height, corner-blended kernel
  relief, detail noise, and valley shaping in one GPU dispatch with CPU-provider
  parity. Pass/corridor shaping is explicitly rejected in this proof path until
  route facts are moved into a GPU-friendly descriptor.
- Split prepared-provider page inputs into a reusable
  `worldgen9.gpu_provider_page_descriptor.v1` descriptor so the later
  renderer-device/no-readback path can consume the same validated params,
  entry bytes, and kernel bytes without changing terrain math.
- Extended `TerrainGpuPageResidency` so it can accept an externally supplied
  main-renderer-device `R32F` height texture RID, wrap it as `Texture2DRD`,
  compute the normal texture on the same renderer device, and own/free the RID
  through the existing bounded page residency lifecycle.
- The RD residency gate now validates the no-readback handoff shape required by
  live GPU height generation: a GPU-produced height texture can enter the page
  cache without CPU `Image` wrappers or ImageTexture uploads.
- Added `TerrainGpuProviderPageTextureBackend`, the first main-renderer-device
  provider-page compute backend. It consumes
  `worldgen9.gpu_provider_page_descriptor.v1`, writes directly into an `R32F`
  height texture RID, keeps dispatch resources alive through residency-owned RID
  cleanup, and hands the texture to `TerrainGpuPageResidency` for
  `Texture2DRD` wrapping plus renderer-device normal compute.
- Added `terrain_gpu_provider_page_texture_backend_check.gd` to the GPU suite.
  The gate proves descriptor-to-height-texture dispatch, zero ImageTexture
  uploads, residency handoff, RD normal compute, and explicit cleanup through the
  existing page lifecycle.
- Wired the provider-page texture backend into `TerrainFarClipmapNode` behind
  the opt-in `use_gpu_provider_page_textures` flag. Far pages can now split by
  base region, dispatch prepared-provider GPU compute blocks directly into one
  renderer-device `R32F` height texture, hand that texture to bounded page
  residency, and compute normal textures on the renderer device with zero CPU
  image wrappers or ImageTexture uploads.
- Extended the same provider texture gate with a live far-clipmap opt-in path.
  The test covers both a region-local clipmap page and a cross-region page at
  the origin, verifying provider dispatch/block counts, descriptor modes, zero
  sync bytes/images, zero ImageTexture uploads, and clean RD normal compute.
- Promoted the provider-page texture path into `walk_review`,
  `gpu_page_review`, `terrain_walk_preview.tscn`, and
  `terrain_gpu_page_review.tscn` when a renderer device is available. The
  review gates now assert cumulative provider-page dispatches, zero
  ImageTexture uploads, RD normal compute, and a non-error provider path while
  headless runs keep the CPU/native fallback behavior.
- Removed the hidden CPU height-page sampling cost from the provider-texture
  far-page commit path. When `use_gpu_provider_page_textures` is available,
  `TerrainFarClipmapNode` now builds only stable page metadata, dispatches
  provider blocks directly into the renderer-device height texture, and uses
  conservative page bounds for culling instead of sampling a CPU height array
  before the GPU dispatch. The CPU sampler remains as the fallback when the GPU
  provider path fails or is unavailable.
- Paced `gpu_page_review` / `terrain_gpu_page_review.tscn` far-page commits to
  one clipmap level per update so the explicit review scene proves the same
  no-readback renderer path without committing all levels in one visible hitch.
- Added `terrain_gpu_page_profile.tscn` and
  `terrain_gpu_page_hitch_profile_check.gd` as the focused far-page hitch
  profiler. The check drives fast motion across page recenters, writes
  `factory/runtime/godot_gpu_page_profile/gpu_page_hitch_profile_report.json`,
  and records per-frame step time, provider-page commit time, provider texture
  dispatch time, RD residency/material time, metadata-only commit counts, and
  ImageTexture/upload/eviction state.
- `TerrainFarClipmapNode` now exposes GPU provider-page phase timings in
  `stats()` so future hitch reports can distinguish provider descriptor work,
  renderer-device texture dispatch, texture residency/normal compute, mesh
  setup, and material assignment.
- The live provider-texture path is now bounded by
  `far_clipmap_gpu_provider_max_sync_blocks`. Pages that would require multiple
  synchronous region blocks are routed through the existing async/native
  height-page path instead of blocking the movement frame. Multi-region GPU
  provider dispatch remains covered by the isolated provider backend gate and
  should be re-promoted only after descriptor staging/prefetch removes the
  visible recenter hitch.
- Async staged far-page payloads now commit through
  `max_staged_payload_commits_per_update` instead of swapping every staged
  clipmap level in one update. The hitch profiler records staged commit count
  and staged commit time so frame-pacing regressions are visible without
  lowering terrain quality.
- Native near-chunk worker completions are now paced through
  `max_native_chunk_worker_results_per_update`. The focused hitch profiler
  records per-frame terrain build deltas and worker-result commits so near
  chunk completion bursts are visible separately from far-page GPU work.
- The streaming preview now treats active-but-unbuilt terrain chunks, queued
  terrain builds, queued native chunk workers, and active native chunk workers
  as pending visual work. This keeps GPU page/walk review scenes draining near
  terrain after motion stops instead of waiting for the next movement tick and
  then committing an edge burst.
- Far clipmap async payloads are now render-context scoped. Worker requests,
  worker payloads, staged payloads, and final commits carry/validate a
  `render_context_version` plus context key covering full-underlay, inner
  extent, persistent page mode, profile/provider identity, and GPU texture path
  state. Context flips clear old in-flight/staged work, and the handoff gate
  now checks actual level-0 mesh index count so stale hole-filtered topology
  cannot be accepted while stats report the page loaded.
- Added an opt-in near-chunk page-render path on `TerrainWorldNode` behind
  `use_gpu_page_chunks`. It keeps chunk topology as a shared persistent flat
  mesh per chunk density and displaces in a shader from page height textures,
  while unsupported modes still fall back to the existing mesh payload path.
- The first accepted near-page integration uses existing native chunk workers as
  the async height producer, then commits the completed height as a bounded
  `Texture2DRD` page with a cheap flat normal payload. This avoids the rejected
  main-thread near-page provider dispatch path, which was measured at visible
  multi-hundred-millisecond stalls when used per chunk.
- `terrain_gpu_page_profile.tscn` keeps direct-RD far clipmap provider-texture
  pages enabled, but near terrain page chunks are no longer part of the saved
  visual review profile. Live review showed under-camera rectangular page
  artifacts, so the accepted visual profile uses the proven native mesh near
  path until the page renderer passes parity/coverage review.
- `terrain_gpu_page_profile.tscn` and `terrain_gpu_page_review.tscn` now use
  three forward-prefetch steps, a one-chunk all-direction residency halo, ten
  native chunk workers, and eight native worker results per update. The halo is
  a real `TerrainStreamer` setting, not a scene-only workaround: it keeps the
  next base-window row resident before the player crosses a chunk boundary,
  while directional prefetch can still trail at the optional outer fringe.
- The hitch profiler now reports base-window missing chunks separately from
  optional prefetch/halo backlog and fails if the required visible base window
  has any data-level holes. After the residency-halo slice, the
  renderer-enabled profile passed with `max_terrain_missing_base_chunks=0`,
  `step_ms max=44`, `p95=11`, `frame_ms max=58`, `p99=40`, and zero ImageTexture
  uploads on the far page residency path. This is now known to be insufficient:
  the live scene can still show a large black slab while those counts look
  healthy.
- Live streaming profiles now keep far clipmap level 0 as a full underlay
  behind the authoritative near chunks instead of cutting a player-centered
  hole. This removed one suspected hole source but did not close the live visual
  blocker: black rectangular/slab terrain can still appear during review. Treat
  the underlay as an attempted mitigation, not an accepted fix.
- `TerrainQualityProfile.GPU_PAGE_REVIEW` and `terrain_gpu_page_review.tscn`
  now explicitly expect zero near GPU page chunks in saved visual review. The
  saved GPU page review scene/profile gates prove far clipmap provider-texture
  direct-RD residency while the near page renderer remains opt-in.
- The GPU page capture and motion manifests still record near page chunk counts,
  but require the saved review scene to keep that experimental path disabled
  until near GPU chunks have visual parity against native chunks.
- Extracted `TerrainChunkPageRenderer` as the near chunk page-rendering boundary.
  It owns bounded page texture residency, shared flat chunk meshes, page shader
  material creation, custom AABB assignment, and flat-normal placeholder bytes;
  `TerrainWorldNode` now keeps orchestration and height/page descriptors instead
  of owning all near page render mechanics.
- Added opt-in near provider descriptor staging. When
  `use_gpu_provider_page_chunk_descriptor_staging` is enabled, near chunks build
  prepared provider blocks into a bounded LRU cache over the update loop and
  direct provider chunk commits consume only staged descriptors. Missing staged
  descriptors no longer trigger hidden CPU mesh fallback; they either use the
  existing native-worker height-page route when that route is enabled, or requeue
  until the descriptor staging budget catches up.
- Added `terrain_gpu_provider_chunk_descriptor_staging_check.gd` to the GPU
  suite. It proves a single near chunk, a moving 3x3 near window, and a full
  7x7 review-window backlog can stage provider descriptors, dispatch
  renderer-device height textures, enter direct RD chunk residency, avoid
  ImageTexture uploads, and avoid staged-path CPU fallbacks without enabling the
  path as a saved-scene default.
- Added `terrain_gpu_provider_chunk_staged_hitch_check.gd` as an experimental
  promotion profiler for staged near provider chunks. It is intentionally not in
  the default GPU suite yet: the current review-density direct provider chunk
  path is correctness-clean but measures far too slow for live use
  (`p95/max step_ms` around `650ms` in the first profile, and still roughly
  `390ms` p95 after per-update commit-budget pacing). This confirms the saved
  scenes should keep native-worker near height pages until near provider
  dispatch is moved off the motion frame, made region-aware, or otherwise made
  much cheaper.
- Hardened direct provider texture ownership for cache-hit and failure cases.
  Provider-generated RD height textures and dispatch buffers are now either
  adopted by `TerrainGpuPageResidency` or explicitly released on rejection.
  Far clipmap and near chunk page paths now skip renderer-device provider
  dispatch when the target page is already resident, using a metadata-only
  descriptor so revisits do not allocate throwaway GPU resources.
- Re-ran the experimental staged near-provider hitch profile after the ownership
  and pacing fixes. Leak warnings are gone and the worst burst is smaller, but
  the profile still rejects promotion on frame pacing (`p95 step_ms` is roughly
  `390ms` after pacing). The per-frame report now shows the cause: descriptor
  staging is cheap, while synchronous provider texture creation costs roughly
  `125-260ms` per near page at review density. Descriptor staging and residency
  ownership are valid, but live review-density provider texture dispatch is
  still not acceptable for saved scenes.

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
    -> externally supplied renderer-device height texture residency
    -> opt-in main RenderingDevice compute-to-texture normal path
  -> existing page residency/material commit contract

prepared provider descriptor
  -> TerrainGpuProviderPageTextureBackend
    -> main RenderingDevice R32F height texture
    -> TerrainGpuPageResidency external-height path
    -> main RenderingDevice normal texture compute

far clipmap page
  -> opt-in TerrainFarClipmapNode.use_gpu_provider_page_textures
    -> base-region GPU provider descriptor block(s)
    -> renderer-device height texture
    -> bounded far-page residency/material commit

near chunk page
  -> opt-in TerrainWorldNode.use_gpu_page_chunks
    -> TerrainChunkPageRenderer render/residency boundary
    -> native worker height result
    -> RF height page bytes
    -> bounded Texture2DRD residency
    -> shared persistent flat chunk mesh
    -> shader displacement from height texture

near provider descriptor staging
  -> opt-in TerrainWorldNode.use_gpu_provider_page_chunk_descriptor_staging
    -> bounded prepared-block LRU cache
    -> direct provider texture dispatch only when descriptor is staged
    -> native worker height-page fallback or requeue when descriptor is missing
```

Acceptance for the next slice:

- no visual semantic change
- no per-frame renderer device creation in live terrain
- no forced GPU readback in the default walk scene
- direct RD texture residency remains explicit in the review profiles and keeps
  ImageTexture fallback for unsupported renderer contexts
- direct RD compute normals remain explicit in the review profiles and keep
  fallback paths for unsupported renderer contexts
- height-image-only worker payloads remain tied to the direct-RD compute-normal
  path and must not be used by fallback ImageTexture materials
- `gpu_page_review`, `terrain_gpu_page_review.tscn`, `walk_review`, and
  `terrain_walk_preview.tscn` now all exercise the provider-page texture path
  when a renderer device exists
- the GPU page review capture must stay present in the Godot review index before
  the direct-RD path can be considered visually accepted
- the GPU page motion manifest must stay present in runtime readiness now that
  the direct-RD path is promoted into `walk_review`
- the GPU page review scene/profile/capture/motion gates must prove direct-RD
  far pages while keeping near GPU page chunks disabled in saved visual review
  scenes; opt-in near chunk renderer tests remain the place to prove that path
- near provider descriptor staging must remain opt-in until a live hitch/profile
  gate proves it improves or preserves frame pacing in the saved review scene;
  the focused GPU gate now proves the full 7x7 review-window backlog without
  hidden CPU fallback, while the experimental live profiler currently rejects
  review-density staged near provider chunks as too slow
- fast and quality gates stay green
- `--suite gpu` proves any GPU path that claims to be enabled
- renderer-device height texture ownership is explicit; externally supplied page
  RIDs must declare whether residency owns cleanup
- provider-page GPU texture dispatch handles pages that cross base region
  boundaries by splitting them into per-region GPU blocks that write into one
  final renderer-device height texture
- the provider-texture path must not build a CPU `height_samples` array before
  dispatching the GPU texture except when falling back from an unavailable or
  failed GPU path
- staged async far-page commits must stay budgeted so direct-RD texture/normal
  uploads do not land as one all-level recenter burst
- native near-chunk worker result application must stay budgeted separately
  from worker count; worker parallelism may stay high without applying every
  completed chunk mesh in one movement frame
- near GPU page chunk commits have an optional per-update millisecond
  budget, `TerrainWorldNode.max_gpu_page_chunk_build_ms_per_update`, which is
  forwarded by the streaming preview scene. This is a pacing guard for the
  experimental path, not acceptance for saved visual review.
- near chunk page mode must keep the legacy mesh path as fallback for hydrology,
  non-fast-gray vertex-color debug, skirts, current geometric LOD-density
  experiments, missing renderer device support, and unsupported providers
- the measured main-thread GPU-provider near chunk path is not accepted for live
  streaming until descriptor staging/prefetch or an async renderer-device commit
  path removes per-chunk stalls

## Not Done Yet

- GPU-resident material masks.
- Full live walk scene height generation on GPU compute for near chunks/local
  detail. Near chunks have an experimental page renderer, but the accepted live
  review path currently stays on native mesh chunks because near page chunks
  showed under-camera rectangle artifacts in live review.
- Pass/corridor facts, hydrology facts, erosion facts, and any final provider
  branches beyond the macro-height/page-profile/kernel/provider-page proof.
- Async/staged near provider-page compute promotion in saved scenes. The focused
  GPU gate proves full-window descriptor backlog behavior, but the saved walk
  and GPU review scenes should keep native-worker near height pages until the
  hitch profiler proves staged provider chunks preserve live frame pacing. The
  first live staged-provider profile measured roughly `650ms` p95/max step time
  at 129x129 review density. After commit-budget pacing and finer telemetry,
  the same rejected profiler now shows descriptor staging is cheap
  (`~5-8ms/frame`) while renderer-device provider height texture creation is the
  blocker (`~125-260ms` per near page, worse when a chunk crosses region
  boundaries and splits into multiple provider blocks). The next real fix is
  async/prefetched renderer texture commits, a cheaper persistent provider
  dispatch path, or a region-aware page layout, not enabling synchronous
  provider chunks by default.
- Re-promoting corridor tour as an acceptance gate.

Those remain roadmap work, not accepted finished systems.
