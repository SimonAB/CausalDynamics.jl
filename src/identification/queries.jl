"""Pearl-style causal queries for identification and estimation."""

"""
    CausalQuery

Supertype for queries posed against a causal graph or temporal unrolling.
"""
abstract type CausalQuery end

"""
    TotalEffectQuery(treatment, outcome)

Backdoor-identifiable total effect of `treatment` on `outcome`.
Node labels may be `Int` indices or `Symbol` names (with a `node_names` map).
"""
struct TotalEffectQuery{T} <: CausalQuery
    treatment::T
    outcome::T
end

"""
    MediationQuery(treatment, outcome, mediators)

Interventional mediation decomposition (NDE / NIE / TE) via mediators on directed paths.
"""
struct MediationQuery{T} <: CausalQuery
    treatment::T
    outcome::T
    mediators::Vector{T}
end

MediationQuery(treatment, outcome, mediators::AbstractVector) =
    MediationQuery(treatment, outcome, collect(mediators))

"""
    TemporalEffectQuery(treatment, outcome, t_treat, t_outcome)

Total effect of `treatment` at occasion `t_treat` on `outcome` at `t_outcome`
after unrolling a [`TemporalDAGSpec`](@ref).
"""
struct TemporalEffectQuery{T} <: CausalQuery
    treatment::T
    outcome::T
    t_treat::Int
    t_outcome::Int
end

"""
    InterventionalPolicyQuery(treatment, outcome; shift=nothing)

Modified treatment policy / stochastic intervention contrast on `treatment`.
`shift` is an application-defined policy descriptor (estimators interpret it).
"""
struct InterventionalPolicyQuery{T, S} <: CausalQuery
    treatment::T
    outcome::T
    shift::S
end

InterventionalPolicyQuery(treatment, outcome; shift = nothing) =
    InterventionalPolicyQuery(treatment, outcome, shift)

export CausalQuery
export TotalEffectQuery, MediationQuery, TemporalEffectQuery, InterventionalPolicyQuery
