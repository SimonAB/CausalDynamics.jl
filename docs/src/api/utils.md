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
