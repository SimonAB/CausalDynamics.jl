# Integration overview

`CausalDynamics.jl` owns causal graph structure, identification certificates, and
executable discrete-time and static structural models. Downstream statistical
estimation, probabilistic inference, causal discovery, continuous ODE
integration, and plotting live in sibling packages or optional package
extensions so core dependencies remain minimal.

## Ecosystem map

| Task | Package(s) | Entry points | Guide |
|------|------------|--------------|-------|
| **Longitudinal, LMTP, MSM, and Bayesian g-computation estimation** | `CausalTargeted.jl` | `CausalTargeted.plan_targeted_estimation`, `CausalTargeted.run_estimation_plan` | [Estimation bridges](#estimation-bridges-causaltargeted-tmlejl-turingjl) · [CausalTargeted.jl](https://simonab.github.io/CausalTargeted.jl/dev/) |
| **Point-treatment TMLE on tabular data** | `TMLE.jl` (optional) | `prepare_for_tmle`, `get_tmle_confounders`, `estimate_effect` | [TMLE.jl](#tmlejl-optional-point-treatment-estimation) |
| **Variational backdoor inference & state-space smoothing** | `RxInfer.jl` / `GraphPPL.jl` (weakdep) | `prepare_for_rxinfer`, `infer_backdoor_effect`, `infer_linear_state_space`, `infer_nonlinear_state_space` | [RxInfer / GraphPPL](RXINFER_INTEGRATION.md) · [Linear Gaussian states](linear_bayesian_states.md) · [Nonlinear states](nonlinear_states.md) |
| **Causal discovery from observational data or series** | `Associations.jl` (weakdep) | `infer_pc_graph`, `infer_oce_temporal_spec`, `prepare_from_discovery`, `interventional_embedding_entropy` | [Associations.jl](ASSOCIATIONS_INTEGRATION.md) |
| **Continuous-time ODE CDMs, sensitivity, and neural residuals** | `OrdinaryDiffEq.jl` / `SciMLSensitivity.jl` / `Lux.jl` (weakdeps) | `ContinuousCDMSpec`, `solve_cdm`, `do_pin`, `forward_sensitivity_cdm`, `MechanismLibrary` | [SciML recipes](SCIML_INTEGRATION.md) |
| **DAG and temporal-unrolling visualisation** | `DAGMakie.jl` (weakdep) | `plot_causal_graph`, `plot_backdoor_paths`, `dagplot_temporal` | [Getting Started](getting-started.md) · [DAGMakie.jl](https://simonab.github.io/DAGMakie.jl/dev/) |
| **Custom Bayesian models in a PPL** | `Turing.jl` (optional) | `prepare_for_turing`, `get_data_for_ppl` | [Turing.jl](#turingjl-probabilistic-programming-bridge) |

Docstrings for all integration helpers are collected in the
[Integrations API](api/integration.md).

## Estimation bridges (CausalTargeted, TMLE.jl, Turing.jl)

### CausalTargeted.jl (primary longitudinal and LMTP bridge)

For longitudinal treatments, modified treatment policies (LMTP), two-part hurdle
outcomes, marginal structural models, Super Learner nuisances, and Bayesian
g-computation, pass a `TemporalUnrolling` and `TemporalEffectQuery` from
`CausalDynamics` to `CausalTargeted.plan_targeted_estimation`, then execute the
returned `EstimationPlan` with `CausalTargeted.run_estimation_plan`.

- `CausalDynamics` supplies structural identification (`identify`,
  `IdentificationResult`), wide-panel mapping (`CDMPanel`, `simulate_panel`,
  `panel_column_name`), and empirical support checks (`identification_support`).
- `CausalTargeted` selects the estimation engine (`:discrete_lmtp`,
  `:sequential_lmtp`, `:lmtp_grid`, or `:two_part_discrete_lmtp`) and fits the
  nuisance and target estimators.

See the [Identification API](api/identification.md#panel-planning-and-compatibility)
and the [CausalTargeted.jl documentation](https://simonab.github.io/CausalTargeted.jl/dev/).

### TMLE.jl (optional point-treatment estimation)

For point-treatment targeted maximum likelihood estimation on tabular data with
[TMLE.jl](https://github.com/TARGENE/TMLE.jl), `CausalDynamics` provides three
helpers:

- `prepare_for_tmle(g, X, Y; node_names=nothing)` returns `(confounders, is_identifiable)` using backdoor identification.
- `get_tmle_confounders(g, X, Y; node_names=nothing)` returns the confounder vector directly.
- `estimate_effect(g, data, X, Y; node_names=nothing, method=:tmle, kwargs...)` combines identification and estimation when `TMLE` is loaded (for a `CausalGraph` with attached data, `data` may be omitted).

> **Optional compatibility note:** `TMLE.jl` is **not** a dependency or weak
> dependency of `CausalDynamics.jl`. `prepare_for_tmle` and
> `get_tmle_confounders` work with core `CausalDynamics` alone. `estimate_effect`
> inspects loaded modules at runtime for `TMLE` (activated via `using TMLE`)
> and delegates to `TMLE.tmle(data; treatment=..., outcome=..., confounders=..., kwargs...)`.
> Ensure that any extra `kwargs...` match your installed `TMLE.jl` version.

```julia
using CausalDynamics, Graphs, DataFrames

# Causal graph: Z → X → Y, Z → Y
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)
confounders, identifiable = prepare_for_tmle(g, 2, 3; node_names = node_names)
# Returns: ([:Z], true)

# Simulated tabular data
n = 200
z = randn(n)
x = Int.(z .+ randn(n) .> 0)
y = 1.5 .* x .+ 0.8 .* z .+ 0.5 .* randn(n)
data = DataFrame(Z = z, X = x, Y = y)

# Once `using TMLE` is loaded in your environment:
# result = estimate_effect(g, data, 2, 3; node_names = node_names)
```

See `examples/tmle_integration.jl` in the package repository for additional
examples (no confounding, multiple confounders, and `CausalGraph` auto-detection).

### Turing.jl (probabilistic programming bridge)

`CausalDynamics` prepares identified adjustment sets and extracts tabular data
for [Turing.jl](https://turinglang.org/stable/) via `prepare_for_turing` and
`get_data_for_ppl`:

- `prepare_for_turing(g, X, Y; node_names=nothing, data=nothing)` returns a
  `NamedTuple` with fields `graph`, `treatment`, `outcome`, `confounders`,
  `data`, `node_names`, and `is_identifiable`. When `g` is a `CausalGraph`,
  attached node names and data are extracted automatically if omitted.
- `get_data_for_ppl(g::CausalGraph; format=:dataframe)` converts attached graph
  data to `:dataframe`, `:namedtuple`, or `:dict` (returning `nothing` if no data
  are attached).

```julia
using CausalDynamics, Graphs, DataFrames

g = CausalGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y
set_node_prop!(g, 1, :name, :Z)
set_node_prop!(g, 2, :name, :X)
set_node_prop!(g, 3, :name, :Y)

n = 200
z = randn(n)
x = randn(n) .+ 0.6 .* z
y = 1.8 .* x .+ 0.7 .* z .+ 0.5 .* randn(n)
attach_data!(g, DataFrame(Z = z, X = x, Y = y))

spec = prepare_for_turing(g, 2, 3)
# spec.treatment == :X, spec.outcome == :Y, spec.confounders == [:Z], spec.is_identifiable == true

nt = get_data_for_ppl(g; format = :namedtuple)
```

You can then pass the extracted columns and identified adjustment variables into
a `Turing` model:

```julia
using Turing

@model function backdoor_linear(y, x, z)
    α ~ Normal(0, 2)
    τ ~ Normal(0, 2)
    β ~ Normal(0, 2)
    σ ~ Exponential(1)
    y .~ Normal.(α .+ τ .* x .+ β .* z, σ)
end

if spec.is_identifiable
    model = backdoor_linear(nt[spec.outcome], nt[spec.treatment], nt[spec.confounders[1]])
    chain = sample(model, NUTS(), 500)
end
```

## Further reading

- [Integrations API](api/integration.md)
- [SciML recipes](SCIML_INTEGRATION.md)
- [RxInfer / GraphPPL](RXINFER_INTEGRATION.md)
- [Exact linear Gaussian states](linear_bayesian_states.md)
- [Known-noise nonlinear states](nonlinear_states.md)
- [Associations.jl](ASSOCIATIONS_INTEGRATION.md)
- [References](references.md)
