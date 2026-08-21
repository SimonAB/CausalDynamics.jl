# Deep SCM stress

Application-scale Quarto stress for the **representation bridge** and
**graph-constrained deep mechanisms** (Phase 1–2b). Package `test/` remains the
merge gate.

**Quarto notebook:**
[`docs/stress/deep_scm_stress.qmd`](https://github.com/SimonAB/CausalDynamics.jl/blob/main/docs/stress/deep_scm_stress.qmd)

```bash
cd docs/stress && quarto render deep_scm_stress.qmd
```

**Estimation on codes** (mediation / LMTP / missing $Y$):
[CausalTargeted deep_scm_estimation_stress.qmd](https://github.com/SimonAB/CausalTargeted.jl/blob/main/docs/stress/deep_scm_estimation_stress.qmd).

**Landing:** [STRESS.md](https://github.com/SimonAB/CausalDynamics.jl/blob/main/STRESS.md).

Covers: large / wide encode, AgeSCM-pattern Lux 1D-CNN stub, ODE residual +
`do_pin`, generative L3 (scalar and multi-dim), Phase 1→2b hand-off, NaN
passthrough.

**Deferred (not in this notebook or core):** UniversalDiffEq hard wiring,
Flux-in-CausalDynamics, non-additive image DeepSCM, full MIRS cohort files.
