## Registration status

CausalDynamics.jl is on the Julia **General** registry.

Install: `Pkg.add("CausalDynamics")`. Requires Julia **1.12+**.

| Version | Status |
|---------|--------|
| **0.3.4** | On General ([#162687](https://github.com/JuliaRegistries/General/pull/162687)) |
| **0.3.13** | On General ([#163196](https://github.com/JuliaRegistries/General/pull/163196)) |
| **0.3.14** | On General ([#163580](https://github.com/JuliaRegistries/General/pull/163580), merged 2026-08-05) |
| **0.3.15** | On General ([#163608](https://github.com/JuliaRegistries/General/pull/163608), merged 2026-08-05) |
| **0.3.16** | Open: [General#163619](https://github.com/JuliaRegistries/General/pull/163619) — tag `v0.3.16` at `2922acc` |

Local `main` is at **0.3.16**. Register **incrementally** (no version skips) so AutoMerge stays happy.

## Incremental register plan

| Step | Version | Commit | Feature |
|------|---------|--------|---------|
| 1 | `0.3.14` | `a8c0a30` | `find_path_mediators` |
| 2 | `0.3.15` | `7e36403` | `find_minimal_mediator_sets` |
| 3 | `0.3.16` | `2922acc` | `MinimalMediatorSets`, `intercepts_all_directed_paths` |

For each step:

1. Tag the feature commit (`git tag v0.3.N <sha>`), push the tag
2. Comment `@JuliaRegistrator register` on that commit (or a tracking issue referencing it)
3. Wait for the General PR to AutoMerge before registering the next version

## Prerequisites (met)

1. **DAGMakie on General** — done (`0.1.6`).
2. **CausalInference on General** — hard dep; local CDCS fork is optional for development.
3. **Core tests pass without DAGMakie** in default `[targets] test`.
4. **No `[sources]`** in `Project.toml` (path deps are CDCS-only).
5. **Weakdep `[compat]`** includes Associations, DAGMakie, DataFrames, GraphPPL,
   OrdinaryDiffEq, RxInfer.

## Ecosystem tracking

| Item | Status | Action |
|------|--------|--------|
| CausalDynamics on General | Tip `0.3.13`; registering through `0.3.16` | Follow incremental plan above |
| CausalInference GraphMakie 0.6 compat | Open | [mschauer/CausalInference.jl#179](https://github.com/mschauer/CausalInference.jl/pull/179) — when merged, restore DAGMakie/CairoMakie to default `Pkg.test` target |
| DAGMakie on General | Done (`0.1.6`) | Optional: restore tuple `node_size` after GraphMakie ships #259 |
| `DAGMakieCausalDynamicsExt` | Deferred | Re-enable in DAGMakie `[extensions]` after registry GraphMakie supports needed APIs |

CI runs an **optional DAGMakie extension job** (develop from GitHub if needed).

## Zenodo DOI

Deposit metadata is in `.zenodo.json` and `CITATION.cff`. Enable GitHub–Zenodo integration and create a release to mint a DOI; then run `julia --project=. --threads=auto scripts/update_package_zenodo_dois.jl` from the CDCS repo. See [packages/ZENODO.md](../ZENODO.md).

## Follow-ups

- Re-enable DAGMakie in default tests when CausalInference widens GraphMakie compat (#179)
- Register reverse extension `DAGMakieCausalDynamicsExt` (symmetric to `CausalDynamicsDAGMakieExt`) once DAGMakie can AutoMerge against registry GraphMakie
