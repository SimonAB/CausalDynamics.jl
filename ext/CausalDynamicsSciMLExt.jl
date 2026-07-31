"""
    CausalDynamicsSciMLExt

Optional SciML integration for continuous-time CDMs: `ODEProblem` construction,
continuous-CDM `do(·)` via RHS wrapping, and SciML-native pin callbacks
(`DiscreteCallback` / `CallbackSet` from OrdinaryDiffEq).
"""
module CausalDynamicsSciMLExt

using CausalDynamics: CausalDynamics,
    ContinuousCDMSpec,
    AbstractCausalIntervention,
    DoIntervention,
    DoPin,
    DoInitialCondition,
    DoForce,
    DoRhs,
    ContinuousInterventionSet,
    apply_initial_conditions!
using OrdinaryDiffEq: ODEProblem, solve, DiscreteCallback, CallbackSet

export interventional_rhs,
    intervention_callback,
    ode_problem_cdm,
    solve_cdm,
    terminal_state,
    state_series

function _validate_u0!(spec::ContinuousCDMSpec, u0)
    length(u0) == length(spec.variables) || throw(ArgumentError(
        "length(u0) ($(length(u0))) must match spec.variables ($(length(spec.variables)))",
    ))
    return nothing
end

# ── Pin helpers (SciML-native: du = 0 + DiscreteCallback, no in-RHS u mutate) ─

function _pin_index_value(spec::ContinuousCDMSpec, intervention::DoPin)
    return spec.index[intervention.variable], intervention.value
end

function _pin_index_value(spec::ContinuousCDMSpec, intervention::DoIntervention)
    return spec.index[Symbol(intervention.variable)], Float64(intervention.value)
end

"""
    intervention_callback(spec, intervention) -> Union{Nothing, DiscreteCallback, CallbackSet}

SciML callbacks that maintain hard pins without mutating `u` inside the ODE RHS.
"""
function intervention_callback(::ContinuousCDMSpec, ::Nothing)
    return nothing
end

function intervention_callback(spec::ContinuousCDMSpec, intervention::Union{DoPin, DoIntervention})
    idx, val = _pin_index_value(spec, intervention)
    return DiscreteCallback(
        (_u, _t, _integrator) -> true,
        integrator -> (integrator.u[idx] = val; nothing);
        save_positions = (false, false),
    )
end

function intervention_callback(::ContinuousCDMSpec, ::DoInitialCondition)
    return nothing
end

function intervention_callback(::ContinuousCDMSpec, ::DoForce)
    return nothing
end

function intervention_callback(::ContinuousCDMSpec, ::DoRhs)
    return nothing
end

function intervention_callback(spec::ContinuousCDMSpec, intervention::ContinuousInterventionSet)
    cbs = Any[]
    for item in intervention.interventions
        cb = intervention_callback(spec, item)
        cb === nothing || push!(cbs, cb)
    end
    isempty(cbs) && return nothing
    length(cbs) == 1 && return cbs[1]
    return CallbackSet(cbs...)
end

function intervention_callback(spec::ContinuousCDMSpec, interventions::AbstractVector)
    return intervention_callback(spec, ContinuousInterventionSet(
        collect(AbstractCausalIntervention, interventions),
    ))
end

function _merge_callback(user_cb, intervention_cb)
    intervention_cb === nothing && return user_cb
    user_cb === nothing && return intervention_cb
    return CallbackSet(user_cb, intervention_cb)
end

# ── RHS wrapping ──────────────────────────────────────────────────────────────

"""
    interventional_rhs(rhs!, spec, intervention)

Return an in-place RHS implementing the intervention. Hard pins only zero `du`
(initial value and `DiscreteCallback` hold the level).
"""
function interventional_rhs(
    rhs!::F,
    spec::ContinuousCDMSpec,
    intervention::Union{DoPin, DoIntervention},
) where {F}
    idx, _ = _pin_index_value(spec, intervention)
    return function (du, u, p, t)
        rhs!(du, u, p, t)
        du[idx] = 0.0
        return nothing
    end
