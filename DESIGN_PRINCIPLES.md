# CDCS package design principles

Shared guidance for **owned** packages in this ecosystem (`CausalDynamics.jl`,
`CausalTargeted.jl`, `CausalMediation.jl`, `DAGMakie.jl`). Application repositories
(e.g. manuscript reproduction code) follow the same spirit but may trade leanness
for parity with reference implementations.

**Canonical copy in the CDCS monorepo:** this file under `packages/`.
Each owned package keeps an identical `DESIGN_PRINCIPLES.md` so GitHub README
links work outside the monorepo. After editing here, run:

`julia --project=. --threads=auto scripts/sync_shared_package_docs.jl`

See also per-package notes: [CausalDynamics.jl/DESIGN.md](CausalDynamics.jl/DESIGN.md), [CausalTargeted.jl/DESIGN.md](CausalTargeted.jl/DESIGN.md), [CausalMediation.jl/DESIGN.md](CausalMediation.jl/DESIGN.md), [DAGMakie.jl/DESIGN.md](DAGMakie.jl/DESIGN.md).

## 1. Julia first

- **Core logic lives in Julia.** Identification, simulation, estimation, and plotting are implemented here—not delegated to R, Python, or external CLIs for package APIs.
- **Reference implementations are for validation, not runtime.** Concordance with R or other tools belongs in application layers and tests, not in hot paths inside packages.
- **Prefer the JuliaGeneral registry and established SciML/JuliaDynamics stacks** over ad-hoc binaries or language bridges.

## 2. Julia native

- **Use idiomatic Julia:** multiple dispatch, parametric types where they clarify intent, `Struct`/`@kwdef` for configuration, and the type system for invalid states.
- **Embrace the ecosystem:** `Graphs.jl` for DAGs, `DataFrames.jl` for tabular workflows, `Makie` for graphics, `SciML` for differential equations—not transliterations of foreign APIs.
- **APIs speak standard causal vocabulary** (`do(·)`, backdoor adjustment, LMTP, EIF). Process-philosophy gloss belongs in the **book**, not in package docstrings or exports.
- **Unicode in code** is welcome when it matches surrounding mathematical notation (e.g. `σ_w`, `β`, `δ`).

## 3. Efficient

- **Type-stable hot paths.** Cross-fitting, grid loops, and graph algorithms should compile cleanly; fix inference failures rather than hiding them behind `Any`.
- **Thread where it is safe and measurable** (`Threads.@threads` on embarrassingly parallel δ-jobs; respect reproducibility via explicit RNG streams).
- **Cache expensive nuisances** when the estimand grid reuses the same folds (see `LMTPFoldCache` in CausalTargeted).
- **Avoid unnecessary copies** of large data frames; prefer views and column references where semantics allow.
- **Profile before micro-optimising.** Correctness and clarity come first; optimise bottlenecks identified by measurement.

## 4. Lean

- **Small, intentional dependency sets.** Hard dependencies are for always-on core functionality; everything else is a **weak dependency** loaded via package extensions.
- **No “kitchen sink” modules.** If a feature needs a heavy optional stack (PPL, discovery, TMLE.jl), expose it as an integration façade, not a required import.
- **Reject scope creep at the package boundary.** When in doubt, read `BOUNDARIES.md` for the package you are editing.
- **One clear owner per concern:** graphs/ID → CausalDynamics; LMTP / SL → CausalTargeted; mediation EIF → CausalMediation; DAG figures → DAGMakie; cohort/registry → application repo.

## 5. Composable

- **Pipeline-shaped APIs:** `graph → identify(query) → IdentificationResult → plan/execute estimand → certificate/metadata`.
- **Small, testable functions** composed in user code and in higher-level drivers—not monolithic “run everything” entry points in core packages (those belong in applications or thin orchestration layers).
- **Feature comparison** (Julia vs typical R/Python analogues, with Unique marks for integration): see [ECOSYSTEM_COMPARISON.md](ECOSYSTEM_COMPARISON.md) at the monorepo `packages/` root and each owned package’s copy.
- **Stable intermediate objects:** `IdentificationResult`, `MTPPlan`, `IdentificationCertificate` carry assumptions and hashes so downstream steps do not re-derive silently.
- **Column resolvers and node maps** bridge graphs to data without baking dataset column names into package code.
- **Plotting is optional.** CausalDynamics must work without Makie; DAGMakie must work without loading estimation code.

