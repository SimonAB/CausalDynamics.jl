## Registration status

CausalDynamics.jl is on the Julia **General** registry.

Install: `Pkg.add("CausalDynamics")`. Requires Julia **1.12+**.

| Version | Status |
|---------|--------|
| **0.3.16** | On General ([#163619](https://github.com/JuliaRegistries/General/pull/163619)) |
| **0.4.0** | On General ([#163649](https://github.com/JuliaRegistries/General/pull/163649), merged 2026-08-05) |
| **0.4.7** | On General (tree `501f55ee96f4098690befdca0d6240999df6ee90`); TagBot tagged `v0.4.7` |
| **0.4.6** | On General ([#166644](https://github.com/JuliaRegistries/General/pull/166644), merged 2026-08-31) — `family_outcome`, session slice, missingness `:structural_skip` |
| **0.4.5** | Shipped in 0.4.6 tip (session-slice planner) |
| **0.4.4** | Shipped in 0.4.6 tip (`EstimationPlan.family_outcome`) |
| **0.4.3** | On General — panel bridge, OutcomeKind, empirical EstimationPlan, occasion resolution |
| **0.4.2** | Skipped on General |
| **0.4.1** | On General ([#163720](https://github.com/JuliaRegistries/General/pull/163720), merged 2026-08-06) |

Version **0.4.7** is registered and tagged. The development tip includes
subsequent RxInfer 6 compatibility work; that change is not part of the
registered release.

## 0.4.7 register steps

Registration is complete; [General](https://github.com/JuliaRegistries/General/blob/master/C/CausalDynamics/Versions.toml)
contains **0.4.7**, and TagBot tagged `v0.4.7` at `b53d8f1`.

## 0.4.6 register steps

1. Push `main` with `version = "0.4.6"`
2. Comment `@JuliaRegistrator register` on [issue #7](https://github.com/SimonAB/CausalDynamics.jl/issues/7)
3. General AutoMerge — done ([#166644](https://github.com/JuliaRegistries/General/pull/166644)); TagBot tagged `v0.4.6`

## 0.4.3 register steps

1. Push `main` with `version = "0.4.3"` — done (`cc36948`, doc fix `c421371`)
2. Comment `@JuliaRegistrator register` — done (issue #7)
3. General AutoMerge — pending

## 0.4.2 register steps

1. Push `main` with `version = "0.4.2"` — done (`e0af719`)
2. Comment `@JuliaRegistrator register` — done ([issue #7](https://github.com/SimonAB/CausalDynamics.jl/issues/7#issuecomment-5414845977))
3. General AutoMerge — pending

## 0.4.1 register steps

1. Push `main` with `version = "0.4.1"` — done (`01f7c38`)
2. Comment `@JuliaRegistrator register` — done ([issue #7](https://github.com/SimonAB/CausalDynamics.jl/issues/7))
3. General AutoMerge — **merged** ([#163720](https://github.com/JuliaRegistries/General/pull/163720)); TagBot tagged `v0.4.1`

## Prerequisites

1. **DAGMakie on General** — `0.1.11` is registered; required by the
   temporal plotting extension (`dagplot_temporal`).
2. **CausalInference on General** — hard dep; local CDCS fork is optional for development.
3. **Core tests pass without DAGMakie** in default `[targets] test`.
4. **No `[sources]`** in `Project.toml` (path deps are CDCS-only).

## Downstream

- **CausalMediation.jl** **0.1.2** is on General; requires `CausalDynamics = "0.4"` (uses `moc` / mediation strategies).
- **CausalTargeted.jl** **0.3.29** is on General and requires CausalDynamics **0.4.7+** for `CDMProvenance`.
