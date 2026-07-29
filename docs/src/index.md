# CausalDynamics.jl

```@meta
CurrentModule = CausalDynamics
```

```@docs
CausalDynamics
```

A Julia package for causal graph operations and identification for **Causal Dynamical Models (CDMs)**. APIs use standard Pearl names (`d_separated`, `backdoor_adjustment_set`, `do_intervention`, `DiscreteTimeCDM`, …). See [Scope](scope.md) for what is in core vs deferred.

## Features

- **Causal graph operations**: d-separation, path finding, ancestral/descendant sets, Markov boundary
- **Identification**: backdoor, frontdoor, instrumental variables, adjustment sets
- **Static SCM**: `GraphSCM` simulation, `do(·)` interventions, counterfactuals with shared `U`
- **Discrete-time CDMs**: trajectory simulation, `DoSequence`, shared-`U` counterfactual paths
- **Soft interventions and g-computation**: `Policy`, `g_computation`
- **Time-indexed identification**: `unroll_temporal_dag`, `temporal_backdoor_adjustment_set`
- **Optional DAGMakie plotting**: `plot_causal_graph`, `plot_backdoor_paths`, …
- **Optional RxInfer / GraphPPL**: variational backdoor inference extension
- **Optional Associations.jl**: PC / OCE discovery bridge to identification

The [CDCS book](https://simonab.github.io/causal-dynamics-book/) showcases these APIs in full narrative form.

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

- [Scope](scope.md) · [Getting Started](getting-started.md) · [API](api/graphs.md)
- [References](references.md) — Pearl, g-methods, discovery, temporal ID (DOIs / BibTeX keys)
- Estimation layer citations: [CausalTargeted.jl references](https://github.com/SimonAB/CausalTargeted.jl/blob/main/docs/src/references.md)

See the [Getting Started](getting-started.md) and [API Reference](api/graphs.md) pages. For conceptual background, see the [CDCS Book](https://simonab.github.io/causal-dynamics-book/).
