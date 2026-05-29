# WorldGen9 Orchestrator Handoff - Current State

Last updated: 2026-05-28

## Purpose

This document is the fresh-start handoff for taking ownership of WorldGen9 from
the current state. The project has a large amount of terrain infrastructure, but
the live infinite-map renderer is not visually accepted yet.

The main instruction for the next owner is simple: do not assume the latest
green gates mean the black terrain slab problem is fixed.

## Current Truth

- Live review still shows large black terrain slabs/rectangles near or in front
  of the viewer.
- The overlay can report full active chunk residency, no queued work, and no
  active workers while the slab is visible.
- The latest user capture showed roughly `chunks 107/107`, `queue 0+0`,
  `workers 0`, `far 4L`, and a large black slab in the foreground.
- The issue appears during fast fly/movement and can trail or move relative to
  the viewer.
- The scene is not ready to be called an infinite good-looking terrain renderer.

## What Passed But Is Not Enough

Recent gates are still useful, but they do not cover the active failure:

- `fast` gate passes data/runtime contracts.
- `gpu` gate passes renderer-device, GPU page, residency, and compute contracts.
- The hitch profiler reported `max_terrain_missing_base_chunks=0` after the
  residency-halo work.
- Far level 0 full-underlay and render-context scoped payload commits are in
  place.
- Streamer residency halo and forward prefetch exist.

These prove that many internal counters and contracts are working. They do not
prove that the visible terrain surface has valid geometry, material, texture
bindings, culling bounds, and depth/render state during live motion.

## Hard Stop

Do not promote more terrain features as accepted runtime progress until the
black slab is identified and closed:

- no biome/material promotion
- no corridor/pass promotion
- no erosion promotion
- no local detail promotion
- no near GPU page chunk promotion
- no more fog/alpha masking as the primary fix

Exploration can continue, but the accepted roadmap is blocked on visual terrain
correctness.

## Primary Reproduction

Run one of the live GPU/walk review scenes:

```text
res://worldgen_terrain/scenes/terrain_gpu_page_profile.tscn
res://worldgen_terrain/scenes/terrain_gpu_page_review.tscn
res://worldgen_terrain/scenes/terrain_walk_preview.tscn
```

Use fast fly and move across chunk/far-page boundaries. Watch for:

- a black rectangular/slab surface near, under, in front of, or behind the
  camera
- visible terrain count reporting full residency
- queue/workers at zero while the artifact remains visible
- far clipmap page/recenter motion coinciding with the artifact

The failure should be treated as visual, not only statistical.

## Current Leading Hypotheses

These are hypotheses, not proven causes:

1. Far clipmap page material or texture binding is invalid but still counted as
   loaded.
2. A far level page is using fallback/error material while diagnostics report a
   healthy page lifecycle.
3. A stale far payload or page descriptor survives a context/profile/recenter
   change.
4. Persistent page mesh, custom AABB, culling, or depth/render priority is wrong.
5. Near chunk mesh/material pooling is displaying an old or invalid surface.
6. Near/far overlap policy is still exposing the wrong surface during motion.
7. Existing tests track keys and residency, but not actual pixel/mesh validity.

Do not pick one and patch blindly. First identify the source surface.

## Required Diagnostic Pass

Build a source-identification layer before another fix attempt.

Add a debug mode or scene that colors surfaces by ownership:

```text
near chunks: one obvious color family
far clipmap level 0: distinct color
far clipmap level 1: distinct color
far clipmap level 2: distinct color
far clipmap level 3: distinct color
fallback/error material: bright magenta or red, never black
```

Add runtime provenance for every terrain MeshInstance3D:

```text
owner: near_chunk | far_clipmap | local_detail | unknown
chunk key or page origin
far level if applicable
render context version/key
payload mode
material mode
height texture valid
normal texture valid
custom AABB min/max
visible/loaded/resident status
```

Add a single isolation matrix, preferably driven by a small test scene:

```text
far clipmap on/off
near chunks on/off if practical
direct RD far textures on/off
GPU provider far textures on/off
native far workers on/off
persistent page mesh on/off
level0 full underlay on/off
elevation-color material vs gray material
```

The output should say which switch removes the slab and which visible surface
owns it.

## Required Gate

Add a renderer-backed visual gate for the specific failure class.

Minimum gate behavior:

- drive fast movement across several recenters
- capture frames from the live scene
- classify large near-camera black connected components
- fail if such a component appears while terrain should cover the view
- write a manifest with overlay counters, active pages/chunks, and surface
  provenance for the failing frame

This gate should sit beside the existing GPU profile checks. The current
`max_terrain_missing_base_chunks=0` metric is not sufficient.

## Current Architecture Snapshot

Near terrain:

- 512m chunks
- 129 vertices by default
- 4m spacing
- native worker payloads remain the accepted near path
- near GPU page chunks exist but are not accepted in saved review scenes

Far terrain:

- persistent page-backed clipmap
- 4 levels in review profiles
- direct `Texture2DRD` page residency when renderer device is available
- GPU provider texture path exists for far pages
- level 0 currently remains as a full underlay below near chunks

Worldgen proof:

- DEM kernel catalog and runtime kernel sampling exist
- kernel gallery/tour and landform profile tour exist
- elevation color debug material exists
- pass/corridor facts exist but are not promoted as a stable live review target

GPU state:

- isolated GPU macro-height, DEM-kernel, and prepared-provider proofs exist
- main renderer device texture handoff exists
- far page direct RD residency exists
- near provider/near page paths are experimental and should remain unpromoted
  until visual parity and pacing are proven

## Recent Attempts That Did Not Close The Blocker

- Full far level-0 underlay with a small downward bias.
- Far render-context versioning for async payloads.
- Staged far payload commit validation.
- Streamer residency halo around the active base window.
- Larger forward prefetch for GPU review/profile scenes.
- Data-level gate for missing base-window chunks.

Keep these unless proven harmful, but do not cite them as acceptance.

## Documentation Rules Going Forward

- If a user screenshot disproves a claim, update docs immediately.
- Separate data-contract pass from visual acceptance.
- Do not write “fixed” unless a live visual gate and a manual review both agree.
- Keep screenshots/artifacts tied to the scene and profile that generated them.
- Record the exact scene and overlay counters for every visual failure.

## Suggested Next Owner Checklist

1. Add ownership-color debug rendering.
2. Add per-surface provenance reporting.
3. Reproduce the black slab and identify its owner.
4. Add the renderer visual gate for black connected components.
5. Fix the identified owner path.
6. Re-run `fast`, `gpu`, and the new visual gate.
7. Only then resume roadmap work beyond renderer correctness.

