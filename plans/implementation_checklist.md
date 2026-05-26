# WorldGen9 Implementation Checklist

Last updated: 2026-05-25

The Godot project shell now exists at `D:/workflows/worldgen9/wg-9-directory/`.
Runtime code can be added there, but it should continue following the parity
order in `plans/godot_phase1_port_plan.md`.

## Current State

- [x] Move raw DEM cache outside `D:/assets`.
- [x] Godot project shell exists at `D:/workflows/worldgen9/wg-9-directory/`.
- [x] Confirm raw DEM cache location: `D:/workflows/worldgen9/dems/`.
- [x] Keep roadmap under `D:/workflows/worldgen9/plans/roadmap.txt`.
- [x] Add standalone DEM factory, independent of Godot.
- [x] Catalog raw DEM GeoTIFFs.
- [x] Generate seed DEM terrain kernels.
- [x] Validate seed kernels.
- [x] Generate full reduced kernel set.
- [x] Split generated kernels into accepted/review catalogs.
- [x] Generate top-per-family kernel shortlist.
- [x] Add manual visual-review notes.
- [x] Create draft promoted seed pack.
- [x] Create final 36-kernel heightfield seed pack for review.
- [x] Build click-through kernel reviewer for full accepted catalog.
- [x] Write infinite heightfield prototype and long-term infra plan.
- [x] Build first Python infinite-heightfield prototype.
- [x] Fix kernel repeat artifacts with mirrored kernel sampling.
- [x] Add hillshade, color relief, oblique, and layer-split review outputs.
- [x] Create v5 prototype visual review contact sheet.
- [x] Tune v6 macro/detail balance and add first valley-guidance layer.
- [x] Create v6 prototype visual review contact sheet.
- [x] Generate multi-seed comparison sheets for the promoted pack.
- [x] Define runtime kernel pack JSON schema.
- [x] Build runtime kernel pack manifest from promoted kernels.
- [x] Smoke-test heightfield prototype against runtime kernel pack.
- [x] Define pre-Godot `TerrainSample` and height-provider contract.
- [x] Add lightweight deterministic runtime-pack verifier.
- [x] Add native `257 x 257` / 1m local-detail timing and seam probe.
- [x] Add near-player 1m detail tier policy and alignment test.
- [x] Add opt-in local 1m detail patch node with native payload builds and independent retire rules.
- [x] Add CPU local-detail height query and neutral collision-heightfield descriptor contract.
- [x] Add optional local-detail height/normal texture material upload path for GPU handoff testing.
- [x] Add far-clipmap heightfield retention and optional height/normal texture material upload path.
- [x] Add backend-neutral slope, curvature, and debug heatmap images to surface descriptors.
- [x] Add edge-safe visual displacement residual image and opt-in local shader toggle.
- [x] Add streaming preview controls for local detail texture material and visual displacement review.
- [x] Avoid full displacement texture generation when visual displacement is disabled.
- [x] Add meter cap for visual displacement review so residual textures cannot create unbounded spikes.
- [x] Add live preview toggles and active-patch material refresh for local detail texture/displacement review.
- [x] Reuse active local-detail surface materials for parameter-only review changes instead of rebuilding textures.
- [x] Add rendered local-detail material/displacement review captures.
- [x] Move local-detail visual-displacement residual generation onto the native backend and worker path.
- [x] Add local-detail texture/displacement perf gate: current measured assignment ~20ms and descriptor ~13-14ms after native optimization.
- [x] Add live walk-preview local-detail review captures at `factory/runtime/godot_walk_local_detail_review/`.
- [x] Add deterministic local-detail review manifests for isolated patch and walk-preview captures, including mesh budget, image readability stats, and subtle-displacement review flags.
- [x] Add runtime readiness checks that lock local-detail review manifest schema, 257x257 / 1m patch budget, image stats, collision-off state, and subtle-displacement review flags.
- [x] Optimize the normal `T` then `Y` review workflow by filling missing displacement residuals through the native backend.
- [x] Add headless regression coverage for the normal `T` then `Y` review workflow; current toggle texture work is ~14ms.
- [x] Align the walk-preview near chunk window with the far-clipmap underlay; handoff samples now test at 0.0 height delta.
- [x] Center walk-preview spawn/review jumps inside chunks so small initial movement does not rebuild far clipmap rings.
- [x] Add far-clipmap level/build timing to the live walk-preview diagnostics overlay.
- [x] Add live far-clipmap height/normal texture-material review toggle and diagnostics.
- [x] Keep far-clipmap boundary recentering on async native workers even while far texture-material review is enabled.
- [x] Split far-clipmap material descriptors from full diagnostic descriptors so `U` review uses lightweight height/normal uploads instead of debug/displacement maps.
- [x] Reuse active far-clipmap surface materials for normal-strength-only review changes instead of rebuilding height/normal textures.
- [x] Budget real far-clipmap recentering to one ring rebuild per update.
- [x] Add boundary-recenter regression: first edge crossing keeps far rings stable, larger travel schedules level 0, leaves two levels pending, then drains cleanly.
- [x] Add native far-clipmap mesh payload helper and direct contract check for centered vertices plus hole-filtered indices.
- [x] Add async far-clipmap payload worker and opt it into the walk/streaming preview.
- [x] Update boundary-recenter regression: chunk-edge ping-pong no longer schedules far recenter, and threshold recenter schedules level 0 without synchronous far rebuild.
- [x] Add rapid far-recenter regression: stale in-flight workers defer, do not synchronously rebuild, and final origins match the latest request.
- [x] Add `tools/godot_runtime_gate.py` fast headless gate for native clipmap, far continuity, async recenter, far-surface async recenter, and walk preview checks.
- [x] Add `--suite extended` to `tools/godot_runtime_gate.py` for native height/mesh/chunk payload parity, far surface material, live far-surface review controls, native chunk workers, LOD continuity, and local-detail worker/material checks.
- [x] Add `--suite quality` to `tools/godot_runtime_gate.py` for landform, hydrology, debug-mode performance, streaming perf, and high-density walk checks.
- [x] Add runtime readiness checks for landform quality and hydrology reports: schema, case counts, terrain signal thresholds, stable/window-limited field policy, and zero tile/cache seam deltas.
- [x] Add `--suite render` to `tools/godot_runtime_gate.py` for deterministic non-headless preview, streaming, LOD/skirt, far-clipmap, and local-detail capture artifacts.
- [x] Add `--suite review` to `tools/godot_runtime_gate.py` for non-headless multi-location and 65-vertex scale contact-sheet review artifacts.
- [x] Make the debug-mode perf artifact deterministic by storing pass/fail timing checks while printing raw milliseconds to stdout.
- [x] Build consolidated Godot visual review index at `factory/runtime/godot_review_index/index.html`.
- [x] Add runtime readiness checks for the Godot review index schema, section order, required review artifacts, and PNG dimensions.
- [x] Add isolated `512m / 257v / 2m` walk-preview performance probe to the quality gate.
- [x] Add 129/4m versus 257/2m walk-density visual review capture and include it in the review index.
- [x] Add deterministic 129/4m versus 257/2m walk-density mesh and memory budget to the runtime budget artifact.
- [x] Add deterministic far-clipmap budget reporting plus scene-level clipmap sizing controls.
- [x] Add runtime readiness checks for baseline LOD totals, walk-density opt-in cost, standalone far clipmap budgets, and walk-preview far clipmap budgets.
- [x] Add walk-density readability manifest and release guard for gray review brightness, luma range, and 129/257 density comparison.
- [x] Lower live walk-preview fly start height and cap gray/far-clipmap material brightness for less washed-out player-scale review.
- [x] Add live walk-preview `G` toggle between free-fly and ground-follow player-eye review mode, with smoke-test coverage for height snap and vertical-input suppression.
- [x] Align near fast-gray and far clipmap gray/surface-review shading so rendered-geometry normals reduce chunk-border lighting seams and far review modes stay in the same brightness regime.
- [x] Keep the saved walk-preview retained window at 7x7 chunks for review responsiveness, add a level-0 far overlap band plus one-cell visual underlap for near/far and far-ring clipmap handoffs, and default live walk far coverage to 4L.
- [x] Stabilize the live far-clipmap anchor so walking back and forth across a chunk boundary does not resample/rebuild far rings.
- [x] Add bounded far-clipmap mesh crossfade so completed recenter rebuilds do not hard-swap visible rings.
- [x] Add far-clipmap geometric transition bands that morph finer outer-ring heights toward the next coarser grid while leaving inner samples unchanged.
- [x] Cap default walk-preview max LOD at 2 and set Shift fly speed to x30 for faster large-area inspection without dropping retained chunks to 17x17.
- [x] Add true geometric LOD morph/blend policy so chunk density transitions do not rely only on skirts; fine chunk edge bands now morph toward coarser neighbor sampling while inner samples stay raw.
- [x] Add 4-ring wide far-clipmap review capture and include it in the review index.
- [x] Harden live far-clipmap sizing controls so changing ring count rebuilds actual clipmap nodes.
- [x] Add live far-clipmap 3-ring/4-ring review toggle and diagnostics coverage.
- [x] Add streaming-preview far-clipmap overview camera helper for inspecting 4-ring coverage.
- [x] Add live streaming 3-ring/4-ring far-overview contact sheet plus deterministic manifest and include both in the review index.
- [x] Fix near-window coverage holes by making core active-chunk fill prioritize missing rendered chunks before stale rebuilds, raise the saved walk scene fill cap to the full 7x7 active window, and add a fast gate for this ordering.
- [x] Align far-clipmap gray/surface shader response with the near fast-gray chunk shader so the moving near window does not draw as a different-toned square, and add a fast shader-alignment gate.
- [x] Convert review fog to edge-only masking by disabling global fog density, pushing fog start/end to the far clipmap horizon, applying the same shader fog to unshaded near/far gray materials, and tracking the fog center from the viewer instead of snapped clipmap origins so the fade does not step/click during movement.
- [x] Review the World 4 ultra-far GPU clipmap motion harness and capture the WG9 adaptation plan at `plans/world4_clipmap_adaptation_review.md`.
- [x] Review World 4 page/cache/budget/profiler/visual/decor/nav/backend patterns and capture the WG9 borrowed-systems plan at `plans/world4_borrowed_systems_plan.md`.
- [x] Add WG9-native `TerrainPageRequest`, `TerrainPageResult`, and `TerrainPageCache` contracts with validation, deterministic keys, and protected-key eviction tests.
- [x] Add a WG9 terrain quality profile source of truth for near density/window, far level count, worker budget, camera far target, edge fog, hidden buffer, and budget gates.
- [x] Add a motion-profile runtime gate for live walk/fly movement that records p95/p99/peak frame time, hitches, pending terrain work, not-ready frames, draw/triangle estimates, and current quality profile.
- [ ] Promote far-edge fog into a visibility contract report with loaded radius, camera far, hidden buffer, fog begin/end, transition length, and pass/fail reasons.
- [ ] Implement GPU-resident far height pages behind the current provider contract before promoting texture-displaced persistent clipmap rings.
- [x] Split cross-region height-grid sampling into per-region fast blocks so padded hydrology/debug windows do not fall back to per-point scalar sampling.
- [x] Add direct hydrology scalar-field sampling for tile-cache grids so debug overlays can request one field without computing all fields per cell.
- [x] Add `TerrainChunkRenderer` as the first renderer boundary for chunk MeshInstance lifecycle, active-node ownership, and bounded pooling.
- [x] Add renderer contract coverage to the extended Godot runtime gate.
- [x] Remove per-call mean normalization from the Python reference sampler.
- [x] Add full-neighbor-chunk seam verification.
- [x] Add executable `TerrainSample` reference output.
- [x] Add chunk-grid reference fixture for future runtime parity tests.
- [x] Add mesh-builder reference fixture with vertices, normals, indices, and UVs.
- [x] Add streamer reference fixture for active chunk sets and LOD rings.
- [x] Add priority/cancel queue policy reference and FIFO comparison.
- [x] Add runtime budget fixture for active LOD triangle and memory estimates.
- [x] Add metadata-only duplicate/overlap detector for accepted kernels.
- [x] Add conservative metadata-only tag/family inference for accepted kernels.
- [x] Build filtered expansion review queue for future kernel-pack growth.

