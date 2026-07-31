# Time-indexed graphs

Discrete-time CDMs often share a **time-invariant lag structure**. Unroll that
structure to a static DAG over occasions `t = 1:T`, then apply standard
identification on the unrolled graph.

```@docs
LaggedEdge
TemporalDAGSpec
TemporalUnrolling
unroll_temporal_dag
temporal_node
temporal_node_label
d_separated_temporal
temporal_backdoor_adjustment_set
temporal_backdoor_adjustment_nodes
```

## Plotting an unrolling

With [DAGMakie.jl](https://simonab.github.io/DAGMakie.jl) loaded,
[`dagplot_temporal`](@ref) places occasions left→right and variables as rows
(same grid as `DAGMakie.dagplot_time_indexed`):

```@example time-graphs-plot
using CausalDynamics, DAGMakie, CairoMakie

spec = TemporalDAGSpec(
    [:x, :y],
    [(:x, :x, 1), (:y, :y, 1), (:x, :y, 1)],
)
u = unroll_temporal_dag(spec, 3)

fig, ax, p = dagplot_temporal(u; figure_size = (520, 260))
fig
```

## Confounded treatment (book Ch. 28)

```julia
using CausalDynamics

spec = TemporalDAGSpec(
    [:x, :y, :a, :c],
    [
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
