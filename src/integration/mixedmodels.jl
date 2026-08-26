"""Optional MixedModels.jl integration for static-treatment repeated outcomes."""

"""
    MixedGComputationResult

Time-indexed standardized means and their contrast from [`mixed_g_computation`](@ref).

`mean_reference` corresponds to `values[1]`, `mean_comparison` to `values[2]`,
and `effect` is `mean_comparison - mean_reference`. `adjustment` records the
graph-derived backdoor set when a graph was supplied. `vcov` is the joint
fixed-effect covariance matrix of the effect trajectory, in `times` order, and
`se` is `sqrt.(diag(vcov))`. `random_effects` records whether nonlinear-link
predictions set random effects to zero (`:zero`) or integrate the response mean
over a supported fitted Gaussian random-effects distribution (`:marginal`).
This uncertainty is fixed-effect-only: it does not include residual,
dispersion, or variance-component uncertainty. `uncertainty` is
`:delta_fixed` or `:parametric_bootstrap`; the latter stores replicate counts,
seed, failure messages, and successful trajectory draws in
`uncertainty_diagnostics`.
"""
struct MixedGComputationResult{T, V, A}
    treatment::Symbol
    outcome::Symbol
    time::Symbol
    id::Symbol
    times::Vector{T}
    values::V
    mean_reference::Vector{Float64}
    mean_comparison::Vector{Float64}
    effect::Vector{Float64}
    adjustment::Vector{A}
    vcov::Union{Nothing, Matrix{Float64}}
    se::Union{Nothing, Vector{Float64}}
    random_effects::Symbol
    uncertainty::Symbol
    uncertainty_diagnostics
end

# Preserve the original positional construction API after adding the estimand label.
function MixedGComputationResult(
    treatment,
    outcome,
    time,
    id,
    times,
    values,
    mean_reference,
    mean_comparison,
    effect,
    adjustment,
    vcov,
    se,
)
    return MixedGComputationResult(
        treatment,
        outcome,
        time,
        id,
        times,
        values,
        mean_reference,
        mean_comparison,
        effect,
        adjustment,
        vcov,
        se,
        :zero,
        :delta_fixed,
        nothing,
    )
end

# Preserve the positional API introduced with the random-effects estimand label.
function MixedGComputationResult(
    treatment,
    outcome,
    time,
    id,
    times,
    values,
    mean_reference,
    mean_comparison,
    effect,
    adjustment,
    vcov,
    se,
    random_effects,
)
    return MixedGComputationResult(
        treatment,
        outcome,
        time,
        id,
        times,
        values,
        mean_reference,
        mean_comparison,
        effect,
        adjustment,
        vcov,
        se,
        random_effects,
        :delta_fixed,
        nothing,
    )
end

function MixedGComputationResult(;
    treatment::Symbol,
    outcome::Symbol,
    time::Symbol,
    id::Symbol,
    times::AbstractVector,
    values,
    mean_reference::AbstractVector,
    mean_comparison::AbstractVector,
    adjustment::AbstractVector = Symbol[],
    vcov::Union{Nothing, AbstractMatrix} = nothing,
    se::Union{Nothing, AbstractVector} = nothing,
    random_effects::Symbol = :zero,
    uncertainty::Symbol = :delta_fixed,
    uncertainty_diagnostics = nothing,
)
    n = length(times)
    length(mean_reference) == n || throw(ArgumentError(
        "mean_reference has length $(length(mean_reference)); expected $n",
    ))
    length(mean_comparison) == n || throw(ArgumentError(
        "mean_comparison has length $(length(mean_comparison)); expected $n",
    ))
    reference = Float64.(mean_reference)
    comparison = Float64.(mean_comparison)
    covariance = vcov === nothing ? nothing : Matrix{Float64}(vcov)
    standard_errors = se === nothing ? nothing : Vector{Float64}(se)
    covariance === nothing || size(covariance) == (n, n) || throw(ArgumentError(
        "vcov has size $(size(covariance)); expected ($n, $n)",
    ))
    standard_errors === nothing || length(standard_errors) == n || throw(ArgumentError(
        "se has length $(length(standard_errors)); expected $n",
    ))
    return MixedGComputationResult(
        treatment,
        outcome,
        time,
        id,
        Vector{eltype(times)}(times),
        values,
        reference,
        comparison,
        comparison .- reference,
        collect(adjustment),
        covariance,
        standard_errors,
        random_effects,
        uncertainty,
        uncertainty_diagnostics,
    )
end

