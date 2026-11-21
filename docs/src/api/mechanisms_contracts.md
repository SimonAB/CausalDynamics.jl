# Mechanisms, representations & contracts

Representation bridges, learned/symbolic mechanism libraries (including L3
abduction–action–prediction counterfactuals), typed intervention algebra, and
auditable provenance, abstraction, and structural constraint contracts.

## Representation bridges

```@docs
RepresentationSpec
representation_certificate
encode_to_panel
```

## Mechanisms and L3 counterfactuals

```@docs
MechanismSpec
MechanismLibrary
mechanism_library_from_cdm
register_mechanism!
mechanism_certificate
lux_mechanisms_available
attach_lux_mechanism!
build_ode_rhs
graphscm_with_mechanisms
train_mechanisms!
pack_parent_vector
abduce_noise
generate_from_noise
mechanism_counterfactual
```

## Typed interventions and descriptors

```@docs
InterventionDescriptor
intervention_descriptor
canonical_intervention_descriptor
compose_intervention_descriptors
ComposedIntervention
compose_intervention_bundle
SetState
SetInitialCondition
ReplacePolicy
ReplaceParameter
ReplaceMechanism
Simultaneous
Sequential
intervention_kind
intervention_target
intervention_interval
canonical_intervention
intervention_fingerprint
```

## Finite laws, provenance, abstraction and structural constraints

```@docs
FiniteLaw
pushforward
law_equal
law_distance
CDMProvenance
provenance_dict
provenance_fingerprint
certificate_schema_version
CertificateEnvelope
certificate_envelope
certificate_dict
CausalAbstractionSpec
CausalAbstractionResult
validate_abstraction
StructuralConstraintSpec
constraint_certificate
```

## Auditable intervention and abstraction declarations

[`InterventionDescriptor`](@ref) records a declared intervention's target,
replacement identifier, timing, scope, stochasticity, and cointerventions. It is
metadata, not a solver-backed SDE surgery. Scalar `DoIntervention` values are
recorded directly; policies and other functions require a caller-supplied stable
identifier before they can be fingerprinted.

`CDMProvenance` also accepts optional `estimand`, `identification`, `estimator`,
`positivity`, and `sensitivity` identifiers. These fields let an analysis
certificate record the query and its evidential qualifications alongside the
model semantics. They remain caller-supplied identifiers rather than hashes of
arbitrary executable code.

[`CausalAbstractionSpec`](@ref) compares finite interventional laws after
push-forward through the declared state map. `exact` means equality of the
laws as mass maps (support order does not matter); `accepted` is controlled by
`law_mode` and the declared tolerance.

## Structural constraint declarations

[`StructuralConstraintSpec`](@ref) records an auditable claim about an
invariance, feasibility condition, viability condition, or relation across
embodiments. It names the variables or mechanisms to which the claim applies,
the predicted consequences, and the identifiers of proposed tests. The
corresponding [`constraint_certificate`](@ref) is deterministic metadata, not
an empirical validation result.

These declarations deliberately remain outside the DAG and simulation
semantics. They do not add a causal parent, graph node, attractor, or agent.
Pair them with a [`MechanismLibrary`](@ref), a [`CausalAbstractionSpec`](@ref),
and typed intervention descriptors when the analysis supplies those artefacts.

[`SetState`](@ref) is the typed form of [`DoIntervention`](@ref) on a
[`GraphSCM`](@ref) and of a constant [`DoSequence`](@ref) on a
[`DiscreteTimeCDM`](@ref). [`ReplacePolicy`](@ref) is the auditable form of
[`Policy`](@ref) when a `rule` is supplied. [`apply_intervention`](@ref) on a
CDM bakes that surgery into `initialise` and `step`.
