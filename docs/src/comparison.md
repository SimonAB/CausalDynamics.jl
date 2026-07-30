# How CausalDynamics compares

CausalDynamics.jl owns one niche: **identify → intervene → shared-`U` counterfactual
trajectories** for discrete-time structural models. It composes with, rather than
competes against, the packages below.

| Need | Reach for | Why |
|------|-----------|-----|
| Learn a DAG from data (PC, OCE) | [Associations.jl](https://juliadynamics.github.io/Associations.jl/stable/) | Optional weakdep bridge (`infer_pc_graph`, `infer_oce_temporal_spec`); see [Associations integration](ASSOCIATIONS_INTEGRATION.md) |
| Learn a DAG from data (legacy Julia PC) | [CausalInference.jl](https://github.com/mschauer/CausalInference.jl) | `pcalg`; we use CausalInference for d-separation and backdoor primitives |
| Solve ODEs / SDEs / UDEs | [SciML](https://sciml.ai/), [UniversalDiffEq.jl](https://github.com/Jack-H-Buckner/UniversalDiffEq.jl) | We supply structure and `do(·)` semantics, not integrators — see [SciML recipes](SCIML_INTEGRATION.md) |
| Doubly robust effect estimation on tables | [TMLE.jl](https://github.com/TARGENE/TMLE.jl) | We identify the adjustment set; TMLE estimates ([integration](integration.md)) |
| Scalable Bayesian inference | [RxInfer.jl](https://github.com/ReactiveBayes/RxInfer.jl) | Variational backdoor head is a weakdep extension |
| Tabular causal simulation / estimation | [CausalTables.jl](https://github.com/salbalkus/CausalTables.jl) | Table-centric; we are trajectory-centric over occasions `t = 1:T` |
| Python causal workflows | [DoWhy](https://github.com/py-why/dowhy) | Broad four-step workflow; no discrete-time trajectory counterfactuals with shared `U` |

## What is distinctive here

- **Trajectories, not single outcomes** — [`simulate`](@ref) returns a
  [`CDMTrajectory`](@ref) with the realised exogenous draws retained
- **Shared-`U` counterfactual paths** — [`counterfactual`](@ref) replays the same
  creative advance under a different intervention, giving unit-level alternative
  histories rather than population contrasts
- **Time-indexed identification** — [`unroll_temporal_dag`](@ref) turns a lag
  specification into a static DAG so ordinary backdoor logic covers lagged confounding
- **Soft interventions** — [`Policy`](@ref) supports treatment rules that react to state
- **Lean core** — hard dependencies are `Graphs` and `CausalInference` only

## What is deliberately absent

Full causal discovery implementations, differential-equation solvers, and full symbolic do-calculus.
Discovery runs in Associations.jl; identification and trajectories stay here. See [Scope](scope.md).

The [CDCS book](https://simonab.github.io/causal-dynamics-book/) is the long-form
narrative companion for these APIs.