"""
    NB2RandomInterceptModel

A fitted NB2/log mixed model with one Gaussian random intercept and an
estimated NB2 shape parameter. Construct it with [`fit_profiled_nb2`](@ref).

Despite the compatibility alias `ProfiledNB2MixedModel`, the authoritative
implementation uses a dedicated subject-integrated likelihood; it does not
profile MixedModels.jl fixed-shape GLMM fits.
"""
struct NB2RandomInterceptModel
    formula
    fixed_formula_term
    id::Symbol
    coefficients::Vector{Float64}
    coefficient_names::Vector{String}
    theta::Float64
    random_intercept_variance::Float64
    loglikelihood::Float64
    converged::Bool
    optimizer_diagnostics
    theta_profile
    beta_vcov::Matrix{Float64}
    uncertainty_method::Symbol
    quadrature_method::Symbol
    quadrature_points::Int
    observations::Int
    fitted_data
end

const ProfiledNB2MixedModel = NB2RandomInterceptModel

"""
    fit_profiled_nb2(formula, data; id, kwargs...)

Fit the optional dedicated subject-integrated NB2/log/random-intercept backend,
jointly estimating fixed effects, random-intercept variance, and NB2 shape with
adaptive Gauss--Hermite quadrature. This method is available after loading
MixedModels.jl and DataFrames.jl.
"""
function fit_profiled_nb2(args...; kwargs...)
    throw(ArgumentError(
        "fit_profiled_nb2 requires MixedModels.jl and DataFrames.jl. " *
        "Load them with `using MixedModels, DataFrames`.",
    ))
end

"""Compare fitted parameters across requested adaptive-quadrature orders."""
function quadrature_diagnostics(args...; kwargs...)
    throw(ArgumentError(
        "quadrature_diagnostics requires the optional MixedModels/DataFrames integration",
    ))
end

"""Audit MixedModels fixed-shape NB2 log likelihoods against independent quadrature."""
function validate_fixed_theta_nb2_likelihood(args...; kwargs...)
    throw(ArgumentError(
        "validate_fixed_theta_nb2_likelihood requires the optional " *
        "MixedModels/DataFrames integration",
    ))
end

"""Return the jointly estimated NB2 shape parameter."""
theta(model::NB2RandomInterceptModel) = model.theta

"""Return whether all convergence and interior-optimum checks passed."""
converged(model::NB2RandomInterceptModel) = model.converged

"""Return optimizer, gradient, profile, and quadrature diagnostics."""
fitdiagnostics(model::NB2RandomInterceptModel) = model.optimizer_diagnostics

"""Return the fitted Gaussian random-intercept variance."""
random_intercept_variance(model::NB2RandomInterceptModel) =
    model.random_intercept_variance

function Base.show(io::IO, model::NB2RandomInterceptModel)
    print(
        io,
        "NB2RandomInterceptModel(NB2/log, estimated theta=",
        model.theta,
        ", group=:",
        model.id,
        ", quadrature=",
        model.quadrature_method,
        "(",
        model.quadrature_points,
        "), converged=",
        model.converged,
        ", uncertainty=",
        model.uncertainty_method,
        ")",
    )
end

function Base.show(io::IO, ::MIME"text/plain", model::NB2RandomInterceptModel)
    show(io, model)
    print(
        io,
        "\n  random-intercept variance: ",
        model.random_intercept_variance,
        "\n  log likelihood: ",
        model.loglikelihood,
        "\n  fixed effects: ",
        length(model.coefficients),
    )
end

"""
    StratifiedMixedGComputationResult

A collection of [`MixedGComputationResult`](@ref)s, one for each observed
stratum requested with `strata`. `strata` records the stratification-column
names, `levels` records stable stratum identifiers, and `results` has the same
order. Index a single-variable result by its observed level, for example
`result["group_a"]`; index a multi-variable result by a named tuple, for example
`result[(Cohort="group_a", Site="north")]`.
"""
struct StratifiedMixedGComputationResult{K, R <: MixedGComputationResult}
    strata::Vector{Symbol}
    levels::Vector{K}
    results::Vector{R}

    function StratifiedMixedGComputationResult(
        strata::AbstractVector{Symbol},
        levels::AbstractVector{K},
        results::AbstractVector{R},
    ) where {K, R <: MixedGComputationResult}
        isempty(strata) && throw(ArgumentError("strata must contain at least one column"))
        length(levels) == length(results) || throw(ArgumentError(
            "levels and results must have the same length",
        ))
        return new{K, R}(collect(strata), collect(levels), collect(results))
    end
end

Base.length(result::StratifiedMixedGComputationResult) = length(result.results)
Base.keys(result::StratifiedMixedGComputationResult) = result.levels
Base.values(result::StratifiedMixedGComputationResult) = result.results
Base.pairs(result::StratifiedMixedGComputationResult) = zip(result.levels, result.results)
Base.iterate(result::StratifiedMixedGComputationResult, state...) =
    iterate(result.results, state...)

