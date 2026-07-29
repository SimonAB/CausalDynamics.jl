"""
    CausalDynamicsSciMLExt

Optional integration with [SciML](https://sciml.ai/) for continuous-time CDMs:
`ODEProblem` construction, `do(·)` RHS wrapping, and named state extraction.
"""
module CausalDynamicsSciMLExt

using CausalDynamics: CausalDynamics,
    ContinuousCDMSpec,
    DoIntervention
using OrdinaryDiffEq: ODEProblem, solve

export interventional_rhs,
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

"""
    interventional_rhs(rhs!, spec::ContinuousCDMSpec, intervention::DoIntervention)

Return an in-place RHS that applies observational dynamics then pins `intervention`.
"""
function interventional_rhs(
    rhs!::F,
    spec::ContinuousCDMSpec,
    intervention::DoIntervention,
) where {F}
    idx = spec.index[Symbol(intervention.variable)]
    val = intervention.value
    return function (du, u, p, t)
        rhs!(du, u, p, t)
        u[idx] = val
        du[idx] = 0.0
        return nothing
    end
end

"""
    ode_problem_cdm(spec, rhs!, u0, tspan, p; intervention=nothing, kwargs...)

Validate dimensions and optionally wrap `rhs!` with [`interventional_rhs`](@ref).
"""
function ode_problem_cdm(
    spec::ContinuousCDMSpec,
    rhs!::F,
    u0,
    tspan,
    p;
    intervention = nothing,
    kwargs...,
) where {F}
    _validate_u0!(spec, u0)
    f = intervention === nothing ? rhs! : interventional_rhs(rhs!, spec, intervention)
    return ODEProblem(f, u0, tspan, p; kwargs...)
end

"""
    solve_cdm(spec, rhs!, u0, tspan, p; intervention=nothing, kwargs...) -> sol

`kwargs` are forwarded to `solve` only.
"""
function solve_cdm(
    spec::ContinuousCDMSpec,
    rhs!::F,
    u0,
    tspan,
    p;
    intervention = nothing,
    kwargs...,
) where {F}
    prob = ode_problem_cdm(spec, rhs!, u0, tspan, p; intervention = intervention)
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
