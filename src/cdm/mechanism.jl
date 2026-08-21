"""Graph-constrained deep mechanisms (Phase 2a/2b).

Core types and certificates live here with **no** Lux/Optimization hard
dependency. Call [`attach_lux_mechanism!`](@ref) after `using Lux` (and related
weakdeps) so the package extension loads.

Phase 2b adds `:generative` mechanisms with additive-noise abduction for L3
counterfactuals on codes (or low-dim tensors treated as vectors).
"""

const MECHANISM_KINDS = (:static, :ode_residual, :generative)

"""
    MechanismSpec(node, parents; kind=:ode_residual, representation=nothing, output_dim=1)

Declare a deep structural mechanism at `node` that may only depend on `parents`
(must be a subset of the graph / CDM parent set).

# Fields
- `node`: endogenous variable
- `parents`: allowed causal parents (order used when packing NN inputs)
- `kind`: `:static` (SCM ``f_i``), `:ode_residual` (additive NN on ``\\dot u``),
  or `:generative` (``X = f(\\mathrm{pa}) + U`` with abduce/generate for L3)
- `representation`: optional [`RepresentationSpec`](@ref) linking Phase 1 codes
- `output_dim`: dimension of the node (1 for scalars; >1 for code/tensor vectors)
- `model`, `parameters`, `states`: filled by the Lux extension (`nothing` until attach)
"""
mutable struct MechanismSpec
    node::Symbol
    parents::Vector{Symbol}
    kind::Symbol
    representation::Union{Nothing, RepresentationSpec}
    model::Any
    parameters::Any
    states::Any
    output_dim::Int
end

function MechanismSpec(
    node::Symbol,
    parents::AbstractVector{Symbol};
    kind::Symbol = :ode_residual,
    representation::Union{Nothing, RepresentationSpec} = nothing,
    output_dim::Int = 1,
)
    kind in MECHANISM_KINDS || throw(ArgumentError(
        "kind must be one of $MECHANISM_KINDS; got :$kind",
    ))
    output_dim >= 1 || throw(ArgumentError("output_dim must be ≥ 1; got $output_dim"))
    pa = Symbol[Symbol(p) for p in parents]
    length(unique(pa)) == length(pa) || throw(ArgumentError(
        "parents must be unique; got $pa",
    ))
    return MechanismSpec(
        Symbol(node), pa, kind, representation, nothing, nothing, nothing, output_dim,
    )
end

"""
    MechanismLibrary(; allowed_parents, graph_hash=zero(UInt64))

Collection of [`MechanismSpec`](@ref)s with parent-set validation against
`allowed_parents` (typically from a DAG or [`ContinuousCDMSpec`](@ref).parents).
"""
mutable struct MechanismLibrary
    mechanisms::Dict{Symbol, MechanismSpec}
    allowed_parents::Dict{Symbol, Vector{Symbol}}
    graph_hash::UInt64
end

function MechanismLibrary(;
    allowed_parents::AbstractDict = Dict{Symbol, Vector{Symbol}}(),
    graph_hash::UInt64 = zero(UInt64),
)
    ap = Dict{Symbol, Vector{Symbol}}(
        Symbol(k) => Symbol[Symbol(p) for p in v] for (k, v) in allowed_parents
    )
    return MechanismLibrary(Dict{Symbol, MechanismSpec}(), ap, graph_hash)
end

"""
    mechanism_library_from_cdm(spec::ContinuousCDMSpec; graph_hash=...) -> MechanismLibrary

Build a library whose allowed parents match `spec.parents`.
"""
function mechanism_library_from_cdm(
    spec::ContinuousCDMSpec;
    graph_hash::UInt64 = zero(UInt64),
)
    return MechanismLibrary(; allowed_parents = spec.parents, graph_hash = graph_hash)
end

"""
    register_mechanism!(lib, spec) -> MechanismLibrary

Insert `spec` after checking `spec.parents ⊆ allowed_parents[spec.node]`.
"""
function register_mechanism!(lib::MechanismLibrary, spec::MechanismSpec)
    haskey(lib.allowed_parents, spec.node) || throw(ArgumentError(
        "node :$(spec.node) not in allowed_parents; known=$(collect(keys(lib.allowed_parents)))",
    ))
    allowed = lib.allowed_parents[spec.node]
    for p in spec.parents
        p in allowed || throw(ArgumentError(
            "parent :$p of :$(spec.node) not in allowed parents $allowed",
        ))
    end
    lib.mechanisms[spec.node] = spec
    return lib
end

"""
    mechanism_certificate(lib) -> NamedTuple

Auditable metadata: nodes, kinds, parent maps, graph hash, whether Lux payloads
are attached.
"""
function mechanism_certificate(lib::MechanismLibrary)
    nodes = sort!(collect(keys(lib.mechanisms)))
    kinds = Dict(n => lib.mechanisms[n].kind for n in nodes)
    parents = Dict(n => copy(lib.mechanisms[n].parents) for n in nodes)
    attached = Dict(
        n => lib.mechanisms[n].model !== nothing for n in nodes
    )
    output_dims = Dict(n => lib.mechanisms[n].output_dim for n in nodes)
    return (
        nodes = nodes,
        kinds = kinds,
        parents = parents,
        attached = attached,
        output_dims = output_dims,
        graph_hash = lib.graph_hash,
        n_mechanisms = length(nodes),
        lux_available = lux_mechanisms_available(),
    )