function Base.getindex(result::StratifiedMixedGComputationResult, level)
    identifier = if length(result.strata) == 1 && level isa NamedTuple
        propertynames(level) == Tuple(result.strata) || throw(KeyError(level))
        only(values(level))
    else
        level
    end
    index = findfirst(x -> isequal(x, identifier), result.levels)
    index === nothing && throw(KeyError(level))
    return result.results[index]
end

function Base.show(io::IO, result::MixedGComputationResult)
    print(
        io,
        "MixedGComputationResult(",
        length(result.times),
        " time points, do(",
        result.treatment,
        "=",
        repr(result.values[2]),
        ") - do(",
        result.treatment,
        "=",
        repr(result.values[1]),
        "), random_effects=",
        repr(result.random_effects),
        ", uncertainty=",
        repr(result.uncertainty),
        ")",
    )
end

function Base.show(io::IO, ::MIME"text/plain", result::MixedGComputationResult)
    show(io, result)
    print(io, "\n", result.time, "\tmean_reference\tmean_comparison\teffect")
    for i in eachindex(result.times)
        print(
            io,
            "\n",
            result.times[i],
            "\t",
            result.mean_reference[i],
            "\t",
            result.mean_comparison[i],
            "\t",
            result.effect[i],
        )
    end
    isempty(result.adjustment) || print(io, "\nadjustment: ", result.adjustment)
end

function Base.show(io::IO, result::StratifiedMixedGComputationResult)
    print(
        io,
        "StratifiedMixedGComputationResult(",
        length(result),
        " strata by ",
        join(string.(result.strata), " × "),
        ")",
    )
end

function Base.show(io::IO, ::MIME"text/plain", result::StratifiedMixedGComputationResult)
    show(io, result)
    for (level, trajectory) in pairs(result)
        print(io, "\n", repr(level), ": ")
        show(io, trajectory)
    end
end

"""
    mixed_g_computation(model, data; treatment, outcome, time, id,
                        values=(0, 1), strata=nothing, random_effects=:zero)
    mixed_g_computation(graph, model, data; treatment, outcome, time, id,
                        values=(0, 1), strata=nothing, random_effects=:zero,
                        node_names=nothing)

Estimate a time-specific standardized contrast for a static treatment and a
repeated outcome using a fitted `MixedModels.LinearMixedModel` or a supported
`MixedModels.GeneralizedLinearMixedModel`.

The first method standardizes population-level predictions under the two static
interventions in `values`. With `strata=nothing` it returns one
[`MixedGComputationResult`](@ref). With a symbol or tuple of symbols, such as
`strata=:Age`, it returns a [`StratifiedMixedGComputationResult`](@ref) whose
trajectories are standardized over the remaining covariates within each stratum.
The graph method first calls [`identify`](@ref) for a
[`TotalEffectQuery`](@ref), requires backdoor identification, validates that the
identified adjustment variables occur in the fitted formula, and records them in
the returned [`MixedGComputationResult`](@ref).

The estimand at each observed time `t` is

```math
E_W[E(Y_t \\mid A=\\text{values}[2], W)] -
E_W[E(Y_t \\mid A=\\text{values}[1], W)].
```

This integration is provided by the optional MixedModels/DataFrames extension.
It supports Gaussian `LinearMixedModel`s, fixed-shape NB2 negative-binomial
`GeneralizedLinearMixedModel` compatibility fits, and dedicated
`NB2RandomInterceptModel`s that estimate shape. The model's grouping factor must
be `id`. For `random_effects=:zero`, MixedModels prediction uses fresh ID levels with
`new_re_levels=:population`, so fitted subject-specific random effects are set
to zero. For an NB2 random-intercept model, `random_effects=:marginal` applies
the analytic Gaussian log-normal correction. The reported delta-method
covariance conditions on all fitted or supplied variance components. Causal
interpretation requires the usual identification assumptions and correct
specification of the parametric outcome model.
"""
function mixed_g_computation(args...; kwargs...)
    throw(ArgumentError(
        "mixed_g_computation requires MixedModels.jl and DataFrames.jl. " *
        "Load them with `using MixedModels, DataFrames`.",
    ))
end

export MixedGComputationResult,
       StratifiedMixedGComputationResult,
       NB2RandomInterceptModel,
       ProfiledNB2MixedModel,
       fit_profiled_nb2,
       quadrature_diagnostics,
       validate_fixed_theta_nb2_likelihood,
       theta,
       converged,
       fitdiagnostics,
       random_intercept_variance,
       mixed_g_computation
