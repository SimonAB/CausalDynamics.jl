"""
    SciML integration (optional)

Load `OrdinaryDiffEq` to activate the `CausalDynamicsSciMLExt` package extension.
Causal structure and `do(·)` semantics stay in CausalDynamics; integration lives in SciML.
"""

"""
    ContinuousCDMSpec

Named continuous-time CDM: maps endogenous symbols to state-vector indices.

Use with [`ode_problem_cdm`](@ref) and [`solve_cdm`](@ref) when the mechanism is an ODE
rather than a [`DiscreteTimeCDM`](@ref).
"""
struct ContinuousCDMSpec
    variables::Vector{Symbol}
    index::Dict{Symbol, Int}
end

"""
    ContinuousCDMSpec(variables)

Build a spec from an ordered list of endogenous variable names.
"""
function ContinuousCDMSpec(variables::AbstractVector{Symbol})
    vars = collect(Symbol, variables)
    return ContinuousCDMSpec(vars, state_index_map(vars))
end

"""
    state_index_map(variables) -> Dict{Symbol, Int}

Map each symbol in `variables` to its 1-based state index.
"""
function state_index_map(variables::AbstractVector{Symbol})
    return Dict(v => i for (i, v) in pairs(variables))
end

"""
    has_sciml() -> Bool

Return `true` when the `CausalDynamicsSciMLExt` extension is loaded (`using OrdinaryDiffEq`).
"""
function has_sciml()
    return !isnothing(Base.get_extension(@__MODULE__, :CausalDynamicsSciMLExt))
end

function _require_sciml!(f::Symbol)
    ext = Base.get_extension(@__MODULE__, :CausalDynamicsSciMLExt)
    ext === nothing && error(
        "SciML extension is not loaded. Run: using OrdinaryDiffEq\n" *
        "Then call CausalDynamics.$f(...). See docs/SCIML_INTEGRATION.md.",
    )
    return ext
end

"""
    interventional_rhs(rhs!, spec::ContinuousCDMSpec, intervention::DoIntervention)

Wrap a continuous RHS so `do(variable = value)` pins that component (zero derivative).
Requires `using OrdinaryDiffEq`.
"""
function interventional_rhs(args...)
    ext = _require_sciml!(:interventional_rhs)
    return ext.interventional_rhs(args...)
end

"""
    ode_problem_cdm(spec, rhs!, u0, tspan, p; intervention=nothing, kwargs...)

Build an `ODEProblem` with `length(u0) == length(spec.variables)`.
Requires `using OrdinaryDiffEq`.
"""
function ode_problem_cdm(args...; kwargs...)
    ext = _require_sciml!(:ode_problem_cdm)
    return ext.ode_problem_cdm(args...; kwargs...)
end

"""
    solve_cdm(spec, rhs!, u0, tspan, p; intervention=nothing, kwargs...) -> sol

Integrate a continuous CDM and return the SciML solution.
Requires `using OrdinaryDiffEq`.
"""
function solve_cdm(args...; kwargs...)
    ext = _require_sciml!(:solve_cdm)
    return ext.solve_cdm(args...; kwargs...)
end

"""
    terminal_state(spec::ContinuousCDMSpec, sol) -> NamedTuple

Terminal endogenous state keyed by symbol. Requires `using OrdinaryDiffEq`.
"""
function terminal_state(args...)
    ext = _require_sciml!(:terminal_state)
    return ext.terminal_state(args...)
end

"""
    state_series(spec::ContinuousCDMSpec, sol) -> NamedTuple

Time series of each endogenous variable. Requires `using OrdinaryDiffEq`.
"""
function state_series(args...)
    ext = _require_sciml!(:state_series)
    return ext.state_series(args...)
end

export ContinuousCDMSpec,
    state_index_map,
    has_sciml,
    interventional_rhs,
    ode_problem_cdm,
    solve_cdm,
    terminal_state,
    state_series
