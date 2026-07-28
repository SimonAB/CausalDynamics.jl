"""
Discrete-time Causal Dynamical Models (CDMs).

A `DiscreteTimeCDM` advances named endogenous state over occasions `t = 1:T`,
sampling exogenous noise each step and optionally applying a `DoSequence`.
Shared-`U` counterfactuals reuse realised noise under an alternate intervention.
"""

"""
    AbstractCDM

Abstract type for Causal Dynamical Models (time-indexed structural models).
"""
abstract type AbstractCDM end

"""
    AbstractIntervention

Supertype for interventions applied during [`simulate`](@ref) and
[`counterfactual`](@ref): [`DoSequence`](@ref) (atomic, time-indexed) and
[`Policy`](@ref) (state-dependent assignment rules).
"""
abstract type AbstractIntervention end

"""
    DoSequence

Time-indexed `do(·)` assignments. Each key is an endogenous variable symbol; each
value is either a scalar (constant for all `t`), an `AbstractVector` indexed by
`t`, or a function `(t) -> value`.
"""
struct DoSequence <: AbstractIntervention
    values::Dict{Symbol, Any}
end

"""
    do_sequence(variable::Symbol, values)

Build a `DoSequence` fixing `variable` to `values` over time.
"""
function do_sequence(variable::Symbol, values)
    return DoSequence(Dict{Symbol, Any}(variable => values))
end

"""
    do_sequence(pairs::Pair{Symbol, <:Any}...)

Build a `DoSequence` from `variable => assignment` pairs.
"""
function do_sequence(pairs::Pair{Symbol, <:Any}...)
    return DoSequence(Dict{Symbol, Any}(pairs...))
end

"""
    Policy

State-dependent (soft) intervention. Each key is an endogenous variable symbol;
each value is a rule `(state, t) -> value` evaluated against the *current* state
before the update. Use for treatment strategies that react to the system, where
[`DoSequence`](@ref) fixes a value independently of state.
"""
struct Policy <: AbstractIntervention
    rules::Dict{Symbol, Any}
end

"""
    policy(variable::Symbol, rule)

Build a [`Policy`](@ref) assigning `variable` via `rule(state, t)`.
"""
function policy(variable::Symbol, rule)
    return Policy(Dict{Symbol, Any}(variable => rule))
end

"""
    policy(pairs::Pair{Symbol, <:Any}...)

Build a [`Policy`](@ref) from `variable => rule` pairs, each `rule(state, t)`.
"""
function policy(pairs::Pair{Symbol, <:Any}...)
    return Policy(Dict{Symbol, Any}(pairs...))
end

"""
    intervention_value(intervention, variable, t, observational_value)
    intervention_value(intervention, variable, t, observational_value, state)

Return the interventional assignment for `variable` at time `t` when present in
`intervention`, otherwise `observational_value`.

Pass `state` (the current endogenous `NamedTuple`) to support [`Policy`](@ref)
rules; [`DoSequence`](@ref) ignores it.
"""
function intervention_value(::Nothing, ::Symbol, ::Int, observational_value)
    return observational_value
end

function intervention_value(intervention::DoSequence, variable::Symbol, t::Int, observational_value)
    haskey(intervention.values, variable) || return observational_value
    raw = intervention.values[variable]
    if raw isa AbstractVector
        t > length(raw) && throw(ArgumentError(
            "DoSequence for :$variable has length $(length(raw)) but t=$t was requested",
        ))
        return raw[t]
    elseif raw isa Function
        return raw(t)
    else
        return raw
    end
end

function intervention_value(intervention::Policy, variable::Symbol, t::Int, observational_value)
    throw(ArgumentError(
        "Policy assignment for :$variable needs the current state; " *
        "call intervention_value(intervention, variable, t, observational_value, state)",
    ))
end

# State-aware forms: DoSequence and `nothing` ignore `state`.
function intervention_value(intervention::Union{Nothing, DoSequence}, variable::Symbol, t::Int, observational_value, ::Any)
    return intervention_value(intervention, variable, t, observational_value)
end

function intervention_value(intervention::Policy, variable::Symbol, t::Int, observational_value, state)
    haskey(intervention.rules, variable) || return observational_value
    return intervention.rules[variable](state, t)