end

function interventional_rhs(
    rhs!::F,
    spec::ContinuousCDMSpec,
    ::DoInitialCondition,
) where {F}
    return rhs!
end

function interventional_rhs(
    rhs!::F,
    spec::ContinuousCDMSpec,
    intervention::DoForce,
) where {F}
    idx = spec.index[intervention.variable]
    target = intervention.target
    κ = intervention.κ
    return function (du, u, p, t)
        rhs!(du, u, p, t)
        du[idx] -= κ * (u[idx] - target)
        return nothing
    end
end

function interventional_rhs(
    rhs!::F,
    spec::ContinuousCDMSpec,
    intervention::DoRhs,
) where {F}
    idx = spec.index[intervention.variable]
    g = intervention.du_fn
    return function (du, u, p, t)
        rhs!(du, u, p, t)
        du[idx] = g(u, p, t)
        return nothing
    end
end

function interventional_rhs(
    rhs!::F,
    spec::ContinuousCDMSpec,
    intervention::ContinuousInterventionSet,
) where {F}
    f = rhs!
    for item in intervention.interventions
        f = interventional_rhs(f, spec, item)
    end
    return f
end

function interventional_rhs(
    rhs!::F,
    spec::ContinuousCDMSpec,
    interventions::AbstractVector,
) where {F}
    return interventional_rhs(
        rhs!,
        spec,
        ContinuousInterventionSet(collect(AbstractCausalIntervention, interventions)),
    )
end

# ── Problem / solve ───────────────────────────────────────────────────────────

"""
    ode_problem_cdm(spec, rhs!, u0, tspan, p; intervention=nothing, kwargs...)

Apply IC interventions, wrap the RHS, and attach SciML pin callbacks. User
`callback` kwargs are composed via `CallbackSet`.
"""
function ode_problem_cdm(
    spec::ContinuousCDMSpec,
    rhs!::F,
    u0,
    tspan,
    p;
    intervention = nothing,
    callback = nothing,
    kwargs...,
) where {F}
    _validate_u0!(spec, u0)
    u0c = copy(u0)
    apply_initial_conditions!(u0c, spec, intervention)
    f = intervention === nothing ? rhs! : interventional_rhs(rhs!, spec, intervention)
    cb = _merge_callback(callback, intervention_callback(spec, intervention))
    if cb === nothing
        return ODEProblem(f, u0c, tspan, p; kwargs...)
    end
    return ODEProblem(f, u0c, tspan, p; callback = cb, kwargs...)
end

"""
    solve_cdm(spec, rhs!, u0, tspan, p; intervention=nothing, kwargs...) -> sol
"""
function solve_cdm(
    spec::ContinuousCDMSpec,
    rhs!::F,
    u0,
    tspan,
    p;
    intervention = nothing,
    callback = nothing,
    kwargs...,
) where {F}
    prob = ode_problem_cdm(
        spec, rhs!, u0, tspan, p;
        intervention = intervention,
        callback = callback,
    )
    return solve(prob; kwargs...)
end

"""
    terminal_state(spec::ContinuousCDMSpec, sol) -> NamedTuple
"""
function terminal_state(spec::ContinuousCDMSpec, sol)
    u_end = sol.u[end]
    return NamedTuple{Tuple(spec.variables)}(Tuple(u_end[i] for i in eachindex(spec.variables)))
end

"""
    state_series(spec::ContinuousCDMSpec, sol) -> NamedTuple
"""
function state_series(spec::ContinuousCDMSpec, sol)
    nvar = length(spec.variables)
    mats = [Vector{eltype(sol.u[1])}(undef, length(sol.t)) for _ in 1:nvar]
    for (k, u) in pairs(sol.u)
        for i in 1:nvar
            mats[i][k] = u[i]
        end
    end
    return NamedTuple{Tuple(spec.variables)}(Tuple(mats[i] for i in 1:nvar))
end

end # module
