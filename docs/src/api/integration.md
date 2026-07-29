# Integration API

Functions for integrating CausalDynamics.jl with other packages (TMLE.jl, RxInfer/GraphPPL).

## TMLE

```@docs
prepare_for_tmle
estimate_effect
get_tmle_confounders
```

## RxInfer / GraphPPL (optional)

Requires `using RxInfer` to load the `CausalDynamicsRxInfer` extension.

```@docs
prepare_for_rxinfer
has_rxinfer
infer_backdoor_effect
backdoor_graphppl_model
ppl_data_from_spec
prepare_for_turing
get_data_for_ppl
```

## Associations.jl (optional)

Requires `using Associations` to load the `CausalDynamicsAssociationsExt` extension.

```@docs
has_associations
prepare_from_discovery
cpdag_to_dag
oce_parents_to_temporal_spec
digraph_with_names
infer_pc_graph
infer_oce_temporal_spec
discover_and_prepare
```

## SciML / OrdinaryDiffEq (optional)

Requires `using OrdinaryDiffEq` to load `CausalDynamicsSciMLExt` for `solve_cdm`.
The types and façade functions below are always exported from core.

```@docs
ContinuousCDMSpec
has_sciml
ode_problem_cdm
solve_cdm
terminal_state
state_series
interventional_rhs
```