end

"""
    lux_mechanisms_available() -> Bool

Return `true` when the Lux mechanism extension is loaded.
"""
function lux_mechanisms_available()
    return Base.get_extension(@__MODULE__, :CausalDynamicsLuxExt) !== nothing
end

function _require_lux_ext(fname::String)
    ext = Base.get_extension(@__MODULE__, :CausalDynamicsLuxExt)
    ext === nothing && throw(ErrorException(
        "$fname requires the Lux mechanism extension. Add Lux, ComponentArrays, " *
        "Optimization, and OptimizationOptimisers, then `using Lux` " *
        "(and ComponentArrays / Optimization as needed) to load CausalDynamicsLuxExt.",
    ))
    return ext
end

"""
    attach_lux_mechanism!(lib, node; parents, hidden, kind, rng, activation, output_dim)

Attach a small Lux MLP at `node`. Requires the Lux weakdep extension.
"""
function attach_lux_mechanism!(lib::MechanismLibrary, node::Symbol; kwargs...)
    return _require_lux_ext("attach_lux_mechanism!").attach_lux_mechanism!(
        lib, node; kwargs...,
    )
end

"""
    build_ode_rhs(known_rhs!, spec, lib) -> Function

Compose an in-place ODE RHS: `known_rhs!` then add Lux residuals for
`:ode_residual` mechanisms, packing only declared parents. Requires Lux ext.
"""
function build_ode_rhs(known_rhs!, spec::ContinuousCDMSpec, lib::MechanismLibrary)
    return _require_lux_ext("build_ode_rhs").build_ode_rhs(known_rhs!, spec, lib)
end

"""
    graphscm_with_mechanisms(g, equations, exogenous, lib; node_names) -> GraphSCM

Replace selected equation entries with Lux `:static` / `:generative` mechanisms
from `lib`. Requires Lux ext.
"""
function graphscm_with_mechanisms(
    g::Graphs.DiGraph,
    equations::Dict{Int, Function},
    exogenous::Set{Int},
    lib::MechanismLibrary;
    node_names::AbstractDict,
)
    return _require_lux_ext("graphscm_with_mechanisms").graphscm_with_mechanisms(
        g, equations, exogenous, lib; node_names = node_names,
    )
end

"""
    train_mechanisms!(lib; loss, maxiters, opt, kwargs...) -> NamedTuple

Thin Adam training loop over attached Lux parameters. Requires Lux ext.

Training designs must be complete: do not pass panels containing `Missing` into
`loss`. Drop or impute under an Observable policy first (see
[`require_complete_matrix`](@ref) / [`apply_missingness_mechanism`](@ref)).
"""
function train_mechanisms!(lib::MechanismLibrary; loss, kwargs...)
    return _require_lux_ext("train_mechanisms!").train_mechanisms!(lib; loss = loss, kwargs...)
end

"""
    abduce_noise(spec, x, pa) -> noise

Infer additive exogenous noise ``U = X - f(\\mathrm{pa})`` for a `:generative`
mechanism. Requires Lux ext when `spec.model` is attached.
"""
function abduce_noise(spec::MechanismSpec, x, pa)
    return _require_lux_ext("abduce_noise").abduce_noise(spec, x, pa)
end

"""
    generate_from_noise(spec, z, pa) -> x

Sample / reconstruct ``X = f(\\mathrm{pa}) + U`` for a `:generative` mechanism.
Requires Lux ext.
"""
function generate_from_noise(spec::MechanismSpec, z, pa)
    return _require_lux_ext("generate_from_noise").generate_from_noise(spec, z, pa)
end

"""
    mechanism_counterfactual(spec, x_factual, pa_factual, pa_cf) -> x_cf

Pearl L3 for one generative node: abduce ``U`` from the factual, then generate
under counterfactual parents (same ``U``). Requires Lux ext.
"""
function mechanism_counterfactual(spec::MechanismSpec, x_factual, pa_factual, pa_cf)
    return _require_lux_ext("mechanism_counterfactual").mechanism_counterfactual(
        spec, x_factual, pa_factual, pa_cf,
    )
end

"""
    pack_parent_vector(u, spec, parents) -> Vector

Gather state coordinates for `parents` from `u` using `ContinuousCDMSpec` indices.
"""
function pack_parent_vector(
    u::AbstractVector,
    spec::ContinuousCDMSpec,
    parents::AbstractVector{Symbol},
)
    raw = [u[spec.index[p]] for p in parents]
    require_complete_values(raw; context = "parent vector for ContinuousCDMSpec")
    return Float64[Float64(v) for v in raw]
end

export MechanismSpec, MechanismLibrary, mechanism_library_from_cdm
export register_mechanism!, mechanism_certificate, lux_mechanisms_available
export attach_lux_mechanism!, build_ode_rhs, graphscm_with_mechanisms, train_mechanisms!
export abduce_noise, generate_from_noise, mechanism_counterfactual
export pack_parent_vector
