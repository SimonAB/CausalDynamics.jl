# Time-indexed graphs

Discrete-time CDMs often share a **time-invariant lag structure**. Unroll that
structure to a static DAG over occasions `t = 0:T`, then apply standard
identification on the unrolled graph. Enduring entity attributes remain single
nodes and may be assigned at an explicit onset time.

```@docs
LaggedEdge
TemporalNodeSpec
TemporalDAGSpec
TemporalUnrolling
unroll_temporal_dag
temporal_node
enduring_node
temporal_node_label
temporal_edge_role
temporal_edge_records
d_separated_temporal
temporal_backdoor_adjustment_set
temporal_backdoor_adjustment_nodes
```

## Enduring attributes (#29)

```@example time-graphs-enduring
using CausalDynamics

spec = TemporalDAGSpec(
    entity = :sheep,
    nodes = [
        TemporalNodeSpec(:diagnosis),
        TemporalNodeSpec(:pasture; temporal_mode = :enduring, onset_time = 1, causal_role = :assigned),
        TemporalNodeSpec(:weight),
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

Panel mapping follows the mode: enduring variables keep their bare column
symbol; occasion variables use `panel_column_name`. Prefer declaring
`temporal_mode` on the DAG rather than a downstream `unit_level` override.

The unrolled graph retains edge provenance. Use `temporal_edge_role` for one
edge and `temporal_edge_records` for an auditable inventory. A constitutive
edge forms an enduring node from earlier occasions; a recurrent influence edge
reuses an enduring node as a parent of later occasions; an occasion influence
edge connects time-indexed nodes. These roles describe the temporal semantics
of the graph and do not add a second causal system alongside it.

```@example time-graphs-provenance
records = temporal_edge_records(u)
filter(record -> record.role === :constitutive, records)
```

## Plotting an unrolling

With [DAGMakie.jl](https://simonab.github.io/DAGMakie.jl) loaded,
[`DAGMakie.dagplot_temporal`](https://simonab.github.io/DAGMakie.jl/dev/) places
occasions left→right and variables as rows. Occasion nodes are circles; enduring
nodes are rounded rectangles placed at their `onset_time` (shape encodes
persistence; colour still encodes causal role). The CausalDynamics extension
adds a `TemporalUnrolling` method automatically.

```@example time-graphs-plot
using CausalDynamics, DAGMakie, CairoMakie

spec = TemporalDAGSpec(
    nodes = [TemporalNodeSpec(:x), TemporalNodeSpec(:y)],
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
        TemporalNodeSpec(:diagnosis),
        TemporalNodeSpec(:pasture; temporal_mode = :enduring, onset_time = 1, causal_role = :assigned),
        TemporalNodeSpec(:weight),
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
    nodes = [TemporalNodeSpec(v) for v in [:x, :y, :a, :c]],
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

## Baseline assignment into an enduring attribute

An occasion can assign a value that persists thereafter. With an enduring
node onset at `t = 1`, a lag-one edge from `diagnosis` connects
`diagnosis[0]` to the single `pasture` node:

```julia
spec = TemporalDAGSpec(
    entity = :sheep,
    nodes = [
        TemporalNodeSpec(:diagnosis),
        TemporalNodeSpec(:pasture; temporal_mode = :enduring, onset_time = 1),
        TemporalNodeSpec(:weight),
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
