## Registration checklist

CausalDynamics.jl **v0.3.4** is ready to submit to the Julia General registry.

## Prerequisites (met)

1. **DAGMakie on General** — weakdep UUID registered (`Pkg.add("DAGMakie")` resolves; prefer ≥ 0.1.1).
2. **CausalInference on General** — hard dep; local CDCS fork is optional for development.
3. **Core tests pass without DAGMakie** in default `[targets] test`.
4. **No `[sources]`** in `Project.toml` (path deps are CDCS-only).
5. **Weakdep `[compat]`** includes Associations, DAGMakie, DataFrames, GraphPPL,
   OrdinaryDiffEq, RxInfer.

## Ecosystem tracking

| Item | Status | Action |
|------|--------|--------|
| CausalDynamics General registration | Pending | Install [JuliaRegistrator](https://github.com/JuliaRegistries/Registrator.jl) on `SimonAB/CausalDynamics.jl`; comment `@JuliaRegistrator register` on [issue #1](https://github.com/SimonAB/CausalDynamics.jl/issues/1) after tagging `v0.3.4` |
| CausalInference GraphMakie 0.6 compat | Open | [mschauer/CausalInference.jl#179](https://github.com/mschauer/CausalInference.jl/pull/179) — when merged, restore DAGMakie/CairoMakie to default `Pkg.test` target |
| DAGMakie 0.1.1+ on General | Submitted / track | CDCS `scripts/update_dagmakie_from_registry.jl` drops path sources when ≥ 0.1.1 |
| `DAGMakieCausalDynamicsExt` | Deferred | Re-enable in DAGMakie `[extensions]` only after CausalDynamics AutoMerge |

CI runs an **optional DAGMakie extension job** (develop from GitHub if not on General).

## Pre-registration polish (2026-07-29)

- Package `Pkg.test` green (incl. Associations / RxInfer / SciML extras)
- All `examples/*.jl` run
- CDCS book `test/runtests.jl` green
- CausalTargeted `Pkg.test` green against this tree
- Docs workflow green

## Submit checklist

1. Confirm `Pkg.test` on a clean env (registry CausalInference only)
2. `[sources]` removed from `Project.toml`
3. Tag `v0.3.4` on `main` and push
4. `@JuliaRegistrator register` on issue #1 or the release commit
5. After AutoMerge: README `Pkg.add("CausalDynamics")`; bump CDCS Manifest; enable `DAGMakieCausalDynamicsExt` in a DAGMakie patch

## After AutoMerge

- Update README installation to `Pkg.add("CausalDynamics")`
- Re-enable DAGMakie in default tests when CausalInference widens GraphMakie compat (#179)
- Register reverse extension `DAGMakieCausalDynamicsExt` (symmetric to `CausalDynamicsDAGMakieExt`)