## 6. Explicit and auditable

- **Identification returns certificates**, not just adjustment vectors: strategy, assumptions, graph hash, identifiable flag.
- **Warn or fail** when backdoor sets are missing; do not silently proceed without documenting the assumption breach.
- **Run metadata** (learners, folds, engine, package version) attaches to estimation outputs for reproducibility.
- **Docstrings** on every export: arguments, returns, and a minimal example.

### Documentation tone

Documenter pages and README prose follow the [Julia Language manual](https://docs.julialang.org/en/v1/) voice:

- **Define first, then show code.** Lead with what the package or API *is*; put examples immediately after.
- **Calm and precise.** Avoid marketing (“publication-ready”, “showcase”, “start here”) and schoolbook framing (“this guide will help you”, “your first …”).
- **Adult-to-adult.** Capability language (`You can…`) is fine; prefer factual section titles over tutorial cheerleading.
- **Docstrings** use an imperative one-liner after the signature (`Return…`, `Compute…`), per the [Julia documentation conventions](https://docs.julialang.org/en/v1/manual/documentation/).
- **British spelling** in prose and docstrings (see §7).

## 7. Testable by construction

- **Synthetic DGPs in packages** (`simulate_linear_mtp`, small SCM fixtures) are the primary regression gate.
- **Real cohort data and manuscript registries** stay in application projects.
- **Integration tests** for optional extensions; core tests must pass with extensions unloaded.
- **British spelling** in prose and docstrings.

## 8. When to add code here vs elsewhere

| Question | If yes → | If no → |
|----------|----------|---------|
| Is it graph structure, ID, or CDM simulation? | CausalDynamics | — |
| Is it nested generative ``U`` / hierarchical DAG structure? | CausalDynamics | — |
| Is it cluster-robust IF / cluster missingness on estimands? | CausalTargeted (mediation EIFs → CausalMediation) | — |
| Is it LMM/GLMM/Bayes partial pooling? | Application repo (or RxInfer demo) | — |
| Is it cross-fitted LMTP estimation? | CausalTargeted | — |
| Is it mediation (RI / natural / RT / moc)? | CausalMediation | — |
| Is it DAG layout or styling? | DAGMakie | — |
| Is it cohort-specific, registry TOML, or R parity? | Application repo | — |
| Does it need a new heavy dependency? | Weakdep + extension | Or application layer |

## 9. Versioning and compatibility

- **Semver** for public API changes; document breaking identification or estimand types in release notes.
- **Latest compatible versions.** `[compat]` should allow the newest General releases the package actually supports. Widen bounds when upstream ships a new minor or major we can test; do not leave stale upper bounds that block `Pkg.update()`.
- **Compat sections** use major-bound constraints (`"0.3"`, `"1"`) unless a pin is documented in `AGENTS.md` (e.g. GraphMakie/Makie/Agents for the book).
- **Vendored checkouts** (CDCS `[sources]`): refresh to the latest upstream tag when bumping, then re-apply any remaining local patches. Drop the vendor once upstream includes those patches.
- **Book and CI** may lag a Manifest resolve; packages should remain usable standalone via `Pkg.test()`.

## 10. Review checklist (before merging)

1. Does this belong in this package per `BOUNDARIES.md`?
2. Is there a weaker dependency option (extension instead of hard dep)?
3. Are exports documented and tested?
4. Does identification/estimation remain auditable (certificates, flags, assumptions)?
5. Will `Pkg.test()` pass without optional integrations?
6. No manuscript-specific symbols or file paths in package source?
