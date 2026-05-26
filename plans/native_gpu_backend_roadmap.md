# WorldGen9 Native/GPU Backend Roadmap

Last updated: 2026-05-26

## Decision

Stop treating GDScript terrain generation as the performance path.

GDScript remains the reference/orchestration layer for:

```text
scene setup
debug mode switching
visual review tools
parity checks
small editor controls
```

Performance-critical terrain work moves behind a native backend contract.

## Why Not GPU First

GPU-only terrain generation is the wrong first replacement because the game also
needs CPU-side facts:

```text
player/camera ground height
collision heightfields
physics queries
save/edit layers
AI/navigation facts
deterministic seam tests
hydrology and river graph inputs
```

The immediate backend should generate deterministic CPU facts quickly, then feed
GPU-friendly buffers. GPU work comes after that contract is stable.

## Backend Order

1. [x] Native backend registration and smoke test.
2. [x] Native grid/mesh budget and request contract.
3. [x] Native height-grid generation matching GDScript/Python parity fixtures.
4. [x] Native mesh payload generation for vertices, normals, UVs, and indices.
5. [x] Single-call native chunk payload generation to avoid Godot/Rust boundary churn.
6. [x] Worker-thread queue for fast-gray native chunk payload builds.
7. [x] Godot scene handoff: main thread only assigns `ArrayMesh`/collision objects.
8. [x] Ring LOD mesh densities and skirted LOD chunks for a larger retained area.
9. [x] Far-terrain visual clipmap prototype for broad horizon coverage.
10. [x] Promote `129 x 129` walk/review terrain after native height timings pass.
11. [x] Test `257 x 257` and 1m-local-detail strategies.
12. [x] Define near-player 1m detail tier policy.
13. [x] Add opt-in local 1m detail patch renderer without changing default streaming.
14. [x] Add local 1m CPU height query and collision-heightfield descriptor contract.
15. [x] Add opt-in local 1m collision body lifecycle behind an explicit runtime flag.
16. [x] Add native worker queue for local 1m detail patch payloads.
17. [x] Add first GPU-friendly local height/normal surface descriptor contract.
18. [x] Add optional texture-backed local material upload path.
19. [x] Add first GPU-friendly far-clipmap height/normal surface descriptor and upload contract.
20. [x] Add first backend-neutral slope/curvature/debug-map surface images.
21. [x] Add first edge-safe visual displacement texture and local shader toggle.
22. [x] Wire visual displacement into streaming preview review controls and no-op texture optimization.
23. [x] Add meter-capped visual displacement review control.
24. [x] Add live local-detail material/displacement review toggles and active-patch refresh.
25. [x] Reuse active local-detail surface materials for parameter-only review changes.
26. [x] Add rendered local-detail texture/displacement review capture.
27. [x] Promote/optimize GPU displacement for production review.
28. [x] Add live walk-preview local-detail texture/displacement review captures.
29. [x] Align the walk-preview chunk window and far-clipmap near hole with a tested zero-delta handoff.
30. [x] Start walk/review positions at chunk centers to avoid artificial first-move clipmap rebuild hitches.
31. [x] Budget real chunk-boundary far-clipmap recentering to one ring rebuild per update.
32. [x] Add native far-clipmap mesh payload generation for centered vertices and hole-filtered indices.
33. [x] Add async native-worker far-clipmap payload rebuilds for walk/streaming previews.
34. [x] Harden rapid async far-clipmap recentering so in-flight stale workers never force synchronous fallback.
35. [x] Add a fast Godot runtime gate for native clipmap, far continuity, async recenter, and walk preview checks.
36. [x] Add an extended Godot runtime gate suite for native height/mesh/chunk payload parity, renderer-boundary coverage, far surface material/review controls, native chunk workers, LOD continuity, and local-detail worker/material paths.
37. [x] Add a quality Godot runtime gate suite for landform, hydrology, debug-mode performance, streaming performance, and high-density walk checks.
38. [x] Add a non-headless render gate suite for deterministic preview, streaming, LOD/skirt, far-clipmap, and local-detail capture artifacts.
39. [x] Add a non-headless review gate suite for multi-location landform and 65-vertex scale contact-sheet artifacts.
40. [x] Add a deterministic Godot review index for current visual artifacts.
41. [x] Add deterministic far-clipmap budget reporting and scene-level clipmap sizing controls.
42. [x] Add a 4-ring wide far-clipmap review capture for larger-area scale decisions.
43. [x] Harden live far-clipmap geometry reconfiguration so level-count changes rebuild actual clipmap nodes.
44. [x] Add live 3-ring/4-ring far-clipmap review toggle and diagnostics coverage.
45. [x] Add streaming-preview far-clipmap overview camera helper for inspecting larger coverage.
46. [x] Add live streaming 3-ring/4-ring far-overview contact sheet and deterministic manifest to the review index.
47. [ ] Human-review local-detail texture/displacement in the live walk preview before default enabling.
48. [x] Add a walk motion/recenter profile gate and guide for diagnosing frame-time, residency, and visual recenter causes before more clipmap tuning.
49. [x] Add the first `TerrainQualityProfile` source of truth for walk review near/far/fog/worker/camera settings and gate it in the fast suite.
50. [x] Add a visibility/fog contract gate that reports loaded radius, camera far, hidden buffer, fog begin/end, transition length, edge shader fog settings, and viewer-tracked fog center.
51. [x] Add movement-direction forward prefetch to the walk profile and gate the fast-flight near residency contract.
52. [x] Add an elevation-color review material for near/far terrain and make it the default walk-review surface before real biome textures.
53. [x] Add a worldgen capability gate proving diverse palettes, families, kernels, and active DEM-kernel relief across review regions.
54. [x] Allow persistent far-page clipmap recenter payloads to use native workers, cache worker-completed height pages, and preserve previous/current page-height blend on commit.
55. [x] Seed initial walk-review stream priority from camera direction and split motion-profile residency into base-window versus prefetch-window readiness.
56. [x] Add first GPU-resident far page texture residency cache with protected-key eviction, live budget diagnostics, walk-profile control, and fast gate coverage.
57. [x] Add persistent page displacement bounds via custom AABBs that cover current and previous height pages during shader blend.
58. [x] Promote the default walk far clipmap to persistent texture-displaced page meshes using raw height pages and shader-only coarse/fine morph.
59. [x] Reuse persistent far page shader materials across page commits while preserving previous/current height-page blend sources.
60. [x] Skip far page height/normal image rebuilds when a page commit can reuse already GPU-resident textures.
61. [x] Gate walk-motion far page GPU upload/eviction budgets so page-residency churn cannot silently regress.
62. [x] Add an opt-in `local_detail_review` quality profile and gate it as review-only before default enabling.
63. [x] Move local-detail review surface/material perf budgets into the `local_detail_review` profile and consume them from the runtime gate.
64. [x] Add an opt-in `high_density_257_review` quality profile and make the 257v walk perf probe consume its settings and budgets.
65. [x] Add a compact kernel-gallery review scene and headless contact-sheet gate proving all current runtime kernel IDs are selectable as live provider terrain.
66. [x] Add a high-camera live kernel-tour scene that advances through diverse selected kernel sites using the normal walk-preview streaming stack.
67. [x] Capture the landform tuning and erosion-order plan before changing generator defaults.
68. [x] Add review-only landform tuning profiles for scale/relief/kernel influence before changing defaults.
69. [x] Add same-site landform profile comparison metrics and review artifacts.
70. [x] Add a live landform profile tour scene for visual comparison of current balance, stronger mountains, and compressed scale through the normal walk/far terrain stack.
71. [ ] Move far page generation/upload toward GPU compute or lower-churn native texture upload after texture-displaced page rendering remains visually accepted.

