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
continuous_cdm_graph
with_parents
ranked_variables_to_parents
has_sciml
ode_problem_cdm
solve_cdm
terminal_state
state_series
interventional_rhs
do_pin
do_ic
do_force
do_rhs
forward_sensitivity_cdm
```

## Interventional Embedding Entropy (IEE)

Julia port of the smsxiaomayi/IEE reference algorithm (Shi et al.). Prefer
`mi = :auto` (Associations KSG1 when loaded); use `:reference` for MATLAB
concordance.

```@docs
interventional_embedding_entropy
iee_score_matrix
iee_to_temporal_spec
infer_iee_temporal_spec
```

## Invariant parent discovery

Leave-one-environment ranking for continuous-CDM parent sets (CausalKinetiX
reference method). Load `DataInterpolations` for cubic-spline derivatives.

```@docs
InvariantParentRanking
infer_invariant_parents
score_invariant_parent_sets
invariant_ranking_to_continuous_spec
candidate_parent_sets
```
