# Runtime Motion Profile Guide

Last updated: 2026-05-26

## Purpose

The walk preview must prove that motion, recentering, chunk streaming, and far
clipmap updates behave as one runtime system. Static seam checks and screenshots
are still useful, but they cannot tell whether a visible jump comes from:

```text
frame-time work
chunk queue starvation
far clipmap recenter cadence
height-page blend timing
LOD/material changes
outer-edge pop-in
```

The motion profile gate exists to separate those causes before more visual
tuning is attempted.

## Current Gate

Run through the Godot wrapper only:

```text
python D:/workflows/worldgen9/tools/godot_runtime_gate.py --suite fast
```

Or run just the motion profile:

```text
python D:/workflows/worldgen9/tools/godot_runtime_gate.py --check terrain_walk_motion_profile_check.gd
```

The check writes:

```text
D:/workflows/worldgen9/factory/runtime/godot_walk_motion_profile/walk_motion_profile_report.json
```

## What It Measures

The profile drives the actual `TerrainWalkPreviewScene` forward at high speed
and records per-frame runtime facts:

```text
step update milliseconds
active vs built chunk count
base-window vs prefetch-window residency
chunk queue and native worker backlog
chunk create/retire churn
far clipmap pending rebuilds
far clipmap worker activity
far page rebuild deltas
far page blend activity
far GPU page residency hits/uploads/evictions/MiB
far page displacement bounds
anchor/recenter frames
near/far draw and triangle estimates
current quality profile report
final diagnostics string
```

The pass/fail thresholds are deliberately conservative. This gate is not yet a
final performance budget. It is a diagnosis contract: it must produce enough
data to decide where the next fix belongs. The first quality-profile residency
policy is now explicit: the walk profile prefetches one movement-biased near
chunk row, and `terrain_walk_prefetch_residency_check.gd` gates that it becomes
resident after workers drain.

## How To Read Failures

```text
motion_step_ms
```

The scene thread is doing too much work during motion. Investigate chunk
payload assignment, page upload/build cost, material refresh, and cache churn
before changing visuals.

```text
not_full_frames
```

The near chunk window is not resident during the motion profile. The current
report splits this into base-window and prefetch-window readiness. Base-window
misses are visual-risk failures; prefetch-window misses mean the optional next
row is still building and should be treated as scheduling pressure.
The first locked fast-flight residency budget is one forward prefetch step:
49 base chunks, 56 cardinal-forward chunks, or 62 diagonal-forward chunks after
movement direction is known.

The current page-backed far clipmap uses native workers for persistent page
recenter payloads. A healthy recenter frame can show pending far work and active
far workers without immediately increasing build counts; the commit should
happen after the full page set is ready, then height-page blend activity should
be observed.

The same far stats now include GPU page residency. A healthy profile should not
show runaway uploads or evictions for active pages; those indicate page churn or
an undersized residency budget before they become visible stutter.

Persistent page meshes are shader-displaced, so they must also carry custom
visibility bounds that cover the current and previous height pages during a
blend. Without that, the renderer can cull a visually displaced page as though
it were still a flat mesh at y=0, which reads as angle-dependent holes or
approach pop-in rather than a generation bug.

```text
queue_backlog_frames
```

Generation work is outpacing the current budget. Do not raise visual density
until the queue policy and cache pressure are understood.
This is currently a warning unless it also causes hard step-time failures.

```text
no_recenter_frames_observed
```

The profile did not cross a far clipmap recenter threshold, so it cannot prove
the thing it is supposed to test.

```text
no_page_blend_activity_observed
```

Far page recentering happened without shader height-page blend activity. That
means the transition policy regressed.

## Roadmap Policy

Use this order when motion feels wrong:

```text
1. Run the motion profile gate.
2. If step times spike, fix scheduling/cache/upload work first.
3. If chunks are missing, fix residency and forward prefetch.
4. If recenter frames are cheap but visible, tune height-page blend, morph
   band width, or recenter cadence.
5. If only distant edge pop-in remains, adjust the visibility contract.
6. Do not use inner fog, full-page alpha fade, or biome textures to hide
   unstable height motion.
```

This keeps the project aligned with the World 4 lesson: stable world-space
pages, previous/current height blend, coarse/fine morph, and measured motion
before subjective visual tweaks.
