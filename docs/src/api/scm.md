# SCM Framework

Structural Causal Models encode a causal graph and structural equations. Use
`simulate_scm` for forward simulation and `compute_counterfactual` for factual vs
counterfactual outcomes with shared exogenous noise `U`.

```@docs
simulate_scm
compute_counterfactual
```

```@docs
AbstractSCM
GraphSCM
SymbolicSCM
create_symbolic_scm
DoIntervention
apply_intervention
do_intervention
counterfactual_graph
```
