# WorldGen Addendum — Alternate Informant Sources

**Addendum ID:** WG-ADD-004  
**Status:** Optional / non-breaking  
**Created:** 2026-05-25  
**Target engine:** Godot 4.6+  
**Applies to:** Pre-cave terrain spec, deformation future-proofing addendum, future biome/hydrology tracks

---

## 0. Purpose

This addendum adds support for **alternate world informant sources** beyond normal Earth DEM heightmaps.

The current terrain spec should remain centered on:

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

This addendum does **not** replace that roadmap.

It simply expands the long-term data model so the generator can use sources like:

```text
Earth DEMs
bathymetry / ocean-floor data
planetary DEMs
brain scans / biological scans
star maps / astronomical catalogs
climate maps
vegetation maps
night-light maps
geology / soils / faults
vector networks such as rivers, roads, or settlements
```

The key shift is:

> Do not think only in terms of heightmaps. Think in terms of scalar fields, feature fields, and world informants.

---

## 1. Non-breaking rule

This addendum must not force changes to the early terrain implementation.

Early terrain can still use:

```gdscript
height = height_provider.sample_height(world_x, world_z)
```

Long-term world generation should move toward:

```gdscript
surface = world_provider.sample_surface(world_x, world_z)
facts = world_provider.sample_world_facts(world_x, world_z)
channel_value = informant_provider.sample_channel(channel_id, world_x, world_z)
```

The mesh builder should **not** directly know about MRI data, star maps, Gaia catalogs, bathymetry, climate data, or any source-specific format.

Correct flow:

```text
Raw data source
    ↓
Importer / normalizer
    ↓
Informant pack
    ↓
World facts provider
    ↓
Height provider / biome resolver / hydrology / cave planner
    ↓
Terrain renderer
```

Incorrect flow:

```text
Raw source image → terrain mesh builder
```

---

## 2. Core concept

A normal terrain heightmap is just this:

```text
x, z → value
```

Many other datasets can be converted into the same general form:

```text
x, z → scalar channel
```

or, for 3D data:

```text
x, y, z → scalar channel
```

Examples:

```text
DEM elevation          → height_m
bathymetry depth       → trench_strength / ridge_strength / height_m
MRI brightness         → organic_fold_strength
star density           → magic_density / macro_region_weight
NDVI vegetation index  → vegetation_density
precipitation          → moisture
night lights           → settlement_pressure
fault lines            → ridge_bias / canyon_bias / geothermal_bias
```

Not every source should become literal terrain height.

Better interpretation:

```text
Source data can become:
  height
  terrain kernel
  biome informant
  cave informant
  hydrology informant
  erosion informant
  settlement informant
  magic/resource field
  alienness/style field
```

---

## 3. Definitions

### 3.1 Informant source

An **Informant Source** is any external or generated data source that can influence world generation.

Examples:

```text
GeoTIFF DEM
bathymetry grid
planetary DEM
MRI/CT volume
star catalog
climate raster
vegetation index raster
land-cover map
geology map
vector river network
```

### 3.2 Informant pack

An **Informant Pack** is the normalized, game-ready version of a source.

It should contain:

```text
metadata
license / attribution info
source type
channels
tile pyramid
normalization rules
confidence map
feature tags
```

### 3.3 Channel

A **Channel** is one sampled field from an informant pack.

Examples:

```text
height_m
normalized_height
slope
ridge_strength
valley_strength
roughness
crater_density
organic_fold_strength
star_density
vegetation_density
moisture
temperature
snow_likelihood
settlement_pressure
alienness
cave_likelihood
```

### 3.4 Terrain kernel

A **Terrain Kernel** is an extracted pattern or feature from real data that can be reused procedurally.

Examples:

```text
volcanic crater kernel
bathymetric trench kernel
glacial valley kernel
brain-fold organic ridge kernel
Mars canyon kernel
lunar crater field kernel
```

### 3.5 World facts

**World Facts** are source-independent values used by terrain, biomes, hydrology, rivers, caves, erosion, and gameplay.

Examples:

```text
height_m
slope
aspect
curvature
wetness
flow_accumulation
river_distance
rockiness
soil_depth
diggable_depth
cave_likelihood
temperature
moisture
biome_weights
resource_likelihood
```

---

## 4. Source categories

### 4.1 Earth elevation sources

Primary use:

```text
realistic terrain
terrain kernels
valley/ridge extraction
erosion references
hydrology references
```

