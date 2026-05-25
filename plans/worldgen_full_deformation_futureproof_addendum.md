# WorldGen Terrain Addendum — Future-Proofing for Deformation, Caves, and Optional Voxel/Density Terrain

**Status:** Non-breaking addendum  
**Intended base spec:** `worldgen_terrain_implementation_with_biome_planning.md`  
**Purpose:** Preserve the original height-based terrain roadmap while leaving a clean path toward deformable land, caves, local voxel zones, or a full density terrain backend later.

This addendum should be appended to the existing terrain spec. It does **not** replace the original roadmap and should not change the current implementation order.

---

## 0. Compatibility Promise

The current terrain roadmap remains unchanged:

```text
1. Infinite terrain chunks
2. Clean height provider
3. DEM sampling
4. DEM resolution blending
5. Procedural infinite fill
6. Hydrology hints
7. Rivers
8. Erosion
```

This addendum adds only future-proofing rules.

Do **not** pause or rewrite the height terrain work for voxels, caves, or full deformation.

The current MVP still starts with:

```gdscript
height = sample_height(world_x, world_z)
```

The long-term architecture should simply avoid making that the only possible terrain model forever.

---

## 1. Core Long-Term Rule

> World generation must be separate from terrain rendering.

The DEM system, procedural fill, hydrology, rivers, erosion, biome facts, caves, and edits should produce reusable world data.

They should not depend directly on one renderer such as:

```text
heightmap chunks
clipmap terrain
mesh caves
voxel terrain
SDF terrain
```

The renderer/backend can change later. The world generation core should remain useful.

---

## 2. Target Long-Term Shape

The system should be able to evolve through these stages:

```text
Stage 1:
  Infinite height terrain

Stage 2:
  Surface deformation
  craters, trenches, digging down, spell impacts, roads, flattening

Stage 3:
  Mesh caves
  cave entrances, tunnels, chambers, underground rivers

Stage 4:
  Local voxel/density zones
  mining pockets, destructible cave walls, special diggable areas

Stage 5:
  Optional full density terrain backend
  true tunnels, overhangs, floating chunks, full terrain destruction
```

Stages 2-5 are optional future tracks. Stage 1 remains the active foundation.

---

## 3. Do Not Break the Current Height Provider

The current provider should remain valid:

```gdscript
func sample_height(world_x: float, world_z: float) -> float:
    return 0.0
```

Long-term, this can become a convenience wrapper around a richer surface sample:

```gdscript
func sample_height(world_x: float, world_z: float) -> float:
    return sample_surface(world_x, world_z).height_m
```

But the early chunk renderer should not need the richer version yet.

---

## 4. Future Sampling Interfaces

### 4.1 Surface sample

Used by height terrain, rivers, biome placement, surface deformation, and collision.

```gdscript
class_name TerrainSurfaceSample

var height_m: float
var base_height_m: float
var edited_height_m: float
var slope: float
var curvature: float
var roughness: float
var source_confidence: float
var dem_confidence: float
var biome_hint_id: int
var wetness: float
var river_distance_m: float
var floodplain_score: float
var soil_depth_m: float
var diggable_depth_m: float
var bedrock_height_m: float
```

Early versions can leave most fields at default values.

### 4.2 World facts sample

Used by biomes, hydrology, cave planning, erosion, and later voxel/density generation.

```gdscript
class_name WorldFactsSample

var elevation_m: float
var normalized_elevation: float
var slope: float
var aspect: float
var curvature: float
var roughness: float
var local_relief: float
var moisture: float
var temperature: float
var wetness: float
var flow_accumulation: float
var river_likelihood: float
var distance_to_river_m: float
var floodplain_score: float
var rockiness: float
var soil_depth_m: float
var diggable_depth_m: float
var cave_likelihood: float
var karst_likelihood: float
var terrain_kernel_type: int
var source_confidence: float
```

This keeps biomes, caves, and deformation from depending directly on mesh chunks.

### 4.3 Density sample

Only needed for local voxel zones or a full voxel/density terrain backend.

```gdscript
class_name TerrainDensitySample

var density: float
var material_id: int
var hardness: float
var moisture: float
var ore_score: float
var source_confidence: float
```

This should not be required for the current terrain phases.

---

## 5. Terrain Backend Split

The long-term system should separate world generation from terrain backends.

```text
WorldGenCore
 ├── DEMProvider
 ├── KernelProvider
 ├── TerrainSurfaceProvider
 ├── WorldFactsProvider
 ├── HydrologyProvider
 ├── RiverProvider
 ├── ErosionProvider
 ├── BiomeFactsProvider
 ├── CavePlanner
 └── TerrainEditStore

TerrainBackend
 ├── HeightTerrainBackend
 ├── DeformableSurfaceBackend
 ├── CaveMeshBackend
 └── VoxelDensityBackend
```

