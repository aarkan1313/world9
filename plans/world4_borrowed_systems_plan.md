# World 4 Borrowed Systems Plan

This document maps concrete World 4 systems to the WG9 pain they can solve.
The goal is not to copy World 4 wholesale. WG9 has a different terrain source:
DEM-derived kernels, runtime packs, hydrology contracts, and future deformation.
The useful pieces are mostly API boundaries, cache/budget accounting, visual
profiles, and test harness patterns.

## Validated World 4 Systems

The following named systems exist in `D:/assets/world 4/the world 4/` and are
real candidates to borrow or adapt:

- `scripts/terrain_backend/TerrainPageRequest.gd`
- `scripts/terrain_backend/TerrainPageResult.gd`
- `scripts/terrain_backend/TerrainPageAnalysis.gd`
- `scripts/terrain_backend/TerrainBackend.gd`
- `scripts/worldgen/WorldGenBackendAdapter.gd`
- `scripts/streaming/TerrainPageCache.gd`
- `scripts/streaming/StreamingBudgetAccountant.gd`
- `scripts/lighting/LightingRecipeController.gd`
- `scripts/atmosphere/AtmosphereController.gd`
- `scripts/decoration/DecorationManager.gd`
- `scripts/decoration/ChunkDecorationLayer.gd`
- `scripts/decoration/DecorationMeshCache.gd`
- `scripts/navigation/NavSourceVisualDemo.gd`
- `scripts/test_harness/ClipmapStartupGate.gd`
- `scripts/test_harness/ClipmapMotionProfiler.gd`
- `scripts/test_harness/ClipmapSpinProfiler.gd`
- `scripts/terrain_backend/GDScriptTerrainBackend.gd`
- `scripts/terrain_backend/GpuTerrainBackend.gd`
- `scripts/csharp/worldgen/CSharpTerrainBackend.cs`

## Pain Points They Solve

### 1. Generation API Drift

Current WG9 pain:

- Near chunks, far clipmap, hydrology, local detail, collision, and future GPU
  paths can all ask the provider for similar facts in slightly different shapes.
- Optional native/GPU paths need stricter request identity and validation.
- Debug failures can look like visual defects because request/result status is
  not always first-class in every path.

World 4 pattern to borrow:

- `TerrainPageRequest` carries center, grid size, spacing, seed, quality tier,
  active biome/material inputs, navigation inputs, generator revision, kernel
  hash, material hash, and deterministic cache key.
- `TerrainPageResult` carries request metadata back with height samples,
  collision samples, slope samples, nav masks, biome weights, density layers,
  timings, and status.
- `TerrainBackend` establishes a narrow `generate_page(request)` contract.
- `WorldGenBackendAdapter` routes through preferred backend, validates request,
  falls back cleanly, and preserves timings/status.

WG9 adaptation:

- Add `TerrainPageRequest` / `TerrainPageResult` equivalents around WG9's
  existing height provider and surface descriptors.
- Keep the DEM kernel provider authoritative; do not replace it with World 4's
  generator.
- Require all renderers/workers to stamp requests with provider revision,
  runtime pack hash, quality profile, spacing, count, origin, and feature flags.

Acceptance checks:

- Same request key returns the same page metadata across GDScript/native paths.
- Invalid grid/spacing/feature requests return structured failure, not crashes.
- Near chunk, far clipmap, and local detail can all emit comparable page stats.
- Stale async completions are rejected by request key/version, not only by chunk key.

### 2. Hidden Memory and Queue Pressure

Current WG9 pain:

- The live overlay exposes some counts, but pressure is still scattered:
  chunks, far rings, local detail, workers, texture descriptors, and future GPU
  pages are not reported under one budget model.
- Long-session cache growth and optional systems can become invisible debt.
- Review scenes can pass functionally while carrying too much queued or retained
  work.

World 4 pattern to borrow:

- `TerrainPageCache` is a deterministic LRU with protected keys, hit/miss
  counters, eviction counters, and debug state.
- `StreamingBudgetAccountant` lets systems publish usage under shared keys:
  draw calls, visible tris, texture MB, jobs, CPU pages, and GPU pages.

WG9 adaptation:

- Add a WG9 `TerrainPageCache` for CPU-visible page facts:
  collision, nav, hydrology/debug, surface descriptors, and future placement
  queries.
- Add a shared streaming budget report with per-system contributors:
  `terrain_chunks`, `far_clipmap`, `local_detail`, `hydrology_debug`,
  `future_material_masks`, `future_decoration`, and `future_nav`.