Examples:

```text
OpenTopography global datasets
USGS 3DEP
Copernicus DEM
SRTM / NASADEM
ALOS World 3D
ArcticDEM / REMA / EarthDEM
```

Recommended channels:

```text
height_m
normalized_height
slope
aspect
curvature
roughness
ridge_strength
valley_strength
drainage_candidate
source_confidence
```

Notes:

```text
DTM/bare-earth sources are better for terrain shape.
DSM/surface sources may include trees, buildings, and infrastructure.
High-resolution DEMs can become detail/residual layers instead of direct base terrain.
```

---

### 4.2 Bathymetry and global relief

Primary use:

```text
ocean worlds
alien terrain
deep trench terrain
underworld/cave shape inspiration
large canyon and ridge kernels
```

Examples:

```text
GEBCO
NOAA ETOPO
SRTM15+
```

Recommended channels:

```text
depth_m
inverted_height_m
trench_strength
seamount_strength
ridge_strength
abyssal_plain_score
continental_shelf_score
roughness
```

Good uses:

```text
turn ocean trenches into alien canyons
turn seamount chains into ridge systems
use abyssal plains as strange flat basins
use continental shelves as biome/elevation transitions
```

Do not assume bathymetry should always be rendered underwater. It can be used as an abstract terrain pattern source.

---

### 4.3 Planetary DEMs and maps

Primary use:

```text
alien worlds
crater fields
barren highlands
impact basins
volcanic terrain
non-Earth terrain kernels
```

Examples:

```text
Moon LOLA DEMs
Mars MOLA DEMs
Mars HRSC/MOLA blended DEMs
USGS Astrogeology planetary maps
NASA PDS planetary datasets
```

Recommended channels:

```text
height_m
normalized_height
crater_density
crater_rim_strength
basin_strength
lava_plain_score
canyon_strength
terrain_age_hint
impact_scarring
alienness
```

Good uses:

```text
Moon DEM → cratered wasteland
Mars DEM → canyon/desert/volcanic alien regions
Venus/Mercury-style maps → harsh alien landforms if available
planetary shaded relief → style guide, not direct height
```

---

### 4.4 Medical, biological, and organic scan sources

Primary use:

```text
organic terrain kernels
alien caves
biome pattern masks
weird ridge/valley structures
biological dungeon spaces
```

Examples:

```text
OpenNeuro datasets
OASIS brain datasets
other open/de-identified MRI or CT datasets
```

Recommended channels:

```text
intensity
fold_strength
organic_ridge_strength
organic_valley_strength
branching_score
void_likelihood
cave_tunnel_bias
alienness
```

Important rule:

```text
Do not use random meme images or private medical scans as source data.
Use open, de-identified datasets with clear reuse terms.
```

Processing options:

```text
2D slice → scalar field
maximum intensity projection → organic map
surface extraction → cave/interior mesh inspiration
edge detection → ridge/valley kernel
segmentation mask → chamber/tunnel probability
3D volume → future density/cave source
```

This category should usually influence **style, caves, or kernels**, not normal realistic terrain height.

---

### 4.5 Star maps and astronomical catalogs

Primary use:

```text
macro world layout
skybox generation
magic/resource density
region identity
faction territory seeds
cosmic/alien biome influence
```

Examples:

```text
ESA Gaia catalog/data releases
NASA Exoplanet Archive
sky survey imagery
nebula imagery
constellation graphs
```

Recommended channels:

```text
star_density
bright_star_influence
nebula_intensity
constellation_line_strength
cosmic_region_id
magic_density
resource_density
alienness
```

Good uses:

```text
star density → magic/resource density
constellation graph → road/leyline/faction network
nebula brightness → fog/color/atmosphere mask
exoplanet parameters → world preset seeds
```

Do not use star catalogs as literal terrain height by default. They are better as macro influence fields.

---

### 4.6 Climate, vegetation, land cover, and night-light sources

Primary use:

```text
biome planning
moisture and temperature fields
vegetation density
settlement pressure
snow/desert/forest masks
```

Examples:

```text
NASA Earthdata
MODIS NDVI/EVI
WorldClim
ERA5 climate reanalysis
NASA Black Marble night lights
land-cover datasets
snow-cover datasets
```

Recommended channels:

```text
moisture
precipitation
temperature
wind_strength
wind_direction
vegetation_density
forest_likelihood
grassland_likelihood
desert_likelihood
snow_likelihood
settlement_pressure
human_activity
```

