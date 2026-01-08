# Examples

## Basic Graph Operations

### d-Separation

```julia
using CausalDynamics, Graphs

# Create a graph: Z → X → Y, Z → Y
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

# X and Y are d-separated by Z
d_separated(g, 2, 3, [1])  # true
```

### Ancestors and Descendants

```julia
# Get ancestors of a node
ancestors = get_ancestors(g, 3)  # {1, 2}

# Get descendants of a node
descendants = get_descendants(g, 1)  # {2, 3}
```

## Identification

### Backdoor Criterion

```julia
# Find backdoor adjustment set
adj_set = backdoor_adjustment_set(g, 2, 3)  # Set([1])

# Check if backdoor adjustment is possible
is_backdoor_adjustable(g, 2, 3)  # true
```

### Frontdoor Criterion

```julia
# Create frontdoor example: U → X → M → Y, U → Y
g_frontdoor = DiGraph(4)
add_edge!(g_frontdoor, 1, 2)  # U → X
add_edge!(g_frontdoor, 1, 4)  # U → Y
add_edge!(g_frontdoor, 2, 3)  # X → M
add_edge!(g_frontdoor, 3, 4)  # M → Y

# Find frontdoor mediators
mediators = find_frontdoor_mediators(g_frontdoor, 2, 4)  # [3]
```

## SCM Framework

### GraphSCM

```julia
# Create a GraphSCM
g = DiGraph(2)
add_edge!(g, 1, 2)

equations = Dict(
    1 => (u) -> u,
    2 => (x, u) -> x + u
)

exogenous = Set([1])

scm = GraphSCM(g, equations, exogenous)
```

For more examples, see the package's `examples/` directory.
