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
    attach_lux_mechanism!(lib, node; parents, hidden, kind, rng, activation, output_dim)

Register and attach a dense MLP ``|parents| → hidden → output_dim`` at `node`.
For `:generative`, the network is ``f(\\mathrm{pa})`` in ``X = f(\\mathrm{pa}) + U``.
"""
function attach_lux_mechanism!(
    lib::MechanismLibrary,
    node::Symbol;
    parents::AbstractVector{Symbol},
    hidden::Int = 8,
    kind::Symbol = :ode_residual,
    rng::AbstractRNG = Random.default_rng(),
    activation = tanh,
    output_dim::Int = 1,
)
    spec = MechanismSpec(node, parents; kind = kind, output_dim = output_dim)
    register_mechanism!(lib, spec)
    nin = length(parents)
    nin >= 1 || throw(ArgumentError("parents must be non-empty for Lux mechanism at :$node"))
    output_dim >= 1 || throw(ArgumentError("output_dim must be ≥ 1"))
    nn = Chain(Dense(nin => hidden, activation), Dense(hidden => output_dim))
    ps, st = Lux.setup(rng, nn)
    spec.model = nn
    spec.parameters = ComponentArray(ps)
    spec.states = st
    lib.mechanisms[node] = spec
    return lib
end

"""
    _apply_vector(spec, x) -> Vector{Float64}

Evaluate attached Lux net on parent vector `x` (length `output_dim`).
"""
function _apply_vector(spec::MechanismSpec, x::AbstractVector{<:Real})
    spec.model === nothing && throw(ArgumentError(
        "mechanism :$(spec.node) has no Lux model; call attach_lux_mechanism! first",
    ))
    y, _ = Lux.apply(spec.model, Float32.(x), spec.parameters, spec.states)
    return Float64.(vec(y))
end

"""
    _apply_scalar(spec, x) -> Float64

Evaluate attached Lux net when `output_dim == 1`.
"""
function _apply_scalar(spec::MechanismSpec, x::AbstractVector{<:Real})
    y = _apply_vector(spec, x)
    length(y) == 1 || throw(ArgumentError(
        "mechanism :$(spec.node) has output_dim=$(spec.output_dim); use _apply_vector",
    ))
    return y[1]
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

For each `:static` or `:generative` mechanism, replace the equation at the
corresponding integer node. Generative nodes use additive noise
``X = f(\\mathrm{pa}) + U`` with ``U`` the last equation argument.
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
        (m.kind === :static || m.kind === :generative) || continue
        haskey(s2i, m.node) || throw(ArgumentError(
            "$(m.kind) mechanism :$(m.node) missing from node_names",
        ))
        idx = s2i[m.node]
        parent_idxs = sort(collect(inneighbors(g, idx)))
        parent_syms = [i2s[i] for i in parent_idxs]
        Set(parent_syms) == Set(m.parents) || throw(ArgumentError(
            "mechanism :$(m.node) parents $(m.parents) ≠ graph parents $parent_syms",
        ))
        order = [findfirst(==(p), parent_syms) for p in m.parents]
        n_pa = length(parent_idxs)
        if m.kind === :static
            eqs[idx] = function (args...)
                length(args) >= n_pa || throw(ArgumentError(
                    "equation for :$(m.node) expected ≥ $n_pa parent args; got $(length(args))",
                ))
                pa_sorted = collect(args[1:n_pa])
                x = [pa_sorted[j] for j in order]
                return m.output_dim == 1 ? _apply_scalar(m, x) : _apply_vector(m, x)
            end
        else
            eqs[idx] = function (args...)
                length(args) >= n_pa + 1 || throw(ArgumentError(
                    "generative :$(m.node) expected parents + U; got $(length(args)) args",
                ))
                pa_sorted = collect(args[1:n_pa])
                x = [pa_sorted[j] for j in order]
                u = args[n_pa + 1]
                return generate_from_noise(m, u, x)
            end
        end
    end
    return GraphSCM(g, eqs, exogenous)
end

"""
    abduce_noise(spec, x, pa) -> z

Additive abduction ``U = X - f(\\mathrm{pa})`` for `:generative` mechanisms.
"""
function abduce_noise(spec::MechanismSpec, x, pa)
    spec.kind === :generative || throw(ArgumentError(
        "abduce_noise requires kind=:generative; got :$(spec.kind)",
    ))
    pa_vec = Float64[Float64(v) for v in pa]
    length(pa_vec) == length(spec.parents) || throw(ArgumentError(
        "expected $(length(spec.parents)) parent values; got $(length(pa_vec))",
    ))
    x_vec = x isa AbstractVector ? Float64.(vec(x)) : Float64[Float64(x)]
    length(x_vec) == spec.output_dim || throw(ArgumentError(
        "x length $(length(x_vec)) ≠ output_dim=$(spec.output_dim)",
    ))
    μ = _apply_vector(spec, pa_vec)
    z = x_vec .- μ
    return spec.output_dim == 1 ? z[1] : z
end

"""
    generate_from_noise(spec, z, pa) -> x

``X = f(\\mathrm{pa}) + U`` for `:generative` mechanisms.
"""
function generate_from_noise(spec::MechanismSpec, z, pa)
    spec.kind === :generative || throw(ArgumentError(
        "generate_from_noise requires kind=:generative; got :$(spec.kind)",
    ))
    pa_vec = Float64[Float64(v) for v in pa]
    length(pa_vec) == length(spec.parents) || throw(ArgumentError(
        "expected $(length(spec.parents)) parent values; got $(length(pa_vec))",
    ))
    z_vec = z isa AbstractVector ? Float64.(vec(z)) : Float64[Float64(z)]
    length(z_vec) == spec.output_dim || throw(ArgumentError(
        "noise length $(length(z_vec)) ≠ output_dim=$(spec.output_dim)",
    ))
    μ = _apply_vector(spec, pa_vec)
    x = μ .+ z_vec
    return spec.output_dim == 1 ? x[1] : x
end

"""
    mechanism_counterfactual(spec, x_factual, pa_factual, pa_cf) -> x_cf

Abduce ``U`` under factual parents, then generate under counterfactual parents.
"""
function mechanism_counterfactual(spec::MechanismSpec, x_factual, pa_factual, pa_cf)
    z = abduce_noise(spec, x_factual, pa_factual)
    return generate_from_noise(spec, z, pa_cf)
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