end

"""
    _apply_do_to_state(state, intervention, t)

Return a `NamedTuple` copy of `state` with any `DoSequence` assignments at time `t`.
"""
function _apply_do_to_state(state::NamedTuple, intervention::Union{Nothing, AbstractIntervention}, t::Int)
    intervention === nothing && return state
    return NamedTuple{keys(state)}(
        ntuple(i -> begin
            k = keys(state)[i]
            intervention_value(intervention, k, t, state[k], state)
        end, length(state)),
    )
end

"""
    DiscreteTimeCDM

Discrete-time Causal Dynamical Model with named endogenous variables.

# Fields
- `variables`: endogenous names (documentation / packing order)
- `initialise`: `(rng) -> NamedTuple` of initial endogenous values at `t = 1`
- `sample_noise`: `(rng, state, t) -> NamedTuple` of exogenous draws for occasion `t`
- `step`: `(state, t, noise, intervention) -> NamedTuple` next endogenous state

The `step` function should use [`intervention_value`](@ref) for intervenable
assignments. In [`simulate`](@ref), `initialise` produces `t = 1` (then `do` is
applied); `step` is called for `t = 2:T`.
"""
struct DiscreteTimeCDM{I, S, N} <: AbstractCDM
    variables::Vector{Symbol}
    initialise::I
    sample_noise::S
    step::N
end

"""
    DiscreteTimeCDM(variables; initialise, sample_noise, step)

Construct a [`DiscreteTimeCDM`](@ref).
"""
function DiscreteTimeCDM(
    variables::AbstractVector{Symbol};
    initialise,
    sample_noise,
    step,
)
    return DiscreteTimeCDM(collect(Symbol, variables), initialise, sample_noise, step)
end

"""
    CDMTrajectory

Result of simulating a [`DiscreteTimeCDM`](@ref).

# Fields
- `T`: number of occasions
- `series`: endogenous trajectories (`Symbol => Vector`)
- `noise`: realised exogenous draws (`Symbol => Vector`)
"""
struct CDMTrajectory
    T::Int
    series::Dict{Symbol, Vector}
    noise::Dict{Symbol, Vector}
end

function _empty_series(keys_nt::NamedTuple, T::Int)
    return Dict{Symbol, Vector}(k => Vector{typeof(v)}(undef, T) for (k, v) in pairs(keys_nt))
end

function _store!(store::Dict{Symbol, Vector}, nt::NamedTuple, t::Int)
    for (k, v) in pairs(nt)
        store[k][t] = v
    end
    return store
end

"""
    simulate(cdm::DiscreteTimeCDM, T; rng=..., intervention=nothing)

Simulate a discrete-time CDM for `T` occasions.

Returns a [`CDMTrajectory`](@ref). When `intervention` is a [`DoSequence`](@ref),
assignments are applied at `t = 1` to the initial state and passed into `step`
for `t ≥ 2` (use [`intervention_value`](@ref) inside `step`).

Note: at `t = 1`, only fields named in the `DoSequence` are overwritten; child
variables are not re-solved until `step` runs for `t ≥ 2`. Encode any t=1
downstream effects in `initialise` if needed.
"""
function simulate(
    cdm::DiscreteTimeCDM,
    T::Integer;
    rng::Random.AbstractRNG = Random.default_rng(),
    intervention::Union{Nothing, AbstractIntervention} = nothing,
)
    T = Int(T)
    T < 1 && throw(ArgumentError("T must be ≥ 1, got $T"))

    state = _apply_do_to_state(cdm.initialise(rng), intervention, 1)
    series = _empty_series(state, T)
    _store!(series, state, 1)

    noise1 = cdm.sample_noise(rng, state, 1)
    noise_store = _empty_series(noise1, T)
    _store!(noise_store, noise1, 1)

    for t in 2:T
        noise = cdm.sample_noise(rng, state, t)
        _store!(noise_store, noise, t)
        state = cdm.step(state, t, noise, intervention)
        _store!(series, state, t)
    end

    return CDMTrajectory(T, series, noise_store)
end

