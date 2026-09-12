"""Orthogonal variable, referent, and graph-kind declarations.

These records do not infer ontology from names, glyphs, or array size.
`temporal_mode` is a deprecated constructor alias only.
"""

"""Abstract temporal extent of the value represented by a node."""
abstract type TemporalSupport end

"""Point-supported value at each discrete ``t ∈ 𝒯`` (default unrolling)."""
struct PointwiseSupport <: TemporalSupport end

"""The value represents ``X(t)`` at one declared time."""
struct PointSupport{T} <: TemporalSupport
    time::T
end

"""The value represents a quantity over ``[start, stop]``."""
struct IntervalSupport{T} <: TemporalSupport
    start::T
    stop::T
end

"""The value applies from an explicitly declared onset."""
struct FromOnsetSupport{T} <: TemporalSupport
    onset::T
end

"""No finite window, or treated as time-invariant within the model."""
struct GlobalSupport <: TemporalSupport end

"""Allowed `value_representation` symbols (plus aliases normalised elsewhere)."""
const VALUE_REPRESENTATIONS = (
    :state, :event, :event_indicator, :trajectory, :interval_summary, :attribute, :unspecified,
)

const IDENTITY_CRITERIA = (
    :causal_inheritance, :lineage, :organisational_continuity, :administrative_identifier,
)

const ONTOLOGICAL_CHARACTERS = (:occasion, :enduring, :unspecified)

"""Allowed `LaggedEdge.relation_kind` symbols."""
const RELATION_KINDS = (
    :causal_influence,
    :constitutive_persistence,
    :constitutive_dependence,
    :participation,
    :measurement,
    :temporal_precedence,
    :identity_succession,
)

"""Claim strength labels for certificates and structural constraints."""
const CLAIM_KINDS = (
    :declared_assumption,
    :structurally_validated,
    :identified_under_assumptions,
    :numerically_checked,
    :empirically_assessed,
)

"""Identification outcome labels on `IdentificationResult`."""
const IDENTIFICATION_STATUSES = (
    :identified,
    :not_identified_by_procedure,
    :unsupported_model_class,
    :proved_nonidentifiable,
)

"""Abstract graph representation class for identification validity."""
abstract type GraphKind end

"""Time-unrolled causal DAG; nodes indexed by temporal support."""
struct TimeUnrolledGraph <: GraphKind end

"""Process-level graph; DAG adjustment does not transfer automatically."""
struct ProcessGraph <: GraphKind end

"""Broader semantic diagram; may mix non-causal relations."""
struct SemanticGraph <: GraphKind end

"""
    ReferentSpec(id; identity_criterion=nothing)

Declare what a variable concerns. `identity_criterion` is required only when
the model claims identity across time.
"""
struct ReferentSpec
    id::Symbol
    identity_criterion::Union{Nothing, Symbol}

    function ReferentSpec(id::Symbol; identity_criterion::Union{Nothing, Symbol} = nothing)
        if identity_criterion !== nothing && identity_criterion ∉ IDENTITY_CRITERIA
            throw(ArgumentError(
                "identity_criterion must be one of $IDENTITY_CRITERIA, got :$identity_criterion",
            ))
        end
        return new(id, identity_criterion)
    end
end

"""
    ObservationSemantics(; realisation, sampling_interval, aggregation_window, measurement, availability)

Separate when a quantity is realised, sampled, summarised, measured, and
available to a decision-maker.
"""
struct ObservationSemantics
    realisation::Any
    sampling_interval::Any
    aggregation_window::Any
    measurement::Any
    availability::Any
end

function ObservationSemantics(;
    realisation = nothing,
    sampling_interval = nothing,
    aggregation_window = nothing,
    measurement = nothing,
    availability = nothing,
)
    return ObservationSemantics(
        realisation, sampling_interval, aggregation_window, measurement, availability,
    )
end

"""Normalise glossary value-type aliases onto `value_representation`."""
function normalise_value_representation(value::Symbol)
    value === :event_indicator && return :event
    value === :point_state && return :state
    value === :summary && return :interval_summary
    value in VALUE_REPRESENTATIONS || throw(ArgumentError(
        "value_representation must be one of $VALUE_REPRESENTATIONS, got :$value",
    ))
    return value
end

"""Normalise edge relation kinds; `:constitutive` → `:constitutive_persistence`."""
function normalise_relation_kind(kind::Symbol)
    kind === :constitutive && return :constitutive_persistence
    kind in RELATION_KINDS || throw(ArgumentError(
        "relation_kind must be one of $RELATION_KINDS, got :$kind",
    ))
    return kind
end

"""Validate optional `ontological_character` metadata."""
function normalise_ontological_character(character::Symbol)
    character in ONTOLOGICAL_CHARACTERS || throw(ArgumentError(
        "ontological_character must be one of $ONTOLOGICAL_CHARACTERS, got :$character",
    ))
    return character
end

"""Return whether unrolling emits one node per discrete time."""
expands_pointwise(::PointwiseSupport) = true
expands_pointwise(::TemporalSupport) = false

"""Return whether the support contributes a single reused graph node."""
is_single_node_support(support::TemporalSupport) = !expands_pointwise(support)

