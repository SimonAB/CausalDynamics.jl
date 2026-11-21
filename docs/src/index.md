# CausalDynamics.jl

```@meta
CurrentModule = CausalDynamics
```

```@docs
CausalDynamics
```

Given a diagram of how variables in a biological or dynamical system influence
one another, CausalDynamics checks whether a causal effect can be identified
from observational or experimental data, determines which covariates to adjust
for (and which to exclude), and simulates interventions and counterfactual
trajectories.

**Deciding which method fits your study?** See
[Choosing an approach](orientation.md) to match a biological question,
estimand, and data structure to the right package and API.

CausalDynamics provides causal graph operations and identification for structural
and discrete-time dynamical models (CDMs). Identification and estimation names
follow Pearl-style conventions (`d_separated`, `backdoor_adjustment_set`,
`do_intervention`, `DiscreteTimeCDM`, …), implementing Pearl (2009) and related
graphical criteria. Backdoor / frontdoor listing delegates to CausalInference
`gensearch` (van der Zander et al., 2019; Wienöbst et al., 2024). Temporal
identity may use the closed lexicon on [Terminology](terminology.md). See
[Scope](scope.md) for what is in core versus deferred. DOIs:
[References](references.md).

The package covers d-separation and path finding; backdoor, frontdoor, and
instrumental-variable criteria; static `GraphSCM` simulation with `do(·)` and
shared-`U` counterfactuals; discrete-time CDMs (`DoSequence`, trajectory
simulation); soft interventions and g-computation; and time-indexed identification
via unrolled lag DAGs. Optional extensions load DAGMakie plotting, RxInfer /
GraphPPL backdoor inference, and Associations.jl discovery bridges.

## Compared with R and Python

CausalDynamics covers classical graphical identification (like `dagitty` and
`DoWhy`), and pairs typed [`IdentificationResult`](@ref) certificates directly
with discrete-time CDMs, temporal unrolling, and SciML continuous-time models in
Julia. Choose CausalDynamics when certificates and trajectories should feed
Julia estimation and plotting; prefer `dagitty` or `DoWhy` for GUI-first or
existing Python four-step workflows. See [Comparison](comparison.md) and
[ECOSYSTEM_COMPARISON.md](https://github.com/SimonAB/causal-dynamics-book/blob/main/packages/ECOSYSTEM_COMPARISON.md).

## Quick start

```@example home
using CausalDynamics, Graphs, DAGMakie, CairoMakie

g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

d_separated(g, 2, 3, [1])                 # false: X → Y remains open
backdoor_adjustment_set(g, 2, 3)            # Set([1])

# Optional DAGMakie highlighting of backdoor paths and the adjustment set
fig = plot_backdoor_paths(g, 2, 3; node_labels = ["Z", "X", "Y"])
fig
```

Adjusting for `Z` blocks the backdoor path `X ← Z → Y`, while leaving the
direct causal path `X → Y` open. A valid backdoor adjustment set does not
imply d-separation of `X` and `Y` in the original DAG.

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

- **Guides:** [Choosing an approach](orientation.md) · [Getting Started](getting-started.md) · [Examples](examples.md) · [Scope](scope.md) · [Terminology](terminology.md) · [Comparison](comparison.md)
- **Domains & integrations:** [Hierarchical / nested units](hierarchy.md) · [Missingness](missingness.md) · [Integration](integration.md) · [Stress validation](stress.md) · [API](api/graphs.md)
- **Design:** [DESIGN.md](https://github.com/SimonAB/CausalDynamics.jl/blob/main/DESIGN.md) · [BOUNDARIES.md](https://github.com/SimonAB/CausalDynamics.jl/blob/main/BOUNDARIES.md) · [ecosystem principles](https://github.com/SimonAB/causal-dynamics-book/blob/main/packages/DESIGN_PRINCIPLES.md)
- [References](references.md) — Pearl, g-methods, discovery, dynamical & temporal ID (DOIs / BibTeX keys)
- Estimation layer: [CausalTargeted.jl references](https://github.com/SimonAB/CausalTargeted.jl/blob/main/docs/src/references.md)
- Narrative companion: [CDCS Book](https://simonab.github.io/causal-dynamics-book/)
