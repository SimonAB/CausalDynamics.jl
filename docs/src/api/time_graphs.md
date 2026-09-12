# Time-indexed graphs

Discrete-time CDMs often share a **time-invariant lag structure**. Unroll that
structure to a static DAG over times `t = 0:T` under a
[`TimeUnrolledGraph`](@ref), then apply standard identification on the
**causal projection**. Node multiplicity follows [`temporal_support`](@ref TemporalSupport)
and [`graph_kind`](@ref GraphKind), not `ontological_character`. Single-node
supports (`FromOnsetSupport`, `GlobalSupport`, …) keep one reused node that may
be assigned at an explicit onset.

```@docs
TemporalSupport
PointwiseSupport
PointSupport
IntervalSupport
FromOnsetSupport
GlobalSupport
GraphKind
TimeUnrolledGraph
ProcessGraph
SemanticGraph
ReferentSpec
LaggedEdge
TemporalNodeSpec
TemporalDAGSpec
TemporalUnrolling
unroll_temporal_dag
temporal_node
enduring_node
temporal_node_label
is_single_node
temporal_edge_role
temporal_edge_records
causal_projection
d_separated_temporal
temporal_backdoor_adjustment_set
temporal_backdoor_adjustment_nodes
semantic_fingerprint
validate_intervention_semantics
assert_interval_summary_do!
assert_feasibility!
InterventionJustification
justifies
intervention_targets
ObservationSemantics
expands_pointwise
is_single_node_support
normalise_value_representation
normalise_relation_kind
normalise_ontological_character
parse_temporal_support
VALUE_REPRESENTATIONS
RELATION_KINDS
IDENTIFICATION_STATUSES
```

## Single-node attributes from onset

Typed support decides node count. A pasture assignment that persists from
onset uses `FromOnsetSupport` (and usually `value_representation = :attribute`).
Identity and ontology, when claimed, live on a shared [`ReferentSpec`](@ref)
and never change node count.

```@example time-graphs-enduring
using CausalDynamics, Graphs

sheep = ReferentSpec(:sheep; identity_criterion = :administrative_identifier)
spec = TemporalDAGSpec(
    entity = :sheep,
    nodes = [
        TemporalNodeSpec(:diagnosis; value_representation = :state, referent = sheep),
        TemporalNodeSpec(
            :pasture;
            temporal_support = FromOnsetSupport(1),
            value_representation = :attribute,
            causal_role = :assigned,
            referent = sheep,
        ),
        TemporalNodeSpec(:weight; value_representation = :state, referent = sheep),
    ],
    edges = [
        (:diagnosis, :pasture, 1),
        (:pasture, :weight, 0),
        (:weight, :weight, 1),
    ],
)
u = unroll_temporal_dag(spec, 2)
nv(u.graph), temporal_node_label(u, enduring_node(u, :pasture))
```

Panel mapping follows support: single-node variables keep their bare column
symbol; pointwise variables use `panel_column_name`. Prefer declaring
`temporal_support` on the DAG rather than a downstream `unit_level` override.
The symbol shorthand `:from_onset` is refused without an onset; write
`FromOnsetSupport(t₀)`.

The unrolled graph retains edge provenance. Use `temporal_edge_role` for one
edge and `temporal_edge_records` for an auditable inventory. For edges declared
with a `relation_kind` other than `:causal_influence` the role **is** that
declared kind. For causal-influence edges the role is a construction-pattern
label only: `:onset_assignment` (pointwise → single-node), `:recurrent_influence`
(single-node → pointwise), `:pointwise_influence` (pointwise → pointwise), or
`:causal_influence` (single-node → single-node). Support patterns never make an
edge constitutive: a diagnosis assigning a subsequently maintained treatment is
a causal parent of that treatment.

[`causal_projection`](@ref) keeps every edge declared `:causal_influence` and
records every other declared kind (`:constitutive_persistence`,
`:constitutive_dependence`, `:participation`, `:measurement`, …) as a
constraint. Constitution therefore has to be declared; it is never inferred
from node multiplicity.

