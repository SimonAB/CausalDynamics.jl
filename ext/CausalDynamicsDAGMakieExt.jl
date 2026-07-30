"""
CausalDynamics extension for DAGMakie plotting.

Activated by `using DAGMakie`.
"""
module CausalDynamicsDAGMakieExt

using CausalDynamics: CausalDynamics,
    AbstractGraph,
    find_backdoor_paths,
    backdoor_adjustment_set,
    d_separated,
    IdentificationResult,
    TotalEffectQuery,
    MediationQuery
using DAGMakie
using Graphs: nv, has_edge

"""
    plot_causal_graph(g; node_labels, highlight_nodes, highlight_edges, kwargs...)
"""
function plot_causal_graph(g::AbstractGraph;
    node_labels = nothing,
    highlight_nodes = Set{Int}(),
    highlight_edges = Tuple{Int, Int}[],
    kwargs...
)
    labels = if node_labels === nothing
        [string(i) for i in 1:nv(g)]
    else
        node_labels
    end

    if isempty(highlight_nodes) && isempty(highlight_edges)
        fig, _ax, _p = dagplot(g; nlabels = labels, kwargs...)
        return fig
    end

    nodes = collect(highlight_nodes)
    highlight = HighlightSpec(
        nodes = nodes,
        node_colors = fill(:indianred, length(nodes)),
        edges = collect(highlight_edges),
        edge_colors = fill(:indianred, length(highlight_edges)),
        labels = String[],
    )
    fig, _ax, _p = dagplot_highlighted(g, highlight; nlabels = labels, kwargs...)
    return fig
end

"""
    plot_with_adjustment_set(g, X, Y, Z; node_labels, kwargs...)
"""
function plot_with_adjustment_set(g::AbstractGraph, X::Int, Y::Int, Z::Vector{Int};
    node_labels = nothing,
    kwargs...
)
    labels = if node_labels === nothing
        [string(i) for i in 1:nv(g)]
    else
        node_labels
    end
    fig, _ax, _p = dagplot_backdoor(g, X, Y; adjustment = Set(Z), nlabels = labels, kwargs...)
    return fig
end

"""
    plot_backdoor_paths(g, X, Y; node_labels, kwargs...)
"""
function plot_backdoor_paths(g::AbstractGraph, X::Int, Y::Int;
    node_labels = nothing,
    kwargs...
)
    labels = if node_labels === nothing
        [string(i) for i in 1:nv(g)]
    else
        node_labels
    end

    adj = backdoor_adjustment_set(g, X, Y)
    adjustment = adj === nothing ? Set{Int}() : Set{Int}(adj)

    # Convert CD path vectors to DAGMakie CausalPath when possible
    raw_paths = find_backdoor_paths(g, X, Y)
    paths = CausalPath[]
    for path in raw_paths
        if path isa CausalPath
            push!(paths, path)
        elseif path isa AbstractVector
            # CD returns node index vectors; treat as undirected for edges via consecutive pairs
            nodes = collect(Int, path)
            dirs = Symbol[]
            for i in 1:(length(nodes) - 1)
                if has_edge(g, nodes[i], nodes[i + 1])
                    push!(dirs, :forward)
                else
                    push!(dirs, :backward)
                end
            end
            # Positional constructor works on DAGMakie 0.1.0+; keyword form needs 0.1.1+
            push!(paths, CausalPath(nodes, dirs))
        end
    end

    fig, _ax, _p = dagplot_backdoor(g, X, Y;
        adjustment = adjustment,
        paths = paths,
        nlabels = labels,
        kwargs...,
    )
    return fig
end

"""
    plot_identification_result(g, result; node_names=nothing, kwargs...) -> Figure

Highlight treatment, outcome, adjustment, and mediators from an `IdentificationResult`.
"""
function plot_identification_result(g::AbstractGraph, result::IdentificationResult;
    node_names::Union{Nothing, Dict{Int, Symbol}} = nothing,
    kwargs...
)
    labels = if node_names === nothing
        [string(i) for i in 1:nv(g)]
    else
        [string(get(node_names, i, i)) for i in 1:nv(g)]
    end

    sym_to_idx = Dict{Symbol, Int}()
    if node_names !== nothing
        for (i, s) in node_names
            sym_to_idx[s] = i
        end
    end

    query = result.query
    treat_idx = outcome_idx = Int[]
    if query isa TotalEffectQuery
        if query.treatment isa Int
            treat_idx = [query.treatment]
        elseif haskey(sym_to_idx, query.treatment)
            treat_idx = [sym_to_idx[query.treatment]]
        end
        if query.outcome isa Int
            outcome_idx = [query.outcome]
        elseif haskey(sym_to_idx, query.outcome)
            outcome_idx = [sym_to_idx[query.outcome]]
        end
    elseif query isa MediationQuery
        if query.treatment isa Symbol && haskey(sym_to_idx, query.treatment)
            treat_idx = [sym_to_idx[query.treatment]]
        end
        if query.outcome isa Symbol && haskey(sym_to_idx, query.outcome)
            outcome_idx = [sym_to_idx[query.outcome]]
        end
    end

    adj_idx = Int[]
    for a in result.adjustment
        if a isa Int
            push!(adj_idx, a)
        elseif a isa Symbol && haskey(sym_to_idx, a)
            push!(adj_idx, sym_to_idx[a])
        end
    end

    med_idx = Int[]
    for m in result.mediators
        m isa Symbol && haskey(sym_to_idx, m) && push!(med_idx, sym_to_idx[m])
    end

    highlight_nodes = unique(vcat(treat_idx, outcome_idx, adj_idx, med_idx))
    title = "ID: $(result.strategy), identifiable=$(result.identifiable)"
    return plot_causal_graph(g;
        node_labels = labels,
        highlight_nodes = Set(highlight_nodes),
        title = title,
        kwargs...,
    )
end

end # module
