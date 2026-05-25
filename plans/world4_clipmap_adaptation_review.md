# World 4 Clipmap Adaptation Review

Source reviewed:

`D:/assets/world 4/the world 4/scenes/test_harness/clipmap_motion_profile_gpu_ultra_far_micro_detail_budget.tscn`

Related World 4 files checked:

- `scenes/components/clipmap_world.tscn`
- `scripts/ClipmapWorld.gd`
- `scripts/ClipmapRing.gd`
- `scripts/terrain_backend/GpuTerrainRenderPageManager.gd`
- `scripts/terrain_backend/GpuMaterialMaskPageManager.gd`
- `scripts/test_harness/ClipmapMotionProfiler.gd`
- `config/quality_tiers.json`
- `shaders/terrain_world_v3.gdshader`

## Short Read

The World 4 scene is not just a visual test scene. It is a high-end GPU clipmap
motion profile harness. It validates a full terrain renderer stack:

- ultra-far clipmap coverage
- GPU-resident height pages
- GPU-resident material mask pages
- smooth height-page blend after page updates
- geometric morph bands between clipmap levels
- world-space material/mask sampling that does not crawl with ring snaps
- far haze/visibility contract
- motion profiler with frame, hitch, task, draw, triangle, mask, and material stability checks

WG9 already has the correct roadmap direction: hybrid near chunks plus far
clipmap, no far collision, deterministic provider contracts, async workers,
surface descriptors, and eventual GPU-assisted clipmap/detail rendering.
World 4 confirms that direction. The parts WG9 should adapt are mostly renderer
contracts and gates, not its old terrain source or full PBR stack.

## Feature Comparison

| Area | World 4 Has | WG9 Current State | Adaptation Decision |
| --- | --- | --- | --- |
| Quality tiers | `low` through `ultra_far`, with ring counts, grid sizes, step ladders, frame budgets, cache budgets, draw/tri limits, and visibility distances. | WG9 has budget reports and gates, but settings are spread across scene exports, tests, and roadmap notes. | Add WG9 terrain quality profiles. They should drive near window, far levels, worker budget, fog edge distance, and review gates. |
| Far range | `ultra_far` uses 10 rings, 256 grid, step ladder `2..256m`, 28km visibility target. | WG9 live preview defaults to 4 far levels, about 65.5km diameter, but CPU/native mesh path and review fog are still transitional. | Keep WG9's wider range as a review target, but do not blindly copy 10 GPU rings until GPU pages exist. |
| Clipmap geometry | Each ring is a square donut/full-square shader-clipped mesh snapped to world grid. | WG9 far clipmap is CPU/native mesh based with overlap, crossfade, and geometric transition bands. | Long-term renderer should move toward persistent ring meshes plus height textures, not rebuild mesh for every clipmap page. |
| Height generation path | GPU `R32F` storage textures via RenderingDevice compute, exposed as `Texture2DRD`; optional CPU page contract remains for collision and debug. | WG9 has CPU/native heightfields, RF/RGBF surface descriptors, optional texture-backed materials, but no GPU compute clipmap pages yet. | This is the main long-term target: keep WG9 provider semantics, move far/detail height images into GPU-resident pages. |
| Update smoothing | Stores previous displacement texture and blends via `height_blend_alpha` over time. | WG9 has mesh crossfade for far recenter and shader fog smoothing, but height data itself still changes by mesh/page replacement. | Add height-page blend once far rings are texture-displaced. Do not depend only on mesh crossfade. |
| LOD morph | Shader samples current and coarser height textures and morphs outer band toward coarser grid. | WG9 has CPU/generated geometric transition bands and seam gates, but still exposes visual LOD quality differences in gray review. | Keep WG9 gates, but final GPU path should use shader morph from fine height texture to coarse height texture. |
| Skirts/overlap | Inner/outer skirts plus shader clipping and overlap guard. | WG9 has skirts, overlap bands, underlap bias, and near/far handoff tests. | Continue. World 4 validates this as a necessary crack-hiding layer, not sufficient alone. |
| Collision | Only inner rings get `HeightMapShape3D`; far rings are visual only. | WG9 local detail collision is near-player opt-in; broad chunks/far clipmap are visual-only. | Aligned. Keep collision decoupled from broad far clipmap. |
| Material masks | Global/follow-camera splat mask; mask origin/extent separate from height origin/extent so materials do not crawl on height snaps. | WG9 does not yet have biome/material masks in live terrain; gray mode currently exposes LOD/normal differences. | Important future requirement: biome/material masks must be world-space, stable, and separately cached from height pages. |
| Micro detail | PBR micro detail is material/shader detail, not added geometry. | WG9 local detail can provide 1m geometry/texture review, but textures/biomes are not in place. | Use material micro detail later for close readability; do not solve every close-up issue by raising mesh density. |
| Visibility/fog | Explicit terrain haze contract: begin/end, strength, curve, hidden buffer, camera far, loaded radius, pass/fail state. | WG9 now has edge-only shader fog, but visibility is not yet a first-class tier contract. | Promote this. WG9 needs a visibility contract gate, not just visual tuning. |
| Motion profiler | Drives camera for a fixed profile, waits for full detail, samples frame time, hitches, tasks, draw calls, tris, not-full frames, mask/material stability. | WG9 has headless/runtime gates and review captures, but not a full motion-profile budget gate. | Add a WG9 motion profiler for the walk scene before more visual systems are promoted. |
| GPU/material mask readiness | Harness requires PBR variants, GPU mask readiness, surface slot masks, and shared streaming mask mode. | WG9 has no equivalent production material stack yet. | Defer. Adapt the gate shape later when biome/material masks exist. |

