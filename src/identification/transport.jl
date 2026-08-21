"""Transport / domain-shift identification (see [`TransportQuery`](@ref))."""

"""
    identify(g, query::TransportQuery; node_names=nothing) -> IdentificationResult

Identify the total effect while unioning domain variables into the adjustment
set. Strategy `:transport_backdoor`; assumptions include `:transportability`.
"""
function identify(
    g::AbstractGraph,
    query::TransportQuery;
    node_names = nothing,
    missingness = nothing,
)
    te = identify(
        g, TotalEffectQuery(query.treatment, query.outcome);
        node_names = node_names, missingness = missingness,
    )
    names = _normalize_node_names(node_names, Graphs.nv(g))
    T = eltype(te.adjustment)
    domain_idx = Set{Int}()
    for d in query.domain
        push!(domain_idx, d isa Int ? _node_index(g, d) : _node_index(g, d, names))
    end
    domain_lab = _labels_from_indices(domain_idx, names)
    domain_lab = T[convert(T, x) for x in domain_lab]
    adj = unique(vcat(te.adjustment, domain_lab))
    assumptions = unique(vcat(te.assumptions, [:transportability, :domain_exchangeability]))
    return IdentificationResult{T}(
        query,
        te.graph_hash,
        adj,
        te.mediators,
        te.moc,
        :transport_backdoor,
        te.identifiable,
        assumptions,
        te.temporal_nodes,
        te.missingness,
    )
end
