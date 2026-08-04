# CausalDynamics.jl

```@meta
CurrentModule = CausalDynamics
```

```@docs
CausalDynamics
```

CausalDynamics provides causal graph operations and identification for structural
and discrete-time dynamical models (CDMs). Names follow Pearl-style conventions
(`d_separated`, `backdoor_adjustment_set`, `do_intervention`, `DiscreteTimeCDM`, …).
See [Scope](scope.md) for what is in core versus deferred.

The package covers d-separation and path finding; backdoor, frontdoor, and
instrumental-variable criteria; static `GraphSCM` simulation with `do(·)` and
shared-`U` counterfactuals; discrete-time CDMs (`DoSequence`, trajectory
simulation); soft interventions and g-computation; and time-indexed identification
via unrolled lag DAGs. Optional extensions load DAGMakie plotting, RxInfer /
GraphPPL backdoor inference, and Associations.jl discovery bridges.

## Compared with R and Python

| Need | CausalDynamics | Familiar elsewhere |
|------|----------------|--------------------|
| d-separation / backdoor / frontdoor / IV | Yes | dagitty, DoWhy, causal-learn |
| Typed `identify` → certificate | **Unique** | Partial |
| Discrete-time CDM + shared-`U` CF | **Unique** | Rare |
| Temporal unroll / SciML continuous CDM | **Unique** | Partial / custom |

**Choose CausalDynamics** when certificates and trajectories should feed Julia
estimation and plotting. **Prefer dagitty / DoWhy** for GUI-first or existing
Python four-step workflows. Details: [Comparison](comparison.md) ·
[ECOSYSTEM_COMPARISON.md](https://github.com/SimonAB/CausalDynamics.jl/blob/main/ECOSYSTEM_COMPARISON.md).

## Quick start

```@example home
using CausalDynamics, Graphs, DAGMakie, CairoMakie

g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

d_separated(g, 2, 3, [1])                 # true
backdoor_adjustment_set(g, 2, 3)            # Set([1])

# Optional DAGMakie highlighting of backdoor paths and the adjustment set
fig = plot_backdoor_paths(g, 2, 3; node_labels = ["Z", "X", "Y"])
fig
```

DAG figures use [DAGMakie.jl](https://simonab.github.io/DAGMakie.jl/dev/);
CausalDynamics supplies the identification sets that the plot helpers consume.

## Installation

```julia
using Pkg
Pkg.add("CausalDynamics")
```

Optional plots: `Pkg.add("DAGMakie")` then `using DAGMakie, CairoMakie`.

See [REGISTRATION.md](https://github.com/SimonAB/CausalDynamics.jl/blob/main/REGISTRATION.md) for newer versions still awaiting registry publication.

## Documentation

- [Scope](scope.md) · [Comparison](comparison.md) · [Getting Started](getting-started.md) · [API](api/graphs.md)
- [References](references.md) — Pearl, g-methods, discovery, temporal ID (DOIs / BibTeX keys)
- Estimation layer: [CausalTargeted.jl references](https://github.com/SimonAB/CausalTargeted.jl/blob/main/docs/src/references.md)
- Narrative companion: [CDCS Book](https://simonab.github.io/causal-dynamics-book/)

Compared with R/Python graph tools and the rest of this Julia stack: see [Comparison](comparison.md)
(summary above) and [ECOSYSTEM_COMPARISON.md](https://github.com/SimonAB/CausalDynamics.jl/blob/main/ECOSYSTEM_COMPARISON.md).
