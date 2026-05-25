# WorldGen9 DEM Factory

Standalone offline tools for turning the raw DEM cache into terrain-kernel
inputs. This folder intentionally has no Godot project dependency.

Raw DEM cache:

```text
D:/workflows/worldgen9/dems/
D:/workflows/worldgen9/dems/opentopo/
```

Generated factory outputs:

```text
D:/workflows/worldgen9/factory/catalog/
D:/workflows/worldgen9/factory/kernels/
```

Common commands:

```powershell
python tools/dem_factory/dem_factory.py catalog
python tools/dem_factory/dem_factory.py kernels --limit 12
python tools/dem_factory/dem_factory.py validate
python tools/dem_factory/dem_factory.py kernels --all --skip-existing
python tools/dem_factory/dem_factory.py validate --no-contact-sheet
python tools/dem_factory/detect_kernel_duplicates.py
python tools/dem_factory/infer_kernel_tags.py
python tools/dem_factory/build_expansion_review_queue.py
```

The catalog pass is cheap: it opens GeoTIFF headers and writes JSON summaries.
The kernel pass reads selected DEMs at a reduced analysis resolution, then writes
normalized height patches, residual patches, stats JSON, and preview PNGs.

Validation writes:

```text
factory/catalog/kernel_validation_report.json
factory/catalog/accepted_kernel_catalog.json
factory/catalog/review_kernel_catalog.json
```

Metadata cleanup writes:

```text
factory/catalog/kernel_duplicate_candidates.json
factory/catalog/kernel_inferred_tags.json
factory/catalog/accepted_kernel_catalog_tagged.json
factory/catalog/kernel_expansion_review_queue.json
factory/catalog/kernel_expansion_review_queue_catalog.json
factory/catalog/expansion_review/expansion_queue_contact_sheet.png
```

`kernel_inferred_tags.json` is conservative. It retains reviewed families,
adds geomorphic tags, and leaves uncertain coordinate-named kernels unresolved
instead of guessing a biome from weak evidence.

`kernel_expansion_review_queue_catalog.json` is not promoted. It is a visual
review queue for expanding the runtime pack after duplicate/manual-hold filters.

Use `accepted_kernel_catalog.json` for downstream terrain experiments. The
review catalog is retained for inspection rather than deleted.
