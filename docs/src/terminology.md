# Terminology

Identification and estimation keep Pearl and SciML names (`DoIntervention`,
`backdoor_adjustment_set`, `d_separated`, `Policy`, …). Those exports are not
renamed.

**Temporal declarations** attach to existing types (`TemporalNodeSpec`,
`LaggedEdge`, `TemporalDAGSpec`, `Policy`). Whitehead glossary terms
(prehension, creative advance, concrescence, superject) belong in the
[CDCS book Concept Reference](https://simonab.github.io/causal-dynamics-book/concept-reference-tables.html),
not in this manual.

| Term | Meaning in this package |
|------|-------------------------|
| **`temporal_support`** | Temporal extent of the value a node represents (`PointwiseSupport`, `PointSupport`, `IntervalSupport`, `FromOnsetSupport`, `GlobalSupport`) |
| **`value_representation`** | How the value represents its referent (`:state`, `:event`, `:trajectory`, `:interval_summary`, `:attribute`) |
| **`referent_id` / `ReferentSpec`** | What entity or organisation the variable concerns |
| **`identity_criterion`** | Why manifestations count as the same referent (required only when endurance is claimed) |
| **`graph_kind`** | `TimeUnrolledGraph`, `ProcessGraph`, or `SemanticGraph` |
| **`ontological_character`** | Optional metadata (`:occasion`, `:enduring`); never selects how many nodes are created |
| **`relation_kind`** | Declared edge semantics (`:causal_influence`, `:constitutive_persistence`, …) |
| **Onset** | Constitution time for `FromOnsetSupport` (`onset_time`) |
| **Replacement / deployment** | Successor instance / policy applicability; not a second intervention algebra |

Deprecated: `temporal_mode = :occasion | :enduring` maps to `PointwiseSupport` or
`FromOnsetSupport` and does **not** set `ontological_character`. Prefer
`temporal_support` and `graph_kind` as the source of truth for unrolling.
