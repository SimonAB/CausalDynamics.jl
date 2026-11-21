# Associations.jl integration (discovery → identification)

[CausalDynamics.jl](https://github.com/SimonAB/CausalDynamics.jl) does **not** implement
causal discovery. [Associations.jl](https://juliadynamics.github.io/Associations.jl/stable/)
(formerly CausalityTools.jl) supplies association measures, independence tests, **PC**, and
**OCE** graph inference. This package bridges discovered structure to identification APIs.

Load the extension:

```julia
using CausalDynamics
using Associations
using DataFrames  # required together with Associations
```

## Pattern: tabular PC → backdoor

```julia
using CausalDynamics, Associations, DataFrames, Random, StableRNGs

rng = StableRNG(1)
n = 2000
z = randn(rng, n)
x = 0.8 * z .+ 0.3 * randn(rng, n)
y = 0.7 * x .+ 0.5 * z .+ 0.3 * randn(rng, n)
df = DataFrame(z = z, x = x, y = y)

ĝ = infer_pc_graph(df, [:z, :x, :y]; verbose = false)
confounders, ok = prepare_from_discovery(ĝ, :x, :y; complete = true)
# confounders == [:z], ok == true
```

PC returns a **CPDAG** (partially directed graph). Pass `complete=true` to
[`cpdag_to_dag`](@ref) when a fully oriented DAG is required before backdoor adjustment.

## Pattern: OCE → temporal identification

```julia
# Bivariate VAR-like series (vectors, one per variable)
ts = [x₁, x₂]
spec = infer_oce_temporal_spec(ts, [:x₁, :x₂]; verbose = false)
u = unroll_temporal_dag(spec, T = 5)
adj = temporal_backdoor_adjustment_nodes(u, :x₁, 1, :x₂, 2)
```

OCE embedding lags in `parents_τs` map to [`TemporalDAGSpec`](@ref) lags via
[`oce_parents_to_temporal_spec`](@ref) (`lag = abs(τ)`).

## One-shot helper

```julia
confounders, ok = discover_and_prepare(
    df, :x, :y;
    method = :pc,
    names = [:z, :x, :y],
    complete = true,
)
```

## What stays in Associations

- Independence / association estimators (`association`, `independence`, …)
- PC, OCE, CCM, transfer entropy, and related tests
- FCI, GES, PCMCI (use other tools or future `Associations.jl` releases)

## Interventional Embedding Entropy (IEE)

Interventional Embedding Entropy (Shi et al., 2026; precursor Embedding Entropy
in Shi et al., 2022 — see [References](references.md)) ranks interventional
dynamical causality (IntDC) edges from observational time series in
delay-embedding space.

Use [`interventional_embedding_entropy`](@ref) for a single candidate edge
``x \to y``. With `Associations` loaded, `mi = :auto` selects the KSG1 mutual
information estimator; pass `mi = :reference` for the self-contained
MATLAB-faithful `MIknn` port (useful for concordance or regression checks):

```julia
using CausalDynamics, Associations, DataFrames

# Preferred KSG1 estimator when Associations is loaded
s = interventional_embedding_entropy(x, y; p = 2, k = 2, mi = :auto)

# Self-contained MATLAB-faithful port (no Associations dependency needed)
s_ref = interventional_embedding_entropy(x, y; p = 2, k = 2, mi = :reference)
```

For multivariate systems, compute the pairwise matrix with
[`iee_score_matrix`](@ref) and threshold it into a [`TemporalDAGSpec`](@ref)
with [`iee_to_temporal_spec`](@ref) (or [`infer_iee_temporal_spec`](@ref)):

```julia
scores = iee_score_matrix([x, y]; p = 2, k = 2)  # mi = :auto
spec = iee_to_temporal_spec(scores, [:x, :y]; threshold = 0.05, lag = 1)
u = unroll_temporal_dag(spec, 5)
```

For ODE parent ranking across environments and forward sensitivity on continuous
CDMs (``\dot{Y} \sim X_S``), see [SciML recipes](SCIML_INTEGRATION.md).

## What stays in CausalDynamics

- `backdoor_adjustment_set`, `d_separated`, frontdoor, IV
- `DiscreteTimeCDM`, `counterfactual`, `g_computation`
- `CausalTargeted`, TMLE, and RxInfer estimation bridges after identification

Executable recipe: `examples/discovery_to_identification.jl`. See also the
[Integrations API](api/integration.md) and the
[CDCS book — Causal Discovery](https://simonab.github.io/causal-dynamics-book/part-structural/05b-causal-discovery.html)
for narrative context.
