# Stress validation — Deep SCM (CausalDynamics)

Application-scale Quarto stress for the **representation bridge** and
**graph-constrained deep mechanisms** (Phase 1–2b). Package `test/` remains the
merge gate; this notebook is the pre-ship / methods notebook.

**Quarto notebook:**
[`docs/stress/deep_scm_stress.qmd`](docs/stress/deep_scm_stress.qmd)

```bash
cd docs/stress && quarto render deep_scm_stress.qmd
open deep_scm_stress.html
```

Activates the parent CDCS book `Project.toml` when present (Lux / Optimization /
OrdinaryDiffEq). Chunks use `#| warning: false`.

**Estimation hand-off** (mediation / LMTP on codes) lives in CausalTargeted:
[`docs/stress/deep_scm_estimation_stress.qmd`](https://github.com/SimonAB/CausalTargeted.jl/blob/main/docs/stress/deep_scm_estimation_stress.qmd).

**Documenter summary:** [stress_deep_scm.md](docs/src/stress_deep_scm.md).

## Last render

- **Date:** 2026-08-21
- **Julia:** 1.12.7 (`release` via CDCS `Project.toml`, Quarto `--project=../../../../`)
- **Artefact:** `docs/stress/deep_scm_stress.html` (local; gitignored)
- **Scope:** synthetic spectra + Lux CNN stub; ODE residual; generative L3;
  no UniversalDiffEq / Flux-in-core / full MIRS cohort
- **Ledger:** all Deep SCM Dynamics checks passed in this render
