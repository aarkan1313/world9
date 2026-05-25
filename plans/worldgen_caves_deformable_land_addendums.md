# WorldGen Addendum — Caves + Optional Deformable Surface Layer

**Project:** Modular DEM-informed infinite terrain system  
**Engine target:** Godot 4.6  
**Status:** Planning addendum / handoff spec  
**Purpose:** Add support for caves and optional spell/digging terrain deformation without forcing the whole world into a full voxel engine.

---

## 0. Main Decision

Keep the main world as efficient height-based terrain:

```text
surface terrain = heightmap/chunk renderer
```

Add caves as a separate 3D mesh system:

```text
caves = streamed procedural interior meshes
```

Add deformable land as an optional shallow surface layer:

```text
deformable land = terrain edit stamps applied to the top layer
```

Do **not** convert the whole world to voxels just because caves and craters exist.

Recommended long-term structure:

```text
WorldGen
 ├── SurfaceTerrainSystem
 │    ├── DEM-informed terrain
 │    ├── procedural infinite fill
 │    ├── rivers / erosion later
 │    └── biome facts later
 │
 ├── CaveSystem
 │    ├── cave entrance placement
 │    ├── cave graph generation
 │    ├── cave mesh generation
 │    └── cave streaming / collision
 │
 └── DeformableSurfaceSystem
      ├── spell craters
      ├── shallow digging
      ├── trenches / road cuts
      ├── mounds / berms
      └── cave mouth cuts
```

---

# Addendum A — Procedural Cave System

## A1. Goal

Add real 3D caves while preserving the current height-based surface terrain plan.

The cave system should support:

```text
cave entrances
short tunnels
chambers
branching paths later
underground water later
cave biomes later
```

The cave system should **not** require full-world voxel terrain.

---

## A2. Non-Goals for First Cave Version

Do not build these in the first cave pass:

```text
full voxel mining
live cave destruction
complex cave biomes
underground rivers
ore simulation
AI navigation
large cave networks
multiplayer syncing
```

First target is only:

```text
surface entrance → tunnel → chamber → collision → stream/unstream
```

---

## A3. Core Cave Architecture

```text
CaveSystem
 ├── CavePlanner
 │    └── chooses where caves can exist
 │
 ├── CaveEntranceAdapter
 │    ├── applies terrain cut stamp
 │    ├── places cave mouth mesh
 │    └── hides surface/cave transition
 │
 ├── CaveGraphGenerator
 │    ├── entrance node
 │    ├── tunnel nodes
 │    ├── chamber nodes
 │    └── branch/dead-end nodes later
 │
 ├── CaveMeshBuilder
 │    ├── tube/ring tunnel meshes
 │    ├── chamber meshes
 │    ├── floor flattening
 │    └── wall/ceiling noise
 │
 ├── CaveCollisionBuilder
 │    └── collision for loaded cave sections
 │
 └── CaveStreamer
      ├── loads caves near player
      └── unloads caves far away
```

---

## A4. Cave Data Model

Minimum cave region data:

```gdscript
class_name CaveRegionData

var cave_id: String
var seed: int
var cave_type: String
var entrance_world_pos: Vector3
var entrance_facing: Vector3
var bounds: AABB
var graph_nodes: Array[CaveNodeData]
var graph_edges: Array[CaveEdgeData]
var entrance_cut: TerrainEdit
var loaded: bool
```

Minimum cave node data:

```gdscript
class_name CaveNodeData

var node_id: int
var world_pos: Vector3
var radius: float
var node_type: String # entrance, tunnel, chamber, branch, dead_end
```

Minimum cave edge data:

```gdscript
class_name CaveEdgeData

var from_node_id: int
var to_node_id: int
var tunnel_radius: float
var tunnel_width_noise: float
var tunnel_floor_flatness: float
```

---

## A5. Cave Placement Rules

Caves should be placed using world facts, not random chance only.

Future cave placement can consider:

```text
slope
local relief
cliff likelihood
valley position
river distance
rockiness
terrain kernel type
moisture
karst/limestone-like geology tag
volcanic terrain tag
coastal cliff tag
```

First pass can use simple rules:

```text
place cave entrance on moderate/steep slope
avoid perfectly flat plains
avoid water surface
avoid terrain chunks that are not loaded/generated yet
require enough underground space behind entrance
```

---

## A6. Cave Entrance Method

A cave entrance is a blend of three things:

```text
1. Surface terrain edit stamp
   cuts/lowers the terrain around the mouth

2. Cave mouth mesh
   rock arch, dark opening, cliff detail, roots, boulders

3. Interior cave mesh
   tunnel and chamber behind the surface terrain
```

Important rule:

```text
The surface terrain does not need to become a true volumetric cave.
The entrance hides the transition into a separate cave interior mesh.
```

