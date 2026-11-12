## Exact linear Gaussian state inference

```@docs
CausalDynamics.infer_linear_state_space
CausalDynamics.update_state_posterior
CausalDynamics.state_crosscovariance
CausalDynamics.trajectory_covariance
```

`infer_linear_state_space` uses GraphPPL/RxInfer for a known linear transition
and observation model, with known Gaussian process and measurement covariance.
It preserves vector-state dependence and returns filtering and smoothing
moments. Loading the optional RxInfer integration enables this API.

Complete observations with a full-column-rank observation matrix use exact
RxInfer Gaussian messages. Missing components or a rank-deficient observation
matrix select the exact analytic Kalman/RTS path, recorded in result provenance.
This avoids a native message rule that attempts to invert singular likelihood
precision. The analytic path returns `raw = nothing`; it does not approximate
missing observations by adding very large measurement noise.

```julia
using CausalDynamics, RxInfer
states = infer_linear_state_space([0.1, missing, 0.4];
    transition = 0.9, observation = 1.0,
    process_covariance = 0.1, observation_covariance = 0.2,
    initial_mean = 0.0, initial_covariance = 1.0)
lag_covariance = state_crosscovariance(states, 1, 2)
updated = update_state_posterior(states, [0.5])
```

Missing measurement components use the corresponding rows of the observation
model and noise covariance. Updating begins from the final filtered state and
consumes only the newly supplied observations. Smoothing additionally uses later
observations; it is not the online filtering posterior.

Smoothing gains recover adjacent-time and longer-lag cross-covariances.
`trajectory_covariance` constructs the joint covariance in time-major order on
request. Marginal state variances alone cannot determine trajectory uncertainty.

All matrices and noise parameters are declared constants. Unknown transition or
noise parameters and nonlinear state models require separate inference and
validation. The experimental bistable example remains an approximation.

The independent validation oracle conditions a dense joint Gaussian trajectory,
including correlated multivariate states, missing measurements and offsets.
The implementation follows the Gaussian filtering and smoothing identities in
[Särkkä and Svensson](https://users.aalto.fi/~ssarkka/pub/bfs_book_2023_online.pdf).