## Key Artifacts

```text
D:/workflows/worldgen9/dems/
D:/workflows/worldgen9/tools/dem_factory/
D:/workflows/worldgen9/tools/build_godot_review_index.py
D:/workflows/worldgen9/tools/godot_runtime_gate.py
D:/workflows/worldgen9/tools/kernel_reviewer/
D:/workflows/worldgen9/tools/heightfield_prototype/
D:/workflows/worldgen9/tools/kernel_pack/
D:/workflows/worldgen9/native/wg9_terrain_backend/
D:/workflows/worldgen9/factory/catalog/dem_catalog.json
D:/workflows/worldgen9/factory/catalog/dem_catalog_summary.json
D:/workflows/worldgen9/factory/catalog/kernel_catalog.json
D:/workflows/worldgen9/factory/catalog/accepted_kernel_catalog.json
D:/workflows/worldgen9/factory/catalog/review_kernel_catalog.json
D:/workflows/worldgen9/factory/catalog/kernel_validation_report.json
D:/workflows/worldgen9/factory/catalog/kernel_duplicate_candidates.json
D:/workflows/worldgen9/factory/catalog/kernel_inferred_tags.json
D:/workflows/worldgen9/factory/catalog/accepted_kernel_catalog_tagged.json
D:/workflows/worldgen9/factory/catalog/kernel_expansion_review_queue.json
D:/workflows/worldgen9/factory/catalog/kernel_expansion_review_queue_catalog.json
D:/workflows/worldgen9/factory/catalog/expansion_review/expansion_queue_contact_sheet.png
D:/workflows/worldgen9/factory/catalog/kernel_shortlist_top_by_family.json
D:/workflows/worldgen9/factory/catalog/promoted_kernel_catalog_draft.json
D:/workflows/worldgen9/factory/catalog/promoted_kernel_catalog.json
D:/workflows/worldgen9/factory/catalog/promoted_review/promoted_heightfield_seed_v1_contact_sheet.png
D:/workflows/worldgen9/factory/runtime/kernel_pack_v1.json
D:/workflows/worldgen9/factory/runtime/hash_reference/
D:/workflows/worldgen9/factory/runtime/kernel_pack_verification.json
D:/workflows/worldgen9/factory/runtime/terrain_sample_reference.json
D:/workflows/worldgen9/factory/runtime/chunk_reference/
D:/workflows/worldgen9/factory/runtime/mesh_reference/
D:/workflows/worldgen9/factory/runtime/streamer_reference/
D:/workflows/worldgen9/factory/runtime/streamer_reference_fifo/
D:/workflows/worldgen9/factory/runtime/runtime_budget/
D:/workflows/worldgen9/factory/runtime/region_grammar/
D:/workflows/worldgen9/factory/runtime/infinite_travel/
D:/workflows/worldgen9/factory/runtime/provider_decisions/
D:/workflows/worldgen9/factory/runtime/runtime_readiness_report.json
D:/workflows/worldgen9/factory/runtime/runtime_artifact_manifest.json
D:/workflows/worldgen9/factory/runtime/godot_streaming_scale_review/
D:/workflows/worldgen9/factory/runtime/godot_hydrology_tiles/
D:/workflows/worldgen9/factory/runtime/godot_lod_skirts/
D:/workflows/worldgen9/factory/runtime/godot_far_clipmap/
D:/workflows/worldgen9/factory/runtime/godot_far_clipmap/far_clipmap_surface_material.png
D:/workflows/worldgen9/factory/runtime/godot_local_detail_displacement/
D:/workflows/worldgen9/factory/runtime/godot_walk_local_detail_review/
D:/workflows/worldgen9/factory/runtime/godot_walk_density_review/
D:/workflows/worldgen9/factory/runtime/godot_performance/
D:/workflows/worldgen9/factory/runtime/godot_review_index/index.html
D:/workflows/worldgen9/factory/runtime/godot_review_index/review_index_manifest.json
D:/workflows/worldgen9/factory/reviews/
D:/workflows/worldgen9/factory/kernels/
D:/workflows/worldgen9/prototypes/infinite_heightfield_v4_mirror/
D:/workflows/worldgen9/prototypes/infinite_heightfield_v5_review/
D:/workflows/worldgen9/prototypes/infinite_heightfield_v6_macro_valleys/
D:/workflows/worldgen9/prototypes/seed_compare_v1/
D:/workflows/worldgen9/prototypes/seed_compare_v2_softened/
D:/workflows/worldgen9/prototypes/seed_compare_runtime_v7_balanced/
D:/workflows/worldgen9/prototypes/runtime_pack_smoke/
D:/workflows/worldgen9/plans/visual_review_notes.md
D:/workflows/worldgen9/plans/promotion_decisions.md
D:/workflows/worldgen9/plans/infinite_heightfield_prototype_plan.md
D:/workflows/worldgen9/plans/native_gpu_backend_roadmap.md
D:/workflows/worldgen9/plans/runtime_height_contract.md
D:/workflows/worldgen9/plans/godot_phase1_port_plan.md
D:/workflows/worldgen9/plans/worldgen_caves_deformable_land_addendums.md
D:/workflows/worldgen9/plans/worldgen_full_deformation_futureproof_addendum.md
```