Good uses:

```text
NDVI → vegetation density
precipitation → moisture
temperature → biome temperature
night lights → settlement pressure
wind → dune/erosion direction
land cover → biome training/reference hints
```

These sources should mostly feed the **biome/world-facts layer**, not terrain height.

---

### 4.7 Geology, soils, faults, and material maps

Primary use:

```text
rockiness
soil depth
diggable depth
ore/resource placement
cave likelihood
terrain material rules
volcanic/geothermal regions
```

Examples:

```text
geologic maps
soil maps
fault-line maps
plate boundary maps
mineral occurrence maps
landslide susceptibility maps
```

Recommended channels:

```text
rock_type_id
soil_depth
rockiness
diggable_depth
bedrock_height_bias
fault_strength
cave_likelihood
ore_likelihood
geothermal_likelihood
landslide_likelihood
```

Good uses:

```text
limestone-like regions → more caves/sinkholes
faults → valleys, hot springs, volcanic zones, cliff lines
soil depth → deformable top-layer thickness
rock type → material/ore generation
landslide score → erosion/deformation events
```

---

### 4.8 Vector and network sources

Primary use:

```text
rivers
roads
settlements
trade routes
faction boundaries
coastlines
fault lines
cave graph seeds
```

Examples:

```text
river networks
road networks
settlement points
administrative boundaries
coastlines
fault polylines
trail maps
```

Recommended converted channels:

```text
distance_to_river
distance_to_road
settlement_pressure
network_density
crossing_score
coast_distance
fault_distance
route_importance
```

Vector data should be rasterized into channels when it needs to participate in terrain, biome, or decoration sampling.

---

## 5. Source-to-use matrix

| Source type | Direct height? | Terrain kernel? | Biome facts? | Cave facts? | Macro layout? | Notes |
|---|---:|---:|---:|---:|---:|---|
| Earth DEM / DTM | Yes | Yes | Some | Some | Some | Best realistic terrain source |
| DSM surface model | Sometimes | Yes | Some | Some | Some | May include trees/buildings |
| Bathymetry | Sometimes | Yes | Some | Yes | Yes | Great alien/canyon source |
| Planetary DEM | Yes | Yes | Some | Some | Yes | Great for alien terrain |
| MRI / CT | Rarely | Yes | Some | Yes | Some | Best as organic/cave kernel |
| Star catalog | Rarely | Rarely | Some | Rarely | Yes | Best as macro influence field |
| Climate raster | No | No | Yes | Some | Yes | Feeds biomes/moisture/temp |
| NDVI / vegetation | No | No | Yes | Rarely | Some | Feeds foliage density |
| Night lights | No | No | Some | No | Yes | Settlement/human activity hints |
| Geology / soils | Rarely | Yes | Yes | Yes | Some | Materials, caves, deformation |
| Vector roads/rivers | No | No | Yes | Some | Yes | Rasterize into distance fields |

---

## 6. Import pipeline

Every informant source should pass through a consistent import pipeline.

```text
1. Choose source
2. Check license / reuse terms
3. Record metadata
4. Convert projection/domain if needed
5. Normalize units
6. Convert to one or more channels
7. Build tile pyramid
8. Build confidence map
9. Extract features/kernels
10. Save informant pack
11. Preview in Godot debug view
12. Allow world provider to consume channels
```

### 6.1 Required metadata

Every imported source should store:

```text
source_id
source_name
source_type
source_url
license_name
license_url
required_attribution
import_date
source_version_or_date
original_format
original_units
normalized_units
coordinate_reference_system_or_domain
bounds_or_domain_mapping
resolution_or_sample_spacing
no_data_value
confidence_strategy
channels
notes
```

### 6.2 Normalization

The importer should normalize values into explicit units or 0..1 ranges.

Examples:

```text
height_m: real meters
slope: 0..1 or radians, but choose one and store it
moisture: 0..1
temperature_c: Celsius
vegetation_density: 0..1
star_density: 0..1 after log scaling
organic_fold_strength: 0..1
crater_density: 0..1
```

Do not silently mix unrelated units.

Bad:

```text
height = dem_height + mri_pixel_brightness + star_count
```

Better:

```text
organic_influence = organic_fold_strength * organic_region_weight
magic_density = log_scaled_star_density
height = base_height + terrain_kernel_detail * kernel_weight
```

