# Scope and architecture

CausalDynamics.jl is the reference Julia package for **Causal Dynamical Models (CDMs)**: Pearl-style identification and executable structural models, with a growing first-class API for **time-indexed** simulation, `do(·)`, and shared-`U` counterfactual trajectories.

The [CDCS book](https://simonab.github.io/causal-dynamics-book/) is the primary **showcase**: chapter chunks call this package’s exported APIs. Process/Whitehead gloss lives in the book ([Concept Reference Table 8](https://simonab.github.io/causal-dynamics-book/concept-reference-tables.html)); package names stay Pearl/SciML-facing.

## What is in core (v0.1–v0.2)

| Layer | Role | Typical API |
|-------|------|-------------|
| Graphs | DAG validation, ancestral sets, paths | `is_dag`, `get_ancestors`, `find_backdoor_paths` |
| Identification | Criteria for adjustment / instruments | `d_separated`, `backdoor_adjustment_set`, frontdoor, IV |
| Static SCM | One-shot settlement given `U` | `GraphSCM`, `DoIntervention`, `simulate_scm`, `compute_counterfactual` |
| Discrete-time CDM | Trajectories over occasions | `DiscreteTimeCDM`, `DoSequence`, `simulate`, `counterfactual` |
| Soft interventions | State-dependent treatment rules | `Policy`, `policy` |
| Interventional means | Monte Carlo g-computation | `g_computation` |
| Time-indexed ID | Unrolled lag DAGs | `TemporalDAGSpec`, `unroll_temporal_dag`, `temporal_backdoor_adjustment_set` |

**Hard dependencies** stay lean: `Graphs` and `CausalInference` (d-separation and minimal backdoor algorithms). Frontdoor, IV, path enumeration, SCM/CDM simulation, and estimation bridges are owned here.

## What is optional

- **DAGMakie.jl** — weakdep plotting (`plot_causal_graph`, …)
- **Associations.jl** — weakdep discovery bridge (PC, OCE → identification); see [Associations integration](ASSOCIATIONS_INTEGRATION.md)
- **RxInfer / GraphPPL / DataFrames** — weakdep variational backdoor head (narrow residualised ATE; see [RxInfer integration](RXINFER_INTEGRATION.md))
- **TMLE.jl** — workflow helpers when the package is loaded (`prepare_for_tmle`)

## What is *not* in core

| Concern | Where it lives |
|---------|----------------|
| Discovery algorithms (PC, OCE, CCM, …) | [Associations.jl](https://juliadynamics.github.io/Associations.jl/stable/) (optional weakdep bridge) |
| ODE/SDE/UDE solvers | SciML (`OrdinaryDiffEq`, `UniversalDiffEq`, …); CausalDynamics supplies structure and `do` semantics |
| Full symbolic do-calculus / ModelingToolkit ID | Stubs only (`is_identifiable`, `SymbolicSCM`); unexported until implemented |
| Process metaphysics vocabulary | CDCS book prose, not package exports |

## Experimental (exported, quarantined)

| API | Status |
|-----|--------|
| `Hypergraph` | Higher-order edges; **not** used by `identify` or CDM simulation |
| `SymbolicSCM` | ModelingToolkit placeholder (`system::Any`); use `GraphSCM` for executable SCMs |

## Façade vs own code

- **Façades over CausalInference:** `d_separated` → `dsep`; `backdoor_adjustment_set` / adjustment listing → CausalInference backdoor helpers.
- **Own code:** frontdoor, instruments, path finding, ancestral sets, `GraphSCM`, `DiscreteTimeCDM`, TMLE/RxInfer/DAGMakie/Associations bridges.

## Version narrative

- **0.1** — static graphs, identification façades, `GraphSCM`
- **0.2** — `DiscreteTimeCDM` trajectories (book Ch. 28 showcase); time-indexed unrolling
- **0.3** — Associations.jl discovery bridge; `prepare_from_discovery`, OCE → `TemporalDAGSpec`

## See also

- [Getting Started](getting-started.md)
- [SCM API](api/scm.md)
- [CDM API](api/cdm.md)
- [Integration](integration.md)
- [References](references.md)
- [Design principles](../../DESIGN.md) (repository root)
- Estimation citations: [CausalTargeted methods](https://github.com/SimonAB/CausalTargeted.jl/blob/main/docs/src/methods.md)