## Offline DEM Factory

- [x] Scan GeoTIFF headers.
- [x] Classify obvious terrain families from names/sidecars.
- [x] Generate reduced `512 x 512` kernel arrays.
- [x] Generate height, slope, and residual previews.
- [x] Compute quality, coverage, relief, slope, roughness, ridge/valley, and orientation stats.
- [x] Write accepted/review catalogs.
- [x] Write per-family shortlist.
- [x] Build contact sheets for each family shortlist.
- [x] Build click-through reviewer for `accepted_kernel_catalog.json`.
- [ ] Human-review shortlist previews and mark `promoted`, `accepted`, `review`, or `reject`.
- [x] Create a draft 40-kernel promoted seed pack.
- [x] Promote final 36-kernel heightfield seed pack into `promoted_kernel_catalog.json`.
- [ ] User-review final promoted contact sheet.
- [x] Add duplicate/overlap detection so near-identical adjacent tiles do not overrepresent one region.
- [x] Add better family inference for the 591 currently accepted but `uncategorized` kernels.
- [ ] Add optional family tags: alpine, canyon, dune, fjord, plateau, delta, mesa, ridge, basin.
- [x] Build duplicate-aware expansion review queue for candidate pack growth.
- [x] Build runtime-facing kernel pack from promoted kernels.

## Kernel Promotion Rules

Promote a kernel only if it has:

- [ ] Clear visual landform identity in plain grayscale.
- [ ] Good coverage and no obvious no-data holes.
- [ ] No import/projection artifacts.
- [ ] Useful slope/roughness structure.
- [ ] A role in the runtime terrain mix.

Reject or quarantine kernels with:

- [ ] Flat/no-data outputs.
- [ ] Water or sea flattening dominating an otherwise non-coastal patch.
- [ ] City/building DSM artifacts where bare-earth terrain is needed.
- [ ] Edge spikes or broken vertical units.
- [ ] Duplicates that add no new terrain character.
- [ ] Projected-footprint artifacts that look rotated, framed, or not like a clean top-down terrain patch.

## Pre-Godot Runtime Design

