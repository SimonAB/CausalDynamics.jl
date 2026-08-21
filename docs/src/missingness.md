# Missingness

Incomplete records are not a single preprocessing step. CausalDynamics owns the
**Structural** and **Dynamical** objects: response indicators, MAR/MNAR claims on
a graph, observation masks, and generative dropout for simulation. Numerical
fill or reweighting policies (`:drop`, `:ipcw`, …) belong in
[CausalTargeted](https://simonab.github.io/CausalTargeted.jl/dev/missingness/)
and CausalMediation.

## What this package does

| Object | Role |
|--------|------|
| [`ObservationMask`](@ref) | Binary $R=1$ (observed) / $R=0$ (missing) aligned to named columns |
| [`MissingnessSpec`](@ref) | Claimed regime (`:mcar`, `:mar`, `:mnar`) and optional conditioning set |
| [`MissingnessCertificate`](@ref) | Result of [`certify_missingness`](@ref): identifiable status, `mar_set`, notes |
| `identify(...; missingness=)` | Attaches a certificate on [`IdentificationResult`](@ref).missingness |
| [`apply_missingness_mechanism`](@ref) | Simulate MCAR/MAR masks on complete columns (MNAR refused) |
| [`simulate_incomplete_panel`](@ref) | Complete CDM panel, then apply a mechanism |
| [`require_complete_values`](@ref) / [`require_complete_matrix`](@ref) | Refuse silent `Missing` → `Float64` |

Causal backdoor / frontdoor identification and missingness identification are
**separate**: an MNAR claim can leave `result.missingness.identifiable == false`
while `result.identifiable` remains `true` for the interventional query under
complete observation.

## Assignment form

For each substantive column $V$ (e.g. $Y$),

$$
\begin{aligned}
V &\coloneqq f_V\bigl(\mathrm{pa}_G(V),\, U^V\bigr), \\
R_V &\coloneqq f_{R_V}\bigl(\mathrm{pa}_G(R_V),\, U^{R_V}\bigr), \\
V^{\mathrm{rec}} &\coloneqq
\begin{cases}
V & R_V = 1, \\
\texttt{missing} & R_V = 0.
\end{cases}
\end{aligned}
$$

Latent complete values stay in the model; Julia `missing` is only the recorded
token when $R_V=0$. Figure labels may write $V^*$ for $V^{\mathrm{rec}}$;
counterfactuals remain $V^{do(\cdot)}(\mathbf{u})$, not $V^*$. Imputed fills
$\tilde{V}$ are Observable policies and are not new nodes on $G$. Dynamics never
invents a float fill inside CDM solvers or [`encode_to_panel`](@ref).

## Regimes

| Regime | Certificate | Simulation |
|--------|-------------|------------|
| `:mcar` | Identified (no conditioning set required) | Bernoulli missingness via `intercept` |
| `:mar` | Identified iff `conditioning_set` nonempty | Logistic in the conditioning covariates |
| `:mnar` | Unidentified without further assumptions | Throws in `apply_missingness_mechanism` |

```julia
using CausalDynamics, Graphs

g = DiGraph(3)
add_edge!(g, 1, 2)  # W → A
add_edge!(g, 1, 3)  # W → Y
add_edge!(g, 2, 3)  # A → Y

miss = MissingnessSpec(:Y; regime = :mar, conditioning_set = [:W])
id = identify(g, TotalEffectQuery(:A, :Y);
    node_names = Dict(1 => :W, 2 => :A, 3 => :Y),
    missingness = miss,
)
id.missingness.identifiable  # true
id.missingness.mar_set       # [:W]
```

## Masks and completeness guards

```julia
y = [1.0, missing, 3.0]
mask = observation_mask(Dict(:y => y); columns = [:y])
miss_rates(mask)  # Dict(:y => 1/3)

require_complete_values([1.0, 2.0]; context = "parents")  # ok
# require_complete_values([1.0, missing]; context = "parents")  # throws
```

High-dimensional assays must be completed or row-dropped under an Observable
policy **before** [`encode_to_panel`](@ref).

## Hand-off to estimation

Estimators read the MAR set via CausalTargeted `mar_set(id)` or pass the
[`IdentificationResult`](@ref) into `impute_posterior(...; certificate=id)`.
Do not treat survival *censoring* IPCW as the same object as MAR missing
terminal outcomes; that distinction is owned downstream.

Stress ledgers for incomplete panels and encode guards live with the estimation
stack ([CausalTargeted missingness grid](https://simonab.github.io/CausalTargeted.jl/dev/stress_missingness/)).
