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