- [x] Define the runtime kernel pack JSON schema.
- [x] Define `TerrainSample` fields for height-only first pass plus future facts.
- [x] Define coordinate contract: meters, deterministic world-space sampling, no per-chunk normalization.
- [x] Define chunk seam contract and seam metric.
- [x] Verify full neighboring chunk edges, not just identical edge-coordinate calls.
- [x] Define first procedural height layers using promoted DEM kernels.
- [x] Write a small non-Godot Python prototype that samples kernels into a large synthetic heightfield.
- [x] Generate preview PNGs for synthetic infinite-fill experiments.
- [x] Generate first seam report with exact-zero edge deltas.
- [x] Generate visual review sheet for prototype terrain.
- [x] Improve macro landform composition.
- [x] Tune first-pass family-specific relief/detail amplitudes.
- [x] Add early drainage/valley guidance.
- [x] Generate side-by-side seed comparison sheets.
- [x] Add repeatable runtime seed-comparison builder.
- [x] Broaden DEM kernel world sampling for less noisy first-pass hillshade.
- [x] Add province-aware region grammar for coherent infinite kernel usage.
- [x] Add region grammar analysis fixture and palette map.
- [x] Add long-distance infinite-travel variety probe and contact sheet.
- [x] Add provider-decision parity fixture for future Godot/C++ ports.
- [x] Add hash/noise parity fixture for future deterministic runtime ports.
- [x] Pick first terrain mix: mountain, glacial, badlands, desert, grassland, coast, volcanic, karst, rainforest.
- [x] Add deterministic runtime-pack seam verifier.
- [x] Add executable `TerrainSample` reference JSON.
- [x] Add 129 x 129 chunk-grid reference fixture with edge hashes and visual sheet.
- [x] Add 129 x 129 mesh reference fixture with shared topology and edge validation.
- [x] Add streamer reference fixture with bounded active count and LOD rings.
- [x] Add streamer priority/cancel policy reference for mesh build queues.
- [x] Add active terrain triangle/memory budget estimates for 65/129/257 LOD0.
- [x] Write Godot Phase 1 port plan and parity gate order.
- [x] Add aggregate runtime readiness validator and passing report.
- [x] Add runtime artifact hash manifest and verifier for drift detection.
- [x] Add no-write runtime release gate for pre-port readiness.
- [x] Add first Godot terrain module folders, settings, hash/noise code, and hash parity runner.
- [x] Match `factory/runtime/hash_reference/hash_reference.json` in Godot.
- [x] Implement `RuntimeKernelPack` JSON loading and first `.npy` runtime array loading in Godot.
- [x] Match provider-decision metadata in Godot: region, province, palette, family bias, kernel ID, moderation, scales, and transforms.
- [x] Implement scalar `TerrainHeightProvider` in Godot.
- [x] Implement `FlatHeightProvider` in Godot.
- [x] Implement `ProceduralHeightProvider` in Godot as the runtime-facing DEM-kernel sampler.
- [x] Add provider contract check for flat/procedural swap compatibility.
- [x] Match `factory/runtime/terrain_sample_reference.json` in Godot.
- [x] Match `factory/runtime/chunk_reference/chunk_reference_manifest.json` in Godot.
- [x] Implement `TerrainMeshBuilder` in Godot.
- [x] Match `factory/runtime/mesh_reference/mesh_reference_manifest.json` in Godot.
- [x] Implement `TerrainChunk` in Godot.
- [x] Implement `TerrainStreamer` in Godot.
- [x] Match `factory/runtime/streamer_reference/streamer_reference.json` and FIFO comparison in Godot.
- [x] Prioritize nearby queued chunk builds and cancel retired queued work in Godot.
- [x] Implement headless `TerrainWorld` coordinator with flat/procedural providers and streamer ownership.
- [x] Add `TerrainWorld` smoke check for bounded active chunks and deterministic provider sampling.
- [x] Add visible `TerrainWorldNode` that builds real `ArrayMesh` terrain chunks.
- [x] Add visible-node smoke check for mesh creation, provider selection, movement, and chunk retirement.
- [x] Generate Godot runtime visual review PNGs for gray height and LOD-ring checks.
- [x] Add minimal `TerrainPreviewScene` with camera/light around `TerrainWorldNode`.
- [x] Add saved Godot preview scene at `wg-9-directory/worldgen_terrain/scenes/terrain_preview.tscn`.
- [x] Add saved preview scene smoke check that loads the `.tscn` directly.
- [x] Set `project.godot` main scene to the interactive streaming preview so editor Play launches moving terrain directly.
- [x] Set saved preview to a 3x3 continuous composite terrain window for human review.
- [x] Reduce saved preview startup cost enough for editor Play review.
- [x] Add separate interactive streaming preview scene with keyboard movement, camera follow, debug mode switching, bounded active chunks, and chunk turnover.
- [x] Add streaming preview smoke check that simulates movement across chunk boundaries.
- [x] Add streaming tier budget check for `33 x 33` and `65 x 65` review tiers.
- [x] Verify `65 x 65`, radius 1 streaming path functionally.
- [ ] Promote `65 x 65` as default interactive preview only after startup/frame cost is acceptable.
- [x] Profile streaming preview startup and movement stalls.
- [x] Reduce main-scene time-to-first-terrain by using a one-chunk launch/update budget.
- [x] Cache per-grid region/kernel decisions for height grids that stay inside one base region, while preserving scalar fallback for region-boundary grids.
- [x] Treat chunk grids ending exactly on a region boundary as fast-path safe, preserving seam parity while avoiding scalar fallback spikes.
- [x] Use normalized-only kernel array loading for live height sampling so interactive chunks do not decode unused residual arrays.
- [x] Add fast interactive gray material so live streaming does not run a second height-grid pass for diagnostic vertex-color hillshade.
- [x] Cache reusable mesh index and UV layout arrays by vertex density.
- [x] Test optional start-region kernel warm-loading and leave it off by default because the startup tradeoff is not clearly better.
- [x] Fix region-corner family-bias seam artifact by making corner decisions stable per region instead of local corner index.
- [x] Re-profile `33 x 33` live streaming after load-path and boundary fast-path fixes: one-chunk cold builds now avoid the 600-700 ms boundary spikes.
- [ ] Promote `65 x 65` as default only after chunk generation moves out of synchronous GDScript or receives a larger runtime optimization pass.
- [x] Refresh provider, terrain sample, chunk, mesh, readiness, and artifact references after the region-corner seam fix.
- [x] Capture actual rendered Godot screenshots for gray, LOD ring, height-band, seam, family/palette, and hydrology debug modes.
- [x] Capture separate interactive streaming screenshots for in-motion streaming and settled terrain review.
- [x] Capture multi-location settled streaming contact sheet for human review across separated regions.
- [x] Add multi-region machine landform quality probe with relief, slope, local-relief, family, confidence, and source-resolution metrics.
- [x] Add first isolated hydrology-hint diagnostic sampler with padded height sampling, flow accumulation, wetness, and channel-likelihood outputs.
- [x] Add hydrology overlap consistency report so seam-safe fields and window-limited fields are explicitly separated before runtime use.
- [x] Remove per-window hydrology value normalization from diagnostics so overlapping wetness/channel captures do not invent artificial seams.
- [x] Add deterministic hydrology tile cache diagnostic so chunks/debug overlays can sample hydrology facts by world coordinate instead of solving per visible chunk.
- [x] Verify hydrology tile cache scalar fields have zero edge delta across a normal chunk edge and across a hydrology tile boundary.
- [x] Add debug-only hydrology overlay mode backed by the hydrology tile cache.
- [x] Add debug-mode performance regression report for switching into hydrology overlay and back to fast gray.
- [x] Use a half-tile hydrology overlay origin offset so the default review area does not sit on a four-tile hydrology boundary.
- [x] Keep hydrology overlay at an interactive `65 x 65` tile tier while retaining `97 x 97` diagnostics for seam/quality probes.
- [x] Extract backend-neutral mesh surface-array payload construction from scene-node mesh assignment.
- [x] Cache reusable local X/Z vertex layout data per mesh density/step.
- [x] Add mesh payload contract check for future threaded/native mesh generation.
- [x] Add `TerrainChunkBuildJob` request/payload/result wrapper so worker/native code has a concrete non-scene handoff contract.
- [x] Route `TerrainWorldNode` through the chunk build payload wrapper while keeping `ArrayMesh` creation/assignment on the main scene path.
- [x] Add chunk build job contract check for uncolored, colored, mesh-created, and invalid-color payloads.
- [x] Add bounded `MeshInstance3D` chunk-node pooling so streamed chunks reuse scene nodes instead of queue-free/new churn.
- [x] Add chunk node pool regression check proving active count stays bounded and large jumps reuse existing children.
- [x] Add runtime chunk build timing stats: last, recent average, recent max, total builds, active chunks, pooled chunks, and child node count.
- [x] Surface build timing and pool count in the interactive streaming diagnostics overlay.
- [x] Extend streaming performance breakdown with average and max chunk build timings.
- [x] Add Rust GDExtension native terrain backend for Godot 4.6.2.
- [x] Build the native backend in release mode for runtime perf checks.
- [x] Match native prepared height-grid generation against GDScript exactly.
- [x] Enable native prepared height-grid generation by default when the backend is available, with GDScript fallback.
- [x] Probe `257 x 257` native payloads at 2m spacing and 1m local spacing with exact-zero adjacent edge deltas.
- [x] Define `TerrainDetailTierPolicy` for snapped 256m / 257v local patches aligned to the 4m base grid.
- [x] Add `TerrainLocalDetailNode` and mount it behind `TerrainStreamingPreviewScene.use_local_detail`.
- [x] Validate local detail patch build, no-op repeat update, patch-boundary retire/build, disable clear, and exact-zero east/west patch seam.
- [x] Validate local 1m height queries against the authoritative provider and expose active collision-heightfield descriptors.
- [x] Add on-demand `HeightMapShape3D` materialization for active local detail heightfields without enabling physics collision by default.
- [x] Add opt-in local `StaticBody3D` collision body lifecycle for active 1m patches, disabled by default.
- [x] Add native worker queue for local 1m patch payloads so dense local detail can build off the scene update path.
- [x] Add stale-worker regression so completed local detail work cannot attach after the viewer moves to another patch.
- [x] Add streaming-level local detail worker performance check with opt-in collision enabled.
- [x] Add GPU-friendly local detail height/normal surface descriptor contract backed by active CPU heightfields.
- [x] Re-profile `33 x 33` streaming after release native height generation: warm chunks average ~3.5 ms, cold chunks average ~11.9 ms in the perf check.
- [x] Promote walk preview to `512m / 129 vertices = 4m` spacing for closer visual review.
- [x] Add walk-preview perf check for the 4m review tier.
- [x] Fix walk-preview WASD movement to follow the actual camera basis and restore the correct horizontal mouse-look direction.
- [x] Change walk preview from forced ground-follow to free-fly review mode so movement no longer snaps/crashes the camera into terrain.
- [x] Add walk-preview region-jump controls and overlay palette/family summary so different DEM-kernel mixes can be reviewed intentionally.
- [x] Reduce walk-preview review jumps to nearby region hops instead of large province-scale teleports.
- [x] Expand walk-preview retained terrain from `3 x 3` to `5 x 5` chunks while keeping `4m` spacing.
- [x] Replace the experimental two-call native mesh path with a single-call native chunk payload builder.
- [x] Enable the single-call native chunk payload path for the 4m walk preview.
- [x] Add native chunk payload parity/perf checks for `33 x 33` and `129 x 129`.
- [x] Enable godot-rust thread support for the native backend.
- [x] Add isolated native chunk payload worker parity check.
- [x] Move fast-gray native chunk payload builds onto an opt-in `TerrainWorldNode` worker queue.
- [x] Keep final `ArrayMesh` creation and scene assignment on the main thread.
- [x] Enable the native worker queue in the 4m walk preview.
- [x] Add optional ring LOD mesh density plumbing: LOD0 keeps `129 x 129`, outer LOD1 can drop to `65 x 65`.
- [x] Add opt-in skirted chunk edge payloads for mixed-density LOD terrain.
- [x] Add mesh-skirt and LOD-skirt regression checks.
- [x] Add rendered skirted-LOD review captures at `factory/runtime/godot_lod_skirts/`.
- [x] Enable skirted LOD density in the walk preview for review: `7 x 7` retained chunks, near ring `129 x 129`, outer rings `65 x 65` and `33 x 33`.
- [x] Add mixed-density LOD edge continuity check for the walk-preview `7 x 7` skirted window: `32` mixed-density pairs, `52` same-density pairs, zero shared-sample deltas.
- [ ] Human-validate the walk preview's skirted LOD transitions during normal camera movement.
- [x] Add visual-only far-terrain clipmap prototype using the same height provider as chunks.
- [x] Mount the far clipmap in the walk preview behind the near chunk hole.
- [x] Add far clipmap smoke/snap test and rendered review captures at `factory/runtime/godot_far_clipmap/`.
- [x] Fix far clipmap level origins to stay concentric and add transition continuity check with zero fine/coarse boundary deltas.
- [ ] Human-validate far clipmap horizon quality and transition behavior in the walk preview.
- [x] Test `257 x 257` review tiers and 1m local-detail strategies after worker/native payload path lands.
- [x] Plan first GPU detail path after CPU/native height, collision, and seam facts remain stable.
- [ ] Reintroduce wetlands later as hydrology/context data, not first heightfield shaping.

