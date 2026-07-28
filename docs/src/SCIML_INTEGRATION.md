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
adjustment sets from identification.

## Bridge to ODEs (application code)

When the mechanism is continuous, keep **causal structure** in CausalDynamics and
**integration** in SciML:

```julia
using CausalDynamics, Graphs
# using OrdinaryDiffEq  # optional; in your app environment

g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y
adj = backdoor_adjustment_set(g, 2, 3)

function cdm_dynamics!(du, u, p, t)
    Z, X, Y = u
    du[1] = p.λ_z * Z
    du[2] = p.α * X + p.β * Z
    du[3] = p.γ * Y + p.δ * X + p.ε * Z
end

# prob = ODEProblem(cdm_dynamics!, u0, tspan, p)
# sol = solve(prob)
```

Book walkthrough: [Ch. 28 — Learning CDMs from Data](https://simonab.github.io/causal-dynamics-book/part-observable/28-cdms-unified.html#learning-cdms-from-data).

## UniversalDiffEq

Use CausalDynamics for **adjustment / `do` semantics**; use
[UniversalDiffEq.jl](https://github.com/Jack-H-Buckner/UniversalDiffEq.jl) to
learn `f` from series. Do not expect UDE training inside CausalDynamics core.

## Version note

- **0.2** — `DiscreteTimeCDM`, time-indexed unrolling helpers
- **0.3+** — optional weakdep SciML recipe module if demand warrants (still no solver in core)