## First Backend Shape

Use the currently available local toolchain:

```text
Rust GDExtension
godot-rust 0.5.2
Godot API 4.6
```

The contract is language-neutral. If C++ tooling is later preferred, the C++
backend should implement the same methods and gates.

## Near Terrain Targets

Current problem:

```text
2048m chunk / 33 vertices = 64m spacing
512m chunk / 65 vertices = 8m spacing
512m chunk / 129 vertices = 4m spacing, too slow in GDScript
```

Desired progression after native generation:

```text
512m chunk / 129 vertices = 4m responsive walk review
512m chunk / 257 vertices = 2m high-detail review
256m chunk / 257 vertices = 1m local player-detail tier
far terrain handled by lower-density rings or GPU clipmap
```

Do not expect the DEM-kernel macro terrain alone to provide final 1m detail.
The 1m tier needs a local detail layer on top of the deterministic base height.

## GPU Role

Use GPU for:

```text
far terrain clipmap or ring mesh
height/normal textures
detail displacement
normal/curvature maps
debug heatmaps
possibly compute-assisted tile buffers
```

Keep CPU/native ownership of:

```text
authoritative base height
collision heightfields
world facts
streaming decisions
save/edit layer composition
seam/parity tests
```

## Acceptance Gates

Native work is not allowed to replace GDScript output until these pass:

```text
native backend loads in Godot 4.6
backend status/metrics smoke check passes
height sample parity matches `terrain_sample_reference.json`
chunk grid parity matches `chunk_reference_manifest.json`
mesh parity matches `mesh_reference_manifest.json`
streaming active-set behavior remains unchanged
chunk edge height deltas remain zero within the declared epsilon
walk preview reaches 4m spacing without editor-stalling
runtime release gate remains pass
```

## Current Status

Release Rust GDExtension is now active for prepared height-grid generation.
The native height path matches the GDScript parity grid exactly and is enabled
by default when the backend is loaded, with GDScript fallback for unsupported
cross-region grids or native failures.

Current measured results:

