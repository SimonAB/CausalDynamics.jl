# Package boundaries

**Design principles:** [DESIGN.md](DESIGN.md) · [shared](DESIGN_PRINCIPLES.md)

## CausalDynamics.jl (this package)

- Causal graphs, d-separation, identification (`identify`, `IdentificationResult`)
- SCMs, CDMs, temporal unrolling, observational panels (`simulate_panel` / `CDMPanel`; `Float64` columns, including integer-coded factor recodes via `Policy`)
- Latent→observed bridges (`ObservationBridge`); high-dim → code
  representation (`RepresentationSpec`, `encode_to_panel`); continuous
  functionals (SciML ext)
- Transport identification (`TransportQuery`); not domain-cohort registries
- Integration **façades** (TMLE.jl, RxInfer, DAGMakie) via package extensions

### Experimental (exported; outside the main pipeline)

- **`Hypergraph`** — higher-order edges; not used by `identify` / CDM simulation
- **`SymbolicSCM`** — ModelingToolkit placeholder (`system::Any`); use `GraphSCM`
- Stub do-calculus (`is_identifiable`, `identify_formula`) — unexported; throw until implemented

## CausalTargeted.jl

- Cross-fitted nuisances, LMTP, mediation EIF, grid execution
- Estimation policies (`ShiftPolicy`, `DiscreteTreatmentPolicy`); do not add those types here

## Application repositories

- Cohort data, manuscript registries, reference-implementation concordance

Do not add estimation grids or SuperLearner stacks here beyond integration examples.
