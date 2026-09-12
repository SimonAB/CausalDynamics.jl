"""
Discrete-time Causal Dynamical Models (CDMs).

A `DiscreteTimeCDM` advances named endogenous state over time steps `t = 1:T`,
sampling exogenous noise each step and optionally applying a `DoSequence`.
Shared-`U` counterfactuals reuse realised noise under an alternate intervention.
"""

"""
    AbstractCDM

Abstract type for Causal Dynamical Models (time-indexed structural models).
"""
abstract type AbstractCDM end

# AbstractIntervention is defined in interventions/abstract.jl

"""
    AbstractDoAssignment

Typed payload for a single variable in a [`DoSequence`](@ref): constant, time
series, or `t -> value` function.
"""
abstract type AbstractDoAssignment end

"""
    ConstantAssignment(value)

Hold a constant `do(·)` value for all time steps.
"""
struct ConstantAssignment{T} <: AbstractDoAssignment
    value::T
end

"""
    SeriesAssignment(values)

Hold a time-indexed `do(·)` series (`values[t]` at time `t`).
"""
struct SeriesAssignment{V <: AbstractVector} <: AbstractDoAssignment
    values::V
end

"""
    TimedAssignment(f)

Hold a time-dependent `do(·)` rule `f(t)`.
"""
struct TimedAssignment{F} <: AbstractDoAssignment
    f::F
end

"""
    normalize_do_assignment(v) -> AbstractDoAssignment

Wrap a raw DoSequence payload as a typed assignment.
"""
function normalize_do_assignment(v)
    v isa AbstractDoAssignment && return v
    v isa AbstractVector && return SeriesAssignment(v)
    v isa Function && return TimedAssignment(v)
    return ConstantAssignment(v)
end

function _do_assignment_value(a::ConstantAssignment, ::Int)
    return a.value
end

function _do_assignment_value(a::SeriesAssignment, t::Int)
    t > length(a.values) && throw(ArgumentError(
        "DoSequence series has length $(length(a.values)) but t=$t was requested",
    ))
    return a.values[t]
end

function _do_assignment_value(a::TimedAssignment, t::Int)
    return a.f(t)
end

"""
    DoSequence

Time-indexed `do(·)` assignments. Each key is an endogenous variable symbol; each
value is a typed [`AbstractDoAssignment`](@ref) (constructed automatically from a
scalar, an `AbstractVector` indexed by `t`, or a function `(t) -> value`).
"""
struct DoSequence <: AbstractIntervention
    values::Dict{Symbol, AbstractDoAssignment}

    function DoSequence(values::AbstractDict{<:Symbol})
        normalised = Dict{Symbol, AbstractDoAssignment}(
            Symbol(k) => normalize_do_assignment(v) for (k, v) in values
        )
        return new(normalised)
    end
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
each value is a `Function` rule `(state, t) -> value` evaluated against the
*current* state before the update. Use for treatment strategies that react to
the system, where [`DoSequence`](@ref) fixes a value independently of state.

Optional `information_set` declares which symbols are available at decision
time ``ℋ_t`` (non-anticipation). It may be

- a collection of symbols: a static ``ℋ`` — rules may only read those symbols
  from `state`; or
- an [`ObservationBridge`](@ref): a time-varying ``ℋ_t`` derived from the
  bridge's `mapping` and `availability`. At decision time `t` the rule sees
  only the state variables whose observed counterpart is `available_at(bridge,
  observed, t)`; unmapped (unobserved) variables are never visible. Availability
  is declared on the observation side and consumed here — it is not re-derived
  from the state.

Rules that need a symbol outside ``ℋ_t`` fail with a field-access error rather
than silently reading future or unobserved information.
"""
abstract type AbstractAvailability end

struct Policy <: AbstractIntervention
    rules::Dict{Symbol, Function}
    information_set::Union{Nothing, Set{Symbol}, AbstractAvailability}

    function Policy(
        rules::AbstractDict{<:Symbol};
        information_set = nothing,
    )
        normalised = Dict{Symbol, Function}()
        for (k, r) in rules
            r isa Function || throw(ArgumentError(
                "Policy rule for :$(Symbol(k)) must be a Function ((state, t) -> value); got $(typeof(r))",
            ))
            normalised[Symbol(k)] = r
        end
        info = if information_set === nothing
            nothing
        elseif information_set isa AbstractAvailability
            information_set
        else
            Set{Symbol}(Symbol(s) for s in information_set)
        end
        return new(normalised, info)
    end
end

"""
    policy(variable::Symbol, rule; information_set=nothing)

Build a [`Policy`](@ref) assigning `variable` via `rule(state, t)`.
"""
function policy(variable::Symbol, rule; information_set = nothing)
    return Policy(Dict{Symbol, Function}(variable => rule); information_set = information_set)
end

"""
    policy(pairs::Pair{Symbol, <:Any}...; information_set=nothing)

Build a [`Policy`](@ref) from `variable => rule` pairs, each `rule(state, t)`.
"""
function policy(pairs::Pair{Symbol, <:Any}...; information_set = nothing)
    return Policy(Dict{Symbol, Any}(pairs...); information_set = information_set)
end

"""
    policy_information_set(policy, t) -> Union{Nothing, Set{Symbol}}