## Godot Phase 1 Boundary

Started after the Godot project shell appeared at `D:/workflows/worldgen9/wg-9-directory/`.

- [x] Create `project.godot` manually.
- [x] Add terrain module folders after project exists.
- [x] Run `python tools/heightfield_prototype/runtime_release_gate.py`.
- [x] Confirm `factory/runtime/runtime_readiness_report.json` is `pass`.
- [x] Verify `factory/runtime/runtime_artifact_manifest.json` before porting fixtures.
- [x] Match `factory/runtime/hash_reference/hash_reference.json` in Godot.
- [x] Implement `RuntimeKernelPack`.
- [x] Match non-height fields in `factory/runtime/provider_decisions/provider_decisions_reference.json`.
- [x] Implement `TerrainHeightProvider`.
- [x] Match `factory/runtime/terrain_sample_reference.json`.
- [x] Implement `FlatHeightProvider`.
- [x] Implement `ProceduralHeightProvider`.
- [x] Implement `TerrainMeshBuilder`.
- [x] Match `factory/runtime/chunk_reference/chunk_reference_manifest.json`.
- [x] Match `factory/runtime/mesh_reference/mesh_reference_manifest.json`.
- [x] Implement `TerrainChunk`.
- [x] Implement `TerrainStreamer`.
- [x] Match `factory/runtime/streamer_reference/streamer_reference.json`.
- [x] Prioritize nearby queued chunk builds and cancel retired queued work.
- [x] Implement `TerrainWorld`.
- [x] Use `2048m` chunks first.
- [x] Start with `129 x 129` LOD0 unless native/threaded mesh building is ready.
- [x] Test `257 x 257` LOD0 after the 129 path is stable.
- [x] Fall back to `65 x 65` LOD0 before shrinking chunks.
- [ ] Optimize/native/thread chunk mesh generation before using `65 x 65` or higher as the normal interactive default.
- [x] Add first visible terrain node with gray, chunk ID, LOD ring, seam, and family/palette debug materials.
- [x] Add first rendered preview capture gate using the normal Godot renderer.
- [x] Add saved `terrain_preview.tscn` for human/editor review.
- [x] Add debug modes: gray, chunk ID, LOD ring, height bands, seam view, family/palette, and hydrology.
- [x] Add automated seam/determinism checks.

Current validation commands:

