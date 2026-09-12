# Terminology

Identification and estimation keep Pearl and SciML names (`DoIntervention`,
`backdoor_adjustment_set`, `d_separated`, `Policy`, …). Those exports are not
renamed.

**Temporal declarations** attach to existing types (`TemporalNodeSpec`,
`LaggedEdge`, `TemporalDAGSpec`, `Policy`, `ObservationBridge`). Whitehead
glossary terms (prehension, creative advance, concrescence, superject) belong
in the
[CDCS book Concept Reference](https://simonab.github.io/causal-dynamics-book/concept-reference-tables.html),
not in this manual.

| Term | Meaning in this package |
|------|-------------------------|
| **`temporal_support`** | Temporal extent of the value a node represents (`PointwiseSupport`, `PointSupport`, `IntervalSupport`, `FromOnsetSupport`, `GlobalSupport`). `GlobalSupport` is not a stand-in for unspecified support or for time invariance of a mechanism. |
| **`value_representation`** | How the value represents its referent (`:state`, `:event`, `:trajectory`, `:interval_summary`, `:attribute`); glossary “value type” |
| **`referent_id` / `ReferentSpec`** | What entity or organisation the variable concerns; prefer `identity_criterion` and optional `ontological_character` on the referent |
| **`identity_criterion`** | Why manifestations count as the same referent (required only when continuity matters to the argument) |
| **`graph_kind`** | `TimeUnrolledGraph`, `ProcessGraph`, or `SemanticGraph` |
| **`ontological_character`** | Optional metadata (`:occasion`, `:enduring`); declare mainly on `ReferentSpec`; never selects how many nodes are created |
| **`relation_kind`** | Declared edge semantics (`:causal_influence`, `:constitutive_persistence`, `:constitutive_dependence`, `:participation`, …); the sole input to `causal_projection` |
| **Edge role** (`temporal_edge_role`) | Declared non-causal `relation_kind` if present; otherwise a construction label (`:onset_assignment`, `:recurrent_influence`, `:pointwise_influence`, `:causal_influence`) describing which supports an edge joins. Roles are descriptive; they never change causal membership |
| **`information_set` / availability** | Policy ``ℋ_t`` and `ObservationBridge.availability`: when a quantity may be used at decision time. A `Policy` may take the bridge itself as its `information_set`, so ``ℋ_t`` is derived from declared availability rather than restated |
| **`InterventionJustification`** | Recorded reason (`kind`, `targets`, `note`) that licenses a scalar ``do`` on an `:interval_summary` or an intervention against a `:feasibility` constraint; Boolean bypasses are refused |
| **`semantic_fingerprint`** | Digest of declared meanings; distinct from `graph_fingerprint` |
| **Onset** | Explicit constitution time in `FromOnsetSupport(t₀)`; must follow the mechanism (not Julia array indexing, and not an implicit package default) |
| **Replacement / deployment** | Successor instance / policy applicability; not a second intervention algebra |

**Governing rule:** declare what each variable represents and its support; construct
nodes from those declarations and `graph_kind`; never derive ontology from
construction or appearance. Node multiplicity follows `temporal_support` and
`graph_kind`; referent identity follows `referent_id`. Identification uses
[`causal_projection`](@ref). Scalar ``do`` on `:interval_summary` and
`:feasibility` constraints are gated by
[`validate_intervention_semantics`](@ref).
