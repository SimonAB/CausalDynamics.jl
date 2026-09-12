"""Orthogonal variable, referent, and graph-kind declarations.

These records do not infer ontology from names, glyphs, or array size.
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

"""No finite window under the model’s declared clock, when that property is
stated separately from time invariance. Do not use this type to mean
“support unspecified”: leave support unspecified or declare it explicitly.
Time invariance of a value or mechanism is a distinct declaration, not an
alias of global support.
"""
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
    ReferentSpec(id; identity_criterion=nothing, ontological_character=:unspecified)

Declare what a variable concerns. Prefer placing `identity_criterion` and
optional `ontological_character` here so measurements of the same referent
share one declaration. `identity_criterion` is required only when continuity of
the referent matters to the argument. An unspecified ontology is not a
defective causal model.
"""
struct ReferentSpec
    id::Symbol
    identity_criterion::Union{Nothing, Symbol}
    ontological_character::Symbol

    function ReferentSpec(
        id::Symbol;
        identity_criterion::Union{Nothing, Symbol} = nothing,
        ontological_character::Symbol = :unspecified,
    )
        if identity_criterion !== nothing && identity_criterion ∉ IDENTITY_CRITERIA
            throw(ArgumentError(
                "identity_criterion must be one of $IDENTITY_CRITERIA, got :$identity_criterion",
            ))
        end
        return new(id, identity_criterion, normalise_ontological_character(ontological_character))
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
    parse_temporal_support(support; onset=nothing) -> TemporalSupport

Accept a typed support or a symbol shorthand (`:point`, `:pointwise`, `:global`).

`:interval` is refused: use [`IntervalSupport`](@ref) with an explicit window.
`:from_onset` is refused unless an explicit `onset` is supplied: the onset must
follow the mechanism (an attribute generated by a lag-one assignment from
`t = 0` has onset `1`; one present at baseline has onset `0`), so a symbol
alone does not name it. Prefer `FromOnsetSupport(t₀)`.
"""
function parse_temporal_support(support::TemporalSupport; onset = nothing)
    return support
end

function parse_temporal_support(support::Symbol; onset = nothing)
    support === :point && return PointwiseSupport()
    support === :pointwise && return PointwiseSupport()
    support === :interval && throw(ArgumentError(
        ":interval requires IntervalSupport(start, stop); a symbol does not name the window",
    ))
    if support === :from_onset
        onset === nothing && throw(ArgumentError(
            ":from_onset requires an explicit onset: use FromOnsetSupport(t₀) " *
            "(the onset follows the mechanism, not the indexing convention)",
        ))
        return FromOnsetSupport(Int(onset))
    end
    support === :global && return GlobalSupport()
    throw(ArgumentError(
        "temporal_support symbol must be :point, :from_onset (with onset), or :global, got :$support",
    ))
end

function parse_temporal_support(::Nothing; onset = nothing)
    return PointwiseSupport()
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
    InterventionJustification(kind, targets, note; source=nothing)

Recorded justification that licenses an otherwise-refused intervention. It is
an artefact for the certificate, not a switch: it names **what** is claimed
(`kind`), **for which targets**, and **why** (`note`), so the claim can be
audited and travels with the analysis.

Accepted `kind`s:

- macro-interventions on `:interval_summary` targets —
  `:trajectory_generator`, `:admissible_trajectory_distribution`,
  `:certificate_note`;
- `:feasibility` constraints — `:physical_justification`.

`note` must be non-empty. `source` may point to a document, protocol, or
certificate identifier.
"""
struct InterventionJustification
    kind::Symbol
    targets::Vector{Symbol}
    note::String
    source::Any

    function InterventionJustification(
        kind::Symbol,
        targets::AbstractVector{Symbol},
        note::AbstractString;
        source = nothing,
    )
        kind in JUSTIFICATION_KINDS || throw(ArgumentError(
            "justification kind must be one of $JUSTIFICATION_KINDS, got :$kind",
        ))
        isempty(strip(note)) && throw(ArgumentError(
            "justification note must state the reason; an empty note is not a justification",
        ))
        isempty(targets) && throw(ArgumentError(
            "justification must name at least one target variable",
        ))
        return new(kind, collect(Symbol, targets), String(note), source)
    end
end

const MACRO_INTERVENTION_JUSTIFICATION_KINDS = (
    :trajectory_generator,
    :admissible_trajectory_distribution,
    :certificate_note,
)
const FEASIBILITY_JUSTIFICATION_KINDS = (:physical_justification,)
const JUSTIFICATION_KINDS = (
    MACRO_INTERVENTION_JUSTIFICATION_KINDS..., FEASIBILITY_JUSTIFICATION_KINDS...,
)

"""Return `true` when `justification` covers `target` with one of `kinds`."""
function justifies(
    justification::Union{Nothing, InterventionJustification},
    target::Symbol,
    kinds,
)
    justification === nothing && return false
    return justification.kind in kinds && target in justification.targets
end

"""
    assert_interval_summary_do!(nodes, intervention; justification=nothing)

Refuse a scalar ``do(·)`` on an `:interval_summary` target unless
`justification` is an [`InterventionJustification`](@ref) of a
macro-intervention kind (`:trajectory_generator`,
`:admissible_trajectory_distribution`, or `:certificate_note`) that names that
target. A bare Boolean records nothing and is not accepted.
"""
function assert_interval_summary_do!(
    nodes,
    intervention;
    justification::Union{Nothing, InterventionJustification} = nothing,
)
    by_name = Dict(n.name => n for n in nodes)
    for target in intervention_targets(intervention)
        spec = get(by_name, target, nothing)
        spec === nothing && continue
        spec.value_representation === :interval_summary || continue
        justifies(justification, target, MACRO_INTERVENTION_JUSTIFICATION_KINDS) && continue
        throw(ArgumentError(
            "scalar do(·) on interval_summary :$target is refused; " *
            "supply a trajectory-generating intervention, a distribution over " *
            "admissible trajectories, or an InterventionJustification naming " *
            ":$target with kind :trajectory_generator, " *
            ":admissible_trajectory_distribution, or :certificate_note",
        ))
    end
    return nothing
end

export InterventionJustification, justifies
export MACRO_INTERVENTION_JUSTIFICATION_KINDS, FEASIBILITY_JUSTIFICATION_KINDS, JUSTIFICATION_KINDS
export TemporalSupport, PointwiseSupport, PointSupport, IntervalSupport
export FromOnsetSupport, GlobalSupport
export GraphKind, TimeUnrolledGraph, ProcessGraph, SemanticGraph
export ReferentSpec, ObservationSemantics
export VALUE_REPRESENTATIONS, RELATION_KINDS, IDENTIFICATION_STATUSES
export expands_pointwise, is_single_node_support, parse_temporal_support
export normalise_value_representation, normalise_relation_kind, normalise_ontological_character
export semantic_fingerprint
export intervention_targets, assert_interval_summary_do!