```text
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/hash_noise_parity_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/runtime_pack_load_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/provider_decision_parity_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/height_provider_contract_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_sample_parity_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/chunk_reference_parity_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/mesh_reference_parity_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/streamer_reference_parity_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_world_smoke_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_world_node_smoke_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_preview_scene_smoke_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_streaming_preview_smoke_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_streaming_tier_budget_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_world_seam_density_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_world_visual_capture_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --path wg-9-directory --script res://worldgen_terrain/tests/terrain_preview_render_capture_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --path wg-9-directory --script res://worldgen_terrain/tests/terrain_streaming_render_capture_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --path wg-9-directory --script res://worldgen_terrain/tests/terrain_streaming_review_contact_sheet_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --path wg-9-directory --script res://worldgen_terrain/tests/terrain_streaming_scale_review_contact_sheet_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_landform_quality_probe_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_hydrology_hint_probe_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_hydrology_consistency_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_hydrology_tile_cache_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_debug_mode_perf_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_mesh_payload_contract_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_chunk_build_job_contract_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_chunk_node_pool_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_build_stats_check.gd
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/terrain_walk_preview_257_perf_probe_check.gd
python tools/godot_runtime_gate.py --suite fast
python tools/godot_runtime_gate.py --suite extended
python tools/godot_runtime_gate.py --suite quality
python tools/godot_runtime_gate.py --suite render
python tools/godot_runtime_gate.py --suite review
python tools/build_godot_review_index.py --verify
python tools/heightfield_prototype/runtime_release_gate.py
```

These pass in this shell using Godot 4.6.2 Mono extracted from
`C:/Users/josep/Downloads/Godot_v4.6.2-stable_mono_win64.zip`.
The provider-decision check intentionally ignores height fields; height sampling,
chunk grids, mesh topology, streamer state, and headless `TerrainWorld` ownership
are covered by later checks in the same bundle.

Latest Godot runtime visual outputs:

```text
D:/workflows/worldgen9/factory/runtime/godot_visual/terrain_world_gray_height.png
D:/workflows/worldgen9/factory/runtime/godot_visual/terrain_world_lod_rings.png
D:/workflows/worldgen9/factory/runtime/godot_review_index/index.html
```

Rendered preview and artifact captures use the normal renderer, not `--headless`,
because headless Godot returns dummy viewport textures. The compact repeatable
render lane is now:

```text
python tools/godot_runtime_gate.py --suite render
```

The broader visual review lane is:

```text
python tools/godot_runtime_gate.py --suite review
```

That suite runs the multi-location streaming sheet, the 65-vertex wide/close
scale sheet, and the 129/4m versus 257/2m walk-density comparison in about 31
seconds on the current machine. Locked render captures should avoid volatile
live overlay text so the runtime artifact manifest remains stable after repeated
render/review-gate runs. Static preview captures opt into the native/fast-gray
chunk path where the debug mode does not require hydrology vertex colors,
keeping the compact render lane around 17 seconds on the current machine.

The locked runtime budget also tracks the current walk-review LOD windows with
skirts. The default 129/4m tier now keeps a 9x9 retained window capped at
max LOD 2, about 572,416 triangles, and about 16.652 MiB of estimated
mesh/height memory. The 257/2m
tier stays as an opt-in 7x7 review window at about 1,947,648 triangles and
56.129 MiB, so it remains a focused scale/detail probe instead of the default
broad streaming density.

Far-clipmap coverage is now budgeted separately from near chunks. The standalone
default 3-ring clipmap covers a 32.768km diameter at about 2.569 MiB of mesh
plus CPU height memory, while a 4-ring variant covers 65.536km at about
3.428 MiB. The locked budget also includes scene-window variants with an
edge-overlap handoff and no full level-0 underlay: the streaming 3x3 review
visual near hole is 3008m, so its active far totals are about 2.461 MiB for 3
rings and 3.319 MiB for 4 rings; the walk 7x7 visual near hole is 1728m, so its
active far totals are about 2.596 MiB and 3.455 MiB. This keeps the intended
scale path focused on far rings/clipmaps rather than raising the retained
near-chunk density indefinitely.

The review index is generated with:

```text
python tools/build_godot_review_index.py
```

It groups plain-gray, scale, hydrology, far-clipmap, and local-detail artifacts
with the specific review questions they are meant to answer. The HTML and JSON
manifest are deterministic and locked by the runtime artifact manifest. Runtime
readiness now also checks the review-index schema, section order, required
manifest/review files, and PNG dimensions so the release gate catches missing or
misindexed visual review evidence.

Latest rendered preview outputs:

```text
D:/workflows/worldgen9/factory/runtime/godot_rendered_preview/preview_gray.png
D:/workflows/worldgen9/factory/runtime/godot_rendered_preview/preview_lod_ring.png
D:/workflows/worldgen9/factory/runtime/godot_rendered_preview/preview_height_bands.png
D:/workflows/worldgen9/factory/runtime/godot_rendered_preview/preview_seam.png
D:/workflows/worldgen9/factory/runtime/godot_rendered_preview/preview_family_palette.png
D:/workflows/worldgen9/factory/runtime/godot_rendered_preview/preview_hydrology.png
```

Latest streaming preview outputs:

```text
D:/workflows/worldgen9/factory/runtime/godot_streaming_preview/streaming_in_motion.png
D:/workflows/worldgen9/factory/runtime/godot_streaming_preview/streaming_settled_gray.png
D:/workflows/worldgen9/factory/runtime/godot_streaming_preview/streaming_gray.png
```

Latest multi-location streaming review outputs:

```text
D:/workflows/worldgen9/factory/runtime/godot_streaming_review/streaming_review_contact_sheet.png
D:/workflows/worldgen9/factory/runtime/godot_streaming_review/streaming_review_manifest.json
D:/workflows/worldgen9/factory/runtime/godot_streaming_review/review_00_origin.png
D:/workflows/worldgen9/factory/runtime/godot_streaming_review/review_01_east_region.png
D:/workflows/worldgen9/factory/runtime/godot_streaming_review/review_02_northwest_region.png
D:/workflows/worldgen9/factory/runtime/godot_streaming_review/review_03_far_southwest.png
D:/workflows/worldgen9/factory/runtime/godot_streaming_review/review_04_far_northeast.png
D:/workflows/worldgen9/factory/runtime/godot_streaming_review/review_05_long_travel.png
```

Latest streaming scale review outputs:

```text
D:/workflows/worldgen9/factory/runtime/godot_streaming_scale_review/streaming_scale_review_contact_sheet.png
D:/workflows/worldgen9/factory/runtime/godot_streaming_scale_review/streaming_scale_review_manifest.json
D:/workflows/worldgen9/factory/runtime/godot_walk_density_review/walk_density_contact_sheet.png
D:/workflows/worldgen9/factory/runtime/godot_walk_density_review/walk_density_129_4m.png
D:/workflows/worldgen9/factory/runtime/godot_walk_density_review/walk_density_257_2m.png
```

Latest machine landform quality outputs:

```text
D:/workflows/worldgen9/factory/runtime/godot_landform_quality/landform_quality_contact_sheet.png
D:/workflows/worldgen9/factory/runtime/godot_landform_quality/landform_quality_report.json
```

Latest hydrology hint diagnostic outputs:

```text
D:/workflows/worldgen9/factory/runtime/godot_hydrology_hints/hydrology_hint_contact_sheet.png
D:/workflows/worldgen9/factory/runtime/godot_hydrology_hints/hydrology_hint_report.json
D:/workflows/worldgen9/factory/runtime/godot_hydrology_hints/hydrology_consistency_report.json
```

Latest hydrology tile diagnostic outputs:

```text
D:/workflows/worldgen9/factory/runtime/godot_hydrology_tiles/hydrology_tile_boundary_contact_sheet.png
D:/workflows/worldgen9/factory/runtime/godot_hydrology_tiles/hydrology_tile_cache_report.json
```

