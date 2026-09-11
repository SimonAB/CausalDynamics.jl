"""Exact interventionally consistent abstraction over finite causal laws."""

abstract type AbstractCausalLaw end

"""A finite probability law with canonical support and probabilities."""
struct FiniteLaw{T} <: AbstractCausalLaw
    support::Vector{T}
    probabilities::Vector{Float64}
    function FiniteLaw{T}(support::Vector{T}, probabilities::Vector{Float64}) where {T}
        new{T}(support, probabilities)
    end
end

function FiniteLaw(values::AbstractVector{T}, masses::AbstractVector{<:Real}) where {T}
    length(values) == length(masses) || throw(ArgumentError("support and probabilities must have equal length"))
    isempty(values) && throw(ArgumentError("a finite law must have non-empty support"))
    all(isfinite, masses) && all(>=(0), masses) || throw(ArgumentError("probabilities must be finite and non-negative"))
    total = sum(masses)
    total > 0 || throw(ArgumentError("probabilities must have positive total mass"))
    index = Dict{T, Int}(); support_values = T[]; probabilities = Float64[]
    for (value, mass) in zip(values, masses)
        position = get!(index, value) do
            push!(support_values, value); push!(probabilities, 0.0); length(support_values)
        end
        probabilities[position] += Float64(mass) / Float64(total)
    end
    return FiniteLaw{T}(support_values, probabilities)
end

support(law::FiniteLaw) = law.support
probabilities(law::FiniteLaw) = law.probabilities

"""Map a finite law through a deterministic state map."""
pushforward(map, law::FiniteLaw) = FiniteLaw(map.(law.support), law.probabilities)

"""Return a mass map that ignores support order."""
function _mass_map(law::FiniteLaw{T}) where {T}
    return Dict{T, Float64}(atom => mass for (atom, mass) in zip(law.support, law.probabilities))
end

"""Exact equality for finite laws with optional numerical tolerance."""
function law_equal(lhs::FiniteLaw, rhs::FiniteLaw; atol::Real = 0.0)
    left = _mass_map(lhs)
    right = _mass_map(rhs)
    keys(left) == keys(right) || return false
    return all(isapprox(left[atom], right[atom]; atol = atol, rtol = 0.0) for atom in keys(left))
end

"""Total-variation distance for finite laws, aligning atoms independently of order."""
function law_distance(lhs::FiniteLaw, rhs::FiniteLaw, _ = :total_variation)
    left = _mass_map(lhs)
    right = _mass_map(rhs)
    atoms = union(keys(left), keys(right))
    return 0.5 * sum(abs(get(left, atom, 0.0) - get(right, atom, 0.0)) for atom in atoms)
end

"""
    CausalAbstractionSpec(τ, ω; interventions, distance=law_distance, tolerance=0.0, law_mode=:exact)

Compare finite interventional laws after push-forward through state map `τ` and
intervention map `ω`. `exact` is mass-map equality; `accepted` uses `law_mode`
and `tolerance`.
"""
struct CausalAbstractionSpec{T, W, I, D}
    τ::T; ω::W; interventions::Vector{I}; distance::D; tolerance::Float64; law_mode::Symbol
end

function CausalAbstractionSpec(τ, ω; interventions::AbstractVector, distance = law_distance,
    tolerance::Real = 0.0, law_mode::Symbol = :exact)
    isempty(interventions) && throw(ArgumentError("intervention domain must not be empty"))
    law_mode in (:exact, :approximate) || throw(ArgumentError("law_mode must be :exact or :approximate"))
    isfinite(tolerance) && tolerance >= 0 || throw(ArgumentError("tolerance must be finite and non-negative"))
    return CausalAbstractionSpec(τ, ω, collect(interventions), distance, Float64(tolerance), law_mode)
end

"""Result of [`validate_abstraction`](@ref): exactness, acceptance, and per-intervention discrepancies."""
struct CausalAbstractionResult{I}
    exact::Bool; accepted::Bool; discrepancy::Float64
    discrepancies::Dict{I, Float64}; failed_interventions::Vector{I}
end

"""Compare micro and macro interventional laws under a [`CausalAbstractionSpec`](@ref)."""
function validate_abstraction(spec::CausalAbstractionSpec, micro_interventions::AbstractDict,
    macro_interventions::AbstractDict)
    discrepancies = Dict{eltype(spec.interventions), Float64}(); failed = eltype(spec.interventions)[]
    pushed_laws = Dict{eltype(spec.interventions), FiniteLaw}()
    for intervention in spec.interventions
        haskey(micro_interventions, intervention) || throw(ArgumentError("missing micro intervention $intervention"))
        macro_i = spec.ω(intervention)
        haskey(macro_interventions, macro_i) || throw(ArgumentError("missing macro intervention $macro_i"))
        pushed = pushforward(spec.τ, micro_interventions[intervention]); pushed_laws[intervention] = pushed
        macro_law = macro_interventions[macro_i]
        discrepancy = Float64(spec.distance(pushed, macro_law))
        isfinite(discrepancy) && discrepancy >= 0 || throw(ArgumentError("abstraction discrepancy must be finite and non-negative"))
        discrepancies[intervention] = discrepancy
        failed_exact = spec.law_mode === :exact && !law_equal(pushed, macro_law)
        failed_tolerance = discrepancy > spec.tolerance
        (failed_exact || failed_tolerance) && push!(failed, intervention)
    end
    discrepancy = maximum(values(discrepancies))
    exact = isempty(failed) && all(law_equal(pushed_laws[i], macro_interventions[spec.ω(i)]) for i in spec.interventions)
    return CausalAbstractionResult(exact, isempty(failed), discrepancy, discrepancies, failed)
end

export AbstractCausalLaw, FiniteLaw, support, probabilities, pushforward, law_equal, law_distance,
    CausalAbstractionSpec, CausalAbstractionResult, validate_abstraction
