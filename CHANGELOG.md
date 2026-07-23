# Changelog

All notable changes to CausalDynamics.jl will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Dropped local monorepo `[sources]` for General registration
- Default `Pkg.test` no longer pulls DAGMakie/CairoMakie (registry CausalInference
  GraphMakie 0.5 weakdep conflicts with DAGMakie 0.1.1); extension covered in CDCS

### Added

- Registration checklist in `REGISTRATION.md`

## [0.1.0] - 2026-07-20

### Added

- Core graph operations: d-separation, paths, sets, hypergraphs, `CausalGraph`
- Identification: backdoor, frontdoor, instruments, adjustment sets
- `GraphSCM`, `do(·)` interventions, counterfactual simulation with shared `U`
- Optional `CausalDynamicsDAGMakieExt` plotting (`plot_causal_graph`, `plot_backdoor_paths`, …)
- Optional `CausalDynamicsRxInfer` extension (GraphPPL + RxInfer + DataFrames)
- CI, Documentation, TagBot, and CompatHelper workflows (Julia 1.12)

### Changed

- Lean core dependencies: hard dep is Graphs only; Documenter, RxInfer, DataFrames, and SciML stacks demoted or removed from load path
- Visualisation no longer uses fragile `Main.isdefined(GraphMakie)` checks

### Removed

- Process / Whiteheadian terminology page from package docs (book-only)
- Public exports of unimplemented stubs (`is_identifiable`, `identify_formula`, `create_symbolic_scm`)