```text
33x33 streaming, warm: ~3.0ms average chunk build, 3ms max
33x33 streaming, cold: ~10.6ms average chunk build, 42ms max
129x129 native chunk payload direct: ~19-35ms for height + mesh payload
129x129 walk preview, radius 2: 25 retained chunks, worker payloads ~18ms average, 19ms max
129x129 walk preview movement step after workers: ~0-2ms in the perf check
129/65/33 skirted LOD walk preview, radius 4: 81 retained chunks with max LOD capped at 2; fast perf gate passes on the current machine
129/65/33 skirted LOD walk preview movement step: ~1-3ms in the perf check
far visual clipmap prototype: 3 rings, 49,923 vertices, 221,184 indices
far visual clipmap budget: 3 rings cover 32.768km diameter at ~2.569 MiB mesh+height; 4 rings cover 65.536km at ~3.428 MiB
far visual clipmap live-scene budgets: streaming/walk previews now keep level 0 as a narrow overlap band beneath authoritative chunk edges while retaining tested near/far handoff extents for diagnostics
far visual clipmap live reconfigure: tested 3-ring to 4-ring rebuild updates actual node count and vertex totals
far visual clipmap live review: live walk preview defaults to 4 rings (~32.768km radius / 65.536km diameter), while H still toggles 3-ring/4-ring coverage in review scenes; diagnostics report far 3L or far 4L
far visual clipmap overview camera: J frames the active far clipmap in the streaming preview for large-area review
far visual clipmap overview review: streaming-scene 3-ring/4-ring contact sheet is locked in the Godot review index
far clipmap transitions: tested zero height delta between adjacent clipmap levels
walk near/far handoff: tested zero height delta at the chunk-window boundary, with visual far level 0 overlapping just inside authoritative near chunk edges to eliminate moat/black-ring gaps
walk preview with far clipmap mounted: setup ~217ms, movement step ~2-3ms after chunk-centered spawn
walk small-move perf: far clipmap build counts remain unchanged instead of rebuilding on first movement
walk chunk-boundary recenter: first edge crossing keeps far rings stable; larger travel schedules far rings asynchronously through native workers, then finishes pending levels without blocking the movement frame
rapid far recenter: boundary ping-pong keeps counts unchanged; rapid larger recenter while level 0 is in flight defers instead of synchronously rebuilding, then all levels finish at the newest origin
fast Godot runtime gate: 19 checks, pass on the current machine, including the quality-profile, visibility-contract, elevation-color material, GPU page residency, walk motion/recenter profile, and forward-prefetch residency gates
extended Godot runtime gate: 33 checks, pass on the current machine
quality Godot runtime gate: 11 checks, including the worldgen capability and kernel-gallery/tour proofs
walk motion profile: high-speed forward profile writes `factory/runtime/godot_walk_motion_profile/walk_motion_profile_report.json`; current first pass proves recenter/page-blend coverage, and the first near-residency optimization slice now prefetches the next movement-biased chunk row
forward-prefetch residency: the walk profile keeps 49 base chunks plus one movement-biased overlap row resident after motion is known, with the fast gate proving 56 cardinal-forward chunks after workers drain
startup prefetch residency: walk setup now preloads the initial camera-forward row; the motion profile reports base-window misses separately from still-building optional prefetch rows
page-backed far workers: persistent far clipmap recentering now schedules native page payload workers, keeps old pages visible while the full level set is pending, caches completed height pages, and starts previous/current height-page blending when the worker set commits
GPU page residency: persistent far page height/normal textures now flow through a bounded residency cache with protected active page keys, upload/hit/eviction/MiB diagnostics, and a walk-profile page limit. This is the first GPU-resident page step; persistent texture-displaced rings remain the next renderer promotion.
persistent page bounds: shader-displaced far pages now set per-level custom AABBs from current and previous page height ranges, preventing engine culling from treating the page as a flat y=0 mesh during height-page blend
persistent page morph: page heightfields now retain raw provider samples in persistent mode; the shader owns coarse/fine LOD morph against the next level height page, avoiding double-morphing transition bands before shading
persistent page material reuse: page commits now update the existing page ShaderMaterial in place instead of allocating a new material per level, while still preserving the previous height/normal textures for shader blend
persistent page descriptor reuse: returning to an already GPU-resident far page uses a lightweight descriptor and reuses resident height/normal textures instead of rebuilding CPU images before the cache hit
walk motion GPU page budget: the motion profile now fails if far page GPU uploads exceed the level-set budget or if the residency cache evicts pages during the profile
elevation-color review: near chunks and far clipmap shaders can use the same dark-low/rainbow-mid/white-high height ramp; gray remains available for old review captures
worldgen capability proof: `terrain_worldgen_capability_check.gd` currently samples 12 diverse region sites and reports 6 palettes, 9 families, 20 unique kernels, with DEM-kernel relief active at all sites
kernel gallery/tour proof: `terrain_kernel_gallery.tscn` builds a compact review grid from real provider-sampled world sites; `terrain_kernel_gallery_contact_sheet_check.gd` writes `factory/runtime/godot_kernel_gallery/kernel_gallery_contact_sheet.png` and currently finds all 36 runtime kernel IDs with 0 missing IDs. `terrain_kernel_tour.tscn` uses the normal walk-preview streaming stack from a high camera and advances through diverse selected kernel sites for live review

landform tuning proof: `terrain_landform_profile_compare_check.gd` writes `factory/runtime/godot_landform_profiles/landform_profile_report.json` plus `landform_profile_contact_sheet.png`; it compares `balanced_current`, `strong_mountains`, and `compressed_scale` at the same selected sites, verifies the neutral profile does not move default terrain, and gates profile seam deltas. Erosion remains later: after base relief/scale, kernel influence, hydrology hints, and first river/pass routing facts are stable
landform live review: `terrain_landform_profile_tour.tscn` cycles `balanced_current`, `strong_mountains`, and `compressed_scale` on representative sites using the normal walk/far terrain stack. `V` advances profile manually, `P` toggles auto profile cycling, and `N`/`B` still move across selected sites.
visibility contract: `terrain_visibility_contract_check.gd` writes `factory/runtime/godot_visibility_contract/visibility_contract_report.json` and keeps edge fog constrained to the outer loaded boundary instead of allowing broad fog as a clipmap/LOD cover-up
local-detail quality profile: `local_detail_review` is an opt-in review-only profile that starts from `walk_review`, enables one native-worker 1m local-detail patch, turns on the texture material plus bounded visual displacement, keeps collision bodies off, and is validated by the quality-profile gate
local-detail review budgets: the streaming local-detail surface perf gate now reads patch assign, surface texture, parameter refresh, displacement-toggle, move-update, and drain-frame budgets from `local_detail_review`
high-density review profile: `high_density_257_review` is an opt-in review-only profile for 257v / 2m near chunks; the 257 walk perf probe now reads its settings and budgets instead of carrying private constants
quality Godot runtime gate: 13 checks, pass on the current machine; debug perf raw timings stay in stdout so locked artifacts remain deterministic; runtime readiness checks landform/hydrology report schemas, case counts, field policies, and seam deltas
render Godot runtime gate: 6 non-headless capture checks, pass in ~17.5s on the current machine; static preview capture uses native/fast-gray chunk payloads where possible, and locked render artifacts avoid volatile diagnostic overlay text
review Godot runtime gate: 4 non-headless contact-sheet checks, pass in ~32.2s on the current machine; release gate remains pass after repeated review runs
Godot review index: deterministic HTML/JSON index locked in the runtime artifact manifest; runtime readiness checks schema, section order, required review files, and PNG dimensions
512m / 257v / 2m walk-preview probe: 49 retained chunks in the opt-in 7x7 review window, setup ~114ms, average build ~20.6ms, max build 72ms, small movement steps ~2ms
129/4m vs 257/2m walk-density capture: locked side-by-side visual artifact for human scale/detail review
walk-density budget with skirts: default 129/4m 9x9 is ~572,416 triangles / 16.652 MiB with max LOD capped at 2; opt-in 257/2m 7x7 is ~1,947,648 triangles / 56.129 MiB
runtime budget release guard: readiness checks enforce baseline 65/129/257 LOD totals, walk-density memory/triangle costs, and far clipmap 3/4-ring budget envelopes
walk readability guard: gray/far-clipmap materials are capped for non-washed-out review, live walk preview starts at 48m fly height, and the walk-density manifest gates max luma, bright-pixel fraction, and luma range
walk review control: `G` toggles between free-fly and height-provider ground-follow mode so player-scale terrain can be inspected without adding physics/collision to the visual renderer
visual seam/material pass: near fast-gray chunks and far clipmap gray/surface-review materials now share the same world-height shading response, review normals guard degenerate geometry, vertical skirt walls are de-emphasized, visual clipmap level 0 uses a handoff overlap band with a downward bias, far-ring handoffs overlap by one cell, and the live far anchor is stable across chunk-edge ping-pong. Page-backed far clipmap transitions must remain opaque and use world-space previous/current height-page blend plus coarse/fine morph, not whole-square alpha crossfade.
257x257 direct native payload at 512m chunk size / 2m spacing: ~68-70ms, 0.0 seam delta
257x257 direct native payload at 256m chunk size / 1m spacing: ~63-66ms, 0.0 seam delta
```

