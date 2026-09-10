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
_literal_intervention_id(value) = _canonical_literal(value)

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
    return _canonical_descriptor_fields(
        descriptor.target, descriptor.replacement, descriptor.replacement_id,
        descriptor.interval, descriptor.scope, descriptor.stochasticity,
        descriptor.cointerventions,
    )
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

"""
    ComposedIntervention(descriptors; mode=:simultaneous)

Audit container for a validated intervention composition. Executable algebra
uses `Simultaneous` and `Sequential`; this type records the same mode for
certificates. Simultaneous bundles still reject duplicate targets; sequential
bundles may repeat a target. The vector-returning
`compose_intervention_descriptors` function remains available.
"""
struct ComposedIntervention
    descriptors::Vector{InterventionDescriptor}
    mode::Symbol
end

function ComposedIntervention(
    descriptors::AbstractVector{<:InterventionDescriptor};
    mode::Symbol = :simultaneous,
)
    mode in (:simultaneous, :sequential) ||
        throw(ArgumentError("intervention composition mode must be :simultaneous or :sequential"))
    isempty(descriptors) && throw(ArgumentError("an intervention composition must not be empty"))
    validated = if mode === :simultaneous
        compose_intervention_descriptors(descriptors...)
    else
        collect(descriptors)
    end
    mode === :simultaneous && _check_intervention_intervals(validated)
    return ComposedIntervention(copy(validated), mode)
end

"""Encode a composed audit bundle, including sequential repeats on one target."""
function canonical_intervention_descriptor(bundle::ComposedIntervention)
    return _canonical_fields((
        bundle.mode, map(canonical_intervention_descriptor, bundle.descriptors)...))
end

"""Validate that simultaneous descriptors do not overlap on one target."""
function _check_intervention_intervals(descriptors)
    # Duplicate targets are already rejected.  This hook deliberately remains
    # conservative: interval-specific overlap rules belong to typed schedulers.
    return descriptors
end

"""Return a typed composition while retaining the legacy vector API."""
compose_intervention_bundle(descriptors::InterventionDescriptor...; mode::Symbol = :simultaneous) =
    ComposedIntervention(collect(descriptors); mode)

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

"""Return the audit descriptor for a typed state assignment."""
function intervention_descriptor(intervention::SetState)
    return InterventionDescriptor(
        intervention.target;
        replacement = :constant,
        replacement_id = _canonical_literal(intervention.value),
        interval = intervention.interval,
        scope = intervention.scope,
    )
end

function intervention_descriptor(intervention::SetInitialCondition)
    return InterventionDescriptor(
        intervention.target;
        replacement = :initial_condition,
        replacement_id = _canonical_literal(intervention.value),
        scope = intervention.scope,
    )
end

function intervention_descriptor(intervention::ReplacePolicy)
    return InterventionDescriptor(
        intervention.target;
        replacement = :policy,
        replacement_id = intervention.replacement_id,
        interval = intervention.interval,
        scope = intervention.scope,
    )
end

function intervention_descriptor(intervention::ReplaceParameter)
    return InterventionDescriptor(
        intervention.target;
        replacement = :parameter,
        replacement_id = intervention.replacement_id,
        scope = intervention.scope,
    )
end

function intervention_descriptor(intervention::ReplaceMechanism)
    return InterventionDescriptor(
        intervention.target;
        replacement = :rhs,
        replacement_id = intervention.replacement_id,
        interval = intervention.interval,
        scope = intervention.scope,
    )
end

function _as_descriptor_vector(intervention)
    descriptor = intervention_descriptor(intervention)
    descriptor isa InterventionDescriptor && return InterventionDescriptor[descriptor]
    descriptor isa AbstractVector && return InterventionDescriptor[descriptor...]
    descriptor isa ComposedIntervention && return copy(descriptor.descriptors)
    throw(ArgumentError("cannot encode $(typeof(intervention)) as an intervention descriptor"))
end

function intervention_descriptor(intervention::Simultaneous)
    return ComposedIntervention(
        reduce(vcat, _as_descriptor_vector.(intervention.interventions); init = InterventionDescriptor[]);
        mode = :simultaneous,
    )
end

function intervention_descriptor(intervention::Sequential)
    return ComposedIntervention(
        reduce(vcat, _as_descriptor_vector.(intervention.interventions); init = InterventionDescriptor[]);
        mode = :sequential,
    )
end

_provenance_intervention_id(intervention::InterventionDescriptor) =
    canonical_intervention_descriptor(intervention)

function _provenance_intervention_id(intervention::AbstractVector{<:InterventionDescriptor})
    descriptors = sort(canonical_intervention_descriptor.(intervention))
    return join(["$(ncodeunits(x)):$x" for x in descriptors], "")
end

_provenance_intervention_id(intervention::ComposedIntervention) =
    canonical_intervention_descriptor(intervention)

export InterventionDescriptor, intervention_descriptor, canonical_intervention_descriptor,
    compose_intervention_descriptors, ComposedIntervention, compose_intervention_bundle
