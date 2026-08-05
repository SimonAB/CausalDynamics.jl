## Registration status

CausalDynamics.jl is on the Julia **General** registry.

Install: `Pkg.add("CausalDynamics")`. Requires Julia **1.12+**.

| Version | Status |
|---------|--------|
| **0.3.16** | On General ([#163619](https://github.com/JuliaRegistries/General/pull/163619)) |
| **0.4.0** | Pending Registrator — mediation ID (`moc`, `effect_kind`, `IdentificationError`) |

Local `main` targets **0.4.0**. Register **incrementally** (no version skips).

## 0.4.0 register steps

1. Push `main` with `version = "0.4.0"`
2. Comment `@JuliaRegistrator register` on the release commit or tracking issue
3. Wait for General AutoMerge; TagBot tags `v0.4.0` if needed

## Prerequisites (met)

1. **DAGMakie on General** — done (`0.1.6`).
2. **CausalInference on General** — hard dep; local CDCS fork is optional for development.
3. **Core tests pass without DAGMakie** in default `[targets] test`.
4. **No `[sources]`** in `Project.toml` (path deps are CDCS-only).

## Downstream

- **CausalMediation.jl** requires `CausalDynamics = "0.4"` (uses `moc` / mediation strategies).
- **CausalTargeted.jl** should bump compat to `"0.4"` when adopting 0.4 certificates.
