# Visual Review Notes

Last updated: 2026-05-24

Manual review is now part of promotion. Numeric validation only means a kernel is
finite, non-flat, and covered enough. It does not guarantee the preview looks
like a clean top-down terrain patch.

## Rejected Or Quarantined

- `uncategorized__arcticdem10m_151_1000_63_0500_151_0000_63_1500`
  - Reason: screenshot review showed a rotated/framed-looking footprint rather
    than a clean top-down terrain patch.
- `wetland__cop30_bulk20260524_wetland_lena_delta_126_5_72_4`
  - Reason: screenshot review showed a delta/wetland preview dominated by dark
    water or flat channels, plus hard contextual edges. Keep it as water/delta
    context, but do not use it as a first terrain-shaping kernel.

## Review Carefully

- Volcanic family
  - Some volcano previews may look visually odd or may include bad crop/context.
  - Keep in draft promotion only until visually approved.
- Uncategorized family
  - Do not promote by default. These can be useful, but need family tags and
    visual review first.
- Polar DEMs / ArcticDEM / REMA
  - Watch for projected-footprint artifacts, no-data wedges, or views that do
    not read like clean top-down terrain kernels.
- Delta and wetland kernels
  - Watch for water masks or flat floodplain values dominating the patch. These
    can be useful later for hydrology/wetness context, but they should not drive
    initial heightfield character unless the dry terrain structure is readable.

## Promotion Rule

A promoted kernel should look good in the preview before it is used in runtime
terrain generation. Data-valid is not enough.
