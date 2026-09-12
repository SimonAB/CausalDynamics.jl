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
intervention_targets
ObservationSemantics
expands_pointwise
is_single_node_support
legacy_temporal_mode
support_from_temporal_mode
normalise_value_representation
normalise_relation_kind
normalise_ontological_character
parse_temporal_support
require_semantics
VALUE_REPRESENTATIONS
RELATION_KINDS
CLAIM_KINDS
IDENTIFICATION_STATUSES
```

## Single-node attributes from onset

Prefer typed support. A pasture assignment that persists from onset uses
`FromOnsetSupport` (and usually `value_representation = :attribute`). Optional
`ontological_character = :enduring` is metadata only.

```@example time-graphs-enduring
using CausalDynamics, Graphs

spec = TemporalDAGSpec(
    entity = :sheep,
    nodes = [
        TemporalNodeSpec(:diagnosis; value_representation = :state),
        TemporalNodeSpec(
            :pasture;
            temporal_support = FromOnsetSupport(1),
            value_representation = :attribute,
            causal_role = :assigned,
            referent_id = :sheep,
            identity_criterion = :administrative_identifier,
        ),
        TemporalNodeSpec(
            :weight;
            value_representation = :state,
            referent_id = :sheep,
            identity_criterion = :organisational_continuity,
        ),
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
Deprecated `temporal_mode = :enduring` still maps to `FromOnsetSupport` and
does **not** set ontology.

The unrolled graph retains edge provenance. Use `temporal_edge_role` for one
edge and `temporal_edge_records` for an auditable inventory. A constitutive
(pointwise → single-node) edge is an assignment into persistence; a recurrent
influence edge reuses a single-node parent for later times; an occasion
influence edge connects pointwise nodes. Declared `relation_kind` values other
than `:causal_influence` are excluded from [`causal_projection`](@ref) and
recorded as constraints.

```@example time-graphs-enduring
proj = causal_projection(u)
ne(proj.graph), length(proj.constraints)
```

```@example time-graphs-enduring
records = temporal_edge_records(u)
filter(record -> record.role === :constitutive, records)
```

## Plotting an unrolling

With [DAGMakie.jl](https://simonab.github.io/DAGMakie.jl) loaded,
[`DAGMakie.dagplot_temporal`](https://simonab.github.io/DAGMakie.jl/dev/) places
times left→right and variables as rows. Pointwise nodes are circles; single-node
supports use rounded rectangles at their onset (shape encodes support /
representation when supplied; colour still encodes causal role). The
CausalDynamics extension adds a `TemporalUnrolling` method automatically.

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
