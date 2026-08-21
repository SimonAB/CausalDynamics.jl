# SciML integration (recipes)

CausalDynamics.jl does **not** hard-depend on SciML solvers. Discrete-time
trajectories live in [`DiscreteTimeCDM`](@ref); continuous mechanisms belong in
**OrdinaryDiffEq** / **UniversalDiffEq** / application code. This page records
composition patterns used in the [CDCS book](https://simonab.github.io/causal-dynamics-book/).

## Pattern: identify → simulate → intervene

1. **Structural** — `TemporalDAGSpec` + `unroll_temporal_dag` or a hand-built `DiGraph`
2. **Dynamical** — `DiscreteTimeCDM` + `simulate` / `counterfactual`, *or* an `ODEProblem`
3. **Observable** — TMLE / RxInfer on adjustment sets from step 1

## Discrete-time CDM (package-native)

```julia
using CausalDynamics, Random

cdm = DiscreteTimeCDM(
    [:z, :x, :y];
    initialise = (rng) -> (z = 0.0, x = 0.0, y = 0.0),
    sample_noise = (rng, state, t) -> (u_z = randn(rng), u_x = randn(rng), u_y = randn(rng)),
    step = (state, t, noise, intervention) -> begin
        z = 0.9 * state.z + noise.u_z
        x = intervention_value(intervention, :x, t, 0.5 * state.x + 0.3 * z + noise.u_x)
        y = 0.5 * x + 0.2 * z + noise.u_y
        (z = z, x = x, y = y)
    end,
)

traj = simulate(cdm, 100; rng = Random.Xoshiro(1))
cf = counterfactual(cdm, traj.noise; intervention = do_sequence(:x, fill(1.0, 100)))
```

Executable recipe: `examples/discrete_cdm.jl`.

## Estimation without leaving the package

For simulated systems, contrast interventional means directly with
[`g_computation`](@ref) — no estimation dependency required:

```julia
treated = g_computation(cdm, 100, :y; intervention = do_sequence(:x, 1.0), n = 500)
control = g_computation(cdm, 100, :y; intervention = do_sequence(:x, 0.0), n = 500)
effect = treated.mean - control.mean
```

State-dependent strategies use [`policy`](@ref) instead of a fixed sequence:

```julia
π = policy(:x, (state, t) -> state.z > 0 ? 1.0 : 0.0)
under_policy = g_computation(cdm, 100, :y; intervention = π, n = 500)
```

For **observational** data (not simulation), use the TMLE or RxInfer bridges with
adjustment sets from identification. Discrete panels use `simulate_panel`;
inferred latents use `ObservationBridge` / `panel_from_latent_series`.

Continuous CDMs support the same Monte Carlo idea via
[`ContinuousEffectFunctional`](@ref) (`:terminal`, `:mean`, `:integral`):

```julia
using OrdinaryDiffEq
spec = ContinuousCDMSpec([:x, :y])
# … define rhs! …
g_do = g_computation(
    spec, rhs!, rng -> [1.0, 0.0], (0.0, 5.0), p;
    intervention = do_pin(:x, 1.0),
    functional = ContinuousEffectFunctional(:y; kind = :terminal),
    n = 200,
)
```

## Bridge to ODEs (application code)

When the mechanism is continuous, keep **causal structure** in CausalDynamics and
**integration** in SciML. Load `OrdinaryDiffEq` to activate `CausalDynamicsSciMLExt`:

```julia
using CausalDynamics, Graphs, OrdinaryDiffEq

g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y
adj = backdoor_adjustment_set(g, 2, 3)

spec = ContinuousCDMSpec([:Z, :X, :Y])
function cdm_dynamics!(du, u, p, t)
    Z, X, Y = u
    du[1] = p.λ_z * Z
    du[2] = p.α * X + p.β * Z
    du[3] = p.γ * Y + p.δ * X + p.ε * Z
end
p = (λ_z = -0.1, α = -0.2, β = 0.3, γ = -0.1, δ = 0.5, ε = 0.2)
sol = solve_cdm(spec, cdm_dynamics!, [1.0, 0.5, 0.2], (0.0, 10.0), p)
terminal_state(spec, sol)  # NamedTuple(:Z, :X, :Y)

# Static do(·): SciML-native hard pin (IC + du=0 + DiscreteCallback)
do_x = do_pin(:X, 1.0)
sol_do = solve_cdm(spec, cdm_dynamics!, [1.0, 0.5, 0.2], (0.0, 10.0), p; intervention = do_x)
```

Helpers: [`ContinuousCDMSpec`](@ref), [`ode_problem_cdm`](@ref), [`solve_cdm`](@ref),
[`terminal_state`](@ref), [`state_series`](@ref), [`interventional_rhs`](@ref),
[`intervention_callback`](@ref), [`do_pin`](@ref), [`do_ic`](@ref), [`do_force`](@ref),
[`do_rhs`](@ref).

Intervention types share [`AbstractCausalIntervention`](@ref):

- discrete CDM: [`AbstractIntervention`](@ref) (`DoSequence`, `Policy`)
- continuous CDM: [`AbstractContinuousIntervention`](@ref) (`DoPin`, `DoInitialCondition`, …)
- static SCM: [`DoIntervention`](@ref)

Hard pins use SciML `DiscreteCallback` to reassert the value after accepted steps
(no in-RHS mutation of `u`). Soft force and RHS replacement modify `du` only.
Optional `parents` on [`ContinuousCDMSpec`](@ref) record the continuous causal
parent graph ([`continuous_cdm_graph`](@ref)).
Executable recipe: `examples/sciml_cdm_recipe.jl`.

## Representation bridge (high-dim → codes)

Before SciML or estimation on imaging/spectral inputs, compress with
[`RepresentationSpec`](@ref) / [`encode_to_panel`](@ref) so the DAG and
nuisance models see low-dim codes, not raw tensors. Roles `:measurement` vs
`:definitional` are recorded in [`representation_certificate`](@ref). Example:
`examples/representation_bridge.jl`. Graph-constrained deep mechanisms
(``f_i`` / UDE residuals) are planned as a later weakdep phase; UniversalDiffEq
remains an external advanced trainer (below).

## UniversalDiffEq

Use CausalDynamics for **adjustment / `do` semantics**; use
[UniversalDiffEq.jl](https://github.com/Jack-H-Buckner/UniversalDiffEq.jl) to
learn `f` from series. Do not expect UDE training inside CausalDynamics core.

ODE parent ranking across environments
([`infer_ode_parents`](@ref); CausalKinetiX reference method
[@pfister2019causalkinetix]) is documented in [Methods adoption](METHODS_ADOPTION.md)
and bridges into [`ContinuousCDMSpec`](@ref) via [`ode_parent_ranking_to_continuous_spec`](@ref).

## Version note

- **0.2** — `DiscreteTimeCDM`, time-indexed unrolling helpers
- **0.3** — `CausalDynamicsSciMLExt` weakdep (`ContinuousCDMSpec`, `solve_cdm`, `do(·)` RHS wrapper)
- **0.3.x** — unified [`AbstractCausalIntervention`](@ref); SciML-native `DoPin` (`DiscreteCallback`); IEE → `TemporalDAGSpec`
