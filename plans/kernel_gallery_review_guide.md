# Kernel Gallery Review Guide

The kernel gallery is a review-only scene for proving that the runtime provider
can expose the full promoted DEM-kernel set as visible terrain variety.

It does not change production biome size, region size, terrain sampling, or the
walk preview. It samples real procedural world sites and lays those samples out
as a compact grid so the current kernel range can be inspected in one place.

## Scene

```text
res://worldgen_terrain/scenes/terrain_kernel_gallery.tscn
```

The scene builds one small colored terrain tile per selected kernel. The current
selection target is 36 tiles, matching the current runtime kernel pack. Each
tile stores metadata for:

```text
kernel_id
region
primary_family
secondary_family
palette
```

The tile geometry is normalized for side-by-side inspection. Heights are still
sampled from the real world provider, but each tile is vertically centered and
scaled so one high mountain kernel does not make nearby lower-relief kernels
unreadable.

## Generated Review Artifacts

```text
D:/workflows/worldgen9/factory/runtime/godot_kernel_gallery/kernel_gallery_contact_sheet.png
D:/workflows/worldgen9/factory/runtime/godot_kernel_gallery/kernel_gallery_manifest.json
```

The contact sheet is renderer-independent and can be generated headlessly. It is
not a replacement for opening the scene, but it is stable enough for CI/review
index inclusion.

## Validation

```text
python D:/workflows/worldgen9/tools/godot_runtime_gate.py --check terrain_kernel_gallery_scene_check.gd
python D:/workflows/worldgen9/tools/godot_runtime_gate.py --check terrain_kernel_gallery_contact_sheet_check.gd
```

Current contract:

```text
36 selected tiles
36 unique kernel IDs
at least 8 families
at least 5 palettes
0 missing kernel IDs
```

## Review Use

Use this scene when the live walk preview feels like it is showing one repeated
geography. The gallery answers a narrower question:

```text
Can the runtime provider find and render every promoted kernel as a distinct
terrain source?
```

It does not answer whether the infinite streaming view places those kernels at
the right frequency, scale, or biome transition width. Those remain walk-preview
and world-facts/biome-resolver questions.
