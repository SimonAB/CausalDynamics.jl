"""Typed, serialisable semantics shared by CDM intervention implementations."""

"""
    InterventionDescriptor(target; replacement, replacement_id, interval, scope,
        stochasticity, cointerventions=Symbol[])

Auditable description of an intervention. The descriptor records semantics without
serialising executable replacement functions. `replacement_id` is a required stable
identifier for a functional replacement; scalar replacements receive a canonical
literal identifier. Callers must supply versioned identifiers for functions.
"""
struct InterventionDescriptor{I}
    target::Union{Int, Symbol}
    replacement::Symbol
    replacement_id::String
    interval::I
    scope::Symbol
    stochasticity::Symbol
    cointerventions::Vector{Symbol}
end

function InterventionDescriptor(
    target::Union{Int, Symbol};
    replacement::Symbol = :assignment,
    replacement_id::AbstractString = "",
    interval = :all,
    scope::Symbol = :unit,
    stochasticity::Symbol = :deterministic,
    cointerventions::AbstractVector{Symbol} = Symbol[],
)
    if replacement in (:policy, :rhs, :time_indexed, :topology, :model_class,
                       :measurement, :environment) && isempty(replacement_id)
        throw(ArgumentError("functional replacement $replacement requires a stable replacement_id"))
    end
    return InterventionDescriptor(
        target, replacement, String(replacement_id), interval, scope, stochasticity,
        collect(cointerventions),
    )
end

"""Return an auditable descriptor for a static SCM intervention."""
function intervention_descriptor(intervention::DoIntervention)
    return InterventionDescriptor(
        intervention.variable;
        replacement = :constant,
        replacement_id = _literal_intervention_id(intervention.value),
    )
end

"""Return a stable literal identifier for a scalar or immutable replacement value."""
_literal_intervention_id(value) = repr(value)

"""Return one descriptor for each assignment in a discrete-time `do` sequence."""
function intervention_descriptor(intervention::DoSequence; replacement_ids::AbstractDict = Dict{Symbol, String}())
    return [InterventionDescriptor(
        v;
        replacement = :time_indexed,
        replacement_id = _assignment_id(intervention.values[v], get(replacement_ids, v, nothing)),
    ) for v in sort!(collect(keys(intervention.values)))]
end

_assignment_id(assignment::ConstantAssignment, _) = _literal_intervention_id(assignment.value)
_assignment_id(assignment::SeriesAssignment, _) = _literal_intervention_id(assignment.values)
function _assignment_id(assignment::TimedAssignment, stable_id)
    stable_id isa AbstractString && !isempty(stable_id) ||
        throw(ArgumentError("TimedAssignment requires an explicit stable replacement_id"))
    return String(stable_id)
end

"""Return one descriptor for each endogenous variable governed by a policy regime."""
function intervention_descriptor(intervention::Policy; replacement_ids::AbstractDict = Dict{Symbol, String}())
    return [InterventionDescriptor(
        v;
        replacement = :policy,
        replacement_id = _required_stable_id(replacement_ids, v, :policy),
    ) for v in sort!(collect(keys(intervention.rules)))]
end

function _required_stable_id(ids::AbstractDict, target, replacement::Symbol)
    id = get(ids, target, nothing)
    id isa AbstractString && !isempty(id) ||
        throw(ArgumentError("$replacement replacement for $target requires a stable replacement_id"))
    return String(id)
end

"""
    canonical_intervention_descriptor(descriptor) -> String

Return an unambiguous, length-prefixed encoding of a declared intervention. This
encodes metadata only; it does not serialise or fingerprint arbitrary Julia
functions. Use an explicit versioned `replacement_id` for functional policies.
"""
function canonical_intervention_descriptor(descriptor::InterventionDescriptor)
    fields = (
        string(descriptor.target), string(descriptor.replacement), descriptor.replacement_id,
        repr(descriptor.interval), string(descriptor.scope), string(descriptor.stochasticity),
        join(["$(ncodeunits(string(x))):$(x)" for x in sort(descriptor.cointerventions)], "|"),
    )
    return join(["$(ncodeunits(field)):$field" for field in fields], "|")
end

"""
    compose_intervention_descriptors(descriptors...) -> Vector{InterventionDescriptor}

Validate a simultaneous declaration. Each target may occur at most once; this
operation represents simultaneous declarations and does not model sequencing.
"""
function compose_intervention_descriptors(descriptors::InterventionDescriptor...)
    targets = getfield.(descriptors, :target)
    length(unique(targets)) == length(targets) ||
        throw(ArgumentError("a composed intervention may not assign one target twice"))
    return collect(descriptors)
end

function intervention_descriptor(intervention::DoPin)
    return InterventionDescriptor(intervention.variable;
        replacement = :pin, replacement_id = _literal_intervention_id(intervention.value),
        scope = :coordinate)
end

function intervention_descriptor(intervention::DoInitialCondition)
    return InterventionDescriptor(intervention.variable;
        replacement = :initial_condition, replacement_id = _literal_intervention_id(intervention.value),
        scope = :coordinate)
end

function intervention_descriptor(intervention::DoForce)
    return InterventionDescriptor(intervention.variable;
        replacement = :force,
        replacement_id = _literal_intervention_id((intervention.target, intervention.κ)),
        scope = :coordinate)
end

function intervention_descriptor(intervention::DoRhs; replacement_id = nothing)
    replacement_id isa AbstractString && !isempty(replacement_id) ||
        throw(ArgumentError("RHS replacement requires a stable replacement_id"))
    return InterventionDescriptor(intervention.variable;
        replacement = :rhs, replacement_id = replacement_id, scope = :coordinate)
end

function intervention_descriptor(interventions::ContinuousInterventionSet; replacement_ids::AbstractDict = Dict())
    descriptors = InterventionDescriptor[]
    for item in interventions.interventions
        descriptor = item isa DoRhs ? intervention_descriptor(item;
            replacement_id = _required_stable_id(replacement_ids, item.variable, :rhs)) :
            intervention_descriptor(item)
        descriptor isa AbstractVector ? append!(descriptors, descriptor) : push!(descriptors, descriptor)
    end
    return descriptors
end

export InterventionDescriptor, intervention_descriptor, canonical_intervention_descriptor,
    compose_intervention_descriptors
