# Getting Started

## Installation

Until CausalDynamics.jl is on the General registry:

```julia
using Pkg
Pkg.add(url="https://github.com/SimonAB/CausalDynamics.jl.git")
```

Afterwards, `Pkg.add("CausalDynamics")` will suffice. Julia **1.12+** is required.

## Basic usage

### Creating a causal graph

```julia
using CausalDynamics
using Graphs

g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y
```

### Checking d-separation

```julia
d_separated(g, 2, 3, [1])  # true (Z blocks the path)
```

### Finding adjustment sets

```julia
adj_set = backdoor_adjustment_set(g, 2, 3)  # Set([1])
```

### Plotting (optional)

```julia
using DAGMakie, CairoMakie

fig = plot_backdoor_paths(g, 2, 3; node_labels = ["Z", "X", "Y"])
```

`plot_causal_graph` and friends require `using DAGMakie` so the package extension loads.

### SCM simulation and intervention

```julia
equations = Dict{Int, Function}(
    1 => (u,) -> u,
    2 => (z, u) -> z + u,
    3 => (x, u) -> 2x + u,
)
scm = GraphSCM(g, equations, Set{Int}())
U = Dict(1 => 1.0, 2 => 0.5, 3 => -0.3)
y_factual = simulate_scm(scm, U)
y_do = simulate_scm(apply_intervention(scm, do_intervention(2, 10.0)), U)
```

## Next steps

- See the [API Reference](api/graphs.md) pages for detailed function documentation
- Check the [Examples](examples.md) for more usage
- Read the [CDCS Book](https://simonab.github.io/causal-dynamics-book/) for conceptual background
