"""Unified identification API: `identify(graph, query)`."""

"""
    IdentificationError <: Exception

Thrown when a mediation (or other) query is not identified under the stated
effect kind and graph structure.
"""
struct IdentificationError <: Exception
    msg::String
end

Base.showerror(io::IO, e::IdentificationError) = print(io, "IdentificationError: ", e.msg)

"""
    _normalize_node_names(node_names, n) -> Union{Nothing, Dict{Int, Symbol}}

Normalise `node_names` to `Dict{Int, Symbol}` (or `nothing`).

Accepts:

- `nothing`
- `Dict{Int, Symbol}` (or integer → name maps convertible to symbols)
- a vector of names of length `n`, where index `i` names node `i`
"""
function _normalize_node_names(node_names::Nothing, n::Integer)
    return nothing
end

function _normalize_node_names(node_names::AbstractDict{Int, Symbol}, n::Integer)
    return Dict{Int, Symbol}(node_names)
end

function _normalize_node_names(node_names::AbstractDict{<:Integer}, n::Integer)
    return Dict{Int, Symbol}(Int(k) => Symbol(v) for (k, v) in node_names)
end

function _normalize_node_names(node_names::AbstractVector, n::Integer)
    length(node_names) == n || throw(ArgumentError(
        "node_names vector length $(length(node_names)) must equal number of nodes $n",
    ))
    return Dict{Int, Symbol}(i => Symbol(node_names[i]) for i in eachindex(node_names))
end

function _normalize_node_names(node_names, n::Integer)
    throw(ArgumentError(
        "node_names must be nothing, a Dict{<:Integer,<:Any}, or a Vector of names; " *
        "got $(typeof(node_names))",
    ))
end

"""
    _node_index(g, x::Int) -> Int
    _node_index(g, x::Symbol, node_names) -> Int
"""
function _node_index(g::AbstractGraph, x::Int)
    1 <= x <= nv(g) || throw(ArgumentError("node index $x out of range 1:$(nv(g))"))
    return x
end

function _node_index(g::AbstractGraph, x::Symbol, node_names::Dict{Int, Symbol})
    for (i, n) in node_names
        n == x && return _node_index(g, i)
    end
    throw(ArgumentError("symbol :$x not found in node_names"))
end

function _labels_from_indices(indices::Set{Int}, node_names::Union{Nothing, Dict{Int, Symbol}})
    sorted = sort(collect(indices))
    if node_names === nothing
        return sorted
    end
    return [node_names[i] for i in sorted if haskey(node_names, i)]
end

function _empty_like(adjustment)
    return similar(adjustment, 0)
end

"""
    _has_directed_path_simple(g, src, dst) -> Bool
"""
function _has_directed_path_simple(g::AbstractGraph, src::Int, dst::Int)
    src == dst && return true
    return dst in get_descendants(g, src)
end

"""
    _recanting_witness_nodes(g, A, Y, mediator_idx) -> Vector{Int}

Nodes Z on a recanting structure: descendants of A, ancestors of Y, and
ancestors of at least one mediator (intermediate confounding / recanting twin).
"""
function _recanting_witness_nodes(g::AbstractGraph, A::Int, Y::Int, mediator_idx::Vector{Int})
    forbidden = Set{Int}(vcat(A, Y, mediator_idx))
    witnesses = Int[]
    for z in 1:nv(g)
        z in forbidden && continue
        _has_directed_path_simple(g, A, z) || continue
        _has_directed_path_simple(g, z, Y) || continue
        if any(_has_directed_path_simple(g, z, m) for m in mediator_idx)
            push!(witnesses, z)
        end
    end
    return witnesses
end

"""
    identify(g, query::TotalEffectQuery; node_names=nothing) -> IdentificationResult
"""
function identify(
    g::AbstractGraph,
    query::TotalEffectQuery;
    node_names = nothing,
)
    names = _normalize_node_names(node_names, nv(g))
    X = query.treatment isa Int ?
        _node_index(g, query.treatment) :
        _node_index(g, query.treatment, names)
    Y = query.outcome isa Int ?
        _node_index(g, query.outcome) :
        _node_index(g, query.outcome, names)

    adj_set = backdoor_adjustment_set(g, X, Y)
    identifiable = adj_set !== nothing
    adjustment = if identifiable
        _labels_from_indices(adj_set, names)
    else
        names === nothing ? Int[] : Symbol[]
    end

    return IdentificationResult{eltype(adjustment)}(
        query,
        graph_fingerprint(g),
        adjustment,
        _empty_like(adjustment),
        _empty_like(adjustment),
        :backdoor,
        identifiable,
        [:no_unmeasured_confounding, :correct_graph],
        Tuple{eltype(adjustment), Int}[],
    )
end

