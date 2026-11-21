# SCM Framework

Structural Causal Models (SCMs) encode a causal graph together with deterministic
structural equations ``X_i = f_i(\mathrm{Pa}(X_i), U_i)`` over endogenous nodes
and unmodelled exogenous noise `U`. Use [`GraphSCM`](@ref) with [`simulate_scm`](@ref)
for forward simulation, [`do_intervention`](@ref) / [`apply_intervention`](@ref)
for graph surgery, and [`compute_counterfactual`](@ref) for factual versus
counterfactual outcomes under shared exogenous draws. Note that [`SymbolicSCM`](@ref)
is **experimental** (a placeholder for future ModelingToolkit integration).

For mechanism-backed SCMs (`graphscm_with_mechanisms`), L3 noise abduction, and
typed interventions such as `SetState`, see
[Mechanisms, representations & contracts](mechanisms_contracts.md).

## Equations and counterfactuals

```@docs
AbstractSCM
GraphSCM
SymbolicSCM
simulate_scm
compute_counterfactual
```

## Interventions

```@docs
DoIntervention
apply_intervention
do_intervention
counterfactual_graph
```
