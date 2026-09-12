"""Identification results and graph fingerprints."""

"""
    IdentificationResult{T}

Machine-readable output of [`identify`](@ref): adjustment sets, strategy, and assumptions.

Optional `missingness` holds a [`MissingnessCertificate`](@ref) when
`identify(...; missingness=MissingnessSpec(...))` was used. Causal
`identifiable` and missingness identification are reported separately.

Optional `semantic_fingerprint`, `claim_kind`, and `identification_status`
record meaning beyond topology. Defaults preserve the historical
`identifiable::Bool` contract.
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
    semantic_fingerprint::Union{Nothing, UInt64}
    claim_kind::Symbol
    identification_status::Symbol
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
    semantic_fingerprint::Union{Nothing, UInt64} = nothing,
    claim_kind::Symbol = :identified_under_assumptions,
    identification_status::Union{Nothing, Symbol} = nothing,
) where {T}
    temporal_node_pairs = Tuple{T, Union{Nothing, Int}}[
        (pair[1], pair[2]) for pair in temporal_nodes
    ]
    status = if identification_status !== nothing
        identification_status in IDENTIFICATION_STATUSES || throw(ArgumentError(
            "identification_status must be one of $IDENTIFICATION_STATUSES",
        ))
        identification_status
    else
        identifiable ? :identified : :not_identified_by_procedure
    end
    claim_kind in CLAIM_KINDS || throw(ArgumentError(
        "claim_kind must be one of $CLAIM_KINDS, got :$claim_kind",
    ))
    return IdentificationResult{T}(
        query, graph_hash, adjustment, mediators, moc,
        strategy, identifiable, assumptions, temporal_node_pairs, missingness,
        semantic_fingerprint, claim_kind, status,
    )
end

"""Positional constructor used by historical call sites."""
function IdentificationResult{T}(
    query::CausalQuery,
    graph_hash::UInt64,
    adjustment::Vector{T},
    mediators::Vector{T},
    moc::Vector{T},
    strategy::Symbol,
    identifiable::Bool,
    assumptions::Vector{Symbol},
    temporal_nodes::AbstractVector,
    missingness::Union{Nothing, MissingnessCertificate},
) where {T}
    temporal_node_pairs = Tuple{T, Union{Nothing, Int}}[
        (pair[1], pair[2]) for pair in temporal_nodes
    ]
    return IdentificationResult{T}(
        query, graph_hash, adjustment, mediators, moc,
        strategy, identifiable, assumptions, temporal_node_pairs, missingness,
        nothing,
        :identified_under_assumptions,
        identifiable ? :identified : :not_identified_by_procedure,
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
        :semantic_fingerprint => result.semantic_fingerprint,
        :claim_kind => result.claim_kind,
        :identification_status => result.identification_status,
    )
end

export IdentificationResult, graph_fingerprint, certificate_dict