Early implementation only needs:

```text
WorldGenCore / height provider pieces
HeightTerrainBackend
```

The other backends are optional future modules.

---

## 6. Backend Contract

Terrain backends should ask the world generation core for data. They should not own world rules.

Suggested abstract shape:

```gdscript
class_name TerrainBackend

func initialize(world_core) -> void:
    pass

func update_viewer_position(world_position: Vector3) -> void:
    pass

func apply_edit(edit: TerrainEdit) -> void:
    pass

func shutdown() -> void:
    pass
```

A height backend may ignore 3D edits. A voxel backend may use them fully. The edit object can be shared.

---

## 7. Future-Proof Terrain Edits

Terrain edits should be saved separately from base terrain.

Base terrain remains deterministic:

```text
DEM + procedural generation + hydrology + erosion
```

Runtime changes are layered on top:

```text
spell craters
trenches
flattened building pads
digging
mounds
cave mouth cuts
mining damage
```

### 7.1 TerrainEdit data shape

```gdscript
class_name TerrainEdit

var id: String
var edit_type: int
var dimensionality: int
var mode: int

var world_position: Vector3
var radius_m: float
var depth_m: float
var strength: float
var falloff: float

var affected_material_id: int
var replacement_material_id: int
var timestamp: float
var owner_id: String
```

Suggested enums:

```gdscript
enum TerrainEditDimensionality {
    SURFACE_2D,
    VOLUME_3D
}

enum TerrainEditMode {
    ADD,
    SUBTRACT,
    REPLACE,
    PAINT_MATERIAL,
    DAMAGE
}

enum TerrainEditType {
    CRATER,
    FLATTEN,
    MOUND,
    TRENCH,
    ROAD_CUT,
    RIVER_CUT,
    CAVE_MOUTH_CUT,
    SPELL_IMPACT,
    MINING_SUBTRACT,
    MATERIAL_REPLACE
}
```

Early surface terrain only needs `SURFACE_2D` edits.

Future voxel/density systems can use `VOLUME_3D` edits.

---

## 8. Deformable Surface Layer

The first deformation system should not be full voxel terrain.

It should be a limited-depth surface layer.

```text
base surface height
minus diggable depth
equals bedrock floor
```

Formula:

```gdscript
var base_height := base_provider.sample_height(x, z)
var diggable_depth := facts_provider.sample_world_facts(x, z).diggable_depth_m
var bedrock_height := base_height - diggable_depth

var edit_delta := terrain_edit_store.sample_surface_delta(x, z)
var edited_height := base_height + edit_delta

var final_height := max(edited_height, bedrock_height)
```

This supports:

```text
spell craters
explosion pits
trenches
digging downward
road cuts
flattened construction areas
mounds / berms
river cuts
landslide deposits
```

It does not support true tunnels, caves, overhangs, or floating chunks. Those require mesh caves or density/voxel terrain.

---

## 9. Spell / Ability Deformation

Spell effects should create terrain edits, not directly modify mesh vertices.

Example flow:

```text
1. Spell hits terrain
2. Create TerrainEdit
3. Save edit to TerrainEditStore
4. Mark affected chunks dirty
5. Rebuild visible mesh chunks
6. Rebuild nearby collision only
7. Optional: spawn temporary particles, decals, rocks, scorch marks
```

Examples:

```text
fireball:
  crater + scorch material hint

earth spike:
  mound / raised cone edit

meteor:
  large crater + debris props

ice spell:
  shallow deformation + frozen material hint

quake:
  trench / crack decals / displaced rocks
```

Visual effects can be immediate. Terrain rebuild can be budgeted across frames.

---

## 10. Mesh Caves Without Full Voxels

Caves should be added as a separate system, not as a replacement for height terrain.

```text
surface terrain = exterior world
cave mesh system = interior spaces
terrain edit store = cave mouth cuts and entrance blending
```

A cave entrance can be made from:

```text
surface edit stamp
cave mouth mesh
rock/arch cover mesh
interior tunnel mesh
occlusion bend, darkness, or fog
stream trigger
```

The height terrain does not need to represent the full cave volume.

### 10.1 Cave planner should use world facts

Cave placement can use:

```text
elevation
slope
rockiness
soil depth
karst likelihood
river distance
wetness
terrain kernel type
mountain/valley position
```

This lets caves connect to the world generator without depending on mesh chunks.

---

## 11. Local Voxel / Density Pockets

