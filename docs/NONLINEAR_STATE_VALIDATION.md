## Nonlinear state validation

This report concerns the experimental development API, not the exact linear
state API registered in CausalDynamics 0.5.1. Parameters and Gaussian noise
variances are known. The approximation describes one local Gaussian surrogate;
it does not estimate parameter uncertainty.

Reproduce from an environment containing CausalDynamics and its RxInfer,
GraphPPL and DataFrames extras:

```sh
julia --project=. --threads=auto test/stress/nonlinear_state_validation.jl report.txt
```

The reference uses the original nonlinear transition density on a trapezoidal
grid. Destination integration weights enter the transition matrix; its columns
are not separately normalised. Independent spacing and domain refinements
check truncation and discretisation. The report includes lost-mass estimates
and posterior boundary mass; these are numerical diagnostics, not rigorous
error bounds. Reference code uses only Julia standard libraries.
Reported interval content is a grid-mass diagnostic: convergence of moments
does not certify tail integrals or quantiles. No interval-tail accuracy claim
is inferred from the mean and covariance gates.

### Deterministic accuracy

Local validation used Julia 1.13.3, RxInfer 6.1.3 and one BLAS thread. All 33
stress assertions passed. The independent dense Gaussian oracle and grid
reference agreed to 1.39e-16 in affine means and 5.55e-17 in joint covariance.
The engine, every covariance block, and continuation agreed with dense affine
conditioning within 1e-6, including time-varying slopes and missing data.

The full package suite passed 1,920 assertions. Focused compatibility checks
passed on Julia 1.12.7 and 1.13.3 with RxInfer 4.7.3, 5.5.3 and 6.1.3:
353 assertions per combination, including 273 nonlinear engine checks and
eight independently refined reference checks. These repeated compatibility
runs establish backend agreement, not calibration beyond the stated fixtures.

For the prespecified transition `0.8x + 0.05sin(x)`, six supplied observations,
prior N(0,0.8), Q=0.15 and R=0.25, the maximum mean error was 0.001735
reference posterior SD and joint covariance relative Frobenius error was
0.002914. These pass the unchanged bounds of 0.2 SD and 0.25. With two missing
observations, the diagnostic errors were 0.002775 SD and 0.004858 respectively.
Spacing and domain changes were below 4e-16 for these smooth fixtures.

### Bimodality remains a failure case

The bounded transition `1.5tanh(x)` with weak observations produces two
reference posterior modes at approximately -1.25 and 1.25. Domain refinement
changed joint covariance by 8.91e-8 relative norm; outer-grid posterior mass
was 3.68e-15. The Gaussian approximation retained a near-zero mean while its
joint covariance error reached **48.49** in relative Frobenius norm. Its
nominal 95% intervals contained essentially all the reference posterior at
later occasions, indicating severe overdispersion.

This case is retained as a diagnostic rather than weakened into an acceptance
test. A small mean error can conceal a poor posterior distribution. A single
Gaussian cannot represent the two wells; successful computation is not evidence
of acceptable posterior accuracy. Interval posterior content here is not
repeated-sampling coverage.

### Performance and scope

The warmed complete API took a median **1.14 ms**, allocating **873,584 bytes**
for six observations over 20 timing samples. Reference construction and
compilation are excluded. This is a small local benchmark, not a controlled
comparison against MCMC or another backend.

The default tests retain a separately refined weak-fixture reference gate,
independent affine oracles, every covariance block, initial-observation timing,
missing measurements, zero observation coefficients, continuation, and numerical
failure checks. These examples establish bounded-scope numerical accuracy;
they do not establish general nonlinear calibration, robustness to unknown
parameters, or causal identification.
