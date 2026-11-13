## Known-noise nonlinear state inference contract

This milestone adds scalar extended Kalman filtering and extended RTS smoothing.
It does not change the existing bistable batch fit or estimate unknown model
parameters. All reported posterior moments are approximations to the nonlinear
model. The affine limit must agree with the independent dense Gaussian oracle.

### Model and public API

The first represented state has the supplied Gaussian prior. For represented
model time t, the transition is x(t+1)=f(x(t),t)+epsilon(t), with known process
variance Q>0. Measurements are y(t)=h*x(t)+c+eta(t), with known R>0. Missing
measurements omit their likelihood. The first represented time defaults to 0;
array row j represents initial_time+j-1. These are scalar states and scalar
measurements only.

Add `infer_nonlinear_state_space(y; transition, transition_derivative,
process_variance, observation_variance, initial_mean, initial_variance,
observation=1.0, observation_offset=0.0, initial_time=0)` to the existing
optional GraphPPL/RxInfer/DataFrames integration. Both callbacks take `(x,t)`
and must be deterministic, use declared constants, and return finite real
values. The derivative is the derivative with respect to x at the same point.
The caller supplies it explicitly; no outcome-derived parameter fit or hidden
automatic differentiation is performed. Validate nonempty vector observations,
finite scalars, positive variances and integer initial_time. Missing predictor
or unknown-parameter inference is outside this API.

### Filtering and local Gaussian approximation

At each transition from filtered mean m(t), evaluate F(t)=df(m(t),t) and
b(t)=f(m(t),t)-F(t)*m(t). Define predicted mean a(t+1)=f(m(t),t) and variance
Pminus(t+1)=F(t)^2*P(t)+Q. For an observed y, K=Pminus*h/(h^2*Pminus+R),
m=a+K*(y-h*a-c), and P=(1-K*h)^2*Pminus+K^2*R (Joseph form). Missing y
leaves prediction unchanged. The initial observation updates the stated prior
without a preceding transition.

The resulting F(t),b(t) determine a time-varying linear Gaussian surrogate.
For complete data with h!=0, specify this surrogate in GraphPPL and run exact
RxInfer Gaussian sum-product messages without variational iterations. Its
smoothed marginals must agree with analytic extended RTS smoothing. For missing
data or h=0, use analytic smoothing, with an explicit backend/reason, to avoid
singular backward information messages. This is exact inference for the chosen
surrogate, not exact nonlinear inference or an iteratively optimised posterior.

The smoother uses J(t)=P(t)*F(t)/Pminus(t+1), mS(t)=m(t)+J(t)*(mS(t+1)-a(t+1)),
and PS(t)=P(t)+J(t)^2*(PS(t+1)-Pminus(t+1)). Cross-time covariance is
CovS(t,s)=J(t)*...*J(s-1)*PS(s), t<s. These gains belong to this same surrogate;
do not apply them to the established bistable RxInfer batch marginals.

Reject nonfinite callback values, overflowed moments or nonpositive variances
with informative errors. Do not clip eigenvalues or silently substitute other
uncertainty. A successful numerical fit does not certify posterior accuracy.

### Result, continuation and provenance

Create `NonlinearGaussianStateResult` in the extension. Retain the linear result
conventions: means are n-by-1 matrices; covariance and gain vectors contain
one-by-one matrices (filter gains may be one-by-zero for missing y); `posterior`
is the final filtered mean vector/covariance matrix. Store model callbacks and
constants, raw RxInfer inference or nothing, n, backend, and linearisation
slopes, offsets, predicted means and predicted variances.

Factor the existing covariance accessors through a shared abstract result
supertype or shared private helpers. Preserve all existing linear API results.
`state_crosscovariance` and `trajectory_covariance` must work on both types.
Certificate fields include exact=false, parameters=:known,
approximation=:extended_kalman_rts, linearisation=:filtering_means,
covariance=:local_gaussian, initial_time, backend and backend reason. Distinguish
surrogate Gaussian exactness from the nonlinear posterior approximation.

Overload `update_state_posterior` for the new result. Forecast exactly one
transition from the previous final filtered posterior, using callback time
previous.model.initial_time+previous.n-1. The new segment begins at the next
integer time and consumes new observations only. Defaults reuse the stored
model. Reject initial_mean, initial_variance and initial_time overrides;
validate any explicitly changed model constants/callbacks before forecasting.
Returned smoothing and joint covariance cover only the new segment.

### Implementation packets and ownership

1. Engine worker owns new ext/nonlinear_state_space.jl and its new unit tests.
   Write failing behavioural tests before production code. Tests include
   nontrivial affine time-dependent callbacks, nonzero offsets, complete and
   missing data, zero observation h, initial observation timing, one-step and
   multi-step continuation, all covariance blocks, invalid inputs and callback
   failures. Use the existing independent dense oracle, not an EKF clone.
2. Reference worker owns new test/nonlinear_state_reference.jl and an optional
   stress script. Build a deterministic scalar-grid forward/backward reference
   for the original nonlinear likelihood, independently of fitted moments.
   Validate grid-spacing and domain convergence separately. Include affine,
   weakly nonlinear, missing-observation and genuinely bimodal fixtures.
3. Supervisor owns integration, facade/exports, shared covariance dispatch,
   documentation, statistical gates and final review. Do not merge or register
   this milestone into the exact 0.5.1 release.

### Independent reference and acceptance gates

Use a finite uniform grid with trapezoidal quadrature weights. Transition
columns use the original Gaussian density times destination integration weight;
do not normalise each transition column, which would change the model at domain
boundaries. Normalise complete forward likelihoods globally at each occasion.
Backward messages and reverse conditional kernels recover smoothing and
cross-time moments. Repeat at smaller spacing and wider domains; report lost
boundary mass and actual convergence, never infer it from algorithm convergence.

Affine fixtures must match dense Gaussian moments and every joint covariance
block to 1e-6 or better, with batch/continuation agreement for all new-segment
moments. The reference must itself match that oracle before use on nonlinear
examples. For a prespecified weak nonlinearity f(x,t)=0.8*x+0.05*sin(x),
Q=0.15,R=0.25,h=1,c=0, prior N(0,0.8), observations
[0.2,-0.1,0.4,0.3,-0.2,0.1], require reference refinement below 1e-4 in
standardised means and relative covariance norm, mean error <=0.2 reference SD,
and joint covariance relative Frobenius error <=0.25. Keep these thresholds
unchanged. Other fixtures report errors without weakening this gate.

The bimodal fixture is diagnostic: Gaussian approximation cannot represent two
wells. Report reference mode structure, posterior content of Gaussian intervals,
mean/covariance errors and numerical failures. No universal nonlinear coverage
or calibration claim is permitted. Optional simulation batches separate
prior-predictive calibration from fixed-state experiments and report Monte
Carlo uncertainty. Benchmark warm inference separately from compilation and
reference work, without claiming an MCMC speed ratio.
