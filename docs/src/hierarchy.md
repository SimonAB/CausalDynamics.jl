# Hierarchical / nested units

CausalDynamics owns **generative** hierarchy: shared cluster-level exogenous
draws ``U_j`` nested with unit-level noise. This is the same role as shared
``U`` for L3 counterfactuals, organised by cluster membership.

Three objects that must not be conflated:

| Object | Meaning | Owner |
|--------|---------|-------|
| Generative hierarchy | Nested ``U_j``, ``U_{ij}`` in simulation | CausalDynamics |
| Sampling hierarchy | Dependence in the IF / cluster-robust sandwich | CausalTargeted (mediation EIFs → CausalMediation) |
| Partial-pooling estimator | LMM/GLMM/Bayes BLUPs | Application layer (or RxInfer demo) |

## API

[`RandomEffectSpec`](@ref) describes cluster count, scale, outcome columns, and
the cluster id name. [`simulate_hierarchical_panel`](@ref) wraps
[`simulate_panel`](@ref) and adds ``U_j + U_{ij}`` to named outcomes.
[`simulate_hierarchical_intercept_ate`](@ref) is a binary-treatment synthetic
gate with known ATE.

[`HierarchicalNestingSpec`](@ref) / [`unroll_hierarchical_dag`](@ref) expand a
unit template plus cluster→outcome edges into a flat DAG for
[`identify`](@ref). [`attach_hierarchy_assumptions`](@ref) unions
[`HIERARCHY_ASSUMPTIONS`](@ref) onto an [`IdentificationResult`](@ref).

```@example hierarchy
using CausalDynamics, Random

cols, truth = simulate_hierarchical_intercept_ate(
    200; n_clusters = 20, σ_cluster = 1.0, β_a = 0.5, rng = MersenneTwister(1),
)
(truth.ate, truth.assumptions, length(unique(cols[:cluster])))
```

```@example hierarchy
using Graphs
spec = HierarchicalNestingSpec(
    [:W, :A, :Y], [(:W, :A), (:W, :Y), (:A, :Y)];
    cluster_variable = :U, affects = [:Y],
)
un = unroll_hierarchical_dag(spec, 4; n_clusters = 2)
nv(un.graph)
```

## Hand-off

- Estimation with joint or **cluster-robust** covariance: CausalTargeted
  `run_repeated_outcome_msm(...; cluster=:cluster)` (and parametric MSM).
  Point estimates are unchanged; only ``\\widehat{\\Sigma}`` uses the cluster sandwich.
- LMM concordance: application repositories (see
  `examples/hierarchical_mixedmodels_concordance.md`); not this package.
- Plate figures: DAGMakie (viz only) when drawing unrolled hierarchical DAGs.
- Optional Bayesian hierarchical heads: RxInfer demos in application code
  ([RxInfer integration](RXINFER_INTEGRATION.md)); not required for ID or LMTP.
- Stress notebook: [Hierarchical nesting stress](stress_hierarchy.md).

See also [Scope](scope.md) and
[BOUNDARIES](https://github.com/SimonAB/CausalDynamics.jl/blob/main/BOUNDARIES.md).
