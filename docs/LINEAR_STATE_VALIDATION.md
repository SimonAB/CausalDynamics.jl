## Linear Gaussian state validation

Local development run: Julia 1.13.3, 20 threads, RxInfer 6.1.3. Reproduce with
`julia --project=test/stress --threads=auto test/stress/linear_bayesian_calibration.jl`
after `Pkg.instantiate()` in that stress environment (package plus RxInfer extras).

Seed 20261112 generated 500 independent trajectories, each with 20 states.
All transition, observation and noise parameters were known. The missing-data
design omitted observations at times 3,7,12,18. Monte Carlo errors treat
trajectories as independent; repeated occasions are not independent trials.

| Backend/design | Filtering coverage at t=10 / t=20 | Smoothing coverage at t=10 / t=20 |
| --- | --- | --- |
| RxInfer / complete | 95.0% / 95.6% | 95.8% / 95.6% |
| Analytic / missing | 95.0% / 95.2% | 96.0% / 95.2% |

Pointwise MCSE was 0.88–0.97 percentage points. Maximum absolute disagreement
with the independent dense joint Gaussian oracle was 1.78e-15.

Warmed median complete-API timings: RxInfer complete 3.788 ms, 3,059,920 bytes;
analytic missing 45 microseconds, 81,024 bytes. The observation patterns differ,
so these measurements do not establish a controlled backend speed ratio.
First-call times were 10.18 s and 0.339 s respectively, predominantly compilation.

Missing or partially observed states deliberately use the analytic path because
the native covariance message attempts to invert singular likelihood precision.
Both paths remain exact for the declared known-parameter Gaussian model. This
validation does not cover unknown parameters or nonlinear approximations.

Release compatibility checks passed on Julia 1.12.7 and 1.13.3 with registered
RxInfer 4.7.3, 5.5.3 and 6.1.3 (GraphPPL 4.6.6 with RxInfer 4; 4.9.0 with
RxInfer 5/6). Each combination passed 71 exact-state assertions and a
fresh-process extension-activation test. The full Julia 1.13.3 package suite
passed 1,639 assertions. Continuation rejects initial-prior overrides rather
than discarding them silently.