State symbols the policy may read at decision time `t` (``ℋ_t``). Returns
`nothing` when the policy declares no information set (unrestricted), the
declared static set, or — for an [`ObservationBridge`](@ref) — the latent
variables whose observed counterparts are available at `t`.
"""
function policy_information_set(intervention::Policy, t::Integer)
    info = intervention.information_set
    info === nothing && return nothing
    info isa Set{Symbol} && return info
    return _information_set_at(info, Int(t))
end

# Implemented per availability declaration (see `cdm/observation.jl`).
function _information_set_at end

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
    return _do_assignment_value(intervention.values[variable], t)
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
    if intervention.information_set !== nothing
        allowed = policy_information_set(intervention, t)
        keys_allowed = Tuple(s for s in keys(state) if s in allowed)
        restricted = NamedTuple{keys_allowed}(
            Tuple(getproperty(state, s) for s in keys_allowed)
        )
        return intervention.rules[variable](restricted, t)
    end
    return intervention.rules[variable](state, t)
end

function intervention_value(intervention::SetState, variable::Symbol, t::Int, observational_value)
    intervention.target === variable || return observational_value
    _in_interval(intervention.interval, t) || return observational_value
    return _setstate_value(intervention.value, t)
end

function intervention_value(intervention::SetInitialCondition, variable::Symbol, t::Int, observational_value)
    intervention.target === variable && t == 1 ? intervention.value : observational_value
end

function intervention_value(intervention::SetInitialCondition, variable::Symbol, t::Int,
    observational_value, ::Any)
    return intervention_value(intervention, variable, t, observational_value)
end

function intervention_value(intervention::SetState, variable::Symbol, t::Int, observational_value, ::Any)
    return intervention_value(intervention, variable, t, observational_value)
end

function intervention_value(::ReplacePolicy, variable::Symbol, t::Int, observational_value)
    throw(ArgumentError(
        "ReplacePolicy assignment for :$variable needs the current state; " *
        "call intervention_value(intervention, variable, t, observational_value, state)",
    ))
end

function intervention_value(intervention::ReplacePolicy, variable::Symbol, t::Int, observational_value, state)
    intervention.target === variable || return observational_value
    _in_interval(intervention.interval, t) || return observational_value
    intervention.rule === nothing && throw(ArgumentError(
        "ReplacePolicy $(intervention.replacement_id) needs a rule for CDM surgery",
    ))
    state === nothing && throw(ArgumentError(
        "ReplacePolicy assignment for :$variable needs the current state",
    ))
    return intervention.rule(state, t)
end

function intervention_value(intervention::Union{Simultaneous, Sequential}, variable::Symbol, t::Int,
    observational_value)
    return intervention_value(intervention, variable, t, observational_value, nothing)
end

function intervention_value(intervention::Simultaneous, variable::Symbol, t::Int, observational_value, state)
    for child in intervention.interventions
        _cdm_assignment_applies(child, variable, t) || continue
        return intervention_value(child, variable, t, observational_value, state)
    end
    return observational_value
end

function intervention_value(intervention::Sequential, variable::Symbol, t::Int, observational_value, state)
    value = observational_value
    for child in intervention.interventions
        value = intervention_value(child, variable, t, value, state)
    end
    return value
end

function _cdm_assignment_applies(intervention::SetState, variable::Symbol, t::Int)
    return intervention.target === variable && _in_interval(intervention.interval, t)
end

_cdm_assignment_applies(intervention::SetInitialCondition, variable::Symbol, t::Int) =
    intervention.target === variable && t == 1

function _cdm_assignment_applies(intervention::ReplacePolicy, variable::Symbol, t::Int)
    return intervention.target === variable && _in_interval(intervention.interval, t)
end

function _cdm_assignment_applies(intervention::DoSequence, variable::Symbol, ::Int)
    return haskey(intervention.values, variable)
end

function _cdm_assignment_applies(intervention::Policy, variable::Symbol, ::Int)
    return haskey(intervention.rules, variable)
end

_cdm_assignment_applies(::AbstractCausalIntervention, ::Symbol, ::Int) = false

_intervention_targets(x::DoSequence) = collect(keys(x.values))
_intervention_targets(x::Policy) = collect(keys(x.rules))

function _canonical_assignment(assignment::ConstantAssignment)
    return _canonical_literal(assignment.value)
end
function _canonical_assignment(assignment::SeriesAssignment)
    return join(_canonical_literal.(assignment.values), ",")
end
_canonical_assignment(::TimedAssignment) = "TimedAssignment"

function canonical_intervention(x::DoSequence)
    parts = ["$(target)=$(_canonical_assignment(x.values[target]))" for target in sort!(collect(keys(x.values)))]
    return _canonical_fields((:do_sequence, parts...))
end

function canonical_intervention(x::Policy)
    return _canonical_fields((:policy, sort!(string.(collect(keys(x.rules))))...))
end

"""
    _apply_do_to_state(state, intervention, t)

