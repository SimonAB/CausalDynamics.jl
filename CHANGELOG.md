# Changelog

All notable changes to CausalDynamics.jl will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.6] - 2026-08-30

### Added

- **Missingness in planner ([#26](https://github.com/SimonAB/CausalDynamics.jl/issues/26)):**
  `EstimationPlan` carries `missingness_note`, `capture_conditioned`, and
  `:structural_skip` estimability when the outcome (or hurdle presence) column
  is absent from the panel.

## [0.4.5] - 2026-08-30

### Added

- **Session-slice planner ([#25](https://github.com/SimonAB/CausalDynamics.jl/issues/25)):**
  `plan_session_estimation` and `session_slice` (DataFrames extension) for
  long-capture → single-occasion estimation hand-off.

## [0.4.4] - 2026-08-30

### Added

- **`EstimationPlan.family_outcome` ([#24](https://github.com/SimonAB/CausalDynamics.jl/issues/24)):**
  `OutcomeKind.binary` → `:binomial`; `count_outcome` → `:negbin` / `:poisson`
  (`count_family` kw).

## [0.4.3] - 2026-08-30

### Added

- **`EstimationPlan` empirical support:** `plan_targeted_estimation(...; data=, min_n=)`
  sets `min_complete_n` and `estimability` via [`identification_support`](@ref)
  ([#18](https://github.com/SimonAB/CausalDynamics.jl/issues/18)).
- **`check_occasion_resolution`:** warn when query occasions differ from measured
  occasions in wide panels ([#17](https://github.com/SimonAB/CausalDynamics.jl/issues/17)).

## [0.4.2] - 2026-08-30

### Added

- **Panel bridge:** `temporal_adjustment_columns`, `adjustment_columns`,
  `query_panel_columns`, `EstimationPlan`, and `plan_targeted_estimation` map
  temporal identification certificates to wide-panel column names and a default
  CausalTargeted engine choice ([#15](https://github.com/SimonAB/CausalDynamics.jl/issues/15),
  [#19](https://github.com/SimonAB/CausalDynamics.jl/issues/19)).

- **OutcomeKind planner:** `OutcomeKind`, `NodeOutcomeSpec`, and
  `outcome_specs` on `plan_targeted_estimation` route hurdle nodes to
  `:two_part_discrete_lmtp` with `presence_col` / `intensity_col` for
  CausalTargeted two-part LMTP ([#22](https://github.com/SimonAB/CausalDynamics.jl/issues/22)).

- **Hierarchical nesting (Phase 1–2):** `RandomEffectSpec`, `assign_cluster_ids`,
  `draw_nested_effects`, `add_nested_effects!`, `simulate_hierarchical_panel`,
  and synthetic `simulate_hierarchical_intercept_ate`. Hierarchical DAG unroll
  via `HierarchicalNestingSpec`, `unroll_hierarchical_dag`,
  `hierarchical_node` / `hierarchical_node_names`, and
  `attach_hierarchy_assumptions`. Coverage: `test/test_hierarchy.jl`. Docs:
  [hierarchy.md](docs/src/hierarchy.md). Application MixedModels concordance:
  `examples/hierarchical_mixedmodels_concordance.md`. LMM fitting remains
  deferred (BOUNDARIES). Stress:
  [`docs/stress/hierarchy_stress.qmd`](docs/stress/hierarchy_stress.qmd);
  Documenter [stress_hierarchy.md](docs/src/stress_hierarchy.md); getting-started
  §6 nested units.

- **Missingness contract (Phase 1):** `ObservationMask`, `observation_mask`,
  `miss_rates`, `apply_observation_mask`, and `require_complete_values`.
  `pack_parent_vector` refuses `Missing` rather than coercing to `Float64`.
  Coverage: `test/test_missingness_contract.jl`. BOUNDARIES document
  Structural masks vs Observable policies.
- **Missingness certificates (Phase 3):** `MissingnessSpec`,
  `MissingnessCertificate`, `certify_missingness`, and
  `identify(...; missingness=)` attaching `result.missingness` (MCAR/MAR/MNAR).
  Causal `identifiable` stays separate from missingness ID. Coverage:
  `test/test_missingness_id.jl`.
- **Dynamical incompleteness (Phase 5):** `apply_missingness_mechanism`,
  `simulate_incomplete_panel`, and `require_complete_matrix` so
  `encode_to_panel` refuses `Missing` assays. Coverage:
  `test/test_missingness_dynamical.jl`; Deep SCM stress encode guard.
- **Missingness edge suite:** `test/test_missingness_edge_cases.jl` (MCAR extremes,
  multi-response joint mask, MNAR certificate separation, mechanism guards).
- **Documentation:** narrative [Missingness](docs/src/missingness.md) page
  (masks, certificates, generative mechanisms, hand-off to estimation).
- **Representation bridge:** `RepresentationSpec`, `encode_to_panel`, and
  `representation_certificate` compress high-dim inputs (spectra, images) to
  low-dim code columns for identification and estimation. No Flux/Lux hard
  dependency; encoders are user callables. Optional DataFrames method when the
  weakdep is loaded.
  Coverage: `test/test_representation.jl` (units, edges, large-panel stress,
  Monte Carlo oracle recovery); CausalMediation
  `test/test_representation_bridge.jl` (codes → one-step mediation).
- **Deep mechanisms (Phase 2a):** `MechanismSpec` / `MechanismLibrary` with Lux
  weakdep (`CausalDynamicsLuxExt`): parent-constrained MLP residuals,
  `build_ode_rhs`, `graphscm_with_mechanisms`, thin `train_mechanisms!`.
  Examples `mechanism_ude.jl` / `mechanism_scm.jl`.
- **Generative L3 (Phase 2b):** `:generative` additive-noise mechanisms with
  `abduce_noise` / `mechanism_counterfactual` (example
  `mechanism_counterfactual.jl`). Non-additive image DeepSCM encoders deferred.
  Coverage: `test/test_mechanism.jl` (construction, register edges, certificates,
  façades, pack, many-node stress); `test/test_mechanism_lux.jl` (attach, ODE/`do`,
  GraphSCM, scalar and multi-dim L3 round-trips, multi-node train, Phase 1 hand-off).
  Application stress: `docs/stress/deep_scm_stress.qmd` (+ CausalTargeted
  `deep_scm_estimation_stress.qmd` for mediation/LMTP on codes).
- Integer-coded factor recode via `Policy` (`2 → 1` on `A_t`): shared-`U`
  counterfactual mean matches the structural recode (CDMPanel stays `Float64`).

### Changed

- Document deferred Deep SCM items (UniversalDiffEq hard dep, Flux-in-core,
  non-additive image DeepSCM, full MIRS) in BOUNDARIES / DESIGN / scope /
  SCIML_INTEGRATION; stress notebooks and SciML recipes describe the shipped tip.
- Documenter: include `IdentificationError` in the identification API page
  (`checkdocs = :exports`).
- Getting-started SCM math uses `\to` (not `\\to`)
  ([#10](https://github.com/SimonAB/CausalDynamics.jl/issues/10)).

### Changed

- Docs/CI use CausalInference from General (≥0.19.4); GraphMakie 0.6 co-install
  no longer requires the SimonAB `cdcs-fork` path.
- Frontdoor docstrings link to CausalInference docs (plain URLs) instead of
  unresolved Documenter `@ref`s across packages.
- Frontdoor identification delegates to `CausalInference.find_frontdoor_adjustment`
  (Wienöbst et al. 2024; CausalInference `gensearch`) instead of the prior reachability/backdoor
  shortcut. New exports: `find_frontdoor_adjustment_set`,
  `find_min_frontdoor_adjustment_set`, `list_frontdoor_adjustment_sets`.
- `find_frontdoor_mediators` validates singleton candidates directly instead of
  listing all frontdoor sets (large speedup on dense graphs).

### Added

- `CDMPanel`, `panel_column_name`, `trajectory_wide_row`, and `simulate_panel`
  for wide observational panels (baseline / timed / terminal columns) for
  hand-off to CausalTargeted sequential LMTP.
- Observation bridge helpers in `src/cdm/observation.jl`.
- `TransportQuery` identification hooks and SciML / DataFrames extension touch-ups.

## [0.4.0] - 2026-08-05

### Breaking

- `IdentificationResult` gains a `moc` field (intermediate confounders) between
  `mediators` and `strategy`. Positional constructors must pass `moc` (use
  `Vector{T}()` when unused). The keyword constructor defaults `moc` to empty.

### Added

- `MediationQuery` fields `moc` and `effect_kind` (`:natural`, `:interventional`,
  `:organic`, `:recanting_twin`).
- `identify` for mediation: natural effects throw `IdentificationError` under
  recanting / intermediate confounding; interventional / organic / RT return
  adjustment, mediators, and suggested `moc`.
- `IdentificationError` exception type.

## [0.3.16] - 2026-08-04

### Changed

- `find_minimal_mediator_sets` returns `MinimalMediatorSets` with
  `.sets` and `.status` (`:ok`, `:no_path`, `:uncuttable_direct_edge`,
  `:uncuttable`) instead of a bare `Vector{Set}`. Sets are sorted stably by
  `(length, sorted members)`. The result iterates over `.sets`.

### Added

- `intercepts_all_directed_paths(g, treatment, outcome, S)`: predicate for the
  same path-cut criterion used by `find_minimal_mediator_sets`.

## [0.3.15] - 2026-08-04

### Added

- `find_minimal_mediator_sets(g, treatment, outcome)`: inclusion-minimal mediator
  sets that intercept every directed treatment→outcome path. See issue #4.

## [0.3.14] - 2026-08-04

### Added

- `find_path_mediators(g, treatment, outcome)`: structural mediator candidates
  (nodes on a proper directed treatment→outcome path). Distinct from
  `find_frontdoor_mediators` (frontdoor criterion). See issue #3.

## [0.3.13] - 2026-07-31

### Added

- `dagplot_temporal` (DAGMakie extension): plot a `TemporalUnrolling` with
  time-indexed layout and `var[t]` labels.

## [0.3.12] - 2026-07-31

### Changed

- Rename parent-discovery APIs to ODE language: `infer_ode_parents`,
  `ODEParentRanking`, `ode_parent_ranking_to_continuous_spec`,
  `score_ode_parent_sets` (was `infer_invariant_parents` / …). Cross-environment
  mechanism stability is described in prose/docstrings, not in the API stem.

## [0.3.11] - 2026-07-31

### Changed

- Prefer ordinary dynamical language in APIs: `infer_invariant_parents`,
  `InvariantParentRanking`, `invariant_ranking_to_continuous_spec` (was
  `infer_kinetic_parents` / `KineticParentRanking` / …). “Kinetic” remains only
  as a Peters / CausalKinetiX citation gloss.

## [0.3.10] - 2026-07-31

### Changed

- Renamed kinetic discovery API to CDCS conventions (CausalKinetiX remains a
  literature reference only):
  - `infer_kinetic_parents` / `KineticParentRanking` /
    `kinetic_ranking_to_continuous_spec` / `score_kinetic_parent_sets`
  - Extension `CausalDynamicsDataInterpolationsExt` (was `…CausalKinetiXExt`)
- IEE keyword `backend` → `mi` (`:auto`, `:associations`, `:reference`)

## [0.3.9] - 2026-07-31

### Added

- `with_parents` / `ranked_variables_to_parents` for kinetic parent maps on
  [`ContinuousCDMSpec`](@ref).
- Associations-backed IEE (`backend = :associations` / `:auto`) via KSG1;
  keep `backend = :reference` for MATLAB concordance.
- CausalKinetiX v0: leave-one-environment OLS derivative scores, variable
  ranking, `causalkinetix_to_continuous_spec` (DataInterpolations extension for
  cubic-spline derivatives).
- `forward_sensitivity_cdm` via SciMLSensitivity package extension.

## [0.3.8] - 2026-07-31

### Added

- `ContinuousCDMSpec` optional `parents` and `continuous_cdm_graph` for causal
  kinetic parent sets on continuous CDMs.
- Interventional Embedding Entropy (IEE) Julia port with concordance tests
  against the smsxiaomayi/IEE MATLAB reference (`test/reference_iee_matlab.jl`).
- Unified continuous interventions: `do_pin`, `do_ic`, `do_force`, `do_rhs`
  with SciML-native hard-pin callbacks.

### Changed

- Documentation: `METHODS_ADOPTION.md`, SciML/Associations notes for Peters /
  Shi / CausalKinetiX adoption map.

## [0.3.4] - 2026-07-29

### Fixed

- `node_names` for `identify` / `prepare_for_tmle` now accepts a **vector** of
  names (index `i` → node `i`) as well as `Dict{Int,Symbol}`; previously a
  vector raised `MethodError` on `haskey`.
- `examples/sciml_cdm_recipe.jl`: load `OrdinaryDiffEq` at top level (Julia
  forbids `using` inside `main`).
- Do not export `has_path` (name clash with `Graphs.has_path`); document as
  `CausalDynamics.has_path`.

### Changed

- Documentation build: SciML API `@docs`, graph path helpers, scope/DESIGN links.

## [0.3.3] - 2026-07-29

### Changed

- `DoSequence` stores typed `AbstractDoAssignment` values
  (`ConstantAssignment`, `SeriesAssignment`, `TimedAssignment`) instead of
  bare `Any`.
- `Policy` rules are `Dict{Symbol, Function}`.
- `CDMTrajectory` series/noise are `Dict{Symbol, Vector{<:Real}}`.

## [0.3.2] - 2026-07-29

### Changed

- Documented **`Hypergraph`** and **`SymbolicSCM`** as experimental / quarantined
  (outside the `identify` pipeline); package blurb no longer markets Hypergraph
  as a primary feature.

## [0.3.1] - 2026-07-29

### Fixed

- **Associations.jl** is only a weak dependency (with DataFrames) for
  `CausalDynamicsAssociationsExt`. It was incorrectly listed under hard `[deps]`
  while the changelog already described it as optional.

## [0.3.0] - 2026-07-27

### Added

- Optional **Associations.jl** weakdep extension (`CausalDynamicsAssociationsExt`):
  `infer_pc_graph`, `infer_oce_temporal_spec`, `discover_and_prepare`
- Core discovery bridge (no Associations required): `prepare_from_discovery`,
  `oce_parents_to_temporal_spec`, `cpdag_to_dag`, `digraph_with_names`
- [Associations integration](docs/src/ASSOCIATIONS_INTEGRATION.md);
  `examples/discovery_to_identification.jl`
- CDCS book Ch. 05b executable PC and OCE examples

## [0.2.0] - 2026-07-23

### Added

- `DiscreteTimeCDM`, `DoSequence`, `simulate`, and shared-`U` `counterfactual` for
  discrete-time Causal Dynamical Models ([docs](docs/src/api/cdm.md))
- Soft interventions: `Policy` / `policy` state-dependent assignment rules, with a
  state-aware `intervention_value` method
- `g_computation` Monte Carlo interventional means (`GComputationResult`)
- Time-indexed identification: `TemporalDAGSpec`, `unroll_temporal_dag`,
  `temporal_backdoor_adjustment_set` ([docs](docs/src/api/time_graphs.md))
- SciML composition recipes ([docs](docs/src/SCIML_INTEGRATION.md));
  `examples/sciml_cdm_recipe.jl`
- Scope / architecture page documenting what is in core vs deferred
- Registration checklist in `REGISTRATION.md`

### Fixed

- `attach_data!(g, data; node_names=...)` now registers names as node properties,
  so `get_node_names`, TMLE, and PPL bridges see them (previously only a
  graph-level property was written and readers silently saw no names)

### Changed

- Dropped local monorepo `[sources]` for General registration
- Default `Pkg.test` no longer pulls DAGMakie/CairoMakie (registry CausalInference
  GraphMakie 0.5 weakdep conflicts with DAGMakie 0.1.1); extension covered in CDCS

## [0.1.0] - 2026-07-20

### Added

- Core graph operations: d-separation, paths, sets, hypergraphs, `CausalGraph`
- Identification: backdoor, frontdoor, instruments, adjustment sets
- `GraphSCM`, `do(·)` interventions, counterfactual simulation with shared `U`
- Optional `CausalDynamicsDAGMakieExt` plotting (`plot_causal_graph`, `plot_backdoor_paths`, …)
- Optional `CausalDynamicsRxInfer` extension (GraphPPL + RxInfer + DataFrames)
- CI, Documentation, TagBot, and CompatHelper workflows (Julia 1.12)

### Changed

- Lean core dependencies: hard dep is Graphs only; Documenter, RxInfer, DataFrames, and SciML stacks demoted or removed from load path
- Visualisation no longer uses fragile `Main.isdefined(GraphMakie)` checks

### Removed

- Process / Whiteheadian terminology page from package docs (book-only)
- Public exports of unimplemented stubs (`is_identifiable`, `identify_formula`, `create_symbolic_scm`)
