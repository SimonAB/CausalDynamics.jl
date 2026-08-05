"""Identification results and graph fingerprints."""

"""
    IdentificationResult{T}

Machine-readable output of [`identify`](@ref): adjustment sets, strategy, and assumptions.
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
    temporal_nodes::Vector{Tuple{T, Int}}
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
    temporal_nodes::Vector{Tuple{T, Int}} = Tuple{T, Int}[],
) where {T}
    return IdentificationResult{T}(
        query, graph_hash, adjustment, mediators, moc,
        strategy, identifiable, assumptions, temporal_nodes,
    )
end

"""
    graph_fingerprint(g) -> UInt64

Stable hash of directed edges for reproducibility certificates.
"""
function graph_fingerprint(g::AbstractGraph)
    edges = sort([(Graphs.src(e), Graphs.dst(e)) for e in Graphs.edges(g)])
    return hash(edges)
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
    )
end

export IdentificationResult, graph_fingerprint, certificate_dict
