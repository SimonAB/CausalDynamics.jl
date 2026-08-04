# Terminology

CausalDynamics.jl keeps standard Pearl and SciML names (`DoIntervention`, `backdoor_adjustment_set`, `d_separated`, …). The table below gives a **process** reading—causality as relations between occasions, not substances with intrinsic natures.

| API / Pearl term | Process reading (when useful) |
|------------------|-------------------------------|
| DAG / SCM graph | **Prehensive structure**: who prehends whom |
| Parent in an equation | **Physical prehension** of past or neighbouring occasions |
| Exogenous `U` in `simulate_scm` | **Creative advance** for this unit (fixed noise realisation) |
| `do_intervention`, `apply_intervention` | **Physical prehension**: impose a value, negate incoming prehensions |
| `GraphSCM` + integer node index | Executable SCM path used in book examples (`simulate_scm`, counterfactuals) |
| `do_intervention(:name, …)` on `GraphSCM` | Not yet supported — use node indices until symbol/name maps land |
| `d_separated` | Associative dependence blocked (Level 1) |
| `backdoor_adjustment_set` | Occasions to condition on so confounding prehension paths close |
| `compute_counterfactual` with shared `U` | **Alternative concrescences** for the same unit |
| Endogenous output of `simulate_scm` | What the occasion **leaves** for successors (**superject**) |
| `prepare_for_rxinfer` | Centrifugal bridge: adjustment set for the observable generative head |
| GraphPPL `@model` (extension) | **Form of relatedness** for backdoor-adjusted outcomes |
| `infer_backdoor_effect` (RxInfer) | **Epistemic concrescence**: VI over `τ` given presentational data |

Use process terms in prose and docstrings where they clarify; keep function names familiar to the causal-inference literature.
