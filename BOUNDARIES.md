# Package boundaries

**Design principles:** [DESIGN.md](DESIGN.md) · [shared](../DESIGN_PRINCIPLES.md)

## CausalDynamics.jl (this package)

- Causal graphs, d-separation, identification (`identify`, `IdentificationResult`)
- SCMs, CDMs, temporal unrolling
- Integration **façades** (TMLE.jl, RxInfer, DAGMakie) via package extensions

## CausalTargeted.jl

- Cross-fitted nuisances, LMTP, mediation EIF, grid execution

## Application repositories

- Cohort data, manuscript registries, reference-implementation concordance

Do not add estimation grids or SuperLearner stacks here beyond integration examples.
