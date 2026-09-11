"""Identification results and graph fingerprints."""

"""
    IdentificationResult{T}

Machine-readable output of [`identify`](@ref): adjustment sets, strategy, and assumptions.

Optional `missingness` holds a [`MissingnessCertificate`](@ref) when
`identify(...; missingness=MissingnessSpec(...))` was used. Causal
`identifiable` and missingness identification are reported separately.
"""
struct IdentificationResult{T}
    query::CausalQuery
    graph_hash::UInt64
    adjustment::Vector{T}
    mediators::Vector{T}
    moc::Vector{T}
    strategy::Symbol
    identifiable::Bool
    assumptions::Vector{Symbol}
    temporal_nodes::Vector{Tuple{T, Union{Nothing, Int}}}
    missingness::Union{Nothing, MissingnessCertificate}
end

function IdentificationResult(;
    query::CausalQuery,
    graph_hash::UInt64,
    adjustment::Vector{T},
    mediators::Vector{T} = Vector{T}(),
    moc::Vector{T} = Vector{T}(),
    strategy::Symbol,
    identifiable::Bool,
    assumptions::Vector{Symbol} = Symbol[],
    temporal_nodes = Tuple{T, Int}[],
    missingness::Union{Nothing, MissingnessCertificate} = nothing,
) where {T}
    temporal_node_pairs = Tuple{T, Union{Nothing, Int}}[
        (pair[1], pair[2]) for pair in temporal_nodes
    ]
    return IdentificationResult{T}(
        query, graph_hash, adjustment, mediators, moc,
        strategy, identifiable, assumptions, temporal_node_pairs, missingness,
    )
end

"""
    graph_fingerprint(g) -> UInt64

Stable digest of directed edges for reproducibility certificates.
"""
function graph_fingerprint(g::AbstractGraph)
    edges = sort([(Graphs.src(e), Graphs.dst(e)) for e in Graphs.edges(g)])
    edge_text = join(["$src->$dst" for (src, dst) in edges], ";")
    return stable_hash64("vertices=$(Graphs.nv(g));edges=$edge_text")
end

"""
    certificate_dict(result) -> Dict{Symbol, Any}
"""
function certificate_dict(result::IdentificationResult)
    return Dict{Symbol, Any}(
        :query => result.query,
        :graph_hash => result.graph_hash,
        :adjustment => result.adjustment,
        :mediators => result.mediators,
        :moc => result.moc,
        :strategy => result.strategy,
        :identifiable => result.identifiable,
        :assumptions => result.assumptions,
        :temporal_nodes => result.temporal_nodes,
        :missingness => result.missingness,
    )
end

export IdentificationResult, graph_fingerprint, certificate_dict