If mining or destructible cave walls become important, add local density zones instead of converting the whole world to voxels.

Use cases:

```text
ore pockets
mining caves
destructible cave walls
special dungeon terrain
sinkholes
soft dirt pockets
localized tunneling zones
```

These zones can exist under or inside the height terrain.

```text
normal world surface:
  height terrain

special underground region:
  local density/voxel chunk group
```

The surface terrain remains the main renderer.

---

## 12. Full Density / Voxel Terrain Path

If the game eventually needs full terrain destruction, the surface terrain can become a density field.

A height surface converts to density like this:

```gdscript
var surface_height := surface_provider.sample_height(x, z)
var density := surface_height - y
```

Meaning:

```text
density > 0 = solid
density < 0 = air
```

Then caves and edits subtract from that field:

```gdscript
density = surface_height - y

density -= cave_carve_field.sample(x, y, z)
density -= terrain_edit_store.sample_volume_subtraction(x, y, z)
density += terrain_edit_store.sample_volume_addition(x, y, z)
```

This allows the existing DEM/procedural surface to become the outer shell of a voxel world.

---

## 13. What Carries Forward to Voxels

The following systems should remain useful even if a voxel backend is added later:

```text
DEM importing
DEM resolution blending
terrain kernels
procedural infinite fill
world coordinate system
chunk/region streaming concepts
floating origin planning
biome facts
moisture / temperature / elevation logic
hydrology facts
river graphs
erosion concepts
cave planning
terrain edit store
save/load regions
material IDs
soil depth / bedrock depth
```

The following systems are renderer-specific and may need replacement or a second implementation:

```text
heightmap mesh builder
heightmap seam handling
terrain skirts
heightmap-only collision
surface-only river carving
surface-only erosion implementation
clipmap surface renderer
```

This is acceptable. The goal is to keep world generation reusable, not every renderer detail.

---

## 14. Save System Implications

Do not save generated base terrain.

Save only:

```text
world seed / source IDs
DEM source references or imported tile IDs
terrain edit records
modified region IDs
local density zone edits
player-built structures
placed props/resources
```

For surface edits:

```text
save TerrainEdit records by 2D region
```

For voxel/density zones:

```text
save modified density/material deltas by 3D region
```

The original world remains reconstructable.

---

## 15. Cache and Dirty Region Rules

Every edit should mark affected regions dirty.

Surface edit dirtying:

```text
2D chunk bounds affected by edit radius
```

Volume edit dirtying:

```text
3D density chunks affected by edit radius
```

Dirty systems may include:

```text
visual mesh
near collision
navigation
foliage placement
river decals/materials
biome material hints
sound/footstep surface hints
```

Do not rebuild the whole world after an edit.

---

## 16. Implementation Guardrails

### Do now

```text
keep sample_height simple
keep terrain chunks working
keep DEM/procedural/world facts separate from mesh chunks
store coordinates in world space
keep edits conceptually separate from base terrain
```

### Do later

```text
add TerrainSurfaceSample
add WorldFactsSample
add TerrainEditStore
add surface deformation
add cave planner
add cave mesh backend
add local density pockets only if needed
```

### Avoid now

```text
full voxel renderer
runtime CSG terrain
mesh chunks owning biome/hydrology/cave rules
saving generated base terrain
making caves block the terrain MVP
making spell deformation require a voxel system
```

---

## 17. Optional Folder Additions

Do not add these folders until the main terrain system is stable.

Future additions may look like:

```text
res://worldgen_terrain/
│
├── edits/
│   ├── terrain_edit.gd
│   ├── terrain_edit_store.gd
│   ├── surface_edit_sampler.gd
│   └── edit_dirty_region_tracker.gd
│
├── caves/
│   ├── cave_planner.gd
│   ├── cave_graph.gd
│   ├── cave_node.gd
│   ├── cave_tunnel_mesher.gd
│   ├── cave_chamber_mesher.gd
│   └── cave_entrance_builder.gd
│
└── density/
    ├── terrain_density_provider.gd
    ├── density_chunk.gd
    ├── density_mesher.gd
    ├── density_material_store.gd
    └── local_density_zone.gd
```

These are optional tracks, not required for the initial eight-phase terrain plan.

---

## 18. Final Design Commitment

The current spec should remain height-terrain-first.

The future-proofing commitment is:

```text
Never make DEMs, biomes, rivers, erosion, caves, or edits depend directly on one terrain renderer.
```

Instead:

```text
world facts first
terrain backend second
```

With that rule, the project can start with fast infinite height terrain and still grow toward:

```text
surface deformation
mesh caves
local voxel pockets
full density terrain
```

without invalidating the original terrain roadmap.
