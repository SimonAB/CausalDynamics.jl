# Scope and architecture

CausalDynamics.jl implements Pearl-style identification and executable structural
models for **Causal Dynamical Models (CDMs)**, including time-indexed simulation,
`do(·)`, and shared-`U` counterfactual trajectories.

The [CDCS book](https://simonab.github.io/causal-dynamics-book/) uses these
exported APIs in narrative chapters. Process/Whitehead gloss lives in the book
([Concept Reference Table 8](https://simonab.github.io/causal-dynamics-book/concept-reference-tables.html));
package names stay Pearl/SciML-facing.

## What is in core (v0.1–v0.2)

| Layer | Role | Typical API |
|-------|------|-------------|
| Graphs | DAG validation, ancestral sets, paths | `is_dag`, `get_ancestors`, `find_backdoor_paths` |
| Identification | Criteria for adjustment / instruments | `d_separated`, `backdoor_adjustment_set`, frontdoor, IV |
| Static SCM | One-shot settlement given `U` | `GraphSCM`, `DoIntervention`, `simulate_scm`, `compute_counterfactual` |
| Discrete-time CDM | Trajectories over occasions | `DiscreteTimeCDM`, `DoSequence`, `simulate`, `counterfactual` |
| Observational panels | Wide tables for sequential estimation | `CDMPanel`, `simulate_panel`, `panel_column_name` |
| Latent → observed bridge | Filter/smoother outputs → panel columns | `ObservationBridge`, `panel_from_latent_series`, `simulate_observed_panel` |
| Representation bridge | High-dim tensor → low-dim codes for ID/estimation | `RepresentationSpec`, `encode_to_panel`, `representation_certificate` |
| Deep mechanisms | Parent-constrained Lux ``f_i`` / ODE residuals | `MechanismSpec`, `MechanismLibrary`, `build_ode_rhs`, `train_mechanisms!` (Lux weakdep) |
| Soft interventions | State-dependent treatment rules | `Policy`, `policy` |
| Interventional means | Monte Carlo g-computation (discrete) | `g_computation` on `DiscreteTimeCDM` |
| Continuous functionals | Monte Carlo g-computation (SciML) | `ContinuousEffectFunctional`, `g_computation` on `ContinuousCDMSpec` |
| Time-indexed ID | Unrolled lag DAGs | `TemporalDAGSpec`, `unroll_temporal_dag`, `temporal_backdoor_adjustment_set` |
| Transport ID | Domain covariates in adjustment | `TransportQuery` → `:transport_backdoor` |

**Hard dependencies** stay lean: `Graphs` and `CausalInference` (d-separation, backdoor, and frontdoor adjustment via `gensearch`). IV, path enumeration, SCM/CDM simulation, and estimation bridges are owned here.

## What is optional

- **DAGMakie.jl** — weakdep plotting (`plot_causal_graph`, …)
- **Associations.jl** — weakdep discovery bridge (PC, OCE → identification); see [Associations integration](ASSOCIATIONS_INTEGRATION.md)
- **RxInfer / GraphPPL / DataFrames** — weakdep variational backdoor head (narrow residualised ATE; see [RxInfer integration](RXINFER_INTEGRATION.md)); `DataFrame(::CDMPanel)` via `CausalDynamicsDataFramesExt`
- **TMLE.jl** — workflow helpers when the package is loaded (`prepare_for_tmle`)
- **CausalTargeted.jl** — sequential LMTP consumes `simulate_panel` wide tables + temporal `IdentificationResult` (`plan_sequential` / `sequential_spec_from_identification`)

## What is *not* in core

| Concern | Where it lives |
|---------|----------------|
| Discovery algorithms (PC, OCE, CCM, …) | [Associations.jl](https://juliadynamics.github.io/Associations.jl/stable/) (optional weakdep bridge) |
| ODE/SDE/UDE solvers | SciML (`OrdinaryDiffEq`, `UniversalDiffEq`, …); CausalDynamics supplies structure and `do` semantics |
| DeepSCM / non-additive image L3 encoders | Deferred; Phase 2b is additive-noise `:generative` on codes / low-dim vectors |
| Full symbolic do-calculus / ModelingToolkit ID | Stubs only (`is_identifiable`, `SymbolicSCM`); unexported until implemented |
| Process metaphysics vocabulary | CDCS book prose, not package exports |

## Experimental (exported, quarantined)

| API | Status |
|-----|--------|
| `Hypergraph` | Higher-order edges; **not** used by `identify` or CDM simulation |
| `SymbolicSCM` | ModelingToolkit placeholder (`system::Any`); use `GraphSCM` for executable SCMs |

## Façade vs own code

- **Façades over CausalInference:** `d_separated` → `dsep`; backdoor adjustment → CausalInference `gensearch` ([van der Zander et al., 2019](https://arxiv.org/abs/1803.00116)); frontdoor adjustment → `find_frontdoor_adjustment` ([Wienöbst et al., 2024](https://arxiv.org/abs/2211.16468)).
- **Own code:** instruments, path finding, ancestral sets, `GraphSCM`, `DiscreteTimeCDM`, TMLE/RxInfer/DAGMakie/Associations bridges.

## Version narrative

- **0.1** — static graphs, identification façades, `GraphSCM`
- **0.2** — `DiscreteTimeCDM` trajectories (book Ch. 28); time-indexed unrolling
- **0.3** — Associations.jl discovery bridge; `prepare_from_discovery`, OCE → `TemporalDAGSpec`

## See also

- [Getting Started](getting-started.md)
- [SCM API](api/scm.md)
- [CDM API](api/cdm.md)
- [Integration](integration.md)
- [References](references.md)
- [Design principles](https://github.com/SimonAB/CausalDynamics.jl/blob/main/DESIGN.md)
- Estimation citations: [CausalTargeted methods](https://github.com/SimonAB/CausalTargeted.jl/blob/main/docs/src/methods.md)
