# CausalDynamics.jl

Causal graph operations and identification for **Causal Dynamical Models (CDMs)**: d-separation, backdoor / frontdoor / IV criteria, `GraphSCM` simulation, `do(·)` interventions, and counterfactuals. Optional plotting via [DAGMakie.jl](https://github.com/SimonAB/DAGMakie.jl); optional variational backdoor inference via RxInfer / GraphPPL.

> **Not yet on the General registry.** Install from GitHub until registration completes (blocked on DAGMakie AutoMerge — see [REGISTRATION.md](REGISTRATION.md)). Requires Julia **1.12+**.

[![Build Status](https://github.com/SimonAB/CausalDynamics.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/SimonAB/CausalDynamics.jl/actions/workflows/CI.yml)
[![Docs](https://img.shields.io/badge/docs-dev-blue)](https://simonab.github.io/CausalDynamics.jl/dev/)
[![Code Style: Blue](https://img.shields.io/badge/code%20style-blue-4495d1.svg)](https://github.com/invenia/BlueStyle)

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/SimonAB/CausalDynamics.jl.git")
using CausalDynamics
```

After registry publication:

```julia
Pkg.add("CausalDynamics")
```

For DAG plots (optional):

```julia
Pkg.add(url="https://github.com/SimonAB/DAGMakie.jl.git")  # until DAGMakie is on General
using DAGMakie, CairoMakie
```

## Quick start

Confounding graph ``Z \to X``, ``Z \to Y``, ``X \to Y`` — adjust for ``Z``:

```julia
using CausalDynamics, Graphs

g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

d_separated(g, 2, 3, [1])                 # true
adj_set = backdoor_adjustment_set(g, 2, 3)  # Set([1]) = {Z}
```

Plot with DAGMakie (after `using DAGMakie`):

```julia
using DAGMakie, CairoMakie
fig = plot_backdoor_paths(g, 2, 3; node_labels = ["Z", "X", "Y"])
```

## SCM intervention sketch

```julia
using CausalDynamics, Graphs

g = DiGraph(3)
add_edge!(g, 1, 2)
add_edge!(g, 2, 3)
equations = Dict{Int, Function}(
    1 => (u,) -> u,
    2 => (z, u) -> z + u,
    3 => (x, u) -> 2x + u,
)
scm = GraphSCM(g, equations, Set{Int}())
U = Dict(1 => 1.0, 2 => 0.5, 3 => -0.3)
factual = simulate_scm(scm, U)
scm_do = apply_intervention(scm, do_intervention(2, 10.0))
intervened = simulate_scm(scm_do, U)
```

## Integrations

- **TMLE.jl** — identify adjustment sets, then estimate effects on tables (`prepare_for_tmle`)
- **RxInfer / GraphPPL** — optional extension (`using RxInfer`) for variational backdoor heads
- **DAGMakie.jl** — optional extension for DAG figures

See the [documentation](https://simonab.github.io/CausalDynamics.jl/dev/) and the [CDCS book](https://simonab.github.io/causal-dynamics-book/).

## Acknowledgements

Part of the Causal Dynamics for Complex Systems (CDCS) project. Maintainer: Simon A. Babayan.