The old separate native mesh-payload toggle is not promoted. It timed out when
used as a two-call path at the 129x129 walk tier. The replacement single-call
native chunk payload path now runs through a small worker queue for the
fast-gray walk preview. `ArrayMesh` construction and scene assignment remain on
the main thread. GPU work still belongs after CPU/native facts are stable.

The first far clipmap is now present as a visual-only renderer. It uses the same
height provider as near chunks and snaps all ring levels to one shared base
origin so fine/coarse ring transitions remain concentric. The walk/streaming
preview now keeps clipmap level 0 as an overlap band beneath the authoritative
near chunk edge, with a downward visual bias and a tested handoff extent. This
removes the moat-style black-ring failure mode while preserving exact-zero
height deltas at the chunk-window boundary. This is still a CPU prototype; it
is not the final GPU/height-texture clipmap.

Walk/review starts are chunk-centered instead of placed on exact chunk
boundaries. This avoids the fake first-step hitch where a tiny movement from
`(0,0)` crossed into the neighboring chunk and rebuilt all far clipmap rings in
one frame. Real chunk-boundary recentering still exists and should move behind
the native/GPU clipmap path later.

Real far recentering is now budgeted in the CPU prototype, but the walk preview
does not recenter far rings just because the viewer crosses one chunk edge. The
stable far anchor only moves after meaningful travel; then the preview rebuilds
one far clipmap level per update, prioritizing level 0 so the near/far handoff
updates first. The remaining far rings complete on following updates and the
overlay reports pending far rebuilds and active workers. Far clipmap levels now
also use a native mesh payload helper for
centered vertices, normals, UVs, and hole-filtered indices. The walk/streaming
preview opts into async far clipmap workers so movement frames schedule the
level rebuild instead of doing height/mesh work synchronously. Direct
`TerrainFarClipmapNode` instances remain synchronous by default for focused
tests and standalone tools. This is still a transitional CPU/native path;
production clipmaps should move height/normal buffers and ring updates to the
GPU contract.