"""
    parse_temporal_support(support; onset=0) -> TemporalSupport

Accept a typed support or a symbol shorthand (`:point`, `:from_onset`, `:global`).
`:interval` is refused: use [`IntervalSupport`](@ref) with an explicit window.
"""
function parse_temporal_support(support::TemporalSupport; onset = 0)
    return support
end

function parse_temporal_support(support::Symbol; onset = 0)
    support === :point && return PointwiseSupport()
    support === :pointwise && return PointwiseSupport()
    support === :interval && throw(ArgumentError(
        ":interval requires IntervalSupport(start, stop); a symbol does not name the window",
    ))
    support === :from_onset && return FromOnsetSupport(onset)
    support === :global && return GlobalSupport()
    throw(ArgumentError(
        "temporal_support symbol must be :point, :from_onset, or :global, got :$support",
    ))
end

function parse_temporal_support(::Nothing; onset = 0)
    return PointwiseSupport()
end

"""Map deprecated `temporal_mode` onto support without setting ontology."""
function support_from_temporal_mode(mode::Symbol, onset::Integer)
    mode === :occasion && return PointwiseSupport()
    mode === :enduring && return FromOnsetSupport(Int(onset))
    throw(ArgumentError("temporal_mode must be :occasion or :enduring, got :$mode"))
end

"""Deprecated compatibility flag derived from support (not ontology)."""
function legacy_temporal_mode(support::TemporalSupport)
    return expands_pointwise(support) ? :occasion : :enduring
end

function onset_from_support(support::TemporalSupport, fallback::Integer)
    support isa FromOnsetSupport && return Int(support.onset)
    support isa PointSupport && return Int(support.time)
    return Int(fallback)
end

"""
    semantic_fingerprint(parts...) -> UInt64

Stable digest of declared meanings. Distinct from [`graph_fingerprint`](@ref).
"""
function semantic_fingerprint(parts...)
    return stable_hash64(string(parts))
end

"""
    require_semantics(op, specs; error=false)

Warn (or error) when gated operations lack declared support / representation.
"""
function require_semantics(op::Symbol, specs; error::Bool = false)
    missing = Symbol[]
    for spec in specs
        if spec.temporal_support isa PointwiseSupport &&
           spec.value_representation === :unspecified &&
           op in (:interval_intervention, :identity, :mixed_relation)
            push!(missing, spec.name)
        end
        if spec.value_representation === :interval_summary && op === :interval_intervention
            # interval summary is declared; nothing missing
        end
    end
    isempty(missing) && return nothing
    msg = "operation :$op requires temporal_support / value_representation for $(missing)"
    error ? throw(ArgumentError(msg)) : @warn msg
    return missing
end

"""Collect intervention target symbols from common intervention types."""
function intervention_targets(intervention)
    intervention === nothing && return Symbol[]
    if hasproperty(intervention, :values) && intervention.values isa AbstractDict
        return sort!(collect(Symbol, keys(intervention.values)))
    end
    if hasproperty(intervention, :rules) && intervention.rules isa AbstractDict
        return sort!(collect(Symbol, keys(intervention.rules)))
    end
    if hasproperty(intervention, :variable)
        v = intervention.variable
        return v isa Symbol ? Symbol[v] : Symbol[]
    end
    if hasproperty(intervention, :target)
        v = intervention.target
        return v isa Symbol ? Symbol[v] : Symbol[]
    end
    if hasproperty(intervention, :interventions)
        return sort!(unique(vcat(intervention_targets.(intervention.interventions)...)))
    end
    return Symbol[]
end

"""
    assert_interval_summary_do!(nodes, intervention; justified=false)

Refuse a scalar ``do(·)`` on an `:interval_summary` unless the caller records an
explicit macro-intervention justification (trajectory generator, distribution
over admissible trajectories, or certificate note).
"""
function assert_interval_summary_do!(
    nodes,
    intervention;
    justified::Bool = false,
)
    justified && return nothing
    by_name = Dict(n.name => n for n in nodes)
    for target in intervention_targets(intervention)
        spec = get(by_name, target, nothing)
        spec === nothing && continue
        if spec.value_representation === :interval_summary
            throw(ArgumentError(
                "scalar do(·) on interval_summary :$target is refused; " *
                "supply a trajectory-generating intervention, a distribution over " *
                "admissible trajectories, or set macro_intervention_justified=true " *
                "when the certificate records that justification",
            ))
        end
    end
    return nothing
end

export TemporalSupport, PointwiseSupport, PointSupport, IntervalSupport
export FromOnsetSupport, GlobalSupport
export GraphKind, TimeUnrolledGraph, ProcessGraph, SemanticGraph
export ReferentSpec, ObservationSemantics
export VALUE_REPRESENTATIONS, RELATION_KINDS, CLAIM_KINDS, IDENTIFICATION_STATUSES
export expands_pointwise, is_single_node_support, parse_temporal_support
export support_from_temporal_mode, legacy_temporal_mode
export normalise_value_representation, normalise_relation_kind, normalise_ontological_character
export semantic_fingerprint, require_semantics
export intervention_targets, assert_interval_summary_do!