"""
    counterfactual(cdm, noise; intervention, initial=nothing)

Resimulate `cdm` under `intervention` using fixed exogenous draws `noise`
(typically `factual.noise` from a prior [`simulate`](@ref)).

# Arguments
- `noise`: `Dict{Symbol, Vector}` of realised exogenous series (common length `T`)
- `intervention`: [`DoSequence`](@ref) for the counterfactual world
- `initial`: optional endogenous `NamedTuple` at `t = 1` before `do` (default:
  `cdm.initialise` with a fixed seed — pass factual initials when they matter)
"""
function counterfactual(
    cdm::DiscreteTimeCDM,
    noise::Dict{Symbol, Vector};
    intervention::AbstractIntervention,
    initial::Union{Nothing, NamedTuple} = nothing,
)
    isempty(noise) && throw(ArgumentError("noise dictionary is empty"))
    T = length(first(values(noise)))
    for (k, v) in noise
        length(v) == T || throw(ArgumentError(
            "noise series :$k has length $(length(v)), expected $T",
        ))
    end

    state0 = initial === nothing ? cdm.initialise(Random.Xoshiro(0)) : initial
    state = _apply_do_to_state(state0, intervention, 1)

    series = _empty_series(state, T)
    _store!(series, state, 1)

    noise_keys = Tuple(keys(noise))
    noise_out = Dict{Symbol, Vector}(k => copy(v) for (k, v) in noise)

    for t in 2:T
        noise_t = NamedTuple{noise_keys}(ntuple(i -> noise[noise_keys[i]][t], length(noise_keys)))
        state = cdm.step(state, t, noise_t, intervention)
        _store!(series, state, t)
    end

    return CDMTrajectory(T, series, noise_out)
end

"""
    GComputationResult

Monte Carlo g-computation summary for an outcome under a fixed intervention.

# Fields
- `mean`: mean terminal outcome across replicate trajectories
- `std`: standard deviation across replicates
- `n`: number of replicates
- `samples`: terminal outcome per replicate
"""
struct GComputationResult
    mean::Float64
    std::Float64
    n::Int
    samples::Vector{Float64}
end

"""
    g_computation(cdm, T, outcome; intervention, n=1000, rng=..., reduce=last)

Estimate `E[outcome ∣ do(intervention)]` by simulating `n` trajectories of length `T`.

Each replicate is summarised by `reduce` applied to the outcome series (default
`last`, the terminal occasion). Contrast two calls to obtain an interventional
effect, e.g. `do_sequence(:a, 1.0)` versus `do_sequence(:a, 0.0)`.

# Arguments
- `cdm`: a [`DiscreteTimeCDM`](@ref)
- `T`: number of occasions per replicate
- `outcome`: endogenous variable symbol to summarise
- `intervention`: [`DoSequence`](@ref) or [`Policy`](@ref)
- `n`: replicate count
- `rng`: random source (advanced across replicates)
- `reduce`: series summary, e.g. `last`, `Statistics.mean`

Returns a [`GComputationResult`](@ref).
"""
function g_computation(
    cdm::DiscreteTimeCDM,
    T::Integer,
    outcome::Symbol;
    intervention::AbstractIntervention,
    n::Integer = 1000,
    rng::Random.AbstractRNG = Random.default_rng(),
    reduce = last,
)
    n = Int(n)
    n < 1 && throw(ArgumentError("n must be ≥ 1, got $n"))

    samples = Vector{Float64}(undef, n)
    for i in 1:n
        traj = simulate(cdm, T; rng = rng, intervention = intervention)
        haskey(traj.series, outcome) || throw(ArgumentError(
            "outcome :$outcome is not an endogenous variable; available: $(collect(keys(traj.series)))",
        ))
        samples[i] = Float64(reduce(traj.series[outcome]))
    end

    m = sum(samples) / n
    s = n > 1 ? sqrt(sum(abs2, samples .- m) / (n - 1)) : 0.0
    return GComputationResult(m, s, n, samples)
end

export AbstractCDM, DiscreteTimeCDM, CDMTrajectory
export AbstractIntervention, DoSequence, do_sequence, intervention_value
export Policy, policy
export GComputationResult, g_computation
export simulate, counterfactual
