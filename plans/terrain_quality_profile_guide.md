# Terrain Quality Profile Guide

Last updated: 2026-05-25

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

It is defined in:

```text
res://worldgen_terrain/core/terrain_quality_profile.gd
```

The walk preview applies this profile in `_init()` and exposes
`quality_profile_report()` so tests and future UI can see the active contract.

## Current Walk Review Contract

```text
near terrain: 512m chunks, 129 vertices, 4m spacing
near window: 7x7 chunks
far terrain: 4 page-backed clipmap levels
far radius: 32768m
camera far: 120000m
fog begin/end: 30000m / 33000m
page recenter: opaque geometry with previous/current height blend
workers: 6 native chunk workers, far page mesh workers disabled
```

The fog values are intentionally part of the profile. They are not a visual
band-aid inside the playable area; they are the outer-edge visibility contract
for the currently loaded far clipmap radius.

## Gates

Run through the wrapper only:

```text
python D:/workflows/worldgen9/tools/godot_runtime_gate.py --check terrain_quality_profile_check.gd
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
```

## Roadmap Use

When the distant edge, motion profile, or residency budget needs tuning, change
the profile first and then let the gates tell us what moved. Do not patch one
scene value by hand unless the change is intentionally local to that scene.

Next profile work:

```text
1. Add a visibility/fog contract report artifact.
2. Add profile-specific motion thresholds once fast-flight residency policy is fixed.
3. Add high-density/local-detail profiles after the default walk profile is stable.
4. Add future GPU page profile fields behind the same profile id.
```
