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
    )
end

export StructuralConstraintSpec, constraint_certificate
