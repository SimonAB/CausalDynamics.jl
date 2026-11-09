"""Identification results and graph fingerprints."""

"""
    IdentificationResult{T}

Machine-readable output of [`identify`](@ref): adjustment sets, strategy, and assumptions.

Optional `missingness` holds a [`MissingnessCertificate`](@ref) when
`identify(...; missingness=MissingnessSpec(...))` was used. Causal
`identifiable` and missingness identification are reported separately.

`identification_status` refines `identifiable::Bool` with the reason
(`:identified`, `:not_identified_by_procedure`, `:unsupported_model_class`,
`:proved_nonidentifiable`; see [`IDENTIFICATION_STATUSES`](@ref)). Optional
`semantic_fingerprint` digests the declared meanings behind the graph.
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
    identification_status::Symbol
end

"""
    IdentificationResult(; query, graph_hash, adjustment, mediators, moc, strategy, identifiable, assumptions, temporal_nodes, missingness, semantic_fingerprint, identification_status) -> IdentificationResult

Keyword constructor: normalises `temporal_nodes` pairs to `(variable, Union{Nothing,Int})`, validates `identification_status`
against [`IDENTIFICATION_STATUSES`](@ref) when provided, else sets `:identified` or `:not_identified_by_procedure` from
`identifiable`. Prefer this constructor for new code so `semantic_fingerprint` and `identification_status` are explicit.
"""
function IdentificationResult(;
    query::CausalQuery,
    graph_hash::UInt64,
    adjustment::Vector{T},
    mediators::Vector{T} = similar(adjustment, 0),
    moc::Vector{T} = similar(adjustment, 0),
    strategy::Symbol,
    identifiable::Bool,
    assumptions::Vector{Symbol} = Symbol[],
    temporal_nodes = Tuple{eltype(adjustment), Int}[],
    missingness::Union{Nothing, MissingnessCertificate} = nothing,
    semantic_fingerprint::Union{Nothing, UInt64} = nothing,
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
    return IdentificationResult{T}(
        query, graph_hash, adjustment, mediators, moc,
        strategy, identifiable, assumptions, temporal_node_pairs, missingness,
        semantic_fingerprint, status,
    )
end

"""
    IdentificationResult{T}(query, graph_hash, adjustment, mediators, moc, strategy, identifiable, assumptions, temporal_nodes, missingness) -> IdentificationResult{T}

Positional constructor retained for historical call sites: sets `semantic_fingerprint` to `nothing` and derives
`identification_status` from `identifiable` only (`:identified` or `:not_identified_by_procedure`). Normalises
`temporal_nodes` like the keyword constructor.
"""
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
    certificate_dict(result::IdentificationResult) -> Dict{Symbol, Any}

Serialise an [`IdentificationResult`](@ref) to a `Symbol`-keyed dict (query, graph hash, adjustment sets, strategy,
assumptions, temporal nodes, optional missingness certificate, semantic fingerprint, identification status). Suitable
for structured logging or merging into downstream metadata.
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
        :identification_status => result.identification_status,
    )
end

export IdentificationResult, graph_fingerprint, certificate_dict
