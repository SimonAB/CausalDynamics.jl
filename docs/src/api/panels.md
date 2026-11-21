# Panels, observation & masks

Wide longitudinal panels ([`CDMPanel`](@ref)), observation bridges mapping
latent states to measured columns ([`ObservationBridge`](@ref)), and
missingness masks ([`ObservationMask`](@ref)). For conceptual background on
missingness identification and handling, see the [Missingness guide](../missingness.md).

## Wide panels

```@docs
CDMPanel
panel_column_name
check_time_resolution
trajectory_wide_row
simulate_panel
```

### Observational panels (estimation hand-off)

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
Monte Carlo effects stay on [`g_computation`](@ref) in [Discrete-time CDMs](cdm.md);
CausalTargeted consumes `df` via `sequential_spec_from_identification` /
`execute_estimand`.

## Observation bridges

```@docs
ObservationBridge
available_at
information_set_at
identity_observation
observe_series
observe_trajectory
panel_from_trajectories
panel_from_latent_series
simulate_observed_panel
```

### Latent → observed panels

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

## Observation masks and missingness mechanisms

```@docs
ObservationMask
observation_mask
n_units
miss_rates
require_complete_values
require_complete_matrix
apply_observation_mask
apply_missingness_mechanism
simulate_incomplete_panel
```
