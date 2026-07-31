"""
    CausalDynamicsRxInfer

Optional integration: GraphPPL.jl model specification + RxInfer.jl variational inference
for backdoor-adjusted observational models after CausalDynamics identification.
"""
module CausalDynamicsRxInfer

using CausalDynamics: CausalDynamics,
    prepare_for_rxinfer,
    AbstractGraph,
    CausalGraph,
    Graphs
using DataFrames: DataFrames
using GraphPPL: GraphPPL
using RxInfer: RxInfer, @model, infer, Normal, KeepLast

export BackdoorInferenceResult,
    backdoor_graphppl_model,
    infer_backdoor_effect,
    ppl_data_from_spec,
    posterior_mean_τ,
    residualise_backdoor

"""
    BackdoorInferenceResult

Result of variational backdoor inference via GraphPPL + RxInfer.

# Fields
- `treatment`, `outcome`: Effect of interest (symbols or indices)
- `confounders`: Adjustment set used
- `identifiable`: Whether a backdoor adjustment set was found
- `τ_posterior`: RxInfer marginal history for `τ` (`NormalWeightedMeanPrecision` per iteration)
- `τ_mean`: Posterior mean of `τ` from the final marginal (use this, not `Statistics.mean` on `τ_posterior`)
- `n`: Number of observations
- `raw`: Full `RxInfer` inference result
"""
struct BackdoorInferenceResult{T}
    treatment::Any
    outcome::Any
    confounders::Vector
    identifiable::Bool
    τ_posterior::T
    τ_mean::Float64
    n::Int
    raw::Any
end

"""
    posterior_mean_τ(τ_posterior) -> Float64

Posterior mean of treatment effect `τ` from an RxInfer `NormalWeightedMeanPrecision` marginal
(or the last entry of an iteration history). Do not use `Statistics.mean` on the history vector.
"""
function posterior_mean_τ(τ_posterior)
    m = τ_posterior isa AbstractVector && !isempty(τ_posterior) ? τ_posterior[end] : τ_posterior
    return Float64(m.xi / m.w)
end

"""
    _column(data, name) -> Vector{Float64}

Extract a numeric column from tabular data for PPL interfaces.
"""
function _column(data, name::Symbol)
    if data isa DataFrames.DataFrame
        col = data[!, name]
    elseif data isa NamedTuple
        col = getproperty(data, name)
    else
        error("Unsupported data type $(typeof(data)). Use DataFrame or NamedTuple.")
    end
    return Vector{Float64}(col)
end

"""
    residualise_backdoor(y, x, confounder_cols) -> (y_res, x_res)

Partial out an intercept and any confounders from outcome and treatment (Frisch–Waugh),
so a conjugate no-intercept RxInfer head on the residualised pair identifies the slope `τ`.
With an empty confounder list this still demeans `(y, x)`.
"""
function residualise_backdoor(y::AbstractVector{<:Real}, x::AbstractVector{<:Real},
    confounder_cols)
    y = Vector{Float64}(y)
    x = Vector{Float64}(x)
    n = length(y)
    cols = collect(AbstractVector{<:Real}, confounder_cols)
    design = isempty(cols) ? ones(n, 1) : hcat(ones(n), cols...)
    β_y = design \ y
    β_x = design \ x
    return y .- design * β_y, x .- design * β_x
end

"""
    ppl_data_from_spec(spec; residualise=true) -> NamedTuple

Build RxInfer data from `prepare_for_rxinfer` output. By default, an intercept and any
confounders are partialled out in Julia; the GraphPPL head estimates `τ` on residualised `(y, x)`.
"""
function ppl_data_from_spec(spec; residualise::Bool=true)
    data = spec.data
    data === nothing && error("No data attached. Pass `data=` to prepare_for_rxinfer.")
    y = _column(data, spec.outcome)
    x = _column(data, spec.treatment)
    n = length(y)
    conf_cols = [_column(data, c) for c in spec.confounders]
    if residualise
        y, x = residualise_backdoor(y, x, conf_cols)
    end
    return (y=y, x=x, n_conf=length(conf_cols), n_obs=n)
