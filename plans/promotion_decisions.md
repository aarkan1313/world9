# Kernel Promotion Decisions

Last updated: 2026-05-24

Final review target:

```text
D:/workflows/worldgen9/factory/catalog/promoted_kernel_catalog.json
D:/workflows/worldgen9/factory/catalog/promoted_review/promoted_heightfield_seed_v1_contact_sheet.png
```

## Decision

Promote a conservative first heightfield seed pack:

```text
36 kernels total
4 mountain
4 glacial
4 badlands
4 desert
4 karst
4 coast
4 grassland
4 rainforest
4 volcanic
```

Wetland and delta kernels are intentionally excluded from the first heightfield
seed. They remain in the library for later hydrology, wetness, floodplain, and
water-context work.

## Why Not Use All Accepted Kernels Yet

The accepted library means technically valid data:

```text
finite arrays
enough coverage
not flat
basic stats are sane
```

It does not mean:

```text
visually distinct
balanced by terrain family
free from water-mask dominance
free from projected-footprint artifacts
good as a heightfield-shaping kernel
```

The first runtime seed pack should be visually clean and balanced. The full
accepted catalog stays available as the larger library.

## Held Out

Held out from first heightfield shaping:

```text
wetland/delta family
uncategorized family
polar DEMs with projected-footprint risk
visually odd volcano/context patches
grassland or wetland-looking tiles dominated by flat/water masks
```

Specific manual rejects or holds are tracked in:

```text
D:/workflows/worldgen9/plans/visual_review_notes.md
```

## Next Review Pass

Review the promoted contact sheet and mark each tile:

```text
keep
replace
maybe
```

If a tile is replaced, pull the replacement from:

```text
D:/workflows/worldgen9/factory/catalog/kernel_shortlist_top_by_family.json
```

After review, the promoted catalog becomes the input for the Python infinite
heightfield prototype.
