# Getting Started

## Installation

```julia
using Pkg
Pkg.add("CausalDynamics")
```

Julia **1.12+** is required. For the tip of `main` before a new version is on General, use `Pkg.add(url="https://github.com/SimonAB/CausalDynamics.jl.git")`.

## Causal graphs

```@example getting_started
using CausalDynamics, Graphs, DAGMakie, CairoMakie

g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y
g
```

## d-separation

```@example getting_started
d_separated(g, 2, 3, [1])  # true (Z blocks the path)
```

## Adjustment sets

```@example getting_started
adj_set = backdoor_adjustment_set(g, 2, 3)  # Set([1])
```

## Plotting (optional)

`plot_causal_graph` and related façades require `using DAGMakie` so the package
extension loads. Layout and styling conventions are documented in the
[DAGMakie user guide](https://simonab.github.io/DAGMakie.jl/dev/).

```@example getting_started
fig = plot_backdoor_paths(g, 2, 3; node_labels = ["Z", "X", "Y"])
fig
```

Highlight an explicit adjustment set (here `{Z}`):

```@example getting_started
fig = plot_with_adjustment_set(g, 2, 3, [1]; node_labels = ["Z", "X", "Y"])
fig
```

## SCM simulation and intervention

`simulate_scm` evaluates each structural equation with **parent values in sorted
`inneighbors` order**, followed by that node's exogenous draw `U`. When several
parents exist, match the function argument order to ascending parent node indices
(e.g. for $Z\to Y$ and $X\to Y$, use `(z, x, u) -> …`, not `(x, z, u)`).

```julia
equations = Dict{Int, Function}(
    1 => (u,) -> u,
    2 => (z, u) -> z + u,
    3 => (z, x, u) -> 2x + z + u,
)
scm = GraphSCM(g, equations, Set{Int}())
U = Dict(1 => 1.0, 2 => 0.5, 3 => -0.3)
y_factual = simulate_scm(scm, U)
y_do = simulate_scm(apply_intervention(scm, do_intervention(2, 10.0)), U)
```

## See also

- [API Reference](api/graphs.md)
- [Examples](examples.md)
- [CDCS Book](https://simonab.github.io/causal-dynamics-book/)
