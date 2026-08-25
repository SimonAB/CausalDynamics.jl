## Registration status

CausalDynamics.jl is on the Julia **General** registry.

Install: `Pkg.add("CausalDynamics")`. Requires Julia **1.12+**.

| Version | Status |
|---------|--------|
| **0.3.16** | On General ([#163619](https://github.com/JuliaRegistries/General/pull/163619)) |
| **0.4.0** | On General ([#163649](https://github.com/JuliaRegistries/General/pull/163649), merged 2026-08-05) |
| **0.4.2** | Local tip of `main` — hierarchical nested ``U`` / `simulate_hierarchical_panel` |
| **0.4.1** | On General ([#163720](https://github.com/JuliaRegistries/General/pull/163720), merged 2026-08-06) |

Local `main` targets **0.4.2**. Register **incrementally** (no version skips).

## 0.4.2 register steps

1. Push `main` with `version = "0.4.2"` — done (`e0af719`)
2. Comment `@JuliaRegistrator register` — done ([issue #7](https://github.com/SimonAB/CausalDynamics.jl/issues/7#issuecomment-5414845977))
3. General AutoMerge — pending

## 0.4.1 register steps

1. Push `main` with `version = "0.4.1"` — done (`01f7c38`)
2. Comment `@JuliaRegistrator register` — done ([issue #7](https://github.com/SimonAB/CausalDynamics.jl/issues/7))
3. General AutoMerge — **merged** ([#163720](https://github.com/JuliaRegistries/General/pull/163720)); TagBot tagged `v0.4.1`

## Prerequisites (met)

1. **DAGMakie on General** — done (`0.1.6`).
2. **CausalInference on General** — hard dep; local CDCS fork is optional for development.
3. **Core tests pass without DAGMakie** in default `[targets] test`.
4. **No `[sources]`** in `Project.toml` (path deps are CDCS-only).

## Downstream

- **CausalMediation.jl** **0.1.0** is on General ([#163653](https://github.com/JuliaRegistries/General/pull/163653)); requires `CausalDynamics = "0.4"` (uses `moc` / mediation strategies).
- **CausalTargeted.jl** **0.3.4** is on General ([#163904](https://github.com/JuliaRegistries/General/pull/163904)); sequential panel bridge needs CausalDynamics **0.4.1+** for `simulate_panel` / `panel_column_name` (compat already `"0.4"`).
