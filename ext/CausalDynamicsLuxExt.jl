"""
    CausalDynamicsLuxExt

Optional Lux mechanisms for Phase 2: parent-constrained MLP residuals on
continuous CDMs and static GraphSCM equations, plus a thin Adam trainer.

Core façades call these functions via `Base.get_extension`; do not overwrite
CausalDynamics methods from this module.
"""
module CausalDynamicsLuxExt

using CausalDynamics
using CausalDynamics:
    MechanismSpec,
    MechanismLibrary,
    register_mechanism!,
    pack_parent_vector,
    ContinuousCDMSpec,
    GraphSCM
using Lux
using ComponentArrays
using Optimization
using OptimizationOptimisers
using Random
using Graphs: DiGraph, inneighbors

"""
    attach_lux_mechanism!(lib, node; parents, hidden, kind, rng, activation)

Register and attach a dense MLP ``|parents| → hidden → 1`` at `node`.
"""
function attach_lux_mechanism!(
    lib::MechanismLibrary,
    node::Symbol;
    parents::AbstractVector{Symbol},
    hidden::Int = 8,
    kind::Symbol = :ode_residual,
    rng::AbstractRNG = Random.default_rng(),
    activation = tanh,
)
    spec = MechanismSpec(node, parents; kind = kind)
    register_mechanism!(lib, spec)
    nin = length(parents)
    nin >= 1 || throw(ArgumentError("parents must be non-empty for Lux mechanism at :$node"))
    nn = Chain(Dense(nin => hidden, activation), Dense(hidden => 1))
    ps, st = Lux.setup(rng, nn)
    spec.model = nn
    spec.parameters = ComponentArray(ps)
    spec.states = st
    lib.mechanisms[node] = spec
    return lib
end

"""
    _apply_scalar(spec, x) -> Float64

Evaluate attached Lux net on parent vector `x`.
"""
function _apply_scalar(spec::MechanismSpec, x::AbstractVector{<:Real})
    spec.model === nothing && throw(ArgumentError(
        "mechanism :$(spec.node) has no Lux model; call attach_lux_mechanism! first",
    ))
    y, _ = Lux.apply(spec.model, Float32.(x), spec.parameters, spec.states)
    return Float64(first(y))
end

"""
    build_ode_rhs(known_rhs!, spec, lib) -> Function

In-place RHS: run `known_rhs!`, then add `:ode_residual` NN outputs on each
mechanism node using only its declared parents.
"""
function build_ode_rhs(
    known_rhs!,
    spec::ContinuousCDMSpec,
    lib::MechanismLibrary,
)
    residuals = MechanismSpec[
        m for m in values(lib.mechanisms) if m.kind === :ode_residual
    ]
    for m in residuals
        haskey(spec.index, m.node) || throw(ArgumentError(
            "mechanism node :$(m.node) not in ContinuousCDMSpec variables",
        ))
        for p in m.parents
            haskey(spec.index, p) || throw(ArgumentError(
                "parent :$p of :$(m.node) missing from ContinuousCDMSpec",
            ))
        end
    end
    return function (du, u, p, t)
        known_rhs!(du, u, p, t)
        for m in residuals
            x = pack_parent_vector(u, spec, m.parents)
            du[spec.index[m.node]] += _apply_scalar(m, x)
        end
        return nothing
    end
end

"""
    graphscm_with_mechanisms(g, equations, exogenous, lib; node_names) -> GraphSCM

For each `:static` mechanism, replace the equation at the corresponding integer
node with a Lux map of sorted graph parents.
"""
function graphscm_with_mechanisms(
    g::DiGraph,
    equations::Dict{Int, Function},
    exogenous::Set{Int},
    lib::MechanismLibrary;
    node_names::AbstractDict,
)
    i2s = Dict{Int, Symbol}()
    s2i = Dict{Symbol, Int}()
    for (k, v) in node_names
        if k isa Integer
            i2s[Int(k)] = Symbol(v)
            s2i[Symbol(v)] = Int(k)
        else
            s2i[Symbol(k)] = Int(v)
            i2s[Int(v)] = Symbol(k)
        end
    end

    eqs = copy(equations)
    for m in values(lib.mechanisms)
        m.kind === :static || continue
        haskey(s2i, m.node) || throw(ArgumentError(
            "static mechanism :$(m.node) missing from node_names",
        ))
        idx = s2i[m.node]
        parent_idxs = sort(collect(inneighbors(g, idx)))
        parent_syms = [i2s[i] for i in parent_idxs]
        Set(parent_syms) == Set(m.parents) || throw(ArgumentError(
            "static mechanism :$(m.node) parents $(m.parents) ≠ graph parents $parent_syms",
        ))
        order = [findfirst(==(p), parent_syms) for p in m.parents]
        n_pa = length(parent_idxs)
        eqs[idx] = function (args...)
            length(args) >= n_pa || throw(ArgumentError(
                "equation for :$(m.node) expected ≥ $n_pa parent args; got $(length(args))",
            ))
            pa_sorted = collect(args[1:n_pa])
            x = [pa_sorted[j] for j in order]
            return _apply_scalar(m, x)
        end
    end
    return GraphSCM(g, eqs, exogenous)
end

"""
    train_mechanisms!(lib; loss, maxiters, lr) -> NamedTuple

Minimise `loss(ps_component_array)` with Adam over all attached parameters.
"""
function train_mechanisms!(
    lib::MechanismLibrary;
    loss::Function,
    maxiters::Int = 200,
    lr::Float64 = 0.01,
)
    nodes = sort!(collect(keys(lib.mechanisms)))
    isempty(nodes) && throw(ArgumentError("MechanismLibrary is empty"))
    for n in nodes
        lib.mechanisms[n].parameters === nothing && throw(ArgumentError(
            "mechanism :$n is not attached; call attach_lux_mechanism!",
        ))
    end
    ps0 = ComponentArray(NamedTuple{Tuple(nodes)}(
        Tuple(lib.mechanisms[n].parameters for n in nodes),
    ))

    function _loss(ps, _)
        for n in nodes
            lib.mechanisms[n].parameters = ps[n]
        end
        return loss(ps)
    end

    optf = OptimizationFunction(_loss, Optimization.AutoFiniteDiff())
    optprob = OptimizationProblem(optf, ps0)
    sol = solve(optprob, OptimizationOptimisers.Adam(lr); maxiters = maxiters)
    for n in nodes
        lib.mechanisms[n].parameters = sol.u[n]
    end
    return (objective = sol.objective, parameters = sol.u, retcode = sol.retcode)
end

end # module
