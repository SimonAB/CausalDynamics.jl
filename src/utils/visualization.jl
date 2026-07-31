"""
Graph visualisation utilities for CausalDynamics.jl.

Plotting requires the optional [DAGMakie.jl](https://github.com/SimonAB/DAGMakie.jl)
dependency. Load it with `using DAGMakie` (and a Makie backend such as CairoMakie)
to activate the `CausalDynamicsDAGMakieExt` package extension.
"""

"""
    has_dagmakie() -> Bool

Return `true` when the `CausalDynamicsDAGMakieExt` extension is loaded (`using DAGMakie`).
"""
function has_dagmakie()
    return !isnothing(Base.get_extension(@__MODULE__, :CausalDynamicsDAGMakieExt))
end

function _require_dagmakie!(f::Symbol)
    ext = Base.get_extension(@__MODULE__, :CausalDynamicsDAGMakieExt)
    ext === nothing && error(
        "DAGMakie.jl is required for visualisation. Load it with: using DAGMakie\n" *
        "Then call CausalDynamics.$f(...). See the package docs for examples.",
    )
    return ext
end

"""
    plot_causal_graph(g; node_labels, highlight_nodes, highlight_edges, kwargs...)

Plot a causal graph with optional node labels and highlighting.

Requires `using DAGMakie`. Returns a Makie `Figure` (via DAGMakie).

# Arguments
- `g::AbstractGraph`: The causal graph to plot
- `node_labels`: Optional labels for nodes (default: node indices)
- `highlight_nodes::Set{Int}`: Nodes to highlight
- `highlight_edges`: Edges to highlight as `(src, dst)` tuples
- `kwargs...`: Forwarded to DAGMakie plotting helpers

# Example
```julia
using CausalDynamics, Graphs, DAGMakie, CairoMakie

g = DiGraph(3)
add_edge!(g, 1, 2)
add_edge!(g, 1, 3)
add_edge!(g, 2, 3)

fig = plot_causal_graph(g;
    node_labels = ["Z", "X", "Y"],
    highlight_nodes = Set([1]),
)
```
"""
function plot_causal_graph(g::AbstractGraph;
    node_labels = nothing,
    highlight_nodes = Set{Int}(),
    highlight_edges = Tuple{Int, Int}[],
    kwargs...
)
    ext = _require_dagmakie!(:plot_causal_graph)
    return ext.plot_causal_graph(g;
        node_labels = node_labels,
        highlight_nodes = highlight_nodes,
        highlight_edges = highlight_edges,
        kwargs...
    )
end

"""
    plot_with_adjustment_set(g, X, Y, Z; node_labels, kwargs...)

Plot a causal graph highlighting treatment `X`, outcome `Y`, and adjustment set `Z`.

Requires `using DAGMakie`.
"""
function plot_with_adjustment_set(g::AbstractGraph, X::Int, Y::Int, Z::Vector{Int};
    node_labels = nothing,
    kwargs...
)
    ext = _require_dagmakie!(:plot_with_adjustment_set)
    return ext.plot_with_adjustment_set(g, X, Y, Z; node_labels = node_labels, kwargs...)
end

"""
    plot_backdoor_paths(g, X, Y; node_labels, kwargs...)

Plot a causal graph highlighting backdoor paths from treatment `X` to outcome `Y`.

Requires `using DAGMakie`. Uses DAGMakie's `dagplot_backdoor` with the CausalDynamics
`find_backdoor_paths` / adjustment helpers where useful.
"""
function plot_backdoor_paths(g::AbstractGraph, X::Int, Y::Int;
    node_labels = nothing,
    kwargs...
)
    ext = _require_dagmakie!(:plot_backdoor_paths)
    return ext.plot_backdoor_paths(g, X, Y; node_labels = node_labels, kwargs...)
end

"""
    plot_identification_result(g, result; node_names=nothing, kwargs...) -> Figure

Plot highlighting nodes from an `IdentificationResult`. Requires `using DAGMakie`.
"""
function plot_identification_result(g::AbstractGraph, result::IdentificationResult;
    node_names = nothing,
    kwargs...
)
    ext = _require_dagmakie!(:plot_identification_result)
    return ext.plot_identification_result(g, result; node_names = node_names, kwargs...)
end

"""
    dagplot_temporal(unrolling; kwargs...) -> Figure, Axis, plot

Plot a [`TemporalUnrolling`](@ref) with DAGMakie time-indexed layout and
`var[t]` labels. Requires `using DAGMakie`.
"""
function dagplot_temporal(unrolling; kwargs...)
    ext = _require_dagmakie!(:dagplot_temporal)
    return ext.dagplot_temporal(unrolling; kwargs...)
end

export has_dagmakie, plot_causal_graph, plot_with_adjustment_set, plot_backdoor_paths
export plot_identification_result, dagplot_temporal
