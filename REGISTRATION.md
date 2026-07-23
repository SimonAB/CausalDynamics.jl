## Registration checklist

CausalDynamics.jl is ready to submit to the Julia General registry.

## Prerequisites (met)

1. **DAGMakie on General** — weakdep UUID registered (`Pkg.add("DAGMakie")` resolves; v0.1.0 on General, v0.1.1 submitted).
2. Local CDCS may still path-develop the **SimonAB fork** of CausalInference.jl. The package UUID matches General, so the published release depends on registered CausalInference; fork-only APIs are not required for core APIs.

## Submit checklist

1. Confirm `Pkg.add("DAGMakie")` works from General
2. `[sources]` removed from `Project.toml` (registry resolve only)
3. `DAGMakie` listed in `[extras]` (not default `[targets] test` until CausalInference widens GraphMakie compat)
4. Run `Pkg.test` and docs build on a clean env (registry CausalInference) — done (260 tests)
5. **Install [JuliaRegistrator](https://github.com/JuliaRegistries/Registrator.jl)** on `SimonAB/CausalDynamics.jl` if not already (it already replies on DAGMakie.jl), then `@JuliaRegistrator register` on [issue #1](https://github.com/SimonAB/CausalDynamics.jl/issues/1) or the registration commit
6. Upstream CausalInference fork deltas only when the CDCS stack is solid (see `packages/CausalInference.jl/FORK.md` in the book monorepo)

## After AutoMerge

- Update README installation to `Pkg.add("CausalDynamics")`
- Optionally tighten `[compat] DAGMakie` to `"0.1.1"` once that release is on General