Rapid recentering is explicitly guarded: chunk-edge ping-pong does not request
a new far origin, and if a far level already has a worker in flight while the
viewer requests a newer threshold-crossing origin, the level is deferred rather
than rebuilt synchronously. The stale worker result is ignored if it no longer
matches the latest pending origin, and the next worker assignment finishes at
the newest origin. This avoids reintroducing boundary hitches during fast
flight.

`tools/godot_runtime_gate.py` is now the headless and renderer-backed Godot gate
for this runtime slice. It complements the existing no-write artifact/readiness
gate. The default `--suite fast` runs native backend registration, native
clipmap payload, far clipmap smoke/transition, near/far handoff, async boundary
recenter, rapid recenter, far-surface async recenter, and walk preview
smoke/perf checks. `--suite extended` adds native prepared-height, mesh-payload,
chunk-payload parity, native chunk worker, far-clipmap surface material, live
far-surface review controls, world-node native worker, mixed-density LOD edge
continuity, local-detail stale worker, local-detail review controls, and
local-detail surface/displacement perf checks. `--suite quality` adds slower
landform, hydrology, debug-mode performance, streaming performance, and the
isolated `512m / 257v / 2m` walk-density probe. The debug-mode performance
artifact stores deterministic pass/fail timing checks instead of raw measured
milliseconds, so running the quality suite does not invalidate the no-write
runtime artifact gate.

The clean sequence from here is:

```text
chunk-density LOD morph policy -> longer-distance clipmap coverage -> human LOD/clipmap review -> define near-player 1m tier policy -> GPU detail/normal maps
```

The `257 x 257` probes are promising for two separate roles: `512m / 257v` as
an opt-in 2m high-detail walk/review tier with LOD rings, and `256m / 257v` as
a 1m local/collision/edit tier. They should not be promoted blindly as the
default global active density: each dense payload is about 3.95 MB before Godot
mesh overhead, and the long-term shape should keep broad terrain on
clipmaps/LOD rings while reserving the densest 1m layer for the near-player
collision/edit window.

`TerrainDetailTierPolicy` now defines that local window shape without changing
the live preview. The current policy snaps `256m / 257v` detail patches to
world-space patch coordinates, keeps 1m spacing, aligns every fourth detail
sample to the current 4m base grid, and handles negative coordinates with floor
semantics. This gives collision/edit/local visual detail a stable request layer
before it is connected to streaming or GPU buffers.

`TerrainLocalDetailNode` is now the first opt-in runtime connection for that
policy. It builds snapped 1m local patches through the native payload path when
available, creates the Godot mesh on the scene thread, retires patches
independently of broad terrain chunks, and can be mounted by the streaming
preview with `use_local_detail = true`. The saved walk preview keeps it off by
default so the current 81-chunk LOD/clipmap review path remains stable.

The local detail node now also keeps CPU-side heightfield facts for active
patches. `sample_height()` queries active local 1m heightfields first and falls
back to the authoritative world provider outside the local window.
`active_collision_heightfields()` exposes neutral descriptors containing origin,
spacing, dimensions, height array, and min/max height. This is not physics
collision yet; it is the contract that lets collision be generated near the
player without involving far chunks or visual clipmaps. `collision_shape_for_key()`
can now materialize a `HeightMapShape3D` from an active local heightfield on
demand, but no collision body is created or attached by default.

Physics collision can now be enabled explicitly on `TerrainLocalDetailNode` with
`enable_collision_bodies = true`, or through the streaming preview's
`enable_local_collision_bodies` flag when local detail is also enabled. The node
creates one `StaticBody3D` per active local detail patch, places the centered
`HeightMapShape3D` at the patch center, scales X/Z by the local spacing, and
retires bodies when patches leave the local window. This is still a near-player
collision path only; broad visual chunks and far clipmaps remain collision-free.