---

## 7. Runtime architecture

### 7.1 New layer

Add a new upstream layer:

```text
WorldInformantProvider
```

Suggested architecture:

```text
WorldGenCore
 ├── TerrainHeightProvider
 ├── WorldFactsProvider
 ├── BiomeFactsProvider
 ├── HydrologyProvider
 ├── CavePlanner
 ├── TerrainEditStore
 └── WorldInformantProvider
      ├── EarthDEMInformants
      ├── BathymetryInformants
      ├── PlanetaryInformants
      ├── OrganicScanInformants
      ├── AstronomyInformants
      ├── ClimateInformants
      ├── GeologyInformants
      └── VectorInformants
```

The terrain renderer still only sees the final terrain sample.

---

## 8. GDScript interface sketch

This is not required for Phase 1. It is a future-facing interface target.

```gdscript
class_name InformantChannel
extends Resource

@export var channel_id: StringName
@export var display_name: String
@export var units: String
@export var min_value: float
@export var max_value: float
@export var default_value: float = 0.0
@export var is_normalized: bool = true
```

```gdscript
class_name InformantPack
extends Resource

@export var source_id: StringName
@export var source_name: String
@export var source_type: StringName
@export var source_url: String
@export var license_name: String
@export var license_url: String
@export var required_attribution: String
@export var channels: Array[InformantChannel]
@export var tags: PackedStringArray

func has_channel(channel_id: StringName) -> bool:
    return false

func sample_channel(channel_id: StringName, world_x: float, world_z: float) -> float:
    return 0.0

func sample_confidence(channel_id: StringName, world_x: float, world_z: float) -> float:
    return 0.0
```

```gdscript
class_name WorldInformantProvider
extends RefCounted

var packs: Array[InformantPack] = []

func sample_channel(channel_id: StringName, world_x: float, world_z: float) -> float:
    var value := 0.0
    var total_weight := 0.0

    for pack in packs:
        if not pack.has_channel(channel_id):
            continue

        var confidence := pack.sample_confidence(channel_id, world_x, world_z)
        value += pack.sample_channel(channel_id, world_x, world_z) * confidence
        total_weight += confidence

    if total_weight <= 0.0:
        return 0.0

    return value / total_weight
```

```gdscript
class_name WorldFactsSample
extends RefCounted

var height_m: float = 0.0
var slope: float = 0.0
var roughness: float = 0.0
var wetness: float = 0.0
var temperature_c: float = 15.0
var moisture: float = 0.0
var vegetation_density: float = 0.0
var cave_likelihood: float = 0.0
var rockiness: float = 0.0
var soil_depth: float = 0.0
var diggable_depth: float = 0.0
var alienness: float = 0.0
var settlement_pressure: float = 0.0
```

---

## 9. Suggested file structure

```text
res://worldgen/
  informants/
    informant_channel.gd
    informant_pack.gd
    world_informant_provider.gd
    importers/
      raster_informant_importer.gd
      geotiff_informant_importer.gd
      volume_informant_importer.gd
      point_catalog_informant_importer.gd
      vector_informant_importer.gd
    processors/
      normalize_channel.gd
      build_tile_pyramid.gd
      extract_ridges_valleys.gd
      extract_crater_density.gd
      extract_organic_folds.gd
      rasterize_vector_distance_field.gd
    debug/
      informant_debug_view.gd
      informant_debug_material.tres
```

Early implementation can start much smaller:

```text
informant_channel.gd
informant_pack.gd
world_informant_provider.gd
simple_grayscale_png_informant_importer.gd
informant_debug_view.gd
```

---

## 10. Minimal implementation target

The first version should be tiny.

### MVP goal

Import a simple grayscale image or raster and sample it as a named channel.

Example:

```text
source image: moon_crater_density.png
channel: crater_density
range: 0..1
usage: debug color only
```

### MVP steps

```text
1. Create InformantChannel resource.
2. Create InformantPack resource.
3. Import one grayscale PNG as one channel.
4. Map it to a test world region.
5. Sample it by world_x/world_z.
6. Show it as a debug overlay on terrain.
7. Confirm terrain renderer does not know where the value came from.
```

### MVP success criteria

```text
Can load at least one alternate informant.
Can sample a named channel at world coordinates.
Can show the channel visually.
Can enable/disable the informant without breaking terrain.
Can keep the original height provider working unchanged.
```

