# Discrete-time CDMs

Causal Dynamical Models advance named endogenous state over discrete occasions
`t = 1:T`. Use [`DiscreteTimeCDM`](@ref) with [`simulate`](@ref) for observational
or interventional trajectories, and [`counterfactual`](@ref) to reuse realised
exogenous draws under an alternate [`DoSequence`](@ref).

```@docs
AbstractCDM
DiscreteTimeCDM
CDMTrajectory
CDMPanel
panel_column_name
trajectory_wide_row
simulate_panel
ObservationBridge
identity_observation
observe_series
observe_trajectory
panel_from_trajectories
panel_from_latent_series
simulate_observed_panel
ObservationMask
observation_mask
n_units
miss_rates
require_complete_values
require_complete_matrix
apply_observation_mask
apply_missingness_mechanism
simulate_incomplete_panel
RepresentationSpec
representation_certificate
encode_to_panel
MechanismSpec
MechanismLibrary
mechanism_library_from_cdm
register_mechanism!
mechanism_certificate
lux_mechanisms_available
attach_lux_mechanism!
build_ode_rhs
graphscm_with_mechanisms
train_mechanisms!
pack_parent_vector
abduce_noise
generate_from_noise
mechanism_counterfactual
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

## Observational panels (estimation hand-off)

[`simulate_panel`](@ref) stacks `n` natural trajectories into a wide
[`CDMPanel`](@ref) for sequential LMTP. Column roles:

- **baseline** — bare symbol, value at ``t = 1`` (e.g. `:w`)
- **timed** — [`panel_column_name`](@ref)`(v, t)` → `:a1`, `:a2`, …
- **terminal** — bare symbol at occasion ``T`` (e.g. `:y`)

```julia
using DataFrames

panel = simulate_panel(
    cdm, 200, 2;
    baseline = [:w],
    timed = [:a, :l],
    terminal = [:y],
)
df = DataFrame(NamedTuple(panel))  # or DataFrame(panel) when CausalDynamicsDataFramesExt is loaded
```

Leave `intervention = nothing` for observational estimation. Interventional
Monte Carlo effects stay on [`g_computation`](@ref); CausalTargeted consumes
`df` via `sequential_spec_from_identification` / `execute_estimand`.

## Latent → observed panels

When latents are inferred outside CausalDynamics (filter, smoother, EM), map them
with [`ObservationBridge`](@ref) and [`panel_from_latent_series`](@ref). No
Kalman/particle code lives here—only the typed hand-off to wide panels.

```julia
bridge = ObservationBridge(
    Dict(:y_hat => :y);
    measure = (state, t) -> (y_hat = state.x,),  # e.g. use latent x as assay
)
panel = panel_from_latent_series(
    inferred_units;  # Vector{<:Dict} of series
    bridge = bridge,
    timed = [:y],
    terminal = Symbol[],
)
```
