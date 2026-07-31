"""
    SciML integration (optional)

Load `OrdinaryDiffEq` to activate the `CausalDynamicsSciMLExt` package extension.
Causal structure and `do(·)` semantics stay in CausalDynamics; integration lives in SciML.
"""

"""
    ContinuousCDMSpec

Named continuous-time CDM: maps endogenous symbols to state-vector indices, with
optional parent sets for each coordinate (causal kinetic graph).

Use with [`ode_problem_cdm`](@ref) and [`solve_cdm`](@ref) when the mechanism is an ODE
rather than a [`DiscreteTimeCDM`](@ref).
"""
struct ContinuousCDMSpec
    variables::Vector{Symbol}
    index::Dict{Symbol, Int}
    parents::Dict{Symbol, Vector{Symbol}}
end

"""
    ContinuousCDMSpec(variables; parents = nothing)

Build a spec from an ordered list of endogenous variable names.

# Arguments
- `variables`: ordered state symbols
- `parents`: optional `Dict` mapping each child to its direct causes (may include self).
  Omitted keys default to `Symbol[]`.
"""
function ContinuousCDMSpec(
    variables::AbstractVector{Symbol};
    parents::Union{Nothing, AbstractDict} = nothing,
)
    vars = collect(Symbol, variables)
    idx = state_index_map(vars)
    pa = Dict{Symbol, Vector{Symbol}}()
    for v in vars
        pa[v] = Symbol[]
    end
    if parents !== nothing
        for (child, ps) in parents
            c = Symbol(child)
            haskey(idx, c) || throw(ArgumentError("unknown child :$c in parents"))
            plist = Symbol[Symbol(p) for p in ps]
            for p in plist
                haskey(idx, p) || throw(ArgumentError("unknown parent :$p for :$c"))
            end
            pa[c] = plist
        end
    end
    return ContinuousCDMSpec(vars, idx, pa)
end

"""
    state_index_map(variables) -> Dict{Symbol, Int}

Map each symbol in `variables` to its 1-based state index.
"""
function state_index_map(variables::AbstractVector{Symbol})
    return Dict(v => i for (i, v) in pairs(variables))
end

"""
    continuous_cdm_graph(spec::ContinuousCDMSpec) -> SimpleDiGraph

Directed graph with an edge `p → child` for each declared parent set entry.
"""
function continuous_cdm_graph(spec::ContinuousCDMSpec)
    g = Graphs.SimpleDiGraph(length(spec.variables))
    for (child, ps) in spec.parents
        j = spec.index[child]
        for p in ps
            i = spec.index[p]
            i == j && continue
            Graphs.add_edge!(g, i, j)
        end
    end
    return g
end

"""
    with_parents(spec::ContinuousCDMSpec, parents) -> ContinuousCDMSpec

Return a copy of `spec` with parent sets replaced by `parents`
(same validation as [`ContinuousCDMSpec`](@ref)).
"""
function with_parents(spec::ContinuousCDMSpec, parents::AbstractDict)
    return ContinuousCDMSpec(spec.variables; parents = parents)
end

"""
    ranked_variables_to_parents(ranking, variables; target, max_parents=2) -> Dict

Build a single-target parent map from a variable ranking
(`ranking[i]` is the rank of `variables[i]`, lower is better; omit `target`).
"""
function ranked_variables_to_parents(
    ranking::AbstractVector{<:Integer},
    variables::AbstractVector{Symbol};
    target::Symbol,
    max_parents::Integer = 2,
)
    length(ranking) == length(variables) || throw(ArgumentError(
        "ranking length must match variables",
    ))
    target in variables || throw(ArgumentError("unknown target :$target"))
    max_parents < 0 && throw(ArgumentError("max_parents must be ≥ 0"))
    cand = [(ranking[i], variables[i]) for i in eachindex(variables) if variables[i] != target]
    sort!(cand; by = first)
    chosen = Symbol[v for (_, v) in Iterators.take(cand, max_parents)]
    parents = Dict{Symbol, Vector{Symbol}}(v => Symbol[] for v in variables)
    parents[target] = chosen
    return parents
