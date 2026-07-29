"""Unified identification API: `identify(graph, query)`."""

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
        similar(adjustment, 0),
        :backdoor,
        identifiable,
        [:no_unmeasured_confounding, :correct_graph],
        Tuple{eltype(adjustment), Int}[],
    )
end

"""
    identify(g, query::MediationQuery; node_names=nothing) -> IdentificationResult
"""
function identify(
    g::AbstractGraph,
    query::MediationQuery;
    node_names = nothing,
)
    te = identify(g, TotalEffectQuery(query.treatment, query.outcome); node_names = node_names)
    meds = query.mediators
    T = eltype(te.adjustment)
    med_vec = T === Symbol ? meds : Symbol.(meds)
    return IdentificationResult{T}(
        query,
        te.graph_hash,
        te.adjustment,
        med_vec,
        :mediation_backdoor,
        te.identifiable,
        vcat(te.assumptions, :no_interference),
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

export identify
