# Package boundaries

**Design principles:** [DESIGN.md](DESIGN.md) · [shared](../DESIGN_PRINCIPLES.md)

## CausalDynamics.jl (this package)

- Causal graphs, d-separation, identification (`identify`, `IdentificationResult`)
- SCMs, CDMs, temporal unrolling
- Integration **façades** (TMLE.jl, RxInfer, DAGMakie) via package extensions

### Experimental (exported; outside the main pipeline)

- **`Hypergraph`** — higher-order edges; not used by `identify` / CDM simulation
- **`SymbolicSCM`** — ModelingToolkit placeholder (`system::Any`); use `GraphSCM`
- Stub do-calculus (`is_identifiable`, `identify_formula`) — unexported; throw until implemented

## CausalTargeted.jl

- Cross-fitted nuisances, LMTP, mediation EIF, grid execution

## Application repositories

- Cohort data, manuscript registries, reference-implementation concordance

Do not add estimation grids or SuperLearner stacks here beyond integration examples.
