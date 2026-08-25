# Hierarchical DGP ↔ MixedModels concordance (application recipe)

CausalDynamics owns **generative** nested ``U`` (`simulate_hierarchical_intercept_ate`,
`RandomEffectSpec`). Fitting an LMM / BLUP is an **application** concern:
do not add MixedModels.jl to CausalDynamics or CausalTargeted.

This note is a concordance checklist for apps (e.g. Sheep_VaccineCDCS, AgeSCM).

## 1. Simulate under Dynamics

```julia
using CausalDynamics, Random
cols, truth = simulate_hierarchical_intercept_ate(
    500; n_clusters = 25, σ_cluster = 1.0, β_a = 0.5, rng = MersenneTwister(1),
)
# cols: :cluster, :W, :A, :Y  — truth.ate is the causal ATE
```

## 2. Optional: cluster-robust MSM (CausalTargeted)

Same estimand ``E[Y\\mid do(A=1)]-E[Y\\mid do(A=0)]`` with cluster sandwich Σ:

```julia
using CausalTargeted, DataFrames
df = DataFrame(cols)
# For a single outcome, prefer AIPW / TMLE on Y; for Y1…YT use
# run_repeated_outcome_msm(...; cluster = :cluster)
```

## 3. MixedModels partial pooling (application only)

Install MixedModels in the **application** environment. A typical check is that
the fixed effect of `A` recovers `truth.ate` under a correctly specified
random-intercept model, while BLUPs shrink cluster means — a **different**
object from the MSM profile.

```julia
# Application Project.toml: MixedModels = "…"
using MixedModels, DataFrames
df = DataFrame(cols)
# Illustrative formula — adjust coding as needed in the app:
# m = fit(MixedModel, @formula(Y ~ 1 + A + W + (1 | cluster)), df)
# compare coef(m) for A to truth.ate
```

## Do not

- Replace MSM ``\\tau(t)`` silently with BLUPs in CausalTargeted
- Add MixedModels as a CausalDynamics / CausalTargeted dependency
- Treat LMM coefficients as `do(·)` effects without stating the estimand