Useful entrance tricks:

```text
bend the first tunnel segment
use darkness/fog inside the mouth
place rock meshes around the seam
use a short transition corridor
keep entrance geometry slightly overlapping terrain
```

---

## A7. Cave Mesh Generation

Recommended first method:

```text
graph path → rings along path → connect rings → distort walls/ceiling/floor
```

Tunnel generation:

```text
for each path point:
  create a ring of vertices
  flatten the lower part slightly for walkable floor
  raise/roughen upper vertices for natural ceiling
  add noise to wall radius
connect rings into triangle strips
```

Chamber generation:

```text
start from sphere/ellipsoid
flatten bottom
roughen walls
open tunnel connection holes
```

First cave material:

```text
plain gray rock material
normal-based lighting
no textures required
```

---

## A8. Cave Streaming

Caves should stream separately from surface terrain.

```text
if player near entrance or inside cave:
  load cave mesh + collision
else:
  unload cave mesh + collision
```

Surface terrain should know only this:

```text
this chunk contains a cave entrance marker
this chunk needs an entrance terrain cut stamp
```

Surface terrain should **not** own the full cave interior.

---

## A9. Cave MVP

Build this first:

```text
one cave entrance
one curved tunnel
one chamber
plain material
basic collision
stream/load near player
stream/unload far from player
```

Acceptance criteria:

```text
player can walk from outside terrain into cave
entrance does not obviously break the terrain mesh
cave has collision
cave can be regenerated from seed
cave can be placed by world coordinate
cave can be disabled without breaking surface terrain
```

---

## A10. Later Cave Features

Add later, not first:

```text
branching cave graphs
multi-level caves
sinkholes
underground streams
springs
wet caves
lava tubes
ice caves
sea caves
cave-specific props
cave biome resolver
ore/mineral placement
local destructible mining pockets
```

---

# Addendum B — Optional Deformable Surface Layer

## B1. Goal

Add optional terrain deformation for gameplay effects such as:

```text
spell craters
explosion marks
digging pits
trenches
road cuts
flattened build pads
raised earth walls
mounds / berms
river cuts
landslide reshaping
```

This should work without converting the full world to voxels.

---

## B2. Main Concept

The terrain keeps a normal height provider, but gains edit layers.

```text
final_height(x, z) =
    base_height(x, z)
  + natural_modifier_delta(x, z)
  + runtime_edit_delta(x, z)
```

Where:

```text
base_height = DEM + procedural terrain
natural_modifier_delta = rivers, erosion, road cuts, etc.
runtime_edit_delta = spells, digging, explosions, player edits
```

The edit layer is saved separately from the base world.

---

## B3. Diggable Top Layer

To get the “top layer of ground can be dug down” behavior, give terrain a diggable depth.

```text
surface_height = base_height(x, z)
diggable_depth = sample_diggable_depth(x, z)
bedrock_height = surface_height - diggable_depth
```

Runtime deformation can lower terrain until it reaches the local bedrock height:

```text
final_height = max(edited_height, bedrock_height)
```

Example values:

```text
soft soil:       3m - 10m diggable depth
sand/dunes:      5m - 20m diggable depth
rocky slope:     0m - 2m diggable depth
river bank:      2m - 8m diggable depth
magic terrain:   custom depth
```

This creates a limited-depth destructible surface shell.

---

## B4. What This Can and Cannot Do

Works well:

```text
craters
pits
trenches
ramps
flattening
raising/lowering ground
spell impact deformation
open-pit digging
surface mining
terrain scars
```

Does not naturally support:

```text
tunnels
overhangs
arches
floating terrain
sideways digging into mountains
underground bases carved from live terrain
```

For those, use:

```text
mesh-based caves
special cave interiors
optional local voxel/mining zones later
```

---

## B5. Terrain Edit Data Model

A terrain edit is a saved gameplay/world change.

```gdscript
class_name TerrainEdit

var edit_id: String
var edit_type: String # crater, lower, raise, flatten, trench, smooth, cave_mouth
var world_pos: Vector3
var radius: float
var strength: float
var falloff: float
var max_depth: float
var material_hint: String
var source_system: String # spell, explosion, river, road, cave, player
var permanent: bool
var created_at_tick: int
```

Optional extra fields:

```gdscript
var direction: Vector3      # useful for trenches/road cuts
var width: float            # useful for roads/trenches
var length: float           # useful for roads/trenches
var target_height: float    # useful for flatten/build pads
var noise_amount: float     # useful for natural craters
```

---

## B6. TerrainEditStore

The edit store is separate from the base terrain generator.

```text
TerrainEditStore
 ├── stores edits by region/chunk
 ├── returns edits affecting a chunk
 ├── samples height delta at x/z
 ├── saves modified regions only
 └── can bake old edits into region delta maps later
```

