# Terrain Quality Profile Guide

Last updated: 2026-05-26

## Purpose

`TerrainQualityProfile` is the source of truth for review/runtime knobs that
must move together. Before this slice, the same decisions lived in the walk
scene script, saved scene files, tests, and roadmap notes.

The profile exists so these settings cannot drift independently:

```text
near chunk size and density
near retained radius
build and worker budget
far clipmap level count and page policy
far recenter/page blend policy
camera far plane
edge fog begin/end
motion-profile expectations
```

## Current Profile

The active default profile is:

```text
walk_review
```

An opt-in review profile also exists:

```text
local_detail_review
high_density_257_review
```

It is defined in:

```text
res://worldgen_terrain/core/terrain_quality_profile.gd
```

The walk preview applies this profile in `_init()` and exposes
`quality_profile_report()` so tests and future UI can see the active contract.

## Current Walk Review Contract

```text
near terrain: 512m chunks, 129 vertices, 4m spacing
review color: elevation_color
near window: 7x7 chunks
near forward prefetch: 1 movement-biased overlap window
far terrain: 4 page-backed clipmap levels
far radius: 32768m
far GPU page residency: 64 height/normal page textures
camera far: 120000m
fog begin/end: 30000m / 33000m
page recenter: opaque geometry with previous/current height blend
workers: 6 native chunk workers, persistent far-page native workers enabled
```

The fog values are intentionally part of the profile. They are not a visual
band-aid inside the playable area; they are the outer-edge visibility contract
for the currently loaded far clipmap radius.

The forward prefetch value is also part of the profile. It does not expand the
base retained window in all directions; it keeps one extra row or diagonal
corner fan ahead of the current movement vector so fast flight has terrain
resident before the viewer reaches the next chunk boundary. The current walk
profile expects 49 base chunks, 56 cardinal-forward chunks, or 62 diagonal
forward chunks after movement direction is known. The walk preview now seeds
that direction from the initial camera yaw during setup, so the first visible
movement already has the forward row preloaded.

`elevation_color` is the default walk-review mode so landform changes are not
hidden by a flat white/gray surface. It is still a debug material, not final
biome texturing: low elevations are dark, middle elevations pass through a
rainbow ramp, and high elevations trend toward white. Press `1` for the old gray
review and `8` to return to elevation color. The saved walk scene now opens in
this mode as well, so launching `terrain_walk_preview.tscn` directly matches the
profile instead of falling back to gray.

## Gates

Run through the wrapper only:

```text
python D:/workflows/worldgen9/tools/godot_runtime_gate.py --check terrain_quality_profile_check.gd
python D:/workflows/worldgen9/tools/godot_runtime_gate.py --check terrain_visibility_contract_check.gd
python D:/workflows/worldgen9/tools/godot_runtime_gate.py --check terrain_walk_prefetch_residency_check.gd
python D:/workflows/worldgen9/tools/godot_runtime_gate.py --suite fast
```

The profile check validates:

```text
profile exists and is listed
required settings are present
walk preview pre-setup values match the profile
live setup values still match the profile
camera far matches the profile
visibility loaded radius matches far clipmap budget
fog begin/end/camera far form a sane edge-only visibility contract
walk profile carries the forward-prefetch setting
walk profile uses elevation-color review by default
walk profile carries the far GPU page residency budget
```

The visibility contract check writes:

```text
D:/workflows/worldgen9/factory/runtime/godot_visibility_contract/visibility_contract_report.json
```

It validates the active walk profile against the live scene and far clipmap:
loaded radius, camera far plane, hidden buffer, fog begin/end, transition
length, global fog density, edge-fog shader settings, page-clipmap mode, and
viewer-tracked fog center.

The prefetch residency check starts the walk scene, applies forward movement,
drains terrain workers, and verifies the movement-biased active set is resident:
49 base chunks plus the expected forward prefetch row for the profile.
The motion profile separately reports base-window misses and prefetch-row
misses so a still-building optional row is not confused with visible terrain
pop-in.