end

include("continuous_interventions.jl")

"""
    apply_initial_conditions!(u0, spec, intervention) -> u0

Mutate a copy-friendly `u0` for initial-condition and hard-pin interventions.
Soft force / RHS replacements leave `u0` unchanged.
"""
function apply_initial_conditions!(u0, spec::ContinuousCDMSpec, ::Nothing)
    return u0
end

function apply_initial_conditions!(u0, spec::ContinuousCDMSpec, intervention::DoIntervention)
    idx = spec.index[Symbol(intervention.variable)]
    u0[idx] = Float64(intervention.value)
    return u0
end

function apply_initial_conditions!(u0, spec::ContinuousCDMSpec, intervention::DoPin)
    idx = spec.index[intervention.variable]
    u0[idx] = intervention.value
    return u0
end

function apply_initial_conditions!(u0, spec::ContinuousCDMSpec, intervention::DoInitialCondition)
    idx = spec.index[intervention.variable]
    u0[idx] = intervention.value
    return u0
end

function apply_initial_conditions!(u0, spec::ContinuousCDMSpec, ::DoForce)
    return u0
end

function apply_initial_conditions!(u0, spec::ContinuousCDMSpec, ::DoRhs)
    return u0
end

function apply_initial_conditions!(u0, spec::ContinuousCDMSpec, intervention::ContinuousInterventionSet)
    for item in intervention.interventions
        apply_initial_conditions!(u0, spec, item)
    end
    return u0
end

function apply_initial_conditions!(u0, spec::ContinuousCDMSpec, interventions::AbstractVector)
    for item in interventions
        apply_initial_conditions!(u0, spec, item)
    end
    return u0
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
    interventional_rhs(rhs!, spec::ContinuousCDMSpec, intervention)

Wrap a continuous RHS for a causal kinetic intervention.
Requires `using OrdinaryDiffEq`.
"""
function interventional_rhs(args...)
    ext = _require_sciml!(:interventional_rhs)
    return ext.interventional_rhs(args...)
end

"""
    intervention_callback(spec, intervention)

SciML `DiscreteCallback` / `CallbackSet` maintaining hard pins.
Requires `using OrdinaryDiffEq`.
"""
function intervention_callback(args...)
    ext = _require_sciml!(:intervention_callback)
    return ext.intervention_callback(args...)
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

"""
    has_sciml_sensitivity() -> Bool

Return `true` when the SciMLSensitivity extension is loaded.
"""
function has_sciml_sensitivity()
    return !isnothing(Base.get_extension(@__MODULE__, :CausalDynamicsSensitivityExt))
end

function _require_sensitivity!(f::Symbol)
    ext = Base.get_extension(@__MODULE__, :CausalDynamicsSensitivityExt)
    ext === nothing && error(
        "SciMLSensitivity extension is not loaded. Run: using OrdinaryDiffEq, SciMLSensitivity\n" *
        "Then call CausalDynamics.$f(...).",
    )
    return ext
end

"""
    forward_sensitivity_cdm(spec, rhs!, u0, tspan, p; kwargs...) -> sol

Forward local sensitivity of a continuous CDM via SciMLSensitivity.
Requires `using OrdinaryDiffEq, SciMLSensitivity`.
"""
function forward_sensitivity_cdm(args...; kwargs...)
    ext = _require_sensitivity!(:forward_sensitivity_cdm)
    return ext.forward_sensitivity_cdm(args...; kwargs...)
end

export ContinuousCDMSpec,
    state_index_map,
    continuous_cdm_graph,
    with_parents,
    ranked_variables_to_parents,
    apply_initial_conditions!,
    has_sciml,
    has_sciml_sensitivity,
    interventional_rhs,
    intervention_callback,
    ode_problem_cdm,
    solve_cdm,
    terminal_state,
    state_series,
    forward_sensitivity_cdm