---

## 11. Integration with the existing terrain roadmap

This addendum should be integrated gently.

```text
Phase 1 — Infinite terrain chunks
  No alternate informants needed.

Phase 2 — Clean height provider
  Reserve naming for future world facts provider.

Phase 3 — DEM sampling
  DEM importer becomes the first real informant importer.

Phase 4 — DEM resolution blending
  Informant confidence maps become useful.

Phase 5 — Procedural infinite fill
  Terrain kernels from DEMs, bathymetry, and planetary DEMs can influence procedural regions.

Phase 6 — Hydrology hints
  Climate, bathymetry, geology, and vector data can become moisture/flow/cave hints.

Phase 7 — Rivers
  Vector/raster river references can become validation/reference fields.

Phase 8 — Erosion
  DEM, bathymetry, and planetary terrain can provide erosion-shape references.
```

Optional visual insert:

```text
Phase 2.5 / 3.5 — Informant Debug Slice
  Import one non-DEM source and display it as a debug channel.
```

---

## 12. How alternate informants help major systems

### 12.1 Terrain

Useful inputs:

```text
DEM height
planetary height
bathymetry ridges/trenches
roughness maps
crater fields
fault lines
```

Use cases:

```text
alien terrain
region-specific landform styles
ridge/valley kernels
large-scale macro shape references
```

### 12.2 Biomes

Useful inputs:

```text
moisture
precipitation
temperature
NDVI/vegetation density
land cover
snow cover
wind
night lights / human activity
```

Use cases:

```text
forest density
wetlands
deserts
snow/alpine zones
settlement pressure
farmland or disturbed land
```

### 12.3 Hydrology and rivers

Useful inputs:

```text
DEM-derived flow accumulation
climate precipitation
existing river vector references
bathymetry basin shapes
geology/fault maps
soil permeability
```

Use cases:

```text
better river placement
springs
sinkholes
wet caves
floodplains
drainage basin style
```

### 12.4 Caves

Useful inputs:

```text
geology/rock type
fault lines
soil depth
bathymetric trench kernels
organic scan kernels
hydrology wetness
karst-like region masks
```

Use cases:

```text
cave entrance placement
branching tunnel style
chamber density
underground river likelihood
organic cave variants
```

### 12.5 Deformable land

Useful inputs:

```text
soil depth
rockiness
diggable depth
bedrock height
geology type
moisture
root density / vegetation density
```

Use cases:

```text
spell craters
trenches
soft mud deformation
rocky areas resisting deformation
sand/dune displacement
bedrock limit for digging
```

### 12.6 Settlements, roads, and gameplay

Useful inputs:

```text
night lights
slope
water access
biome
resource likelihood
road/vector networks
coast distance
```

Use cases:

```text
settlement placement
road corridors
resource distribution
quest region identity
faction territory
```

---

## 13. Visual debug modes

Every informant channel should be viewable.

Recommended debug modes:

```text
height_m
normalized_height
source_confidence
ridge_strength
valley_strength
roughness
crater_density
organic_fold_strength
star_density
moisture
temperature
vegetation_density
settlement_pressure
rockiness
diggable_depth
cave_likelihood
alienness
```

Debug display should answer:

```text
What source is active?
What channel am I seeing?
What are the min/max values?
Is confidence low or high?
Is the source tiled correctly?
Are there seams?
Is it affecting terrain, biomes, caves, or nothing yet?
```

---

## 14. Recommended experiments

### Experiment A — Planetary crater field

```text
Source: Moon or Mars DEM
Extract: crater_density, rim_strength, roughness
Use: alien terrain region
Goal: cratered landscape debug demo
```

### Experiment B — Bathymetry as alien canyon terrain

```text
Source: GEBCO or ETOPO region
Extract: trench_strength, ridge_strength, abyssal_plain_score
Use: non-ocean alien terrain kernel
Goal: deep ridge/canyon terrain style
```

### Experiment C — Brain scan organic cave kernel

```text
Source: open/de-identified MRI dataset
Extract: fold_strength, branching_score, organic_ridge_strength
Use: cave/chamber style, not direct surface height
Goal: organic cave layout or alien biome mask
```

### Experiment D — Star density as macro world field

```text
Source: star catalog or sky-density raster
Extract: star_density, bright_star_influence
Use: magic/resource density or faction territory seed
Goal: debug overlay on world map
```

