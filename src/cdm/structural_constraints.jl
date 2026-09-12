"""Declarative, auditable statements about structural constraints on a model."""

const STRUCTURAL_CONSTRAINT_KINDS = (
    :invariance,
    :feasibility,
    :viability,
    :cross_embodiment,
)

"""
    StructuralConstraintSpec(id, targets; kind, claim, predictions = Symbol[],
        test_ids = Symbol[], embodiments = Symbol[])

Declare a structural claim that constrains a model's admissible states,
transformations, or embodiments. `kind` must be one of `:invariance`,
`:feasibility`, `:viability`, or `:cross_embodiment`.

The declaration records a claim, its named targets, and the predictions and
tests through which a caller intends to assess it. It is metadata: it neither
adds a causal parent or graph node, nor executes a test or numerical solver.
Use it alongside a `MechanismLibrary`, `CausalAbstractionSpec`, and explicit
intervention descriptors when those corresponding artefacts are available.
"""
struct StructuralConstraintSpec
    id::Symbol
    targets::Vector{Symbol}
    kind::Symbol
    claim::String
    predictions::Vector{Symbol}
    test_ids::Vector{Symbol}
    embodiments::Vector{Symbol}

    function StructuralConstraintSpec(
        id::Symbol,
        targets::Vector{Symbol},
        kind::Symbol,
        claim::String,
        predictions::Vector{Symbol},
        test_ids::Vector{Symbol},
        embodiments::Vector{Symbol},
    )
        isempty(String(id)) && throw(ArgumentError("structural constraint id must not be empty"))
        isempty(targets) && throw(ArgumentError("structural constraint targets must not be empty"))
        kind in STRUCTURAL_CONSTRAINT_KINDS || throw(ArgumentError(
            "structural constraint kind must be one of $(STRUCTURAL_CONSTRAINT_KINDS)"))
        isempty(strip(claim)) && throw(ArgumentError("structural constraint claim must not be blank"))
        _require_unique_constraint_symbols(targets, "targets")
        _require_unique_constraint_symbols(predictions, "predictions")
        _require_unique_constraint_symbols(test_ids, "test_ids")
        _require_unique_constraint_symbols(embodiments, "embodiments")
        return new(id, targets, kind, claim, predictions, test_ids, embodiments)
    end
end

"""Require that a constraint field does not repeat symbolic identifiers."""
function _require_unique_constraint_symbols(values::Vector{Symbol}, field_name::AbstractString)
    length(unique(values)) == length(values) || throw(ArgumentError(
        "structural constraint $field_name must not contain duplicates"))
    return nothing
end

function StructuralConstraintSpec(
    id::Symbol,
    targets::AbstractVector{Symbol};
    kind::Symbol = :invariance,
    claim::AbstractString,
    predictions::AbstractVector{Symbol} = Symbol[],
    test_ids::AbstractVector{Symbol} = Symbol[],
    embodiments::AbstractVector{Symbol} = Symbol[],
)
    return StructuralConstraintSpec(
        id,
        collect(targets),
        kind,
        String(claim),
        collect(predictions),
        collect(test_ids),
        collect(embodiments),
    )
end

"""
    constraint_certificate(spec) -> NamedTuple

Return a deterministic, serialisable record of a declared structural
constraint. The fingerprint identifies the declaration's content; it is not
evidence that the claim has been empirically confirmed.
"""
function constraint_certificate(spec::StructuralConstraintSpec)
    canonical = _canonical_fields((
        string(spec.id),
        string(spec.kind),
        join(string.(spec.targets), ","),
        spec.claim,
        join(string.(spec.predictions), ","),
        join(string.(spec.test_ids), ","),
        join(string.(spec.embodiments), ","),
    ))
    return (
        id = spec.id,
        kind = spec.kind,
        targets = copy(spec.targets),
        claim = spec.claim,
        predictions = copy(spec.predictions),
        test_ids = copy(spec.test_ids),
        embodiments = copy(spec.embodiments),
        fingerprint = stable_hash64(canonical),
        claim_kind = :declared_assumption,
    )
end

"""
    assert_feasibility!(constraints, intervention; justification=nothing)

Wire `:feasibility` [`StructuralConstraintSpec`](@ref)s into intervention
gates. Mathematical admissibility and practical availability are separate;
positivity is none of these. An intervention on a constrained target passes
only when `justification` is an [`InterventionJustification`](@ref) of kind
`:physical_justification` naming that target. The deprecated `justified::Bool`
bypass is refused.
"""
function assert_feasibility!(
    constraints,
    intervention;
    justification::Union{Nothing, InterventionJustification} = nothing,
    justified::Union{Nothing, Bool} = nothing,
)
    justified === true && _refuse_boolean_justification("assert_feasibility!", "justified")
    targets = Set(intervention_targets(intervention))
    isempty(targets) && return nothing
    for spec in constraints
        spec.kind === :feasibility || continue
        hit = [t for t in spec.targets if t in targets]
        isempty(hit) && continue
        unjustified = [t for t in hit if !justifies(justification, t, FEASIBILITY_JUSTIFICATION_KINDS)]
        isempty(unjustified) && continue
        throw(ArgumentError(
            "feasibility constraint :$(spec.id) blocks intervention on $unjustified " *
            "without physical justification; pass an InterventionJustification of kind " *
            ":physical_justification naming those targets. Claim: $(spec.claim)",
        ))
    end
    return nothing
end

"""
    validate_intervention_semantics(nodes, intervention; constraints, kwargs...)

Combined P0 gate: interval-summary scalar ``do`` refusal and feasibility
constraints. Call from simulate/identify paths that carry a temporal spec.
Justifications are [`InterventionJustification`](@ref) records
(`macro_intervention_justification`, `feasibility_justification`); the
deprecated Boolean `*_justified` switches are refused.
"""
function validate_intervention_semantics(
    nodes,
    intervention;
    constraints = StructuralConstraintSpec[],
    macro_intervention_justification::Union{Nothing, InterventionJustification} = nothing,
    feasibility_justification::Union{Nothing, InterventionJustification} = nothing,
    macro_intervention_justified::Union{Nothing, Bool} = nothing,
    feasibility_justified::Union{Nothing, Bool} = nothing,
)
    macro_intervention_justified === true && _refuse_boolean_justification(
        "validate_intervention_semantics", "macro_intervention_justified",
    )
    feasibility_justified === true && _refuse_boolean_justification(
        "validate_intervention_semantics", "feasibility_justified",
    )
    assert_interval_summary_do!(
        nodes, intervention; justification = macro_intervention_justification,
    )
    assert_feasibility!(
        constraints, intervention; justification = feasibility_justification,
    )
    return nothing
end

export StructuralConstraintSpec, constraint_certificate
export assert_feasibility!, validate_intervention_semantics