Local detail patch payloads can now run through the same native worker contract
as streamed chunks. `TerrainLocalDetailNode.use_native_workers` defaults on for
opt-in local detail, queues one active patch build by default, assigns meshes
and optional collision bodies on the scene thread after the worker completes,
and ignores completed work for patches that are no longer desired. The worker
check currently shows the patch transition update itself around 1ms while the
~68ms dense payload runs off-thread.

The stale-worker path is now explicitly covered: if the viewer moves to another
local patch before a dense payload worker completes, the old result is ignored
and cannot attach stale mesh or collision. The current implementation cannot
force-kill an already-running Godot thread safely, so stale active work may run
to completion, but it is filtered before scene assignment.

The streaming-level local detail worker performance check now runs with local
detail, native workers, and local collision enabled. Current result: setup
around 41ms, patch-transition update steps around 4/1/1ms, and dense worker
payloads around 69ms. This closes the immediate `257 x 257` local-detail worker
strategy gate while keeping the saved walk preview unchanged.

The first GPU-prep surface contract is now in place. `TerrainSurfaceTextureBuilder`
converts authoritative height arrays into `Image.FORMAT_RF` height images,
`Image.FORMAT_RGBF` normal images, decoded normal values, and min/max/range
metadata. `TerrainLocalDetailNode.active_surface_texture_descriptors()` exposes
those images for active local detail patches from the same heightfield used for
mesh and collision. This does not start GPU compute or shader displacement yet;
it establishes deterministic CPU-to-GPU upload data for the near-player tier.

`TerrainChunkRenderer` is now the first explicit renderer boundary for broad
chunk surfaces. It owns `MeshInstance3D` lifecycle and bounded pooling while
`TerrainWorldNode` keeps the build policy, provider, and debug-mode decisions.
This keeps future GPU/clipmap renderer replacement from depending on the world
or provider internals.

`TerrainLocalDetailNode` also has an opt-in texture-backed material path via
`use_surface_texture_material`. When enabled, each active local patch uploads
its authoritative RF height image and RGBF normal image into shader parameters
for rendering. This is intentionally disabled by default because the CPU
heightfield remains authoritative and the texture upload cost belongs behind a
budgeted local-detail/GPU policy before it is used in normal play.

`TerrainFarClipmapNode` now follows the same contract for broad horizon terrain.
Each rebuilt clipmap level retains a cheap CPU heightfield descriptor by
default, while `active_surface_texture_descriptors()` can materialize RF height
and RGBF normal images for inspection or GPU upload tests. The optional
`use_surface_texture_material` path uploads those images into per-level shader
materials, but remains off by default so the walk preview does not pay texture
build/upload cost during normal review.

The live streaming/walk preview can toggle that far-clipmap texture-backed
material with `U`. This keeps far horizon height/normal texture review in the
normal flight scene without enabling local 1m detail patches or changing the
authoritative CPU height/collision contracts.

Far surface review still uses the async native clipmap worker path for boundary
recenters. Completed worker payloads build the per-level surface descriptors on
assignment, so enabling `U` does not fall back to synchronous height/mesh ring
rebuilds during flight.

The far material path now uses a lightweight descriptor that only builds the
height and normal images the shader consumes, reusing native mesh normals from
the completed payload. Full slope/curvature/heatmap/displacement descriptors
remain available through `active_surface_texture_descriptors()` for diagnostics,
but are no longer paid by ordinary `U` review.

Active far surface materials now also support parameter-only refreshes. Changing
far normal strength while the texture-backed material is already enabled updates
the shader parameter in place instead of rebuilding the height/normal textures
or replacing the material.

Surface descriptors now include the first debug-map payloads as well:
`slope_deg_image`, `curvature_image`, raw slope/curvature arrays, and a compact
RGBF debug heatmap where red is slope, green is curvature magnitude, and blue is
normalized height. These maps are derived from the same authoritative height
arrays as mesh, collision, and clipmap descriptors, giving future shader/debug
views a common data contract instead of one-off per-scene calculations.

The first visual displacement contract is also present. Surface descriptors can
emit `visual_displacement_image` and raw residual values derived from the
authoritative heightfield by subtracting a local smoothed height. Border samples
are edge-locked to zero so enabling visual displacement cannot pull neighboring
patch edges apart. `TerrainLocalDetailNode` can opt into this through
`use_visual_displacement` and `visual_displacement_strength` when the
texture-backed material path is enabled. It is still shader-only and disabled by
default; collision, height queries, save/edit facts, and seam tests remain tied
to the CPU/native heightfield.

The streaming preview can now opt into the local detail texture material and
visual displacement path with explicit exported controls:
`use_local_detail_surface_material`, `local_detail_surface_normal_strength`,
`use_local_detail_visual_displacement`, and
`local_detail_visual_displacement_strength`. This keeps human review possible
from the normal preview scene without promoting the path globally. When the
surface material is enabled but visual displacement is disabled, the shader gets
a shared 1x1 zero displacement texture instead of building a full displacement
map, so normal texture-material review does not accidentally pay displacement
cost.