"""
    identify(g, query::MediationQuery; node_names=nothing) -> IdentificationResult

Identification for mediation queries:

- `:natural` — refuses when `moc` is nonempty or the graph has a recanting
  witness (treatment → Z → mediator and Z → outcome).
- `:interventional` / `:organic` / `:recanting_twin` — allow intermediate
  confounders; return adjustment, mediators, and moc in the certificate.
"""
function identify(
    g::AbstractGraph,
    query::MediationQuery;
    node_names = nothing,
)
    names = _normalize_node_names(node_names, nv(g))
    te = identify(g, TotalEffectQuery(query.treatment, query.outcome); node_names = node_names)
    T = eltype(te.adjustment)

    A = query.treatment isa Int ?
        _node_index(g, query.treatment) :
        _node_index(g, query.treatment, names::Dict{Int, Symbol})
    Y = query.outcome isa Int ?
        _node_index(g, query.outcome) :
        _node_index(g, query.outcome, names::Dict{Int, Symbol})

    med_idx = Int[
        m isa Int ? _node_index(g, m) : _node_index(g, Symbol(m), names::Dict{Int, Symbol})
        for m in query.mediators
    ]
    moc_user_idx = Int[
        z isa Int ? _node_index(g, z) : _node_index(g, Symbol(z), names::Dict{Int, Symbol})
        for z in query.moc
    ]

    witnesses = _recanting_witness_nodes(g, A, Y, med_idx)
    moc_idx = isempty(moc_user_idx) ? witnesses : moc_user_idx

    med_vec = _labels_from_indices(Set(med_idx), names)
    moc_vec = _labels_from_indices(Set(moc_idx), names)
    # Match adjustment eltype when Int-labelled graphs
    if T === Int || eltype(te.adjustment) === Int
        med_vec = sort(unique(med_idx))
        moc_vec = sort(unique(moc_idx))
    end

    ek = query.effect_kind
    if ek === :natural
        if !isempty(query.moc) || !isempty(witnesses)
            throw(IdentificationError(
                "Natural mediation effects are not identified under intermediate confounding " *
                "(moc=$(query.moc), graph witnesses=$(witnesses)). " *
                "Use effect_kind=:interventional or :recanting_twin.",
            ))
        end
        strategy = :mediation_natural
        assumptions = vcat(te.assumptions, :no_interference, :no_intermediate_confounding)
    elseif ek === :recanting_twin
        strategy = :mediation_recanting_twin
        assumptions = vcat(te.assumptions, :no_interference, :recanting_twin)
    elseif ek === :organic
        strategy = :mediation_organic
        assumptions = vcat(te.assumptions, :no_interference, :organic_effect)
    else
        strategy = :mediation_interventional
        assumptions = vcat(te.assumptions, :no_interference, :interventional_mediator_law)
    end

    return IdentificationResult{T}(
        query,
        te.graph_hash,
        te.adjustment,
        convert(Vector{T}, med_vec),
        convert(Vector{T}, moc_vec),
        strategy,
        te.identifiable,
        assumptions,
        te.temporal_nodes,
    )
end

"""
    identify(g, query::InterventionalPolicyQuery; node_names=nothing) -> IdentificationResult

Policy contrasts reduce to total-effect identification on the same `(treatment, outcome)` pair.
"""
function identify(
    g::AbstractGraph,
    query::InterventionalPolicyQuery;
    node_names = nothing,
)
    te = identify(g, TotalEffectQuery(query.treatment, query.outcome); node_names = node_names)
    return IdentificationResult{eltype(te.adjustment)}(
        query,
        te.graph_hash,
        te.adjustment,
        te.mediators,
        te.moc,
        :interventional_policy,
        te.identifiable,
        te.assumptions,
        te.temporal_nodes,
    )
end

"""
    identify(unrolling::TemporalUnrolling, query::TemporalEffectQuery) -> IdentificationResult
"""
function identify(unrolling::TemporalUnrolling, query::TemporalEffectQuery)
    X = temporal_node(unrolling, query.treatment, query.t_treat)
    Y = temporal_node(unrolling, query.outcome, query.t_outcome)
    g = unrolling.graph
    adj_set = backdoor_adjustment_set(g, X, Y)
    identifiable = adj_set !== nothing
    temporal_nodes = temporal_backdoor_adjustment_nodes(
        unrolling, query.treatment, query.t_treat, query.outcome, query.t_outcome,
    )
    # Expose baseline symbols (variable component of temporal nodes)
    adj_syms = sort!(unique([var for (var, _) in temporal_nodes]))
    return IdentificationResult{Symbol}(
        query,
        graph_fingerprint(g),
        adj_syms,
        Symbol[],
        Symbol[],
        :temporal_backdoor,
        identifiable,
        [:no_unmeasured_confounding, :correct_lag_structure],
        collect(temporal_nodes),
    )
end

"""
    identify(g, query::CausalQuery; kwargs...) -> IdentificationResult
"""
identify(g::AbstractGraph, query::CausalQuery; kwargs...) =
    error("identify not implemented for $(typeof(query)) on $(typeof(g))")

export identify, IdentificationError