Latest Godot performance diagnostic outputs:

```text
D:/workflows/worldgen9/factory/runtime/godot_performance/debug_mode_perf_report.json
```

Latest local-detail review outputs:

```text
D:/workflows/worldgen9/factory/runtime/godot_local_detail_displacement/local_detail_base.png
D:/workflows/worldgen9/factory/runtime/godot_local_detail_displacement/local_detail_texture_material.png
D:/workflows/worldgen9/factory/runtime/godot_local_detail_displacement/local_detail_displacement.png
D:/workflows/worldgen9/factory/runtime/godot_local_detail_displacement/local_detail_displacement_manifest.json
D:/workflows/worldgen9/factory/runtime/godot_walk_local_detail_review/walk_local_detail_contact_sheet.png
D:/workflows/worldgen9/factory/runtime/godot_walk_local_detail_review/walk_local_detail_manifest.json
```

The local-detail manifests lock the 257x257 / 1m patch budget and image
readability stats. Runtime readiness now checks those manifest schemas, the
257x257 / 1m budget, collision-off walk state, image stats, and the current
subtle-displacement review flags. Current review flags mark displacement as
subtle in both the isolated and walk-preview captures, so that path remains
review-only.

The locked performance JSON intentionally stores deterministic pass/fail timing
checks rather than raw milliseconds. Raw switch timings are printed by
`terrain_debug_mode_perf_check.gd` and `tools/godot_runtime_gate.py`, but they
are not written into the artifact manifest path.

Human/editor review scene:

```text
D:/workflows/worldgen9/wg-9-directory/worldgen_terrain/scenes/terrain_preview.tscn
D:/workflows/worldgen9/wg-9-directory/worldgen_terrain/scenes/terrain_streaming_preview.tscn
```

In the streaming/walk preview, `U` toggles far-clipmap height/normal
texture-material review. This is visual-only GPU handoff review for the broad
horizon rings; it does not change collision, authoritative height queries, or
near-player local detail.

Current visual finding:

```text
The saved scene and rendered captures are real and repeatable. The old
region-boundary block artifact was traced to local corner-salt family bias and
fixed in both Python references and Godot runtime code. Height seams, gray
edge-color seams, chunk parity, mesh parity, and the runtime release gate pass.
Plain gray terrain still needs human acceptance for large contiguous landform
readability before it should be marked done. The saved editor scene is a 3x3
static review window into the infinite sampler. The project main scene is now a
cheap interactive streaming preview using 33 x 33 chunk meshes, radius 1, and
movement-driven chunk turnover; it is a GDScript review tier, not the final
high-density performance target. The streaming capture now writes both an
in-motion proof and a settled gray view so human review is not confused by a
partially filled queue. A separate multi-location contact sheet uses the slower
analytical gray review material and a pulled-back camera to judge landform
readability across separated regions, while live preview keeps the fast gray
shader. The machine landform-quality probe over six 12.288km windows currently
reports 4 strong and 2 moderate landform-signal cases with no warnings, and
now reports actual DEM-kernel source spacing instead of the runtime fallback.
The first hydrology-hint diagnostic is isolated from terrain rendering and
height generation; it uses padded low-resolution height sampling and currently
reports flow/wetness/channel hints for six windows with no warnings. The
hydrology overlap report now gates seam safety separately: height, slope, and
local flow direction are stable fields; accumulation, wetness, and channel
likelihood remain diagnostic-only until a persistent basin/tile hydrology layer
exists. The diagnostic no longer uses per-window value normalization, so
overlapping wetness/channel captures do not create artificial value seams. A
first hydrology tile cache now owns fixed 32768m world tiles and exposes
world-coordinate hydrology samples for future chunk/debug use. Its current
diagnostic reports zero scalar edge delta for flow accumulation, wetness,
channel likelihood, and slope across both a normal chunk seam and a hydrology
tile boundary. The tile check is still a low-resolution diagnostic contract,
not final river generation. A debug-only hydrology overlay now renders through
that same tile cache, so editor/runtime visual review does not solve hydrology
independently per chunk. In the streaming preview, key `7` selects hydrology
debug mode. The interactive hydrology overlay uses a `65 x 65` tile cache with
16 padding cells and a half-tile origin offset; the stronger `97 x 97` tile
diagnostic remains available for seam/quality checks. The debug-mode perf check
still prints boundary-stress switch timings, and the locked artifact stores
only whether those timings stay under their limits so repeated quality-gate
runs do not dirty the runtime artifact manifest. This remains acceptable for a
debug view in GDScript but not good enough for final runtime overlays.
Runtime readiness now checks the landform quality report and hydrology reports
semantically: six review windows, no warnings, usable terrain relief/source
confidence, stable/window-limited hydrology field policy, repeatable tile-cache
sampling, and zero edge deltas across both normal chunk seams and hydrology tile
boundaries.
The 65 x 65, radius 1 tier passes functional streaming checks, but is still too
slow in GDScript for default interactive use.
After the grid-decision cache, the headless tier-budget smoke measured about
`review_33_r1: 8.9s` and `review_65_r1: 34.7s` for the scripted movement pass.
The actual main scene time-to-first-terrain is much lower because it now builds
one chunk on launch instead of synchronously filling the whole 3x3 ring. After
the fast interactive gray material, normalized-only live kernel loading, and the
region-boundary grid fast path, the performance breakdown measured 33 x 33
one-chunk builds around 100-170ms in the scripted profile. Optional kernel
warm-loading reduced first-chunk work slightly but added setup cost and did not
remove later cold-family work, so it remains disabled by default. Static
captures and seam diagnostics still use the more expensive analytical/vertex-
color gray path. Mesh construction now has a backend-neutral surface-array
payload path with cached local X/Z layout data, so future worker/native code can
generate arrays off the scene tree while the main thread only creates or assigns
`ArrayMesh` instances. The terrain node now routes chunk construction through a
`TerrainChunkBuildJob` request/payload wrapper; it is still synchronous GDScript
today, but it defines the non-scene handoff point needed for worker threads or
C++/GDExtension later. After that wrapper, the 33 x 33 streaming perf breakdown
still measures one-chunk live builds around 100-160ms, and the debug hydrology
stress switch is about `23.0s` with four hydrology tiles. Streamed chunk
`MeshInstance3D` nodes are now pooled and reused; a large-jump pool check keeps
active chunks at 9 with 9 child nodes instead of accumulating retired scene
objects. The streaming diagnostics overlay now reports last/average build time,
pooled node count, vertex count, grid spacing, and camera distance/height. The streaming performance breakdown now reports average
and max chunk build time; the current 33 x 33 live path measures about
`103-126ms` average chunk build time across the profiled tiers, with the
boundary/cold path still spiking higher.
A separate 65 x 65 streaming scale-review contact sheet now captures wide and
close views across three separated locations. That sheet is a visual diagnostic,
not the default interactive tier. Current visual read: close views reveal more
DEM-shaped terrain, but the surface can still look blocky/stepped at human
inspection distance, so scale/detail tuning remains open.
The isolated high-density walk probe now tests the same walk-preview shape at
512m / 257 vertices / 2m spacing, with LOD rings, skirts, far clipmap, and
native workers. It intentionally keeps the opt-in 7x7 retained window: current
measured result is 49 retained chunks, setup ~114ms, warmup 56 drain steps,
average chunk build ~20.6ms, max chunk build 72ms, small movement steps ~2ms,
and no far-clipmap rebuild on small movement. This is promising enough for
human high-detail review, but it is still not promoted as the default
editor/main scene until visual scale and memory expectations are reviewed.
```