- Integrate the report into the walk overlay and runtime readiness gates.

Acceptance checks:

- Runtime budget report includes totals, headroom, failures, and per-system rows.
- Protected active pages are retained; non-protected old pages evict first.
- A forced small cache produces deterministic evictions and no stale active page.
- Review gate fails when queue/jobs/texture/page budgets exceed profile limits.

### 3. Runtime Introspection and Deterministic Recenter Behavior

Current WG9 pain:

- Ring/LOD/fog issues are hard to debug by eye.
- Near/far overlap, pending workers, and visual readiness need one state report.
- "It popped" needs to become a reproducible state transition.

World 4 pattern to borrow:

- `ClipmapWorld.get_clipmap_debug_state()` reports quality tier, ring readiness,
  tasks, cache, budget, masks, visibility, and backend state.
- Motion profiling waits for full detail, then records movement samples.

WG9 adaptation:

- Add a `get_terrain_runtime_debug_state()` style report that merges:
  chunks, far clipmap, local detail, provider/page cache, quality profile,
  visibility contract, worker queues, and budget accountant.
- Keep the live overlay human-readable, but write the full state to gate
  artifacts and profiler logs.

Acceptance checks:

- Each live screenshot/review capture can be tied to a machine-readable state.
- Motion profile logs show no not-ready frames after preload settle.
- Fast movement reports pending work and resolved work deterministically.

### 4. Visual Tuning Without Terrain Math Changes

Current WG9 pain:

- Gray readability, fog, lighting, and exposure tuning have repeatedly been
  mixed into terrain rendering changes.
- It is hard to tell whether a bad frame is terrain data, material response, or
  environment setup.

World 4 pattern to borrow:

- `AtmosphereController` owns sky/fog/time-of-day profile state.
- `LightingRecipeController` owns shadows, SSAO, GI, and terrain shadow flags.
- Both expose profile state dictionaries for gates/probes.

WG9 adaptation:

- Add lightweight WG9 visual profiles before adding final PBR:
  `gray_review`, `horizon_review`, `hydrology_review`, `walk_readability`,
  and later `biome_material_review`.
- Keep profiles outside provider/height math.
- Let profiles set environment, sky, sun, fog contract, and shadow policy.

Acceptance checks:

- Switching visual profile does not rebuild terrain pages.
- Profile state is captured in review manifests.
- Fog/lighting changes are testable without touching height provider tests.

### 5. Future Decoration Layer

Current WG9 pain:

- No decoration layer yet, but terrain will eventually need rocks, vegetation,
  scatter, biome props, and maybe debug markers.
- If decoration is bolted directly onto chunk code later, it will fight chunk
  streaming, LOD, budgets, and material masks.

World 4 pattern to borrow:

- `DecorationManager` owns its own residency lifecycle around a focus position.
- `ChunkDecorationLayer` and `DecorationMeshCache` separate instance data,
  mesh reuse, LOD bands, hysteresis, and budget publishing.

WG9 adaptation:

- Defer actual decorations until terrain families/material masks are accepted.
- Borrow the architecture now in the roadmap: decoration is a separate streamed
  layer above terrain pages, not part of chunk mesh generation.

Acceptance checks for future slice:

- Decoration can be disabled without changing terrain meshes.
- Decoration publishes budget usage.
- LOD changes use per-instance hysteresis and movement-gated refresh.
- Mesh cache prevents repeated mesh construction for repeated props.

### 6. Navigation and Gameplay Tooling

Current WG9 pain:

- Terrain visual/collision work is moving ahead, but gameplay tooling will need
  nav source generation, agent probes, exported debug artifacts, and validation.
- Deformation/caves will make nav even easier to neglect if not first-class.

World 4 pattern to borrow:

- Navigation source JSON is loaded and visually rendered.
- `NavigationServer3D` registration and agent path probes are part of test
  harnesses, not manual editor steps.

WG9 adaptation:

- Defer full nav until local collision and deformation policy settle.
- Add a future `TerrainNavSource` contract that consumes the same page/collision
  facts as local detail, not rendered far clipmap geometry.

Acceptance checks for future slice:

- Nav source export schema validates.
- Visual nav source scene renders source triangles.
- Agent smoke probe travels a minimum distance on generated nav.
- Nav rebuild is limited to near/gameplay pages, never far visual clipmap pages.

### 7. Test Harness Discipline

Current WG9 pain:

- Unit/headless gates are good, but live movement regressions still show up in
  user review: pop-in, hitches, fog stepping, ring transitions, and unreadable
  LOD shifts.

World 4 pattern to borrow:

- `ClipmapStartupGate` checks cold-start readiness.
- `ClipmapMotionProfiler` drives real movement and records frame/budget state.
- `ClipmapSpinProfiler` catches camera-angle and material stability issues.
- Capture probes turn visual states into repeatable artifacts.

WG9 adaptation:

- Add startup, motion, and spin gates for the WG9 walk preview.
- Gate them against quality profiles, not hardcoded scene values.

Acceptance checks:

- Startup gate reaches full terrain readiness within profile limit.
- Motion gate reports p95/p99/peak frame time, hitches, not-ready frames, and
  max queue/worker pressure.
- Spin gate catches view-angle material/LOD shifts without moving terrain.
- Review artifacts include the debug-state JSON beside screenshots.

### 8. Backend Multipath and Parity

Current WG9 pain:

- WG9 is moving toward native/GPU/C++ paths, but each new path risks subtle
  parity drift with GDScript/reference behavior.
- We need GPU eventually, but it should not become a second world generator.

World 4 pattern to borrow:

- Preferred backend can be `gpu`, `csharp`, or `gdscript`.
- Adapter falls back when a backend cannot satisfy a request.
- Page requests/results preserve enough metadata for parity checks.

WG9 adaptation:

- Expose explicit backend names in page results:
  `gdscript_reference`, `rust_native`, `gpu_compute_future`, `cpp_future`.
- Add parity tests at the page contract level before renderer-specific tests.
- Keep GPU compute as page production/render acceleration, not a separate
  terrain design source.

Acceptance checks:

- Same request is comparable across GDScript/native/GPU page paths.
- Backend fallback is reported in state, not silent.
- Page parity tolerance is profile/field-specific and fails on offset bugs.

## Recommended Borrow Order

### Slice 1: Page Contract and Cache

Implement WG9-native `TerrainPageRequest`, `TerrainPageResult`, and
`TerrainPageCache`. Wrap existing provider calls; do not rewrite the renderer.

Why first:

- Reduces stale async bugs.
- Gives all renderers a shared request identity.
- Makes cache and page pressure testable before GPU pages arrive.

### Slice 2: Budget Accountant and Runtime Debug State

Add a shared budget accountant and a merged runtime debug state report.

Why second:

- Turns "laggy" and "pop-in" into measurable budget and readiness failures.
- Lets profile gates enforce terrain pressure before adding decorations/nav.

### Slice 3: Motion/Startup/Spin Gates

Port the harness mindset, not the exact World 4 scenes.

Why third:

- WG9's current remaining problems are live movement quality problems.
- Static tests cannot prove fast flight, recentering, or view-angle stability.

### Slice 4: Visual Profiles

Add atmosphere/lighting profile controllers for review scenes.

Why fourth:

- Stabilizes visual review without touching terrain math.
- Reduces accidental regressions from hand-tuned scene settings.

### Slice 5: GPU-Resident Pages and Persistent Clipmap Rings

Start the true long-term renderer replacement.

Why fifth:

- By then request identity, cache, budget, and motion gates should exist.
- GPU compute becomes a backend under contract instead of a parallel prototype.

### Slice 6: Decoration and Navigation Contracts

Plan now, implement after terrain/material/collision contracts are stable.

Why later:

- Decoration and nav are important, but they depend on accepted terrain,
  material masks, collision policy, and page contracts.

## Scope Boundaries

Do borrow:

- request/result/page contracts
- cache and protected eviction pattern
- shared budget accounting
- runtime state report shape
- movement profiler approach
- visual profile separation
- future decoration/nav layer boundaries
- backend adapter/fallback semantics

Do not blindly borrow:

- World 4's procedural source as WG9 terrain source
- full PBR/variant/surface-slot material system before WG9 terrain families are accepted
- 10-ring ultra-far as default
- decoration assets or nav schemas as final WG9 gameplay content
- GPU path before provider/page parity is locked

## Immediate Next Step

Start Slice 1:

1. Add WG9 `TerrainPageRequest`.
2. Add WG9 `TerrainPageResult`.
3. Add a small `TerrainPageCache`.
4. Add tests for request validation, deterministic key stability, cache eviction,
   and protected active-page retention.
5. Wrap one existing path first, preferably far clipmap or local detail, so the
   new contract proves value without destabilizing all chunk rendering.