### Experiment E — Climate/vegetation biome reference

```text
Source: WorldClim + MODIS NDVI/EVI
Extract: moisture, temperature, vegetation_density
Use: biome resolver reference channels
Goal: simple forest/desert/snow debug map
```

---

## 15. Anti-goals

Do not do these early:

```text
Do not build a huge ML pipeline first.
Do not make every source directly modify terrain height.
Do not let the mesh builder parse source data.
Do not use private or unclear-license medical data.
Do not mix raw units without metadata.
Do not depend on one specific data source for core terrain.
Do not block the original 8-phase terrain roadmap.
```

This addendum is about optional inputs, not scope explosion.

---

## 16. Design rules

1. **Terrain remains provider-driven.**  
   The terrain renderer asks for final terrain facts, not raw source data.

2. **Sources become channels.**  
   All external data should become named, normalized, documented channels.

3. **Channels have confidence.**  
   Every sampled channel should be able to report confidence or coverage.

4. **Not all channels are height.**  
   Many channels are better for biomes, caves, resources, or style.

5. **Metadata is mandatory.**  
   Source, license, date/version, units, and normalization rules must travel with the data.

6. **Visual debug comes first.**  
   Before using a channel in gameplay, make it visible as a debug overlay.

7. **No source-specific logic in renderers.**  
   Mesh generation should not care if a value came from Earth DEMs, Mars, MRI, or star maps.

8. **Optional means optional.**  
   Disabling all alternate informants should leave the original terrain system working.

---

## 17. Future informant pack example

```yaml
source_id: mars_mola_hrsc_v2_example
source_name: Mars MOLA/HRSC Blended DEM Example Region
source_type: planetary_dem
source_url: https://astrogeology.usgs.gov/
license_name: source-specific
license_url: TBD
required_attribution: TBD
import_date: 2026-05-25
original_format: GeoTIFF
original_units: meters
normalized_units: meters_and_0_to_1_channels
crs_or_domain: planetary_lat_lon
world_mapping: local_projected_region
resolution_m: 200
no_data_value: TBD
channels:
  - height_m
  - normalized_height
  - slope
  - roughness
  - crater_density
  - alienness
confidence_strategy: source_coverage_and_no_data_mask
tags:
  - planetary
  - mars
  - alien
  - cratered
  - dry
notes: Used as an informant/kernel source, not necessarily literal Mars terrain.
```

---

## 18. Starter reference sources

These are not mandatory dependencies. They are examples of source families worth testing.

### Earth elevation

```text
OpenTopography Developers / Global Datasets API
https://opentopography.org/developers

USGS 3D Elevation Program
https://www.usgs.gov/3d-elevation-program

Copernicus DEM information
https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM
```

### Bathymetry / global relief

```text
GEBCO
https://www.gebco.net/

NOAA ETOPO Global Relief Model
https://www.ncei.noaa.gov/products/etopo-global-relief-model
```

### Planetary DEMs

```text
USGS Astrogeology Mars MOLA / HRSC products
https://astrogeology.usgs.gov/

NASA PDS Geosciences Node — LRO LOLA
https://pds-geosciences.wustl.edu/missions/lro/lola.htm
```

### Medical / biological scans

```text
OpenNeuro
https://openneuro.org/

OASIS Brains
https://sites.wustl.edu/oasisbrains/
```

### Astronomy / star maps

```text
ESA Gaia DR3
https://www.cosmos.esa.int/web/gaia/dr3

NASA Exoplanet Archive
https://exoplanetarchive.ipac.caltech.edu/
```

### Climate, vegetation, night lights

```text
WorldClim
https://www.worldclim.org/

NASA MODIS Vegetation Index Products
https://modis.gsfc.nasa.gov/data/dataprod/mod13.php

NASA Black Marble
https://www.earthdata.nasa.gov/data/projects/black-marble
```

---

## 19. Final recommendation

Add this as an optional long-term track:

```text
Optional Track — Alternate Informant Sources
```

Do not implement it before the basic terrain system works.

The first real implementation should be simple:

```text
one grayscale source
one channel
one debug overlay
no gameplay dependency
```

Long-term, this track lets WorldGen use real Earth data, ocean-floor data, planetary data, biological forms, star maps, climate maps, and human/geologic maps as modular world-generation inputs.

The main architecture rule remains unchanged:

> World facts first. Terrain backend second. Source-specific data never leaks into the renderer.
