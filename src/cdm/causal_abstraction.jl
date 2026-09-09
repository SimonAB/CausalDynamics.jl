"""Interventionally explicit causal abstraction contracts."""

"""
    CausalAbstractionSpec(τ, ω; interventions, distance=abs, tolerance=0.0)

Specify a micro-to-macro state map `τ`, an intervention map `ω`, and the declared
micro intervention domain. `validate_abstraction` checks the commuting condition
against supplied interventional summaries; it does not infer an abstraction.
"""
struct CausalAbstractionSpec{T, W, I, D}
    τ::T
    ω::W
    interventions::Vector{I}
    distance::D
    tolerance::Float64
end

function CausalAbstractionSpec(
    τ,
    ω;
    interventions::AbstractVector,
    distance = (x, y) -> abs(x - y),
    tolerance::Real = 0.0,
)
    isempty(interventions) && throw(ArgumentError("intervention domain must not be empty"))
    isfinite(tolerance) && tolerance >= 0 || throw(ArgumentError("tolerance must be finite and non-negative"))
    return CausalAbstractionSpec(τ, ω, collect(interventions), distance, Float64(tolerance))
end

"""Result of checking declared interventional causal-abstraction consistency."""
struct CausalAbstractionResult{I}
    exact::Bool
    accepted::Bool
    discrepancy::Float64
    discrepancies::Dict{I, Float64}
end

"""
    validate_abstraction(spec, micro_interventions, macro_interventions)

Evaluate the declared discrepancy between a coarse-grained micro intervention and
its mapped macro intervention over the intervention domain declared in
`spec`. Inputs contain already-computed interventional summaries or distributions;
the caller selects a distance appropriate to the scientific decision.
"""
function validate_abstraction(
    spec::CausalAbstractionSpec,
    micro_interventions::AbstractDict,
    macro_interventions::AbstractDict,
)
    discrepancies = Dict{eltype(spec.interventions), Float64}()
    for i in spec.interventions
        haskey(micro_interventions, i) || throw(ArgumentError("missing micro intervention $i"))
        macro_i = spec.ω(i)
        haskey(macro_interventions, macro_i) || throw(ArgumentError("missing macro intervention $macro_i"))
        discrepancy_i = Float64(spec.distance(spec.τ(micro_interventions[i]), macro_interventions[macro_i]))
        isfinite(discrepancy_i) && discrepancy_i >= 0 ||
            throw(ArgumentError("abstraction discrepancy for $i must be finite and non-negative"))
        discrepancies[i] = discrepancy_i
    end
    discrepancy = maximum(values(discrepancies))
    return CausalAbstractionResult(discrepancy == 0.0, discrepancy <= spec.tolerance,
        discrepancy, discrepancies)
end

export CausalAbstractionSpec, CausalAbstractionResult, validate_abstraction
