# SciML integration (recipes)

CausalDynamics.jl does **not** hard-depend on SciML solvers. Discrete-time
trajectories live in [`DiscreteTimeCDM`](@ref); continuous mechanisms belong in
**OrdinaryDiffEq** / **UniversalDiffEq** / application code. This page records
composition patterns used in the [CDCS book](https://simonab.github.io/causal-dynamics-book/)
and related docstrings in [Integrations API](api/integration.md).

## Pattern: identify → simulate → intervene

1. **Structural** — `TemporalDAGSpec` + `unroll_temporal_dag` or a hand-built `DiGraph`
2. **Dynamical** — `DiscreteTimeCDM` + `simulate` / `counterfactual`, *or* an `ODEProblem` via `ContinuousCDMSpec`
3. **Observable** — `CausalTargeted`, TMLE, or RxInfer on adjustment sets from step 1

## Discrete-time CDM (package-native)

```julia
using CausalDynamics, Random

cdm = DiscreteTimeCDM(
    [:z, :x, :y];
    initialise = (rng) -> (z = 0.0, x = 0.0, y = 0.0),
    sample_noise = (rng, state, t) -> (u_z = randn(rng), u_x = randn(rng), u_y = randn(rng)),
    step = (state, t, noise, intervention) -> begin
        z = 0.9 * state.z + noise.u_z
        x = intervention_value(intervention, :x, t, 0.5 * state.x + 0.3 * z + noise.u_x)
        y = 0.5 * x + 0.2 * z + noise.u_y
        (z = z, x = x, y = y)
    end,
)

traj = simulate(cdm, 100; rng = Random.Xoshiro(1))
cf = counterfactual(cdm, traj.noise; intervention = do_sequence(:x, fill(1.0, 100)))
```

Executable recipe: `examples/discrete_cdm.jl`.

## Estimation without leaving the package

For simulated systems, contrast interventional means directly with
[`g_computation`](@ref) — no external estimation dependency required:

```julia
treated = g_computation(cdm, 100, :y; intervention = do_sequence(:x, 1.0), n = 500)
control = g_computation(cdm, 100, :y; intervention = do_sequence(:x, 0.0), n = 500)
effect = treated.mean - control.mean
```

State-dependent strategies use [`policy`](@ref) instead of a fixed sequence:

```julia
π = policy(:x, (state, t) -> state.z > 0 ? 1.0 : 0.0)
under_policy = g_computation(cdm, 100, :y; intervention = π, n = 500)
```

For **observational** data (not simulation), use `CausalTargeted`, TMLE, or
RxInfer with adjustment sets from identification. Discrete panels use
`simulate_panel`; inferred latents use `ObservationBridge` /
`panel_from_latent_series`.

Continuous CDMs support the same Monte Carlo idea via
[`ContinuousEffectFunctional`](@ref) (`:terminal`, `:mean`, `:integral`):

```julia
using OrdinaryDiffEq
spec = ContinuousCDMSpec([:x, :y])
# … define rhs! …
g_do = g_computation(
    spec, rhs!, rng -> [1.0, 0.0], (0.0, 5.0), p;
    intervention = do_pin(:x, 1.0),
    functional = ContinuousEffectFunctional(:y; kind = :terminal),
    n = 200,
)
```

## Bridge to ODEs (application code)

When the mechanism is continuous, keep **causal structure** in CausalDynamics and
**integration** in SciML. Load `OrdinaryDiffEq` to activate `CausalDynamicsSciMLExt`:

```julia
using CausalDynamics, Graphs, OrdinaryDiffEq

g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y
adj = backdoor_adjustment_set(g, 2, 3)

spec = ContinuousCDMSpec([:Z, :X, :Y])
function cdm_dynamics!(du, u, p, t)
    Z, X, Y = u
    du[1] = p.λ_z * Z
    du[2] = p.α * X + p.β * Z
    du[3] = p.γ * Y + p.δ * X + p.ε * Z
end
p = (λ_z = -0.1, α = -0.2, β = 0.3, γ = -0.1, δ = 0.5, ε = 0.2)
sol = solve_cdm(spec, cdm_dynamics!, [1.0, 0.5, 0.2], (0.0, 10.0), p)
terminal_state(spec, sol)  # NamedTuple(:Z, :X, :Y)

# Static do(·): SciML-native hard pin (IC + du=0 + DiscreteCallback)
do_x = do_pin(:X, 1.0)
sol_do = solve_cdm(spec, cdm_dynamics!, [1.0, 0.5, 0.2], (0.0, 10.0), p; intervention = do_x)
```

Helpers: [`ContinuousCDMSpec`](@ref), [`ode_problem_cdm`](@ref), [`solve_cdm`](@ref),
[`terminal_state`](@ref), [`state_series`](@ref), [`interventional_rhs`](@ref),
[`intervention_callback`](@ref), [`do_pin`](@ref), [`do_ic`](@ref), [`do_force`](@ref),
[`do_rhs`](@ref).

Intervention types share [`AbstractCausalIntervention`](@ref):

- discrete CDM: [`AbstractIntervention`](@ref) (`DoSequence`, `Policy`)
- continuous CDM: [`AbstractContinuousIntervention`](@ref) (`DoPin`, `DoInitialCondition`, …)
- static SCM: [`DoIntervention`](@ref)

Hard pins use SciML `DiscreteCallback` to reassert the value after accepted steps
(no in-RHS mutation of `u`). Soft force and RHS replacement modify `du` only.
Optional `parents` on [`ContinuousCDMSpec`](@ref) record the continuous causal
parent graph ([`continuous_cdm_graph`](@ref)).
Executable recipe: `examples/sciml_cdm_recipe.jl`.

## Forward local sensitivity

Load `OrdinaryDiffEq` and `SciMLSensitivity` to activate
`CausalDynamicsSensitivityExt` and compute forward-mode local sensitivities
along a continuous CDM trajectory with [`forward_sensitivity_cdm`](@ref):

```julia
using CausalDynamics, OrdinaryDiffEq, SciMLSensitivity

spec = ContinuousCDMSpec([:prey, :predator])
function lotka!(du, u, p, t)
    X, Y = u
    du[1] = p.r * X - p.α * X * Y
    du[2] = p.β * X * Y - p.δ * Y
    return nothing
end
p = [1.0, 0.1, 0.02, 0.5]
# With parameter vector p (or custom intervention):
sol = forward_sensitivity_cdm(spec, lotka!, [40.0, 9.0], (0.0, 10.0), p)
```

`forward_sensitivity_cdm` wraps `ode_problem_cdm` and solves with
`ForwardDiffSensitivity()`.

## ODE parent discovery across environments

[`infer_ode_parents`](@ref) and [`ode_parent_ranking_to_continuous_spec`](@ref)
rank candidate parent sets for a target coordinate of a continuous-time causal
model (Peters, Bauer, & Pfister, 2022; Pfister, Bauer, & Peters, 2019 — see
[References](references.md)). The implementation uses the derivative-space
leave-one-environment ordinary least-squares stability score from CausalKinetiX
(without constrained quadratic-programming smoothers):

1. Differentiate trajectories ([`finite_difference_derivative`](@ref), or cubic
   splines when `DataInterpolations` is loaded).
2. Score each candidate parent set by leave-one-environment-out stability of
   ``\dot{Y} \sim X_S`` across environments ([`score_ode_parent_sets`](@ref)).
3. Aggregate inclusion frequencies among the top-``K`` models
   ([`aggregate_parent_inclusion`](@ref)).
4. Bridge the resulting ranking into [`ContinuousCDMSpec`](@ref) parents via
   [`ode_parent_ranking_to_continuous_spec`](@ref).

```julia
using CausalDynamics, DataInterpolations

ranking = infer_ode_parents(times, trajectories, env, target; max_size = 2)
spec = ode_parent_ranking_to_continuous_spec(ranking, [:Y, :X1, :X2]; max_parents = 2)
```

Discovery rankings feed structural specification and sensitivity comparisons;
they do not replace [`identify`](@ref) certificates.

## Representation bridge (high-dimensional inputs → codes)

Before SciML integration or downstream estimation on imaging or spectral inputs,
compress observations with [`RepresentationSpec`](@ref) /
[`encode_to_panel`](@ref) so the DAG and nuisance models operate on
low-dimensional codes rather than raw tensors. Roles `:measurement` vs
`:definitional` are recorded in [`representation_certificate`](@ref). Example:
`examples/representation_bridge.jl`.

## Graph-constrained Lux mechanisms

Parent-constrained neural residuals attach via [`MechanismLibrary`](@ref) /
[`attach_lux_mechanism!`](@ref) (requiring `Lux`, `ComponentArrays`, and
`Optimization`; no `Flux` hard dependency). Compose them with known physics
using [`build_ode_rhs`](@ref), then integrate or intervene with
[`solve_cdm`](@ref) / [`do_pin`](@ref). Thin training runs through
[`train_mechanisms!`](@ref). Examples: `examples/mechanism_ude.jl`,
`examples/mechanism_scm.jl`.

Application-scale Quarto stress notebooks:
[`docs/stress/deep_scm_stress.qmd`](https://github.com/SimonAB/CausalDynamics.jl/blob/main/docs/stress/deep_scm_stress.qmd)
([STRESS.md](https://github.com/SimonAB/CausalDynamics.jl/blob/main/STRESS.md)).
Estimation on encoded summaries (mediation and LMTP) lives in the CausalTargeted
sibling
[`deep_scm_estimation_stress.qmd`](https://github.com/SimonAB/CausalTargeted.jl/blob/main/docs/stress/deep_scm_estimation_stress.qmd).

## Additive generative counterfactuals on codes

For `:generative` nodes, ``X = f(\mathrm{pa}) + U``. Use
[`abduce_noise`](@ref) and [`mechanism_counterfactual`](@ref) for same-unit
counterfactuals; see `examples/mechanism_counterfactual.jl`. Prefer
low-dimensional representation codes (or other low-dimensional vectors) as
mechanism nodes; raw images are not mechanism parents.

## Scope boundaries (explicitly not in core)

- `UniversalDiffEq` as a **hard** dependency (use as an optional advanced trainer below)
- `Flux` in core (stays in MLJFlux nuisances or application encoders)
- Non-additive image DeepSCM (learned encoder abduction on raw tensors)
- Full cohort data fixtures in-package (stress notebooks use synthetic spectra)

## UniversalDiffEq (optional advanced trainer)

Use `CausalDynamics` for **adjustment and `do(·)` semantics**, and Lux
[`MechanismLibrary`](@ref) residuals when you want parent masks in-process. Use
[UniversalDiffEq.jl](https://github.com/Jack-H-Buckner/UniversalDiffEq.jl) only
when you need that package’s ecology-oriented UDE training APIs. Do **not**
expect UDE training inside `CausalDynamics` core, and do not add
`UniversalDiffEq` to `CausalDynamics` dependencies.

## Version note

- **0.2** — `DiscreteTimeCDM`, time-indexed unrolling helpers
- **0.3** — `CausalDynamicsSciMLExt` weakdep (`ContinuousCDMSpec`, `solve_cdm`, `do(·)` RHS wrapper)
- **0.3.x** — unified [`AbstractCausalIntervention`](@ref); SciML-native `DoPin` (`DiscreteCallback`); IEE → `TemporalDAGSpec`; `infer_ode_parents`; `forward_sensitivity_cdm`
- **0.4.x** — representation bridge; Lux `MechanismLibrary` and additive generative counterfactuals on codes; Deep SCM stress notebooks
- **0.5.x** — orthogonal temporal support semantics (`TemporalSupport`, `ReferentSpec`, `graph_kind`), RxInfer 6 compatibility, exact linear Gaussian and known-noise nonlinear state inference
