# Stress validation

Package `test/` remains the merge gate for CausalDynamics.jl; the Quarto stress
notebooks below provide pre-ship and application-scale probes.

## Deep SCM stress

Application-scale Quarto stress for the **representation bridge** and
**graph-constrained deep mechanisms** (Phase 1–2b):

- **Quarto notebook:**
  [`docs/stress/deep_scm_stress.qmd`](https://github.com/SimonAB/CausalDynamics.jl/blob/main/docs/stress/deep_scm_stress.qmd)
- **Landing ledger:**
  [`STRESS.md`](https://github.com/SimonAB/CausalDynamics.jl/blob/main/STRESS.md)
- **Estimation on codes** (mediation / LMTP / missing ``Y``):
  [CausalTargeted `deep_scm_estimation_stress.qmd`](https://github.com/SimonAB/CausalTargeted.jl/blob/main/docs/stress/deep_scm_estimation_stress.qmd) ·
  [CausalTargeted stress validation](https://simonab.github.io/CausalTargeted.jl/dev/stress_validation/)

```bash
cd docs/stress && quarto render deep_scm_stress.qmd
```

Covers: large / wide encode, AgeSCM-pattern Lux 1D-CNN stub, ODE residual +
`do_pin`, generative L3 (scalar and multi-dim), Phase 1→2b hand-off, and `NaN`
passthrough.

**Deferred (not in this notebook or core):** `UniversalDiffEq` hard wiring,
`Flux`-in-core, non-additive image DeepSCM, and full MIRS cohort files.

## Hierarchical nesting stress

Application-scale probes for nested exogenous ``U``, hierarchical DAG unrolling,
and the CausalTargeted cluster-robust MSM hand-off:

- **Quarto notebook:**
  [`docs/stress/hierarchy_stress.qmd`](https://github.com/SimonAB/CausalDynamics.jl/blob/main/docs/stress/hierarchy_stress.qmd)

```bash
cd docs/stress && quarto render hierarchy_stress.qmd
```

See also [Hierarchical / nested units](hierarchy.md) and the application
MixedModels recipe in
[`examples/hierarchical_mixedmodels_concordance.md`](https://github.com/SimonAB/CausalDynamics.jl/blob/main/examples/hierarchical_mixedmodels_concordance.md).
