## Registration checklist

CausalDynamics.jl is **not** yet submitted to the Julia General registry.

## Blockers

1. **DAGMakie on General** — weakdep UUID must be registered ([General#161837](https://github.com/JuliaRegistries/General/pull/161837)).
2. Local CDCS uses the **SimonAB fork** of CausalInference.jl (`packages/CausalInference.jl`) via path develop. The package UUID matches General, so registry submit can depend on registered CausalInference; fork-only APIs must not be required for the published release until upstreamed.

## After DAGMakie AutoMerge

1. Confirm `Pkg.add("DAGMakie")` works from General
2. Add `DAGMakie` to `[extras]` / `[targets] test` if not already
3. Run `Pkg.test` and docs build on a clean env
4. `@JuliaRegistrator register` on CausalDynamics
5. Upstream CausalInference fork deltas only when the CDCS stack is solid (see `packages/CausalInference.jl/FORK.md`)