The page-backed far clipmap now uses native workers for recenter payloads. The
old CPU page path remains as a fallback/cache-hit path, but normal motion should
schedule page payloads off the scene thread, commit the full level set together,
and start the previous/current height-page blend on assignment.

Persistent far page height/normal textures now pass through a bounded GPU page
residency cache. The cache is keyed by the same page request contract as the CPU
page cache, protects currently active page keys from ordinary eviction, and
reports hits, uploads, evictions, page count, and MiB usage through far clipmap
stats. This is still a texture-backed page residency step; the final renderer
promotion is persistent ring geometry displaced from resident height pages.

The default walk far clipmap now uses raw provider height pages for persistent
mode and leaves coarse/fine LOD morph to the shader. CPU-side morphing remains
for the older non-persistent mesh path, but persistent page rendering should not
double-morph height data before the shader sees it.

## Local Detail Review Profile

`local_detail_review` is review-only and does not change the default walk scene.
It starts from `walk_review`, then enables one active 1m local-detail patch with:

```text
surface texture material: on
visual displacement: on
displacement strength/limit: 0.45 / 2.5m
collision bodies: off
active patch budget: 1
native local-detail workers: on
```

The quality-profile gate applies this profile to a live walk scene and verifies
that the local-detail node, surface material, visual displacement, and collision
policy match the profile. This gives the remaining human-review step a stable
launch contract without default-enabling local detail for normal walk review.

The profile also owns the local-detail review performance budgets consumed by
`terrain_streaming_local_detail_surface_perf_check.gd`, including patch assign,
surface texture, parameter refresh, displacement-toggle texture, move-update,
and drain-frame limits. Local-detail review settings and the gate that protects
them should move together.

## High Density 257 Review Profile

`high_density_257_review` is review-only and does not change the default walk
scene. It starts from `walk_review`, then switches the near chunk density to:

```text
near vertices: 257 x 257
near spacing: 2m on 512m chunks
near window: 7x7 chunks
build budget: 2 chunks per frame
preload before start: off
native chunk workers: 4
forward prefetch: off
```

The profile owns the 257v probe budgets consumed by
`terrain_walk_preview_257_perf_probe_check.gd`: setup time, queue drain steps,
average native chunk build time, native payload time, and small-move update
time. This keeps high-density review measurable without quietly promoting it to
the normal walk-review profile.

## Roadmap Use

When the distant edge, motion profile, or residency budget needs tuning, change
the profile first and then let the gates tell us what moved. Do not patch one
scene value by hand unless the change is intentionally local to that scene.

Next profile work:

```text
1. Add profile-specific motion thresholds now that the first fast-flight residency policy is gated.
2. Add human-review acceptance notes for `local_detail_review` and `high_density_257_review` before either influences defaults.
3. Move far page generation/upload toward GPU compute or lower-churn native texture upload after visual review remains stable.
4. Add optional profile tiers for review-only far radius and hidden-edge buffer tuning.
```

## Landform Profiles

Terrain quality profiles are runtime/render contracts. Landform tuning profiles
are generator contracts and live in:

```text
res://worldgen_terrain/height/terrain_landform_profile.gd
```

Current landform profiles:

```text
balanced_current
strong_mountains
compressed_scale
```

They are validated by:

```text
python D:/workflows/worldgen9/tools/godot_runtime_gate.py --check terrain_landform_profile_compare_check.gd
```

The check writes:

```text
D:/workflows/worldgen9/factory/runtime/godot_landform_profiles/landform_profile_report.json
D:/workflows/worldgen9/factory/runtime/godot_landform_profiles/landform_profile_contact_sheet.png
```

Live profile review scene:

```text
res://worldgen_terrain/scenes/terrain_landform_profile_tour.tscn
```

Controls:

```text
V advances profile
P toggles automatic profile cycling
N/B moves to next/previous representative site
```

Non-neutral landform profiles are review-only. They intentionally disable native
prepared-grid/chunk payload support until the native/GPU backend consumes the
same profile settings and passes parity.
