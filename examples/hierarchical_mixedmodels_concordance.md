# Hierarchical DGP ↔ MixedModels concordance

CausalDynamics owns **generative** nested ``U`` (`simulate_hierarchical_intercept_ate`,
`RandomEffectSpec`). Fitting an LMM / BLUP or MixedModels-based g-computation is an
**estimation** concern in **CausalTargeted** (optional `CausalTargetedMixedModelsExt`:
`fit_profiled_nb2`, `mixed_g_computation`). Do not add MixedModels.jl to CausalDynamics.

## 1. Simulate under Dynamics

```julia
using CausalDynamics, Random
cols, truth = simulate_hierarchical_intercept_ate(
    500; n_clusters = 25, σ_cluster = 1.0, β_a = 0.5, rng = MersenneTwister(1),
)
# cols: :cluster, :W, :A, :Y  — truth.ate is the causal ATE
```

## 2. Cluster-robust MSM (CausalTargeted)

Same estimand ``E[Y\\mid do(A=1)]-E[Y\\mid do(A=0)]`` with cluster sandwich Σ:

```julia
using CausalTargeted, DataFrames
df = DataFrame(cols)
# For a single outcome, prefer AIPW / TMLE on Y; for Y1…YT use
# run_repeated_outcome_msm(...; cluster = :cluster)
```

## 3. Optional MixedModels / profiled NB2 (CausalTargeted weakdep)

```julia
using CausalTargeted, MixedModels, FastGaussQuadrature, NLopt, SpecialFunctions, DataFrames
df = DataFrame(cols)
# Illustrative: fit(MixedModel, @formula(Y ~ 1 + A + W + (1 | cluster)), df)
# or fit_profiled_nb2 / mixed_g_computation for repeated outcomes — see CausalTargeted docs
```

## Do not

- Replace MSM ``\\tau(t)`` silently with BLUPs
- Add MixedModels as a CausalDynamics dependency
- Treat LMM coefficients as `do(·)` effects without stating the estimand
