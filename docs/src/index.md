# CausalDynamics.jl

```@meta
CurrentModule = CausalDynamics
```

```@docs
CausalDynamics
```

A Julia package for causal graph operations and identification algorithms, designed for Causal Dynamical Models (CDMs) and integration with the SciML ecosystem.

## Features

- **Causal Graph Operations**: d-separation, path finding, ancestral/descendant sets, Markov boundary
- **Identification Algorithms**: Backdoor criterion, frontdoor criterion, instrumental variables
- **Structural Causal Model (SCM) Framework**: Graph-based and symbolic SCM representation
- **Intervention Operators**: `do(·)` operators for causal interventions
- **SciML Integration**: Uses ModelingToolkit.jl, Symbolics.jl, Graphs.jl

## Quick Start

```julia
using CausalDynamics
using Graphs

# Create a causal graph
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

# Check d-separation
d_separated(g, 2, 3, [1])  # true (Z blocks the path)

# Find backdoor adjustment set
backdoor_adjustment_set(g, 2, 3)  # Set([1])
```

## Installation

```julia
using Pkg
Pkg.add("CausalDynamics")
```

## Documentation

See the [API Reference](@ref) pages for detailed documentation of all functions.

For conceptual background and worked examples, see the [CDCS Book](https://simonab.quarto.pub/cdcs/).

## Integration with TMLE.jl

CausalDynamics.jl integrates seamlessly with [TMLE.jl](https://github.com/TARGENE/TMLE.jl) for causal effect estimation. CausalDynamics.jl identifies adjustment sets from causal graphs, and TMLE.jl estimates causal effects using those adjustment sets.

```julia
using CausalDynamics, TMLE, DataFrames

# Create causal graph
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

# Identify and estimate in one step
node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)
result = estimate_effect(g, data, 2, 3; node_names=node_names)
```

See the [Integration Guide](@ref) for more details.

## References

- Pearl, J. (2009). *Causality: Models, Reasoning, and Inference*
- Hofmann et al. (2023). Spectral DCM with ModelingToolkit.jl
- Shpitser, I., & Pearl, J. (2006). Identification of joint interventional distributions
