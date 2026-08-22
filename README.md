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

> On the Julia **General** registry (`Pkg.add("CausalDynamics")`). Requires Julia **1.12+**.
> Registry tracking: [REGISTRATION.md](REGISTRATION.md).

## Installation

```julia
using Pkg
Pkg.add("CausalDynamics")
using CausalDynamics
```

Development tip of `main` (before a new version hits General):

```julia
Pkg.add(url="https://github.com/SimonAB/CausalDynamics.jl.git")
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

Registry CausalDynamics + DAGMakie resolve together with GraphMakie **≥0.6.6**
(CausalInference **≥0.19.4** widened the GraphMakie weakdep to `"0.5, 0.6"`).
Book authoring may still path-develop the CDCS GraphMakie fork for extra
features (e.g. auto-label alignment).

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

### Compared with R and Python

| Need | This package | Familiar elsewhere |
|------|--------------|--------------------|
| d-separation / backdoor / frontdoor / IV | Yes | dagitty, DoWhy |
| Typed `identify` → certificate | **Unique** (`IdentificationResult`) | Partial |
| Discrete-time CDM + shared-`U` trajectories | **Unique** | Rare |
| Temporal unroll / SciML continuous CDM | **Unique** | Partial / custom |

**Choose this** when you want identification and dynamical simulation to share types with Julia estimation and Makie figures. **Prefer dagitty / DoWhy** for GUI-first or existing Python four-step pipelines.

Full matrices: [ECOSYSTEM_COMPARISON.md](ECOSYSTEM_COMPARISON.md) ·
[Documenter comparison](https://simonab.github.io/CausalDynamics.jl/dev/comparison/).

## Testing and validation

CI runs `Pkg.test()` on Julia **1.12** (macOS and Ubuntu). Package `test/` is the merge gate; Quarto stress notebooks are pre-ship / methods probes (see [STRESS.md](STRESS.md)).

| Guardrail | What we exercise | Where |
|-----------|------------------|-------|
| **Unit / API** | d-separation, backdoor / frontdoor / IV, typed `identify`, SCM / discrete-time CDM, observation masks, Structural / Dynamical missingness, `RepresentationSpec`, mechanisms (static / ODE / generative), policies, transport queries, temporal unrolling | `test/` |
| **Synthetic recovery** | SCM intervention vs factual, OLS slope checks, linear representation oracle, Lux mechanism training, incomplete panels | `test/test_scm.jl`, `test/test_representation.jl`, `test/test_mechanism*.jl`, `test/test_cdm.jl` |
| **Integration / extensions** | TMLE bridge, CausalInference frontdoor, SciML ODE parents, RxInfer (optional), Associations / PC discovery, Lux weakdep | `test/test_integration.jl`, `test/test_frontdoor_ci.jl`, `test/test_sciml.jl`, `test/test_rxinfer.jl`, `test/test_discovery.jl` |
| **Reference concordance** | Interventional embedding entropy vs MATLAB reference port | `test/test_iee.jl`, `test/reference_iee_matlab.jl` |
| **Edge / contract tests** | Invalid inputs, MNAR refusal, certificate separation, dense frontdoor graphs | `test/test_missingness_*.jl`, `test/test_best_practices.jl` |
| **Stress (pre-ship)** | Wide panels, Lux 1D-CNN encoder stub, ODE residuals under `do`, generative L3 abduction | [docs/stress/deep_scm_stress.qmd](docs/stress/deep_scm_stress.qmd) |
| **Estimation hand-off** | Codes → LMTP / mediation / missing $Y$ (sibling notebook) | [CausalTargeted deep SCM estimation stress](https://github.com/SimonAB/CausalTargeted.jl/blob/main/docs/stress/deep_scm_estimation_stress.qmd) |

If you have a scenario that should be harder to pass (tighter oracle bounds, messier missingness, larger real cohorts), please open an issue — we welcome stress cases that expose gaps before users do.

## Integrations

- **[TMLE.jl](https://github.com/TARGENE/TMLE.jl)** — identify adjustment sets, then estimate CM / ATE / AIE (`prepare_for_tmle`)
- **[RxInfer](https://github.com/ReactiveBayes/RxInfer.jl) / [GraphPPL](https://github.com/ReactiveBayes/GraphPPL.jl)** — optional extension for variational backdoor heads
- **[DAGMakie.jl](https://github.com/SimonAB/DAGMakie.jl)** — optional extension for DAG figures (`plot_causal_graph`, `plot_backdoor_paths`, …)
- **[Associations.jl](https://github.com/JuliaDynamics/Associations.jl)** — optional PC / OCE discovery bridge
- **Representation bridge** — `RepresentationSpec` / `encode_to_panel` compress high-dim tensors (spectra, images) to low-dim **code** columns for identification and estimation (no Flux/Lux hard dependency; user-supplied encoder). Example: `examples/representation_bridge.jl`.
- **Deep mechanisms** — `MechanismSpec` / Lux weakdep for parent-constrained ``f_i`` and ODE residuals (`examples/mechanism_ude.jl`, `examples/mechanism_scm.jl`).
- **Generative L3** — `:generative` additive-noise abduction / counterfactuals on codes (`examples/mechanism_counterfactual.jl`).

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
- [Deep SCM stress](STRESS.md) — Quarto ([qmd](docs/stress/deep_scm_stress.qmd)); encode / CNN stub / mechanisms / L3; [Documenter](https://simonab.github.io/CausalDynamics.jl/dev/stress_deep_scm/)
- [Stack stress (Targeted)](https://github.com/SimonAB/CausalTargeted.jl/blob/main/STRESS.md) — estimation path ([qmd](https://github.com/SimonAB/CausalTargeted.jl/blob/main/docs/stress/stress_validation.qmd)); [Documenter](https://simonab.github.io/CausalTargeted.jl/dev/stress_validation/)
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