## What WG9 Already Planned Correctly

- Clipmap is treated as a renderer, not the world model.
- Near gameplay/collision detail is separate from far visual terrain.
- Far clipmap is visual only.
- Renderer can be swapped later for GPU clipmap/height textures.
- CPU/native provider parity and seams are being stabilized before GPU.
- Far range, fog, LOD transitions, and visual review are explicit roadmap items.
- Local detail is opt-in until review and budgets are proven.

World 4 supports this plan. It does not imply that WG9 should abandon the
current DEM-kernel provider work or replace it with World 4's procedural source.

## Gaps WG9 Should Close

### 1. Quality Profile Unification

WG9 needs one terrain profile source of truth:

- near chunk radius/window
- near vertex density
- far clipmap level count
- far level spacing/extent
- worker count and per-frame build budget
- camera far target
- edge fog begin/end
- hidden loaded buffer
- max active chunks/pages
- expected budget envelope

This should replace scattered scene-only tuning.

### 2. Motion Profile Gate

Add a deterministic walk/fly profiler that records:

- p95/p99/peak frame time
- hitch count
- max active workers
- pending queue count
- chunks/clipmap levels not ready
- pop-in/fill frames
- draw/triangle estimates
- current quality profile

This is the most direct way to prove "fast flight does not visibly pop or hitch".

### 3. GPU-Resident Height Page Plan

WG9 should not keep rebuilding far mesh geometry as the final clipmap renderer.
The long-term renderer should keep stable ring meshes and update height pages:

- far rings: persistent mesh, height texture displacement
- detail window: optional 1m CPU/native source, then GPU upload/compute path
- CPU heightfields retained only where collision/query/debug require it
- no CPU readback from GPU pages for normal rendering

### 4. Height Page Blend

When a clipmap page updates, WG9 should blend old height page to new height page
in shader. Mesh crossfade hides some swaps, but texture height blending is the
cleaner long-term answer for "rings pop every time the clipmap recenters".

### 5. Shader Coarse/Fine Morph

WG9 already tests geometric continuity, but final texture-displaced clipmaps
should morph fine edge samples toward the next coarser height texture in shader.
That is the World 4 pattern and it is the right long-term fix for visible LOD
step changes.

### 6. Stable World-Space Material Masks

World 4 separates material-mask origin/extent from height-page origin/extent.
WG9 should copy that idea when biome/material masks arrive. Otherwise textures
and biome blends will crawl or shift when clipmap pages snap.

### 7. Visibility Contract

WG9 should have a first-class visibility report:

- loaded radius
- camera far
- hidden buffer beyond far plane
- fog/haze begin/end
- minimum transition length
- pass/fail reason

Fog should only hide the outer pop-in edge, but it should be validated as a
contract instead of tuned by eye.

## What Not To Copy Yet

- Do not copy World 4's full PBR variant/material-slot stack before WG9 has
  accepted terrain families and biome material rules.
- Do not make `ultra_far` the default target. It is a high-end profile.
- Do not use GPU compute as a replacement for provider correctness; use it as
  a renderer acceleration layer after provider contracts are stable.
- Do not make far clipmaps responsible for gameplay collision or edit facts.
- Do not build the new WG9 Godot project around a specific test harness scene.
  The renderer contract should be project/runtime-level.

## Recommended WG9 Sequence

1. Add `TerrainQualityProfile` data and route the walk preview through it.
2. Add a motion-profile gate for the live walk/fly scene.
3. Promote current edge fog into a visibility contract with pass/fail reporting.
4. Keep fixing current CPU/native clipmap visual issues only enough to support review.
5. Implement GPU-resident far height pages behind the existing provider contract.
6. Switch far clipmap rendering from rebuilt meshes to persistent rings with height texture displacement.
7. Add previous/current height-page blending.
8. Add shader coarse/fine morph against neighboring height pages.
9. Add world-space biome/material masks only after terrain families/material rules are ready.
10. Add material micro detail after the mask/material path is stable.

## Immediate Practical Takeaway

The current WG9 problems are not evidence that the roadmap is wrong. They are
symptoms of a transitional CPU/native clipmap renderer trying to stand in for a
final GPU page renderer. World 4's best lesson is that far terrain should be
stable geometry plus streamed world-space height/material pages, with morph and
blend handled in shader and proven by a movement profiler.