Return a `NamedTuple` copy of `state` with any `DoSequence` assignments at time `t`.
"""
function _apply_do_to_state(state::NamedTuple, intervention::Union{Nothing, AbstractCausalIntervention}, t::Int)
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
- `sample_noise`: `(rng, state, t) -> NamedTuple` of exogenous draws for time step `t`
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
    apply_intervention(cdm::DiscreteTimeCDM, intervention)

Return a CDM whose initial state and step close over `intervention`, so later
[`simulate`](@ref) calls apply that surgery without passing it again.
"""
function apply_intervention(cdm::DiscreteTimeCDM, intervention::ReplacePolicy)
    intervention.rule === nothing && throw(ArgumentError(
        "ReplacePolicy $(intervention.replacement_id) needs a rule for CDM surgery",
    ))
    return _bake_cdm_intervention(cdm, intervention)
end

function apply_intervention(cdm::DiscreteTimeCDM, intervention::AbstractCausalIntervention)
    intervention isa Union{SetState, SetInitialCondition, ReplacePolicy, Simultaneous, Sequential,
        DoSequence, Policy} || throw(ArgumentError(
            "$(intervention_kind(intervention)) interventions are not implemented for DiscreteTimeCDM"))
    return _bake_cdm_intervention(cdm, intervention)
end

function _bake_cdm_intervention(cdm::DiscreteTimeCDM, intervention)
    initialise = rng -> _apply_do_to_state(cdm.initialise(rng), intervention, 1)
    step = (state, t, noise, _) -> cdm.step(state, t, noise, intervention)
    return DiscreteTimeCDM(cdm.variables; initialise = initialise, sample_noise = cdm.sample_noise, step = step)
end

"""
    CDMTrajectory

Result of simulating a [`DiscreteTimeCDM`](@ref).

# Fields
- `T`: number of time steps
- `series`: endogenous trajectories (`Symbol => Vector{<:Real}`)
- `noise`: realised exogenous draws (`Symbol => Vector{<:Real}`)
"""
struct CDMTrajectory
    T::Int
    series::Dict{Symbol, Vector{<:Real}}
    noise::Dict{Symbol, Vector{<:Real}}
end

function _empty_series(keys_nt::NamedTuple, T::Int)
    return Dict{Symbol, Vector{<:Real}}(k => Vector{typeof(v)}(undef, T) for (k, v) in pairs(keys_nt))
end

function _store!(store::Dict{Symbol, Vector{<:Real}}, nt::NamedTuple, t::Int)
    for (k, v) in pairs(nt)
        store[k][t] = v
    end
    return store
end

"""
    simulate(cdm::DiscreteTimeCDM, T; rng=..., intervention=nothing)

Simulate a discrete-time CDM for `T` time steps.

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
    intervention::Union{Nothing, AbstractCausalIntervention} = nothing,
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
- `noise`: `Dict{Symbol, Vector{<:Real}}` of realised exogenous series (common length `T`)
- `intervention`: [`DoSequence`](@ref) for the counterfactual world
- `initial`: optional endogenous `NamedTuple` at `t = 1` before `do` (default:
  `cdm.initialise` with a fixed seed — pass factual initials when they matter)
"""
function counterfactual(
    cdm::DiscreteTimeCDM,
    noise::Dict{Symbol, <:AbstractVector};
    intervention::AbstractCausalIntervention,
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
    noise_out = Dict{Symbol, Vector{<:Real}}(k => copy(v) for (k, v) in noise)

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
- `provenance`: optional semantic manifest for the analysis
"""
struct GComputationResult
    mean::Float64
    std::Float64
    n::Int
    samples::Vector{Float64}
    provenance::Union{Nothing, CDMProvenance}
end

GComputationResult(mean, std, n, samples) =
    GComputationResult(Float64(mean), Float64(std), Int(n), Float64.(samples), nothing)

"""
    g_computation(cdm, T, outcome; intervention, n=1000, rng=..., reduce=last)

Estimate `E[outcome ∣ do(intervention)]` by simulating `n` trajectories of length `T`.

Each replicate is summarised by `reduce` applied to the outcome series (default
`last`, the terminal time step). Contrast two calls to obtain an interventional
effect, e.g. `do_sequence(:a, 1.0)` versus `do_sequence(:a, 0.0)`.

# Arguments
- `cdm`: a [`DiscreteTimeCDM`](@ref)
- `T`: number of time steps per replicate
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
    intervention::AbstractCausalIntervention,
    n::Integer = 1000,
    rng::Random.AbstractRNG = Random.default_rng(),
    reduce = last,
    provenance::Union{Nothing, CDMProvenance} = nothing,
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
    return GComputationResult(m, s, n, samples, provenance)
end

export AbstractCDM, DiscreteTimeCDM, CDMTrajectory
export AbstractIntervention, DoSequence, do_sequence, intervention_value
export AbstractDoAssignment, ConstantAssignment, SeriesAssignment, TimedAssignment
export Policy, policy, policy_information_set, AbstractAvailability
export GComputationResult, g_computation
export simulate, counterfactual
