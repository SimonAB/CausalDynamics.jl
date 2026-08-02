## Registration status

CausalDynamics.jl is on the Julia **General** registry.

| Version | Status |
|---------|--------|
| **0.3.4** | On General ([JuliaRegistries/General#162687](https://github.com/JuliaRegistries/General/pull/162687), merged 2026-08-01) |
| **0.3.13** (`main`) | Ready to register — tag `v0.3.13`, then `@JuliaRegistrator register` |

Install: `Pkg.add("CausalDynamics")`. Requires Julia **1.12+**.

## Prerequisites (met)

1. **DAGMakie on General** — done (`Pkg.add("DAGMakie")`; current series is 0.1.x).
2. **CausalInference on General** — hard dep; local CDCS fork is optional for development.
3. **Core tests pass without DAGMakie** in default `[targets] test`.
4. **No `[sources]`** in `Project.toml` (path deps are CDCS-only).
5. **Weakdep `[compat]`** includes Associations, DAGMakie, DataFrames, GraphPPL,
   OrdinaryDiffEq, RxInfer.

## Ecosystem tracking

| Item | Status | Action |
|------|--------|--------|
| CausalDynamics on General | Done (`0.3.4`) | Register `0.3.13` from `main` when ready |
| CausalInference GraphMakie 0.6 compat | Open | [mschauer/CausalInference.jl#179](https://github.com/mschauer/CausalInference.jl/pull/179) — when merged, restore DAGMakie/CairoMakie to default `Pkg.test` target |
| DAGMakie on General | Done (`0.1.0`–`0.1.1`) | Newer DAGMakie blocked on registry GraphMakie tuple `node_size` (see CDCS notes / fork `4977033`) |
| `DAGMakieCausalDynamicsExt` | Deferred | Re-enable in DAGMakie `[extensions]` after a DAGMakie release that targets registry GraphMakie cleanly |

CI runs an **optional DAGMakie extension job** (develop from GitHub if needed).

## Register next version (`0.3.13`)

1. Confirm `Pkg.test` on a clean env (registry CausalInference only) — done for `main`
2. Tag `v0.3.13` on `main` and push
3. `@JuliaRegistrator register` on [issue #1](https://github.com/SimonAB/CausalDynamics.jl/issues/1) or the release commit
4. After AutoMerge: close or retitle issue #1; bump CDCS Manifest if desired

## Zenodo DOI

Deposit metadata is in `.zenodo.json` and `CITATION.cff`. Enable GitHub–Zenodo integration and create a release to mint a DOI; then run `julia --project=. --threads=auto scripts/update_package_zenodo_dois.jl` from the CDCS repo. See [packages/ZENODO.md](../ZENODO.md).

## Follow-ups

- Re-enable DAGMakie in default tests when CausalInference widens GraphMakie compat (#179)
- Register reverse extension `DAGMakieCausalDynamicsExt` (symmetric to `CausalDynamicsDAGMakieExt`) once DAGMakie can AutoMerge against registry GraphMakie
