# CausalDynamics.jl — design principles

This package is the **structural and dynamical core**: graphs, identification, SCMs/CDMs, temporal unrolling, and thin integration façades.

**Shared principles:** [DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md)  
**Scope and architecture:** [docs/src/scope.md](docs/src/scope.md)  
**Boundaries:** [BOUNDARIES.md](BOUNDARIES.md)

## Role in the stack

```
Graph / CDM spec  →  identify(query)  →  IdentificationResult
                              ↓
     simulate · simulate_panel · counterfactual · g-computation
                              ↓
        optional: CausalTargeted sequential LMTP · TMLE.jl · RxInfer · DAGMakie
```

CausalDynamics answers **what is identifiable and how state evolves**; it does not run SuperLearner grids or cohort pipelines. Wide observational panels from `simulate_panel` use baseline / timed (`:a1`, `:a2`, …) / terminal column roles for hand-off to CausalTargeted `SequentialPolicy`.

## Package-specific principles

### Identification is first-class

- Prefer **`identify(g, query)`** and **`IdentificationResult`** over ad-hoc helper chains.
- Queries (`TotalEffectQuery`, `MediationQuery`, `TemporalEffectQuery`, …) are stable, serialisable intent objects.
- **`prepare_for_tmle`** and similar bridges delegate to `identify`; do not fork parallel ID logic.

### Façade where upstream is authoritative

- **CausalInference.jl** owns minimal backdoor listing and `dsep`; wrap, do not reimplement.
- **Own** frontdoor, instruments, path enumeration, ancestral algorithms, SCM/CDM simulation, and temporal unrolling.

### Lean core, extensions for weight

| Always loaded | Optional (weakdeps) |
|---------------|---------------------|
| `Graphs`, `CausalInference` | `DAGMakie`, `Associations`, `RxInfer`, `TMLE`, `DataFrames` |

New integrations follow the same pattern: narrow API in `src/integration/`, implementation in `ext/`, tests in `test/test_integration.jl` or extension-specific tests.

### Composable dynamical semantics

- **Static:** `GraphSCM`, `DoIntervention`, shared-`U` counterfactuals.
- **Discrete-time:** `DiscreteTimeCDM`, typed `DoSequence` assignments, `Policy`, trajectory simulation, `CDMPanel` / `simulate_panel`.
- **Observable bridge:** `ObservationBridge` maps latent/filter series to estimation columns (no filter algorithms in core).
- **Continuous functionals:** `ContinuousEffectFunctional` + SciML `g_computation` (weakdep).
- **Transport ID:** `TransportQuery` unions domain covariates into backdoor adjustment.
- **Time-indexed ID:** unroll lag structure, then apply backdoor on the unrolled graph.

Keep simulation and identification **orthogonal**: the same `IdentificationResult` should feed sequential LMTP, TMLE, RxInfer, or custom estimators.

### Julia native types

- Graphs are **`Graphs.jl`** `SimpleDiGraph` or `CausalGraph` wrappers—not string dagitty at runtime.
- Prefer **`Symbol` node labels** with explicit `node_names` maps rather than lowercase string conventions baked into algorithms.

### Efficiency

- Memoize or cache only when profiling shows benefit; graph algorithms are usually small relative to estimation.
- **`graph_fingerprint`** is cheap and stable for certificates; use it instead of serialising full edge lists in metadata.

### What not to add

- Cross-fitted nuisances, LMTP grids, or manuscript registry loaders.
- Process-philosophy renames of Pearl APIs (`do_surgery`, `backdoor_adjustment_set` stay as they are).
- Full symbolic do-calculus until there is a complete, tested implementation—avoid stub exports that imply completeness.

### Experimental (quarantined)

Keep these exported for exploration, but do not grow the `identify` pipeline around them until they have a real use path:

- **`Hypergraph`** — orthogonal to DAG identification / CDM simulation.
- **`SymbolicSCM`** — MTK placeholder (`system::Any`); prefer `GraphSCM`.

## Adding a feature (workflow)

1. Confirm the feature is structural/dynamical, not estimation (see [BOUNDARIES.md](BOUNDARIES.md)).
2. Define or extend a **`CausalQuery`** if it affects identification.
3. Return **`IdentificationResult`** with strategy, assumptions, and `identifiable`.
4. Add unit tests with small hand-built graphs; add extension tests only if optional deps are required.
5. Document in Documenter under `docs/src/api/`; update [scope.md](docs/src/scope.md) for major capability shifts.
