# Package boundaries

**Design principles:** [DESIGN.md](DESIGN.md) · [shared](DESIGN_PRINCIPLES.md)

## CausalDynamics.jl (this package)

- Causal graphs, d-separation, identification (`identify`, `IdentificationResult`)
- SCMs, CDMs, temporal unrolling, observational panels (`simulate_panel` / `CDMPanel`; `Float64` columns, including integer-coded factor recodes via `Policy`)
- **Hierarchical / nested exogenous structure** (`RandomEffectSpec`, nested
  cluster→unit noise, `simulate_hierarchical_panel`, synthetic
  `simulate_hierarchical_intercept_ate`): generative nesting and panel
  columns for downstream cluster-aware estimation; **not** LMM/BLUP fitting
- **Hierarchical DAG unroll** (`HierarchicalNestingSpec`,
  `unroll_hierarchical_dag`, `attach_hierarchy_assumptions`): expand unit
  templates + cluster nodes to a flat DAG for `identify`
- Latent→observed bridges (`ObservationBridge`); high-dim → code
  representation (`RepresentationSpec`, `encode_to_panel`); graph-constrained
  deep mechanisms (`MechanismSpec` / `MechanismLibrary`; Lux weakdep);
  continuous functionals (SciML ext)
- Missingness **structure**: `ObservationMask`, `MissingnessSpec`,
  `MissingnessCertificate`, generative `apply_missingness_mechanism` /
  `simulate_incomplete_panel`. `encode_to_panel` refuses `Missing` matrices;
  **silent** `Missing` → `Float64` coercion is forbidden. Numerical policies
  (`:drop`, `:ipcw`, imputation) belong in CausalTargeted / CausalMediation
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

## Deferred (beyond Phase 2b)

- MixedModels / lme4-style fitting lives in **CausalTargeted** as an optional
  weakdep extension (`fit_profiled_nb2`, `mixed_g_computation`); not in
  CausalDynamics core. Generative nesting stays here.
- Non-additive DeepSCM (learned encoder abduction on raw image/tensor nodes);
  Phase 2b is additive-noise `:generative` on codes / low-dim vectors
- UniversalDiffEq as a CausalDynamics hard dependency (optional advanced trainer
  only; see [SCIML_INTEGRATION.md](docs/src/SCIML_INTEGRATION.md))
- Flux as a CausalDynamics hard or weakdep (Flux remains MLJFlux / application
  encoders; Lux is the SciML mechanism path)
- Full MIRS / Twins cohort files in-package (synthetic spectra in
  `docs/stress/`; real cohorts stay application / book-harness data)
