# RxInfer and GraphPPL integration

CausalDynamics.jl handles **identification** (backdoor adjustment sets, `prepare_for_rxinfer`). **GraphPPL.jl** specifies the observational generative head; **RxInfer.jl** runs variational message-passing inference.

## Nonlinear bistable state-space inference

The extension also provides `infer_bistable_state_space`, an explicit nonlinear
state-space model for the CDCS bistable benchmark. Its transition is represented
as a GraphPPL Delta factor:

```julia
μ[t] ~ bistable_transition(x[t], a[t], c[t], r[t], Δt) where {
    meta = DeltaMeta(method = Linearization())
}
```

RxInfer therefore performs Gaussian variational message passing with local
linearisation of the cubic drift; this is a nonlinear factor rather than a
pre-filtered observed proxy. The result exposes posterior state means and
variances through `state_means` and `state_variances`.

```julia
result = infer_bistable_state_space(y, a, c, r; iterations = 20)
result.state_means
result.state_variances
```

The method estimates latent states conditional on declared transition and noise
parameters. It does not by itself identify interventions, learn regime
mechanisms, or establish causal validity. Compare its posterior predictive and
interventional rollouts with the particle-filter reference before making policy
claims.

### Choosing an inference backend

Use the RxInfer backend when the transition and observation factors admit a
smooth local linearisation and fast repeated posterior updates matter. Use the
Laplace or assumed-density filter for a lightweight baseline, particle filtering
when the posterior is strongly non-Gaussian or multimodal, and Turing/NUTS when
joint parameter uncertainty or a richer likelihood is the primary target. The
certificate returned by `infer_bistable_state_space` records the backend,
factor type, linearisation method and numerical settings so these choices remain
auditable.

Load the extension:

```julia
using CausalDynamics
using RxInfer   # activates CausalDynamicsRxInfer
```

## Workflow

1. Build a DAG and attach tabular data (`DataFrame` or `NamedTuple`).
2. `prepare_for_rxinfer(g, X, Y; node_names=...)` — confounders + identifiability flag.
3. `infer_backdoor_effect(g, data, X, Y; ...)` — Frisch–Waugh partialing in Julia, then a conjugate GraphPPL head and VI for `τ`.

Confounders in the identified adjustment set are **partialled out** of outcome and treatment (`residualise_backdoor`) so the RxInfer head is a single conjugate slope `τ` on residualised `(y, x)`. A full multi-coefficient GraphPPL regression with latent `β` vectors is reserved for a later release (non-conjugate without custom initialisation).

**Hierarchical Bayesian heads** (random intercepts / partial pooling on residualised ATE) belong in **application** GraphPPL models or optional demos — not in CausalDynamics core and not as a substitute for [`identify`](@ref) or CausalTargeted MSM / LMTP. Generative nesting uses [`RandomEffectSpec`](@ref) / [`simulate_hierarchical_intercept_ate`](@ref); see [Hierarchical / nested units](hierarchy.md).

```julia
using CausalDynamics, RxInfer, Graphs, DataFrames, Random

g = DiGraph(3)
add_edge!(g, 1, 2)
add_edge!(g, 1, 3)
add_edge!(g, 2, 3)
names = Dict(1 => :Z, 2 => :X, 3 => :Y)
data = DataFrame(Z=randn(100), X=randn(100), Y=randn(100))

result = infer_backdoor_effect(g, data, 2, 3; node_names=names)
result.τ_mean   # posterior mean; do not use Statistics.mean(result.τ_posterior)
```

See `examples/rxinfer_backdoor.jl` in the package root.

## API

| Function | Role |
|----------|------|
| `has_rxinfer()` | Extension loaded? |
| `prepare_for_rxinfer` | Identification bridge (always available) |
| `residualise_backdoor` | Frisch–Waugh partialing of `(y, x)` on confounders |
| `backdoor_graphppl_model` | GraphPPL `@model` generator (`backdoor_gaussian_ate`) |
| `ppl_data_from_spec` | Tabular → residualised RxInfer data tuple |
| `infer_backdoor_effect` | Full identify + partial + infer pipeline |
| `posterior_mean_τ` | Scalar mean from `τ_posterior` marginals |

## Process vs Pearl naming

Package APIs stay in Pearl / SciML vocabulary. For a process-metaphysics gloss used in the CDCS book, see the book’s Concept Reference (Table 8), not this package manual.

## Dependencies

Optional weak dependencies: `GraphPPL`, `RxInfer`. They are **not** required for core CausalDynamics.

On Julia 1.13, `CausalTargeted` + `CausalDynamics` + `RxInfer` 4+ resolve together from General; Julia 1.12 remains supported by the package compat bounds. **PrettyTables** enters only transitively (via `DataFrames` / MLJ) at **2.x**, matching RxInfer’s weak `PrettyTablesExt`. Neither owned package pins PrettyTables.

The CDCS book environment lists `RxInfer` explicitly and is the reference unified stack for stress notebooks ([CausalTargeted stress validation](https://github.com/SimonAB/CausalTargeted.jl/blob/main/docs/src/stress_validation.md)).

If `Pkg.resolve()` still fails in an older or heavily pinned application env, check for stale Manifest pins (PrettyTables 1.x) or cap **Graphs** at `1.13` when RxInfer 5.x clashes with `DataStructures` 0.19. See AgeSCM `docs/RXINFER_DEPS.md` for a resolved stack example.

## Further reading

- [RxInfer docs](https://docs.rxinfer.com/stable/)
- [GraphPPL docs](https://reactivebayes.github.io/GraphPPL.jl/stable/)
- [TMLE integration](integration.md) for doubly robust estimation
