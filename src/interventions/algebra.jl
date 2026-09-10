"""Immutable typed intervention algebra and canonical composition."""

abstract type AbstractTypedIntervention <: AbstractCausalIntervention end

struct InterventionConflict <: Exception
    message::String
end
Base.showerror(io::IO, error::InterventionConflict) = print(io, error.message)

struct SetState{V, I} <: AbstractTypedIntervention
    target::Union{Int, Symbol}; value::V; interval::I; scope::Symbol
end
SetState(target, value; interval = :all, scope::Symbol = :unit) = SetState(target, value, interval, scope)

struct SetInitialCondition{V} <: AbstractTypedIntervention
    target::Union{Int, Symbol}; value::V; scope::Symbol
end
SetInitialCondition(target, value; scope::Symbol = :coordinate) = SetInitialCondition(target, value, scope)

struct ReplacePolicy <: AbstractTypedIntervention
    target::Union{Int, Symbol}; replacement_id::String; interval; scope::Symbol
end
ReplacePolicy(target, id::AbstractString; interval = :all, scope::Symbol = :unit) = ReplacePolicy(target, String(id), interval, scope)

struct ReplaceParameter <: AbstractTypedIntervention
    target::Union{Int, Symbol}; replacement_id::String; scope::Symbol
end
ReplaceParameter(target, id::AbstractString; scope::Symbol = :model) = ReplaceParameter(target, String(id), scope)

struct ReplaceMechanism <: AbstractTypedIntervention
    target::Union{Int, Symbol}; replacement_id::String; interval; scope::Symbol
end
ReplaceMechanism(target, id::AbstractString; interval = :all, scope::Symbol = :mechanism) = ReplaceMechanism(target, String(id), interval, scope)

struct Simultaneous{I <: AbstractTypedIntervention} <: AbstractTypedIntervention
    interventions::Vector{I}
end

struct Sequential{I <: AbstractTypedIntervention} <: AbstractTypedIntervention
    interventions::Vector{I}
end

_intervention_vector(xs) = AbstractTypedIntervention[xs...]

function _validate_nonempty(xs)
    isempty(xs) && throw(ArgumentError("an intervention composition must not be empty"))
    return xs
end

function Simultaneous(xs::AbstractTypedIntervention...)
    values = _validate_nonempty(_intervention_vector(xs))
    targets = [intervention_target(x) for x in values]
    for (i, left) in enumerate(values), right in values[(i + 1):end]
        intervention_target(left) == intervention_target(right) &&
            throw(InterventionConflict("simultaneous interventions conflict on target $(intervention_target(left))"))
    end
    sort!(values; by = canonical_intervention)
    return Simultaneous(values)
end

Sequential(xs::AbstractTypedIntervention...) = Sequential(_validate_nonempty(_intervention_vector(xs)))

intervention_kind(::SetState) = :state
intervention_kind(::SetInitialCondition) = :initial_condition
intervention_kind(::ReplacePolicy) = :policy
intervention_kind(::ReplaceParameter) = :parameter
intervention_kind(::ReplaceMechanism) = :mechanism
intervention_kind(::Simultaneous) = :simultaneous
intervention_kind(::Sequential) = :sequential

intervention_target(intervention::Union{SetState, SetInitialCondition, ReplacePolicy, ReplaceParameter, ReplaceMechanism}) = intervention.target
intervention_target(::Union{Simultaneous, Sequential}) = nothing
intervention_interval(intervention::Union{SetState, ReplacePolicy, ReplaceMechanism}) = intervention.interval
intervention_interval(::SetInitialCondition) = :initial
intervention_interval(::ReplaceParameter) = :all

_canonical_fields(xs) = join(["$(ncodeunits(string(x))):$(x)" for x in xs], "|")
canonical_intervention(x::SetState) = _canonical_fields((:state, x.target, repr(x.value), repr(x.interval), x.scope))
canonical_intervention(x::SetInitialCondition) = _canonical_fields((:initial_condition, x.target, repr(x.value), x.scope))
canonical_intervention(x::ReplacePolicy) = _canonical_fields((:policy, x.target, x.replacement_id, repr(x.interval), x.scope))
canonical_intervention(x::ReplaceParameter) = _canonical_fields((:parameter, x.target, x.replacement_id, x.scope))
canonical_intervention(x::ReplaceMechanism) = _canonical_fields((:mechanism, x.target, x.replacement_id, repr(x.interval), x.scope))
canonical_intervention(x::Simultaneous) = _canonical_fields((:simultaneous, map(canonical_intervention, x.interventions)...))
canonical_intervention(x::Sequential) = _canonical_fields((:sequential, map(canonical_intervention, x.interventions)...))

"""Return a stable SHA-256 identity for intervention semantics."""
intervention_fingerprint(intervention::AbstractTypedIntervention) = bytes2hex(sha256(canonical_intervention(intervention)))

export AbstractTypedIntervention, InterventionConflict, SetState, SetInitialCondition,
    ReplacePolicy, ReplaceParameter, ReplaceMechanism, Simultaneous, Sequential,
    intervention_kind, intervention_target, intervention_interval, canonical_intervention,
    intervention_fingerprint
