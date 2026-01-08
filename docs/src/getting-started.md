# Getting Started

## Installation

Install CausalDynamics.jl using Julia's package manager:

```julia
using Pkg
Pkg.add("CausalDynamics")
```

For the latest development version:

```julia
using Pkg
Pkg.add(url="https://github.com/yourusername/CausalDynamics.jl.git")
```

## Basic Usage

### Creating a Causal Graph

```julia
using CausalDynamics
using Graphs

# Create a simple causal graph
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y
```

### Checking d-Separation

```julia
# Check if X and Y are d-separated by Z
d_separated(g, 2, 3, [1])  # true (Z blocks the path)
```

### Finding Adjustment Sets

```julia
# Find a backdoor adjustment set
adj_set = backdoor_adjustment_set(g, 2, 3)  # Set([1])
```

## Next Steps

- See the [API Reference](@ref) pages for detailed function documentation
- Check the [Examples](@ref) for more comprehensive usage
- Read the [CDCS Book](https://simonab.quarto.pub/cdcs/) for conceptual background