## Godot Phase 1 Acceptance

- [x] Viewer can move in any direction.
- [x] Chunks appear ahead and retire behind.
- [x] Chunk count stays bounded.
- [x] Same world coordinate returns same height from any chunk.
- [x] Neighbor edge height difference is zero or within defined epsilon.
- [x] LOD rings are visible in debug.
- [ ] Plain gray terrain reads as large contiguous landforms.
- [x] No textures, biomes, rivers, erosion, foliage, or settlements.

## Phase 2 And Beyond

- [x] Swap height providers without changing streamer/mesh code.
- [x] Load promoted kernel pack.
- [x] Use DEM-derived kernels to shape procedural infinite fill.
- [x] Blend regions between kernel families.
- [x] Add source confidence and resolution facts.
- [x] Expose backend-neutral `TerrainWorld.sample()` and world-space height-grid sampling so future native/GPU backends have a stable facts API target.
- [ ] Add DEM patch sampling only after procedural/provider contract is stable.
- [x] Add first hydrology-hint diagnostic only after height and seams are stable.
- [x] Add hydrology overlap consistency check before any hydrology runtime/debug promotion.
- [x] Add first basin/tile-shaped hydrology cache diagnostic for chunk-safe world-coordinate sampling.
- [x] Promote hydrology hints into a debug-only runtime view backed by the hydrology tile cache.
- [x] Add debug-mode performance check so hydrology overlay work does not quietly regress the live preview path.
- [x] Split mesh surface-array payload generation from scene-node assignment as the first native/threading preparation step.
- [x] Add chunk-build job request/payload wrapper as the second native/threading preparation step.
- [x] Add chunk node pooling as a scene-ownership optimization before real threaded/native generation.
- [x] Add build-time stats overlay and regression check so future native/threading work has a measured baseline.
- [x] Add first Godot 4.6 native backend GDExtension scaffold and registration smoke check.
- [x] Port deterministic height-grid generation into native backend.
- [x] Port mesh payload generation into native backend.
- [x] Add worker-thread chunk build queue using native backend payloads.
- [ ] Add GPU-assisted far/detail terrain only after native CPU parity gates pass.
- [ ] Human-review and tune hydrology overlay readability before river graph/path work.
- [ ] Add rivers only after hydrology hints are useful.
- [ ] Add erosion only after river/channel logic proves value.
- [ ] Defer cave system until height terrain, streamer, mesh, debug views, and visual quality are stable.
- [ ] Defer deformable surface edits until base surface/collision rebuild rules are stable.
- [ ] Keep caves as separate streamed mesh interiors, not a reason to convert the whole terrain to voxels.
- [ ] Keep deformation as saved edit layers over deterministic base terrain, not direct mutation of generated base height.
- [ ] Reserve future `TerrainSurfaceSample`, `WorldFactsSample`, `TerrainEditStore`, and backend split concepts without implementing them before the MVP terrain is solid.

## Native/GPU Backend Pivot

The current walk preview proved the GDScript generation path is not a viable
performance target for human-scale terrain. The project has pivoted to native
backend work:

```text
D:/workflows/worldgen9/plans/native_gpu_backend_roadmap.md
D:/workflows/worldgen9/native/wg9_terrain_backend/
D:/workflows/worldgen9/wg-9-directory/wg9_terrain_backend.gdextension
```

Current native status:

```text
Rust GDExtension backend registers in Godot 4.6.2
Wg9TerrainNativeBackend.debug_status() passes
Wg9TerrainNativeBackend.chunk_grid_metrics() passes 512m / 129 = 4m spacing check
native prepared height-grid generation matches the GDScript parity path
native mesh-payload generation from height matches the GDScript mesh builder
single-call native chunk payload generation is active in the walk preview worker path
GPU generation is not started yet
```

Validation command:

```text
Godot_v4.6.2-stable_mono_win64_console.exe --headless --path wg-9-directory --script res://worldgen_terrain/tests/native_backend_registration_check.gd
```

## Future Addendum Position

The cave/deformation addendums are accepted as future-proofing guardrails, not as
a current implementation-order change. They reinforce the current architecture:

```text
current: height-based infinite terrain first
later: shallow surface edit layer
later: separate streamed cave mesh backend
optional much later: local voxel/density pockets only if gameplay requires them
```

Do not rewrite the current height provider, chunk streamer, or mesh path for
caves/deformation. The current `sample_height(world_x, world_z)` contract remains
valid and should later become a convenience wrapper around richer surface/world
facts only after the visible terrain runtime is stable.

## Immediate Next Actions

1. Human-review `godot_rendered_preview/preview_gray.png`, `godot_streaming_preview/streaming_settled_gray.png`, `godot_streaming_review/streaming_review_contact_sheet.png`, `godot_landform_quality/landform_quality_contact_sheet.png`, the saved 3x3 static preview, and the interactive streaming preview for plain gray landform readability.
2. Human-review `godot_streaming_scale_review/streaming_scale_review_contact_sheet.png` for wide-vs-close scale, mesh-density readability, and obvious block/step artifacts before promoting any higher-density tier.
3. Human-review `godot_rendered_preview/preview_hydrology.png`, `godot_hydrology_hints/hydrology_hint_contact_sheet.png`, and `godot_hydrology_tiles/hydrology_tile_boundary_contact_sheet.png` to confirm flow/wetness/channel hints generally follow valleys and divides.
4. Tune hydrology overlay readability only if visual review says it is unclear; keep it debug-only and tile-cache-backed. Do not raise the interactive overlay above the `65 x 65` tile tier until native/threaded terrain jobs exist.
5. Human-review `factory/runtime/godot_review_index/index.html` and record plain-gray, scale, hydrology, far-clipmap, and local-detail decisions.
6. Human-review `godot_streaming_far_overview/streaming_far_overview_contact_sheet.png`, `godot_streaming_far_overview/streaming_far_overview_manifest.json`, and `godot_far_clipmap/far_clipmap_4ring_wide.png`; then use `H` in the live streaming preview to compare `far 3L` and `far 4L`, and `J` to frame the current far clipmap overview before promoting 4-ring review scenes.
7. Human-review `godot_walk_density_review/walk_density_contact_sheet.png` to decide whether the high-detail `512m / 257v / 2m` walk tier earns an explicit editor/review scene despite its roughly 4x mesh/memory budget over 129/4m.
8. Human-review `godot_local_detail_displacement/local_detail_displacement_manifest.json` and `godot_walk_local_detail_review/walk_local_detail_manifest.json`; current manifests flag displacement as visually subtle, so do not default-enable local visual displacement until that is an intentional decision.
9. Add GPU-assisted far/detail terrain only after CPU-native parity and collision/query requirements are satisfied.
10. Keep offline DEM curation moving separately with `factory/catalog/expansion_review/expansion_queue_contact_sheet.png`.
