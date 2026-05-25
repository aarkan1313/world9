# Infinite Heightfield Prototype

Standalone Python prototype for testing DEM-kernel terrain blending before any
Godot runtime work.

Run:

```powershell
python tools/heightfield_prototype/infinite_heightfield.py
```

Runtime-pack verification:

```powershell
python tools/heightfield_prototype/verify_runtime_pack.py --catalog factory/runtime/kernel_pack_v1.json --out factory/runtime/kernel_pack_verification.json
python tools/heightfield_prototype/export_hash_reference.py --out factory/runtime/hash_reference/hash_reference.json
python tools/heightfield_prototype/sample_terrain_reference.py --catalog factory/runtime/kernel_pack_v1.json --out factory/runtime/terrain_sample_reference.json
python tools/heightfield_prototype/export_provider_decisions.py --catalog factory/runtime/kernel_pack_v1.json --out factory/runtime/provider_decisions/provider_decisions_reference.json
python tools/heightfield_prototype/export_chunk_reference.py --catalog factory/runtime/kernel_pack_v1.json --out-dir factory/runtime/chunk_reference --vertices-per-side 129
python tools/heightfield_prototype/export_mesh_reference.py --chunk-dir factory/runtime/chunk_reference --out-dir factory/runtime/mesh_reference
python tools/heightfield_prototype/simulate_streamer_reference.py --out-dir factory/runtime/streamer_reference
python tools/heightfield_prototype/simulate_streamer_reference.py --out-dir factory/runtime/streamer_reference_fifo --queue-policy fifo
python tools/heightfield_prototype/estimate_runtime_budget.py --streamer factory/runtime/streamer_reference/streamer_reference.json --out factory/runtime/runtime_budget/runtime_budget.json
python tools/heightfield_prototype/analyze_region_grammar.py --catalog factory/runtime/kernel_pack_v1.json --out-dir factory/runtime/region_grammar
python tools/heightfield_prototype/analyze_infinite_travel.py --catalog factory/runtime/kernel_pack_v1.json --out-dir factory/runtime/infinite_travel
python tools/heightfield_prototype/build_seed_comparison.py --catalog factory/runtime/kernel_pack_v1.json --out-dir prototypes/seed_compare_runtime_v7_balanced
python tools/heightfield_prototype/validate_runtime_readiness.py --out factory/runtime/runtime_readiness_report.json
python tools/heightfield_prototype/lock_runtime_artifacts.py --out factory/runtime/runtime_artifact_manifest.json
python tools/heightfield_prototype/lock_runtime_artifacts.py --out factory/runtime/runtime_artifact_manifest.json --verify
python tools/heightfield_prototype/runtime_release_gate.py
```

Inputs, in priority order:

```text
factory/reviews/user_shortlist_kernel_catalog.json
factory/catalog/promoted_kernel_catalog.json
factory/runtime/kernel_pack_v1.json when passed with --catalog
```

Outputs:

```text
prototypes/infinite_heightfield/
factory/runtime/chunk_reference/
factory/runtime/mesh_reference/
factory/runtime/streamer_reference/
factory/runtime/streamer_reference_fifo/
factory/runtime/runtime_budget/
factory/runtime/region_grammar/
factory/runtime/infinite_travel/
factory/runtime/provider_decisions/
factory/runtime/hash_reference/
factory/runtime/runtime_readiness_report.json
factory/runtime/runtime_artifact_manifest.json
prototypes/seed_compare_runtime_v7_balanced/
```

This prototype is intentionally preview-oriented. It is not the final runtime
terrain system.

Important runtime rule:

```text
sample_height_layers must not subtract the mean of the requested grid
```

Per-grid normalization makes pretty previews but breaks chunk seams. The current
sampler keeps world-space heights stable and the runtime verifier checks full
neighboring chunk edges, not only isolated matching coordinates.

Current visual tuning broadens DEM kernel sampling to about `2.20x` to `3.20x`
the region size. That keeps recognizable DEM landform character while reducing
the harsh, noisy hillshade produced by tighter sampling.

The current region grammar groups regions into `4 x 4` provinces. Provinces
create coherent large-area style, while each region still receives deterministic
kernel transforms so the result does not become a visible stamp repeat.

`provider_decisions_reference.json` is the low-level parity fixture for future
ports. Match its region, province, corner weight, kernel, and transform
decisions before comparing mesh output.

`hash_reference.json` comes before provider decisions. If `stable_hash`,
`hash_grid`, `value_noise`, or `fbm` differ in a port, all higher-level
deterministic choices are suspect.

`runtime_readiness_report.json` is the aggregate gate. It checks that all
runtime references are present, passing, and mutually consistent with the
current `129 x 129` / 2048m / province-based contract. It also checks the
long-distance travel probe so basic infinite variety is not judged only from a
single local preview.

`runtime_artifact_manifest.json` is the byte-level lockfile for the current
reference set. It hashes the runtime JSON reports, binary `.npy` arrays, runtime
preview/reference images, and the selected seed comparison sheet. Regenerate it
only after an intentional reference update. Use `--verify` before porting so
accidental fixture drift is caught before runtime debugging starts.

`runtime_release_gate.py` is the no-write pre-port gate. It recomputes readiness
in memory, verifies the stored readiness report has not drifted, and checks the
artifact manifest. Run it before starting Godot, C++, or GPU runtime work.