Visual displacement review is now bounded by `visual_displacement_limit_m`,
also exposed from the streaming preview as
`local_detail_visual_displacement_limit_m`. The shader clamps residual
displacement to that meter limit before applying the review strength. This keeps
the path useful for visual tuning while preventing rough kernels from producing
large accidental spikes.

The walk/streaming preview can now toggle the local detail texture material and
visual displacement during a running review. Pressing `T` toggles the local
detail texture material path; pressing `Y` toggles visual displacement and
mounts local detail on demand if it was not already active. Existing local
detail patches refresh their material immediately from retained CPU heightfields,
so review does not require flying across a patch boundary to see changes.

Active surface materials now update shader parameters in place when the required
texture set is already available. Changing normal strength, displacement
strength, or displacement meter cap no longer rebuilds height/normal/displacement
textures for active patches. A rebuild is still allowed when enabling a texture
path that was not previously present, such as turning displacement on after a
texture-material-only review.

Local-detail material/displacement review captures now write:

```text
D:/workflows/worldgen9/factory/runtime/godot_local_detail_displacement/local_detail_base.png
D:/workflows/worldgen9/factory/runtime/godot_local_detail_displacement/local_detail_texture_material.png
D:/workflows/worldgen9/factory/runtime/godot_local_detail_displacement/local_detail_displacement.png
D:/workflows/worldgen9/factory/runtime/godot_local_detail_displacement/local_detail_displacement_manifest.json
```

These captures compare plain local-detail terrain, texture-backed normal-map
material review, and bounded visual displacement review from the same
authoritative 1m heightfield. The manifest records the 257x257 / 1m patch
budget, image readability stats, and review flags. Runtime readiness now checks
that schema, budget, image stats, and subtle-displacement flag. Current capture
metadata marks displacement as visually subtle, so this remains a review-only
path rather than a default setting. The render test also keeps a headless skip
path so CI-style runs do not fail when Godot starts without a real renderer.

The first production-review optimization is also in place. Local-detail surface
materials now reuse the mesh normals already produced by the native payload, and
the residual visual-displacement values are generated by the Rust backend on the
worker/sync native path instead of by GDScript on the scene thread. The measured
local-detail surface/displacement perf gate moved from roughly:

```text
before: patch assignment ~160ms, surface descriptor ~155ms
after:  patch assignment ~20ms,  surface descriptor ~13-14ms
```

This still is not the final GPU compute path. The current contract is:

```text
native CPU: authoritative height, normals, visual displacement residual values
Godot main thread: ImageTexture upload and material assignment only
GPU shader: bounded visual-only vertex displacement and normal-map shading
```

The path remains opt-in for review. Collision, height queries, seam tests, and
save/edit facts still use the authoritative CPU heightfields.

The actual walk-preview scene now has its own local-detail review capture set:

```text
D:/workflows/worldgen9/factory/runtime/godot_walk_local_detail_review/walk_base.png
D:/workflows/worldgen9/factory/runtime/godot_walk_local_detail_review/walk_local_texture.png
D:/workflows/worldgen9/factory/runtime/godot_walk_local_detail_review/walk_local_displacement.png
D:/workflows/worldgen9/factory/runtime/godot_walk_local_detail_review/walk_local_detail_contact_sheet.png
D:/workflows/worldgen9/factory/runtime/godot_walk_local_detail_review/walk_local_detail_manifest.json
```

This uses the same first-person/free-fly preview scene as normal human review,
waits for streamed chunks and local-detail workers to settle, and captures base
terrain, local texture-material review, and bounded displacement review from the
same camera. The manifest records the same patch budget and image stats as the
isolated capture, plus the collision-off state for the normal walk review path;
runtime readiness checks those invariants. Current metadata also flags subtle
displacement in the walk view. The test also caught and fixed the common
`T` then `Y` workflow:
enabling displacement after the texture material now fills missing residuals
through the native backend instead of rebuilding the residual map in GDScript.
The captured path reports about 17-18ms local patch assignment and about 14ms
surface texture work after that fix.

That workflow is now covered by a headless regression in
`terrain_streaming_local_detail_surface_perf_check.gd`. The check starts with a
texture-material local patch, then enables visual displacement as a second step
and fails if the toggle texture work exceeds the budget. Current measured result:

```text
T then Y displacement toggle: ~14ms surface texture work
```

Optional ring LOD density plumbing and opt-in mesh skirts now run in the walk
preview. The near `3 x 3` area stays `129 x 129`; ring 2 drops to `65 x 65`;
ring 3 drops to `33 x 33`; all rings use skirts. This keeps close review at 4m
spacing while expanding retained visible terrain to `7 x 7` chunks.
A rendered skirted-LOD review capture now writes:

