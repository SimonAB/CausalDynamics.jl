# Utilities

Optional plotting requires [DAGMakie.jl](https://simonab.github.io/DAGMakie.jl)
(`using DAGMakie`). See the [DAGMakie docs](https://simonab.github.io/DAGMakie.jl/dev/)
for layout, themes, and path-highlighting conventions.

```@docs
has_dagmakie
plot_causal_graph
plot_with_adjustment_set
plot_backdoor_paths
plot_identification_result
dagplot_temporal
```

## Live example

```@example api-utils
using CausalDynamics, Graphs, DAGMakie, CairoMakie

g = DiGraph(3)
add_edge!(g, 1, 2)
add_edge!(g, 1, 3)
add_edge!(g, 2, 3)

fig = plot_causal_graph(g;
    node_labels = ["Z", "X", "Y"],
    highlight_nodes = Set([1]),
)
fig
```

## Temporal unrolling

```@example api-utils-temporal
using CausalDynamics, DAGMakie, CairoMakie

spec = TemporalDAGSpec([:a, :y], [(:a, :y, 0), (:a, :a, 1), (:y, :y, 1)])
u = unroll_temporal_dag(spec, 4)
fig, ax, p = dagplot_temporal(u;
    figure_size = (560, 240),
    fit_node_size_to_labels = false,
    node_size = 28,
)
fig
```

For raw Graphs without a `TemporalUnrolling`, use
`DAGMakie.dagplot_time_indexed` (see the
[DAGMakie skeletons & time guide](https://simonab.github.io/DAGMakie.jl/dev/guide/skeletons_and_time/)).
