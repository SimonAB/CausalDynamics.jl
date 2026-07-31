# Adoption notes: dynamical causality methods (Peters / Shi)

Working notes for expanding CausalDynamics toward methods from:

- Peters, Bauer, Pfister (2022) — continuous-time causal models, often called
  *causal kinetic models* in that literature ([`@peters2022causal`](https://arxiv.org/abs/2001.06208))
- Pfister, Bauer, Peters (2019) — CausalKinetiX reference method ([`@pfister2019causalkinetix`](https://arxiv.org/abs/1810.11776))
- Shi et al. (2026) — IntDC / IEE ([`@shi2026interventional`](https://arxiv.org/abs/2407.01621)); precursor EE ([`@shi2022embedding`](https://doi.org/10.1098/rsif.2021.0766))

## Status in this package

| Method | Status | Location |
|--------|--------|----------|
| Continuous `do` taxonomy (pin / IC / soft force / RHS) | **Implemented** | SciML ext + continuous interventions |
| Continuous parent sets / ODE parent graph | **Implemented** | `ContinuousCDMSpec(; parents)`, `continuous_cdm_graph`, `with_parents` |
| IEE → `TemporalDAGSpec` | **Implemented** | `iee.jl`; Associations KSG1 via `mi=:auto` |
| ODE parent ranking across environments | **Implemented (v0)** | `ode_parents.jl` + DataInterpolations ext |
| Forward local sensitivity | **Implemented** | `forward_sensitivity_cdm` |
| Conditional IEE (cIEE) / PC pruning | Deferred | Shi outlook |
| Full constrained-spline CausalKinetiX scoring | Deferred | Derivative-space LOO score for now |

## IEE estimators

```julia
using CausalDynamics, Associations, DataFrames

# Preferred when Associations is loaded
s = interventional_embedding_entropy(x, y; p = 2, k = 2, mi = :auto)

# MATLAB-faithful port (concordance / regression tests)
s_ref = interventional_embedding_entropy(x, y; p = 2, k = 2, mi = :reference)
```

## ODE parents across environments (CausalKinetiX reference)

The Julia API is [`infer_ode_parents`](@ref) / [`ode_parent_ranking_to_continuous_spec`](@ref).
It implements the **derivative-space** leave-one-environment OLS score from the
CausalKinetiX papers (without constrained QP smoothers):

1. Differentiate trajectories ([`finite_difference_derivative`](@ref), or
   cubic splines via DataInterpolations)
2. Score each candidate parent set by LOO stability of ``Ẏ ∼ X_S`` across environments
3. Aggregate inclusion among top-`K` models
4. Bridge into [`ContinuousCDMSpec`](@ref) parents

```julia
using CausalDynamics, DataInterpolations

ranking = infer_ode_parents(times, trajectories, env, target; max_size = 2)
spec = ode_parent_ranking_to_continuous_spec(ranking, [:Y, :X1, :X2]; max_parents = 2)
```

## Forward sensitivity

```julia
using OrdinaryDiffEq, SciMLSensitivity
sol = forward_sensitivity_cdm(spec, lotka!, u0, tspan, p)
```

## Boundaries

- Discovery rankings feed identification; they do not replace `identify` / certificates.
- Estimation grids stay in CausalTargeted.
- Prefer Associations.jl when upstreaming IEE.
- Prefer ordinary dynamical / continuous-CDM language in APIs; reserve “kinetic”
  for Peters/CausalKinetiX citations, and “invariant” for explicit ICP glosses
  (mechanism stable across environments), not as standing API names.