end

# Conjugate Gaussian head for residualised (Y, X) — matches RxInfer's supported factorisation.
@model function backdoor_gaussian_ate(y, x, n_obs)
    τ ~ Normal(mean=0.0, var=10.0)
    for i in 1:n_obs
        y[i] ~ Normal(mean=τ * x[i], var=1.0)
    end
end

"""
    backdoor_graphppl_model(; n_conf=0)

Return the GraphPPL model generator for the backdoor Gaussian ATE head on
(possibly residualised) outcome and treatment vectors.
"""
backdoor_graphppl_model(; n_conf::Int=0) = backdoor_gaussian_ate()

"""
    infer_backdoor_effect(
        g, data, X, Y;
        node_names=nothing,
        iterations=25,
        showprogress=false,
        warn_not_identifiable=true,
        kwargs...
    ) -> BackdoorInferenceResult

Identify a backdoor adjustment set with CausalDynamics, partial out confounders (Frisch–Waugh),
fit a conjugate GraphPPL Gaussian head on residualised `(y, x)`, and run RxInfer VI for `τ`.

Requires `using RxInfer` (loads this extension).

# Arguments
- `g`: `DiGraph` or `CausalGraph`
- `data`: `DataFrame` or `NamedTuple` with treatment, outcome, and confounder columns
- `X`, `Y`: Treatment and outcome node indices
- `node_names`: Optional `Dict{Int,Symbol}` for column names
- `iterations`: RxInfer VI iterations
- `warn_not_identifiable`: Warn when no backdoor set is found

# Example

```julia
using CausalDynamics, RxInfer, Graphs, DataFrames, Random

g = DiGraph(3)
add_edge!(g, 1, 2)
add_edge!(g, 1, 3)
add_edge!(g, 2, 3)
names = Dict(1 => :Z, 2 => :X, 3 => :Y)
data = DataFrame(Z=randn(100), X=randn(100), Y=randn(100))

result = infer_backdoor_effect(g, data, 2, 3; node_names=names)
result.τ_mean   # or posterior_mean_τ(result.τ_posterior)
```
"""
function infer_backdoor_effect(
    g::AbstractGraph,
    data,
    X::Int,
    Y::Int;
    node_names=nothing,
    iterations::Int=25,
    showprogress::Bool=false,
    warn_not_identifiable::Bool=true,
    kwargs...,
)
    spec = prepare_for_rxinfer(g, X, Y; node_names=node_names, data=data)
    if warn_not_identifiable && !spec.is_identifiable
        @warn "No backdoor adjustment set found for $(spec.treatment) → $(spec.outcome). " *
              "Proceeding with empty adjustment; effect may be biased."
    end
    ppl_data = ppl_data_from_spec(spec; residualise=true)
    n_obs = ppl_data.n_obs
    model = backdoor_gaussian_ate(n_obs=n_obs)
    infer_data = (y=ppl_data.y, x=ppl_data.x)
    raw = infer(;
        model=model,
        data=infer_data,
        iterations=iterations,
        showprogress=showprogress,
        returnvars=(τ=KeepLast(),),
        kwargs...,
    )
    τ_posterior = raw.posteriors[:τ]
    τ_mean = posterior_mean_τ(τ_posterior)
    return BackdoorInferenceResult(
        spec.treatment,
        spec.outcome,
        spec.confounders,
        spec.is_identifiable,
        τ_posterior,
        τ_mean,
        ppl_data.n_obs,
        raw,
    )
end

function infer_backdoor_effect(g::CausalGraph, data, X::Int, Y::Int; kwargs...)
    return infer_backdoor_effect(g.graph, data, X, Y; kwargs...)
end

function infer_backdoor_effect(g::CausalGraph, X::Int, Y::Int; kwargs...)
    data = CausalDynamics.get_data(g)
    data === nothing && error("CausalGraph has no attached data. Pass `data` explicitly.")
    return infer_backdoor_effect(g.graph, data, X, Y; kwargs...)
end

end # module
