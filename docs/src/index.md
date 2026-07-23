# CausalDynamics.jl

```@meta
CurrentModule = CausalDynamics
```

```@docs
CausalDynamics
```

A Julia package for causal graph operations and identification algorithms for **Causal Dynamical Models (CDMs)**. APIs use standard Pearl names (`d_separated`, `backdoor_adjustment_set`, `do_intervention`, …).

## Features

- **Causal graph operations**: d-separation, path finding, ancestral/descendant sets, Markov boundary
- **Identification**: backdoor, frontdoor, instrumental variables, adjustment sets
- **SCM framework**: `GraphSCM` simulation, `do(·)` interventions, counterfactuals with shared `U`
- **Optional DAGMakie plotting**: `plot_causal_graph`, `plot_backdoor_paths`, …
- **Optional RxInfer / GraphPPL**: variational backdoor inference extension

## Quick start

```julia
using CausalDynamics
using Graphs

g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

d_separated(g, 2, 3, [1])                 # true
backdoor_adjustment_set(g, 2, 3)            # Set([1])
```

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/SimonAB/CausalDynamics.jl.git")
```

After General registration:

```julia
Pkg.add("CausalDynamics")
```

Optional plots: `Pkg.add("DAGMakie")` then `using DAGMakie, CairoMakie`.

See [REGISTRATION.md](https://github.com/SimonAB/CausalDynamics.jl/blob/main/REGISTRATION.md) for registry status.

## Documentation

See the [Getting Started](@ref) and [API Reference](@ref) pages. For conceptual background, see the [CDCS Book](https://simonab.github.io/causal-dynamics-book/).

## References

- Pearl, J. (2009). *Causality: Models, Reasoning, and Inference*
- Shpitser, I., & Pearl, J. (2006). Identification of joint interventional distributions
