# Terminology

Identification and estimation keep Pearl and SciML names (`DoIntervention`,
`backdoor_adjustment_set`, `d_separated`, `Policy`, …). Those exports are not
renamed.

**Temporal identity** may use a closed lexicon when the words name distinct
objects on existing types (`TemporalNodeSpec`, `LaggedEdge` roles, `Policy`,
`onset_time`). Whitehead glossary terms (prehension, creative advance,
concrescence, superject) belong in the
[CDCS book Concept Reference](https://simonab.github.io/causal-dynamics-book/concept-reference-tables.html),
not in this manual.

| Term | Meaning in this package |
|------|-------------------------|
| **Occasion** | One node per observation step (`temporal_mode = :occasion`) |
| **Enduring** | One node per entity across the horizon (`temporal_mode = :enduring`) |
| **Onset** | Time at which an enduring node is constituted (`onset_time`) |
| **Constitution / constitutive** | Assignment into persistence; `temporal_edge_role` `:constitutive` |
| **Influence** | Later use of an enduring node, or occasion-to-occasion dependence |
| **Replacement** | Successor enduring instance after a realised prefix (not in-place overwrite) |
| **Deployment** | Where, when, and to whom a constituted policy applies; not the rule \(d(\cdot)\) itself |

Replacement and deployment are lexicon for identity and applicability. They are
not a second intervention algebra beside `DoSequence` and `Policy`.
