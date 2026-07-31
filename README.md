# CausalDynamics.jl

[![Build Status](https://github.com/SimonAB/CausalDynamics.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/SimonAB/CausalDynamics.jl/actions/workflows/CI.yml)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21703325.svg)](https://doi.org/10.5281/zenodo.21703325)
[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://simonab.github.io/CausalDynamics.jl/dev/)
[![Code Style: Blue](https://img.shields.io/badge/code%20style-blue-4495d1.svg)](https://github.com/invenia/BlueStyle)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

CausalDynamics provides causal graph operations and identification for structural
and discrete-time dynamical models (CDMs): d-separation, backdoor / frontdoor /
IV criteria, `GraphSCM` simulation, `do(·)` interventions, and counterfactuals.
Optional DAG figures via [DAGMakie.jl](https://github.com/SimonAB/DAGMakie.jl);
optional variational backdoor inference via RxInfer / GraphPPL.

**Design principles:** [DESIGN.md](DESIGN.md) · [BOUNDARIES.md](BOUNDARIES.md) ·
[ecosystem](DESIGN_PRINCIPLES.md)

> **Registration in progress.** Until CausalDynamics appears on General, install
> from GitHub (see [REGISTRATION.md](REGISTRATION.md)). Requires Julia **1.12+**.

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

From the CDCS monorepo:

```julia
Pkg.develop(path="packages/CausalDynamics.jl")
```

Optional DAG plots ([DAGMakie.jl](https://github.com/SimonAB/DAGMakie.jl) on General):

```julia
Pkg.add("DAGMakie")
using DAGMakie, CairoMakie
```

## Quick start

Confounding graph $Z \to X$, $Z \to Y$, $X \to Y$; adjust for $Z$:

```julia
using CausalDynamics, Graphs

g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

d_separated(g, 2, 3, [1])                  # true
adj_set = backdoor_adjustment_set(g, 2, 3)   # Set([1]) = {Z}
```

Plot with DAGMakie (after `using DAGMakie`):

```julia
using DAGMakie, CairoMakie
fig = plot_backdoor_paths(g, 2, 3; node_labels = ["Z", "X", "Y"])
```

SCM intervention sketch:

```julia
equations = Dict{Int, Function}(
    1 => (u,) -> u,
    2 => (z, u) -> z + u,
    3 => (x, u) -> 2x + u,
)
scm = GraphSCM(g, equations, Set{Int}())
U = Dict(1 => 1.0, 2 => 0.5, 3 => -0.3)
factual = simulate_scm(scm, U)
intervened = simulate_scm(apply_intervention(scm, do_intervention(2, 10.0)), U)
```

## Ecosystem

| Package | Role |
|---------|------|
| **CausalDynamics** | Graphs, identification, `GraphSCM` / discrete-time CDMs |
| [CausalTargeted.jl](https://github.com/SimonAB/CausalTargeted.jl) | Cross-fitted LMTP / interventional mediation |
| [DAGMakie.jl](https://github.com/SimonAB/DAGMakie.jl) | DAG figures (optional) |
| Application repos | Cohort data, registries, concordance (thin) |

## Integrations

- **[TMLE.jl](https://github.com/TARGENE/TMLE.jl)** — identify adjustment sets, then estimate CM / ATE / AIE (`prepare_for_tmle`)
- **[RxInfer](https://github.com/ReactiveBayes/RxInfer.jl) / [GraphPPL](https://github.com/ReactiveBayes/GraphPPL.jl)** — optional extension for variational backdoor heads
- **[DAGMakie.jl](https://github.com/SimonAB/DAGMakie.jl)** — optional extension for DAG figures (`plot_causal_graph`, `plot_backdoor_paths`, …)
- **[Associations.jl](https://github.com/JuliaDynamics/Associations.jl)** — optional PC / OCE discovery bridge

## Related packages

| Package | Role |
|---------|------|
| [TMLE.jl](https://github.com/TARGENE/TMLE.jl) | Point-treatment TMLE / OSE / C-TMLE (CM, ATE, AIE) |
| [CausalTargeted.jl](https://github.com/SimonAB/CausalTargeted.jl) | Continuous MTP / LMTP and interventional mediation |
| [DAGMakie.jl](https://github.com/SimonAB/DAGMakie.jl) | DAG figures for causal diagrams |
| [CausalTables.jl](https://github.com/salbalkus/CausalTables.jl) | SCM-aware tables; often paired with TMLE.jl |
| [CausalInference.jl](https://github.com/mschauer/CausalInference.jl) | Structure learning and classical graphical criteria |

## Documentation

- [Documenter site](https://simonab.github.io/CausalDynamics.jl/dev/) (API, examples, live DAGMakie figures)
- [References](https://simonab.github.io/CausalDynamics.jl/dev/references/) — DOIs / BibTeX keys
- [CDCS book](https://simonab.github.io/causal-dynamics-book/) — narrative companion

Estimation-layer citations live in
[CausalTargeted.jl](https://github.com/SimonAB/CausalTargeted.jl/blob/main/docs/src/references.md).

## Acknowledgements

Part of the Causal Dynamics for Complex Systems (CDCS) project.
Maintainer: [Simon A. Babayan](https://orcid.org/0000-0002-4949-1117).

## License

MIT License — see [LICENSE](LICENSE).

## Citation

See [CITATION.cff](CITATION.cff) or:

```bibtex
@software{causaldynamics2026,
  author = {Babayan, Simon A.},
  title  = {CausalDynamics.jl: Causal graph operations and identification for CDMs},
  year   = {2026},
  doi    = {10.5281/zenodo.21703325},
  url    = {https://github.com/SimonAB/CausalDynamics.jl}
}
```
