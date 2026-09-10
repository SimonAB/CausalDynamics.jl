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

struct ReplacePolicy{R} <: AbstractTypedIntervention
    target::Union{Int, Symbol}; replacement_id::String; interval; scope::Symbol; rule::R
end
ReplacePolicy(target, id::AbstractString; interval = :all, scope::Symbol = :unit, rule = nothing) =
    ReplacePolicy(target, String(id), interval, scope, rule)

struct ReplaceParameter <: AbstractTypedIntervention
    target::Union{Int, Symbol}; replacement_id::String; scope::Symbol
end
ReplaceParameter(target, id::AbstractString; scope::Symbol = :model) = ReplaceParameter(target, String(id), scope)

struct ReplaceMechanism <: AbstractTypedIntervention
    target::Union{Int, Symbol}; replacement_id::String; interval; scope::Symbol
end
ReplaceMechanism(target, id::AbstractString; interval = :all, scope::Symbol = :mechanism) = ReplaceMechanism(target, String(id), interval, scope)

struct Simultaneous <: AbstractTypedIntervention
    interventions::Vector{AbstractCausalIntervention}
end

struct Sequential <: AbstractTypedIntervention
    interventions::Vector{AbstractCausalIntervention}
end

_intervention_vector(xs) = AbstractCausalIntervention[xs...]

function _validate_nonempty(xs)
    isempty(xs) && throw(ArgumentError("an intervention composition must not be empty"))
    return xs
end

function Simultaneous(xs::AbstractCausalIntervention...)
    values = _validate_nonempty(_intervention_vector(xs))
    _assert_no_simultaneous_conflict(values)
    sort!(values; by = canonical_intervention)
    return Simultaneous(values)
end

Sequential(xs::AbstractCausalIntervention...) = Sequential(_validate_nonempty(_intervention_vector(xs)))

"""Return the targets that cannot share a simultaneous assignment."""
_intervention_targets(x::Union{SetState, SetInitialCondition, ReplacePolicy, ReplaceParameter, ReplaceMechanism}) = Any[x.target]
_intervention_targets(::AbstractCausalIntervention) = Any[]

function _assert_no_simultaneous_conflict(values)
    seen = Any[]
    for intervention in values
        for target in _intervention_targets(intervention)
            target in seen && throw(InterventionConflict(
                "simultaneous interventions conflict on target $target"))
            push!(seen, target)
        end
    end
    return values
end

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

canonical_intervention(x::SetState) = _canonical_descriptor_fields(
    x.target, :constant, _canonical_literal(x.value), x.interval, x.scope, :deterministic, Symbol[])
canonical_intervention(x::SetInitialCondition) = _canonical_descriptor_fields(
    x.target, :initial_condition, _canonical_literal(x.value), :initial, x.scope, :deterministic, Symbol[])
canonical_intervention(x::ReplacePolicy) = _canonical_descriptor_fields(
    x.target, :policy, x.replacement_id, x.interval, x.scope, :deterministic, Symbol[])
canonical_intervention(x::ReplaceParameter) = _canonical_descriptor_fields(
    x.target, :parameter, x.replacement_id, :all, x.scope, :deterministic, Symbol[])
canonical_intervention(x::ReplaceMechanism) = _canonical_descriptor_fields(
    x.target, :rhs, x.replacement_id, x.interval, x.scope, :deterministic, Symbol[])
canonical_intervention(x::Simultaneous) = _canonical_fields((
    :simultaneous, map(canonical_intervention, x.interventions)...))
canonical_intervention(x::Sequential) = _canonical_fields((
    :sequential, map(canonical_intervention, x.interventions)...))

"""Whether occasion `t` lies in a typed intervention interval."""
function _in_interval(interval::Symbol, ::Int)
    interval === :all && return true
    throw(ArgumentError("unsupported intervention interval :$interval"))
end
_in_interval(interval::AbstractUnitRange, t::Int) = t in interval
_in_interval(interval::Integer, t::Int) = t == Int(interval)
_in_interval(interval, t::Int) = throw(ArgumentError("unsupported intervention interval $(interval) at t=$t"))

"""Evaluate a SetState payload at occasion `t`."""
function _setstate_value(value::AbstractVector, t::Int)
    t > length(value) && throw(ArgumentError(
        "SetState series has length $(length(value)) but t=$t was requested"))
    return value[t]
end
_setstate_value(value::Function, t::Int) = value(t)
_setstate_value(value, ::Int) = value

"""Return a stable SHA-256 identity for intervention semantics."""
intervention_fingerprint(intervention::AbstractTypedIntervention) = bytes2hex(sha256(canonical_intervention(intervention)))

export AbstractTypedIntervention, InterventionConflict, SetState, SetInitialCondition,
    ReplacePolicy, ReplaceParameter, ReplaceMechanism, Simultaneous, Sequential,
    intervention_kind, intervention_target, intervention_interval, canonical_intervention,
    intervention_fingerprint
