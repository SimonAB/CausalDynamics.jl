## Known-noise nonlinear states

The development `infer_nonlinear_state_space` API provides scalar extended
Kalman filtering and extended Rauch–Tung–Striebel smoothing. Transition and
noise parameters are supplied constants. The observation model is linear;
nonlinear observations and unknown parameter inference are deferred.

```julia
using CausalDynamics, RxInfer, GraphPPL, DataFrames
transition = (x, t) -> 0.8x + 0.05sin(x)
derivative = (x, t) -> 0.8 + 0.05cos(x)
states = infer_nonlinear_state_space([0.2, -0.1, 0.4, 0.3, -0.2, 0.1];
    transition, transition_derivative = derivative,
    process_variance = 0.15, observation_variance = 0.25,
    initial_mean = 0.0, initial_variance = 0.8)
lag_covariance = state_crosscovariance(states, 1, 2)
joint_covariance = trajectory_covariance(states)
continued = update_state_posterior(states, [missing, 0.2])
```

Both callbacks take `(x,t)`; the derivative is with respect to x. The initial
prior applies to the first represented state, at `initial_time=0` by default.
Array row j represents time `initial_time+j-1`; a transition callback at t
maps the state at t to the state at t+1. The first observation updates the
supplied prior without an extra transition.

### Which posterior is represented?

The forward filter chooses a tangent transition at each filtered mean. These
slopes and offsets specify a single time-varying Gaussian surrogate. Complete
informative observations use GraphPPL/RxInfer Gaussian messages for smoothing;
missing measurements or a zero observation coefficient use analytic RTS
smoothing. Both routes describe this same surrogate.

Consequently, `certificate.exact` is false for the nonlinear model, while
`certificate.surrogate_exact` records exact inference within the declared
local Gaussian approximation. Cross-time covariance is recovered from that
surrogate's smoothing gains. It does not describe the joint distribution of
the existing bistable batch fit, which is a separate approximation.

Means have one column and time in rows. Covariance vectors hold one-by-one
matrices, following the exact linear API. Joint covariance uses time-major
order. `posterior` is the final filtered state, rather than a retrospectively
smoothed estimate of a past state. Diagnostic fields retain transition slopes,
offsets and predicted moments.

### Updating and assumptions

Continuation forecasts one transition from the previous filtered posterior,
consumes only new observations, and advances the callback's model time.
Smoothing and joint covariance in the returned object cover the new segment.
Initial-prior and initial-time overrides are rejected. Explicit changes to
declared transition or noise constants condition on a different supplied model;
they do not estimate those parameters from the data.

Callbacks must remain deterministic and unchanged after fitting, and their
derivatives must be correct. Missing measurements remove their likelihood;
they are not replaced by large-variance pseudo-observations. Invalid callback
values or nonpositive numerical variances fail explicitly. The method supplies
no uncertainty for parameter estimates or an unknown observation mechanism.

### Validation and limitations

The affine limit is checked against an independent dense Gaussian oracle,
including every cross-time covariance block and batch/continuation agreement.
A separate scalar-grid forward/backward reference checks the original nonlinear
model, with grid spacing and domain refinement tested independently. The
prespecified weakly nonlinear fixture has fixed mean and covariance error gates;
a two-well fixture reports the failure of a single Gaussian to represent
bimodality. Numerical convergence alone does not establish posterior accuracy.

See [the implementation contract](https://github.com/SimonAB/CausalDynamics.jl/blob/main/docs/NONLINEAR_STATE_INFERENCE.md)
and the reproducible `test/stress/nonlinear_state_validation.jl` script.
The [validation report](https://github.com/SimonAB/CausalDynamics.jl/blob/main/docs/NONLINEAR_STATE_VALIDATION.md)
records both the weakly nonlinear agreement and the large two-well covariance
error, alongside the small-model benchmark.
This experimental API makes no general nonlinear calibration claim.

```@docs
CausalDynamics.infer_nonlinear_state_space
```
