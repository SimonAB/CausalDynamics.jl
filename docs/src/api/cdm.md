# Discrete-time CDMs

Causal Dynamical Models advance named endogenous state over discrete occasions
`t = 1:T`. Use [`DiscreteTimeCDM`](@ref) with [`simulate`](@ref) for observational
or interventional trajectories, and [`counterfactual`](@ref) to reuse realised
exogenous draws under an alternate [`DoSequence`](@ref).

```@docs
AbstractCDM
DiscreteTimeCDM
CDMTrajectory
AbstractIntervention
DoSequence
do_sequence
AbstractDoAssignment
ConstantAssignment
SeriesAssignment
TimedAssignment
Policy
policy
intervention_value
simulate
counterfactual
GComputationResult
g_computation
```

## Minimal example

```julia
using CausalDynamics
using Random

cdm = DiscreteTimeCDM(
    [:x, :y];
    initialise = (rng) -> (x = 1.0, y = 1.0),
    sample_noise = (rng, state, t) -> (u_x = randn(rng), u_y = 0.1 * randn(rng)),
    step = (state, t, noise, intervention) -> begin
        x = 0.5 * state.x + noise.u_x
        y = x + noise.u_y
        (x = x, y = y)
    end,
)

factual = simulate(cdm, 20; rng = Random.Xoshiro(1))
cf = counterfactual(
    cdm,
    factual.noise;
    intervention = do_sequence(:x, fill(0.0, 20)),
    initial = (x = 1.0, y = 1.0),
)
```

Inside `step`, call [`intervention_value`](@ref) for any intervenable assignment
so the same structural map works under observation and `do(·)`.

## Soft interventions (policies)

A [`DoSequence`](@ref) fixes a value regardless of state. A [`Policy`](@ref)
assigns via a rule `(state, t) -> value`, so treatment can react to the system.
Pass `state` as the fifth argument to [`intervention_value`](@ref):

```julia
step = (state, t, noise, intervention) -> begin
    a = intervention_value(intervention, :a, t, 0.5 * state.a + noise.u_a, state)
    (a = a, y = 2a + noise.u_y)
end

# Treat only when the previous action was non-positive
π = policy(:a, (state, t) -> state.a <= 0 ? 1.0 : 0.0)
traj = simulate(cdm, 20; intervention = π)
```

## Performance notes

`simulate` preallocates one vector per variable (length `T`) from the element types
returned by `initialise` and `sample_noise`, so the cost of a run is dominated by
your `step` function.

- **Keep `step` type-stable.** Return the same `NamedTuple` field names and element
  types on every call; a variable that is `Int` at `t = 1` and `Float64` later forces
  boxed storage. Prefer `0.0` over `0` in `initialise`.
- **Avoid allocation inside `step`.** Build the returned `NamedTuple` directly rather
  than assembling intermediate arrays or dictionaries.
- **Reuse noise for counterfactuals.** `counterfactual` copies the supplied noise
  once; it does not resample, so contrasting many interventions against one factual
  run is cheap.
- **Batch with `g_computation`.** Replicates advance a single `rng`, so results are
  reproducible from one seed without allocating a generator per replicate.

## Interventional means (g-computation)

[`g_computation`](@ref) estimates `E[outcome ∣ do(·)]` by Monte Carlo over
replicate trajectories. Contrast two interventions for an effect:

```julia
treated = g_computation(cdm, 20, :y; intervention = do_sequence(:a, 1.0), n = 500)
control = g_computation(cdm, 20, :y; intervention = do_sequence(:a, 0.0), n = 500)
effect = treated.mean - control.mean
```