```text
D:/workflows/worldgen9/factory/runtime/godot_lod_skirts/lod_skirt_gray.png
D:/workflows/worldgen9/factory/runtime/godot_lod_skirts/lod_skirt_rings.png
```

The remaining skirt validation is human review of the live walk preview and
transition captures to confirm the skirts hide cracks without adding obvious
walls or lighting noise.

Mixed-density LOD chunk edges now have machine coverage too.
`terrain_lod_mixed_density_edge_check.gd` builds the same `7 x 7` skirted LOD
window used by the walk preview and compares top-edge vertices at shared world
coordinates across every adjacent chunk pair. It covers same-density neighbors
and mixed `129->65` / `65->33` boundaries:

```text
skirted LOD top-edge shared samples: mixed_pairs=32, same_pairs=52, max_height_delta=0.0, max_xz_delta=0.0
```

Skirts are still needed because fine edges contain intermediate samples between
the coarse vertices, but the shared vertices now have explicit continuity
coverage instead of relying only on rendered captures.

Far clipmap review captures now write:

```text
D:/workflows/worldgen9/factory/runtime/godot_far_clipmap/far_clipmap_gray.png
D:/workflows/worldgen9/factory/runtime/godot_far_clipmap/far_clipmap_levels.png
D:/workflows/worldgen9/factory/runtime/godot_far_clipmap/far_clipmap_surface_material.png
D:/workflows/worldgen9/factory/runtime/godot_far_clipmap/far_clipmap_4ring_wide.png
D:/workflows/worldgen9/factory/runtime/godot_streaming_far_overview/streaming_far_overview_contact_sheet.png
D:/workflows/worldgen9/factory/runtime/godot_streaming_far_overview/streaming_far_overview_manifest.json
```

The remaining validation before deeper GPU work is human review of the live
walk preview and clipmap captures to confirm the far rings improve horizon
readability without visible holes, popping, or transition artifacts. The 4-ring
wide capture, streaming overview contact sheet, and overview manifest exist
specifically to evaluate larger-area readability and active live-scene budgets
without promoting dense near chunks.

The far clipmap now uses one shared base-snapped origin for all levels. The
earlier per-level snapping was cheaper on paper, but it made the square rings
non-concentric after movement and produced height mismatches at level handoff
boundaries. `terrain_far_clipmap_transition_check.gd` now samples the shared
fine/coarse boundary for several viewer positions, including a region-offset
case, and requires exact height agreement within epsilon:

```text
far clipmap level transitions: max_delta=0.0 across tested boundaries
```

This does not replace visual review for popping or horizon readability, but it
does prove the current CPU clipmap renderer is no longer introducing data-level
height discontinuities between rings.

## World 4 Clipmap Harness Comparison

The World 4 `clipmap_motion_profile_gpu_ultra_far_micro_detail_budget.tscn`
harness was reviewed as a long-term reference, not as code to copy directly.
It validates a mature GPU clipmap stack: quality tiers, persistent clipmap
rings, GPU-resident `R32F` height pages, GPU-resident material masks, previous
height-page blending, shader coarse/fine morph bands, stable world-space
material masks, terrain haze/visibility contract, and a motion profiler with
frame/hitch/task/draw/triangle/material stability budgets.

The comparison is captured in:

```text
D:/workflows/worldgen9/plans/world4_clipmap_adaptation_review.md
D:/workflows/worldgen9/plans/world4_borrowed_systems_plan.md
```

The main WG9 conclusion is that the roadmap is still pointed the right way:
near gameplay/detail should remain separate from far visual terrain, far
clipmaps should stay visual-only, and GPU compute should accelerate renderer
pages after the DEM/provider contracts are stable. The current CPU/native
clipmap is a transitional review renderer; the durable target is persistent
ring geometry plus streamed height/material pages, with page blend and
coarse/fine morph handled in shader.

New roadmap gates from that review:

```text
1. terrain quality profile source of truth
2. live motion-profile budget gate
3. first-class visibility/fog contract
4. GPU-resident far page texture residency cache
5. persistent texture-displaced clipmap rings
6. previous/current height-page blend
7. shader coarse/fine morph against neighboring height pages
8. stable world-space biome/material masks after terrain-family material rules
```

### Current Clipmap Discipline (2026-05-26)

The current page-backed far clipmap is an intermediate renderer, but its
transition rules should already match the long-term GPU direction:

```text
accepted:
- opaque page/ring geometry
- world-space height sampling by page origin/extent
- previous/current height-page blend during recenter
- coarse/fine morph in a bounded LOD transition band
- fog only at the outer loaded edge

rejected:
- alpha-crossfading whole square pages/rings
- inner fog to hide LOD or page transitions
- treating biome/material textures as a fix for unstable height motion
```

The next backend work should start with a motion/recenter profiler gate. If
the profiler shows frame-time spikes, fix scheduling, prefetch, and cache
pressure. If it shows visual-only snapping, adjust page cadence, morph bands,
and height-page blend timing before adding new terrain systems.