```@example time-graphs-enduring
proj = causal_projection(u)
ne(proj.graph), length(proj.constraints)
```

```@example time-graphs-enduring
records = temporal_edge_records(u)
filter(record -> record.role === :onset_assignment, records)
```

## Plotting an unrolling

With [DAGMakie.jl](https://simonab.github.io/DAGMakie.jl) loaded,
[`DAGMakie.dagplot_temporal`](https://simonab.github.io/DAGMakie.jl/stable/)
places times left→right and variables as rows. Markers follow
`value_representation`: only `:interval_summary` uses a rounded rectangle under
the package convention. From-onset attributes and pointwise states remain
circles unless you pass an explicit `node_marker`. Shape does not encode
enduring identity. The CausalDynamics extension adds a `TemporalUnrolling`
method automatically.

```@example time-graphs-plot
using CausalDynamics, DAGMakie, CairoMakie

spec = TemporalDAGSpec(
    nodes = [
        TemporalNodeSpec(:x; value_representation = :state),
        TemporalNodeSpec(:y; value_representation = :state),
    ],
    edges = [(:x, :x, 1), (:y, :y, 1), (:x, :y, 1)],
)
u = unroll_temporal_dag(spec, 3)

fig, ax, p = dagplot_temporal(u;
    figure_size = (520, 260),
    fit_node_size_to_labels = false,
    node_size = 28,
)
fig
```

```@example time-graphs-plot-enduring
using CausalDynamics, DAGMakie, CairoMakie

spec = TemporalDAGSpec(
    entity = :sheep,
    nodes = [
        TemporalNodeSpec(:diagnosis; value_representation = :state),
        TemporalNodeSpec(
            :pasture;
            temporal_support = FromOnsetSupport(1),
            value_representation = :attribute,
            causal_role = :assigned,
        ),
        TemporalNodeSpec(:weight; value_representation = :state),
    ],
    edges = [
        (:diagnosis, :pasture, 1),
        (:pasture, :weight, 0),
        (:weight, :weight, 1),
    ],
)
u = unroll_temporal_dag(spec, 2)
fig, ax, p = dagplot_temporal(u;
    figure_size = (560, 280),
    fit_node_size_to_labels = false,
    node_size = 26,
)
fig
```

## Confounded treatment (book Ch. 28)

```julia
using CausalDynamics

spec = TemporalDAGSpec(
    nodes = [TemporalNodeSpec(v; value_representation = :state) for v in [:x, :y, :a, :c]],
    edges = [
        (:c, :c, 1), (:a, :c, 1), (:c, :a, 0),  # confounder dynamics + confounding
        (:x, :x, 1), (:a, :x, 1), (:c, :x, 1),  # state evolution
        (:x, :y, 0),                             # measurement
    ],
)
u = unroll_temporal_dag(spec, 10)

# Effect of A_{t-1} on X_t: adjust for C_{t-1}
adj = temporal_backdoor_adjustment_nodes(u, :a, 2, :x, 2)
# Set containing (:c, 1)
```

See also [Utilities](utils.md), [Discrete-time CDMs](cdm.md), and the
[CDCS book Ch. 28](https://simonab.github.io/causal-dynamics-book/part-observable/28-cdms-unified.html).

## Baseline assignment into a from-onset attribute

A point-supported diagnosis can assign a value that persists thereafter. With
`FromOnsetSupport(1)`, a lag-one edge from `diagnosis` connects `diagnosis[0]`
to the single `pasture` node:

```julia
spec = TemporalDAGSpec(
    entity = :sheep,
    nodes = [
        TemporalNodeSpec(:diagnosis; value_representation = :state),
        TemporalNodeSpec(
            :pasture;
            temporal_support = FromOnsetSupport(1),
            value_representation = :attribute,
        ),
        TemporalNodeSpec(:weight; value_representation = :state),
    ],
    edges = [
        (:diagnosis, :pasture, 1),
        (:pasture, :weight, 0),
    ],
)
u = unroll_temporal_dag(spec, 4)
temporal_node(u, :diagnosis, 0)
enduring_node(u, :pasture)
```