Suggested interface:

```gdscript
class_name TerrainEditStore

func add_edit(edit: TerrainEdit) -> void:
    pass

func get_edits_for_chunk(chunk_coord: Vector2i) -> Array[TerrainEdit]:
    pass

func sample_runtime_delta(world_x: float, world_z: float) -> float:
    pass

func sample_diggable_depth(world_x: float, world_z: float) -> float:
    pass
```

---

## B7. Spell Effect Flow

When a spell deforms land:

```text
1. Spell hits terrain
2. System creates TerrainEdit stamp
3. TerrainEditStore saves the edit
4. Affected chunks are marked dirty
5. Dirty chunks rebuild mesh data
6. Nearby collision is rebuilt
7. VFX/debris/scorch decals spawn
8. Edit persists through save/load if permanent
```

Example:

```gdscript
func apply_spell_crater(hit_pos: Vector3, radius: float, depth: float) -> void:
    var edit := TerrainEdit.new()
    edit.edit_type = "crater"
    edit.world_pos = hit_pos
    edit.radius = radius
    edit.strength = -abs(depth)
    edit.falloff = 1.0
    edit.source_system = "spell"
    edit.permanent = true

    terrain_edit_store.add_edit(edit)
    terrain_streamer.mark_chunks_dirty_around(hit_pos, radius)
```

---

## B8. Deformation Shape Examples

Crater:

```text
lowers center
soft falloff to edge
optional raised rim
optional scorch/debris decal
```

Flatten/build pad:

```text
moves terrain toward target height
soft feathered edges
useful for settlements or player building
```

Trench:

```text
long capsule-shaped cut
can follow a direction/path
useful for spells, roads, rivers, or battle damage
```

Raise/mound:

```text
adds height
soft falloff
can be used for earth magic or construction
```

Smooth:

```text
reduces local roughness
useful for roads or repair magic
```

---

## B9. Performance Rules

Do not rebuild the whole world after an edit.

Only rebuild:

```text
chunks touched by edit radius
neighbor chunks if edge vertices changed
collision only near player / active gameplay area
```

Use tiers:

```text
Tier 0: visual decal only, no mesh deformation
Tier 1: mesh deformation, no collision rebuild
Tier 2: mesh deformation + nearby collision rebuild
Tier 3: saved deformation + baked region delta maps
```

Suggested first implementation:

```text
Tier 1 first
Tier 2 after terrain collision is stable
```

---

## B10. Save Strategy

Do not save full terrain meshes.

Save only edits or baked region delta maps.

Early save format:

```text
region_id
list of TerrainEdit objects
```

Later optimized format:

```text
region_id
baked height delta texture/map
remaining live edits
last_bake_tick
```

This keeps the infinite world mostly procedural while preserving changed areas.

---

## B11. Deformable Surface MVP

Build this first:

```text
one crater edit type
runtime edit store
mark dirty chunks
rebuild affected chunk meshes
plain visual result
optional save/load of edits
no collision rebuild at first if needed
```

Acceptance criteria:

```text
spell impact creates visible crater
only affected chunks rebuild
terrain returns crater after save/load
crater respects max diggable depth
system can be disabled without affecting normal terrain
```

---

# Shared Integration Notes

## C1. One Edit Store Can Support Both Systems

The cave system and deformable land system can share the same terrain edit layer.

Examples:

```text
cave mouth cut = TerrainEdit type "cave_mouth"
spell crater = TerrainEdit type "crater"
road cut = TerrainEdit type "road_cut"
river carve = TerrainEdit type "river_cut"
```

This avoids separate systems fighting over the same surface height.

---

## C2. World Facts to Reserve Now

Add these fields to future terrain/world samples, even if they return defaults early:

```text
diggable_depth_m
bedrock_height_m
rockiness
soil_depth
cave_likelihood
cave_type_hint
cave_entrance_mask
surface_material_hint
underground_material_hint
```

These make caves and deformation easier to add later.

---

## C3. Roadmap Placement

Add to the main roadmap as optional tracks:

```text
5.5 Cave entrance reservation
6.5 Basic mesh cave system
8.5 Deformable surface layer MVP
9.0 Biome materials / foliage / props
10.0 Advanced cave networks
11.0 Advanced surface destruction
12.0 Optional local voxel/mining zones only if needed
```

Do not put these before the terrain chunk system and height provider are stable.

---

## C4. Final Recommendation

Use this long-term compromise:

```text
height-based infinite terrain
+
mesh-based procedural caves
+
limited-depth deformable surface layer
+
optional local voxel pockets only if mining becomes core gameplay
```

This preserves the DEM-informed terrain plan while still allowing:

```text
real caves
spell craters
digging pits
battlefield deformation
road/river cuts
surface destruction
future special mining zones
```
